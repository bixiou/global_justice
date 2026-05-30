# code_simulator/questionnaire.R
# Generates the inputs for the questionnaire pages:
#   - ../data/ineq_2100.csv      21 brackets × 14 cols ({IT,World} × {PI,PC,SC1,SC2,SC45k,SC30k,SC15k})
#   - ../data/ineq_IT_2035.csv   127 gpercentiles × 7 cols (PI,PC,SC1,SC2,SC45k,SC30k,SC15k)
#   - ../data/world_pi_2100.png  World PI 2100 distribution (country-specific vs uniform growth)
#
# Self-contained: every quantity is rebuilt from raw data (.dta + .xlsx); no
# .csv produced by other R scripts is consumed. Construction follows
# build_cash_income_2025.R (FG → cash_income_2025) and prepare_data.R
# (Bothe simul → post-GIT income), with the new monotonicity rule applied.

suppressPackageStartupMessages({library(haven); library(readxl)})

CHANCEL <- "../data/Chancel/Chanceletal2026Appendix_MacroScenarios.xlsx"
MACRO   <- "../data/Bothe/Botheetal2026AppendixMacro.xlsx"
SIMUL   <- "../data/Bothe/distribution_simul.dta"
FG      <- "../data/FisherGethin/fisher-gethin-2023-slim.dta"
WID     <- "../data/WID/wid-mprico-nni.csv"

# Population-share width of each Bothe 127-bracket lower bound (sums to 1)
gp_width <- function(g) ifelse(g < 99, 0.01,
                       ifelse(g < 99.9, 0.001,
                       ifelse(g < 99.99, 0.0001, 0.00001)))

# FG / Bothe gperc index (1..127) → lower-bound (0, 1, ..., 99.999)
gperc_to_lb <- function(g) ifelse(g <= 99,  g - 1,
                          ifelse(g <= 108, 99    + (g - 100) * 0.1,
                          ifelse(g <= 117, 99.9  + (g - 109) * 0.01,
                          ifelse(g <= 126, 99.99 + (g - 118) * 0.001, 99.999))))

# Sort each value column ascending over rows with gpercentile < 99, per country,
# leaving top-1% values (gpercentile >= 99) untouched. Used to neutralise local
# non-monotonicities inherited from FG / Bothe raw data.
sort_bottom99 <- function(d, value_cols, p_col = "gpercentile", country_col = "country") {
  for (ctry in unique(d[[country_col]])) {
    r <- which(d[[country_col]] == ctry & d[[p_col]] < 99)
    for (vc in value_cols) d[r, vc] <- sort(d[r, vc], na.last = TRUE)
  }
  d
}

# Read a Chancel macro-scenario sheet (year × {World, 8 regions, 57 countries}).
# Some sheets have trailing growth-rate rows (e.g. "2025-2100"); we filter to
# rows with a numeric year so rownames stay plain "YYYY" strings.
read_chancel_ts <- function(sheet, file = CHANCEL) {
  d <- suppressMessages(read_excel(file, sheet = sheet, col_names = FALSE))
  hdr  <- as.character(unlist(d[4, ]))
  yrs  <- suppressWarnings(as.numeric(unlist(d[-(1:4), 1])))
  body <- d[-(1:4), -1][!is.na(yrs), ]
  yrs  <- yrs[!is.na(yrs)]
  v    <- suppressWarnings(apply(body, 2, as.numeric))
  if (is.null(dim(v))) v <- matrix(v, nrow = 1)
  colnames(v) <- hdr[-1]
  df <- as.data.frame(v); rownames(df) <- as.character(yrs)
  df
}

# ── 1. income[c, gp, y] from Bothe distribution_simul.dta ──────────────────
# Same formula as prepare_data.R: income = sdiinc * nni / diff - ypt + dividend[y]
message("Building income...")
simul <- as.data.frame(read_dta(SIMUL))
for (v in c("sdiinc","nni","diff","ypt","pop"))
  simul[[v]] <- ifelse(is.na(simul[[v]]), 0, simul[[v]])
simul$yp_recomp <- with(simul, ifelse(diff > 0, sdiinc * nni / diff, NA_real_))
# Equal-per-adult worldwide GJF dividend (E3bp col 2 = World, uniform across countries)
e3bp <- suppressMessages(read_excel(MACRO, sheet = "E3bp", col_names = FALSE))
dividend <- setNames(
  suppressWarnings(as.numeric(unlist(e3bp[-(1:4), 2]))),
  as.character(suppressWarnings(as.numeric(unlist(e3bp[-(1:4), 1])))))
simul$income <- simul$yp_recomp - simul$ypt + dividend[as.character(simul$year)]

yrs_inc  <- sort(unique(simul$year))
inc_wide <- reshape(simul[, c("country","p1","year","income")],
                    idvar = c("country","p1"), timevar = "year",
                    v.names = "income", direction = "wide")
names(inc_wide) <- c("country", "gpercentile", paste0("income_", yrs_inc))
inc_wide <- inc_wide[order(inc_wide$country, inc_wide$gpercentile), ]
inc_wide <- sort_bottom99(inc_wide, paste0("income_", yrs_inc))

# ── 2. cash_income_2025[c, gp] from FG 2023 + Bothe 2025 macro ─────────────
# Dimensionless FG factor at each (country, gperc) × Bothe NNI 2025, minus ypt.
message("Building cash_income_2025...")
RETENTION_RATE <- 0.5
RENTAL_YIELD   <- 0.035   # imputed rent ≈ 3.5% of NNI (PSZ 2018, GGLP 2018, BCG 2022 avg)
housing_gradient <- function(gp)
  ifelse(gp < 50, 1.5, ifelse(gp < 90, 1.2, ifelse(gp < 99, 0.8, ifelse(gp < 99.9, 0.4, 0.2))))

main_countries <- c(
  "DE","DK","ES","FR","GB","IT","NL","NO","SE","US","CA","AU","NZ",
  "AR","BR","CL","CO","MX","AE","DZ","EG","IR","MA","SA","TR",
  "CD","CI","ET","KE","ML","NE","NG","RW","SD","ZA","RU","CN","JP","KR","TW",
  "BD","IN","ID","MM","PK","PH","TH","VN")

# Residual WID regions (9): non-main constituent country lists by area
WEUR <- c("AD","AT","BE","CH","DE","DK","ES","FI","FR","GB","GG","GI","GR","IE","IM","IS","IT","JE","LI","LU","MC","MT","NL","NO","PT","SE","SM")
EEUR <- c("AL","BA","BG","CY","CZ","EE","HR","HU","KS","LT","LV","MD","ME","MK","PL","RO","RS","SI","SK")
NAOC <- c("AU","BM","CA","FJ","FM","GL","KI","MH","NC","NR","NZ","PF","PG","PW","SB","TO","TV","US","VU","WS")
LATA <- c("AG","AI","AR","AW","BB","BO","BQ","BR","BS","BZ","CL","CO","CR","CU","CW","DM","DO","EC","GD","GT","GY","HN","HT","JM","KN","KY","LC","MS","MX","NI","PA","PE","PR","PY","SR","SV","SX","TC","TT","UY","VC","VE","VG")
MENA <- c("AE","BH","DZ","EG","IL","IQ","IR","JO","KW","LB","LY","MA","OM","PS","QA","SA","SY","TN","TR","YE")
SSAF <- c("AO","BF","BI","BJ","BW","CD","CF","CG","CI","CM","CV","DJ","ER","ET","GA","GH","GM","GN","GQ","GW","KE","KM","LR","LS","MG","ML","MR","MU","MW","MZ","NA","NE","NG","RW","SC","SD","SL","SN","SO","SS","ST","SZ","TD","TG","TZ","UG","ZA","ZM","ZW")
RUCA <- c("AM","AZ","BY","GE","KG","KZ","RU","TJ","TM","UA","UZ")
EASA <- c("CN","HK","JP","KP","KR","MN","MO","TW")
SSEA <- c("AF","BD","BN","BT","ID","IN","KH","LA","LK","MM","MV","MY","NP","PH","PK","SG","TH","TL","VN")
residual_def <- list(
  OC = setdiff(WEUR, main_countries), QM = EEUR,
  OH = setdiff(NAOC, main_countries), OD = setdiff(LATA, main_countries),
  OE = setdiff(MENA, main_countries), OJ = setdiff(SSAF, main_countries),
  OA = setdiff(RUCA, main_countries), OB = setdiff(EASA, main_countries),
  OI = setdiff(SSEA, main_countries))

fg <- as.data.frame(read_dta(FG)); fg <- fg[fg$year == 2023, ]
for (v in c("a_pre","a_pre_cap","tax_dir_pit","tax_dir_wea","tax_cit",
            "tax_soc","tax_ind","gov_soc","weight"))
  fg[[v]] <- ifelse(is.na(fg[[v]]), 0, fg[[v]])

wid <- read.csv(WID)
mprico_share   <- setNames(wid$mprico_share, wid$country)
mprico_default <- median(mprico_share)

re_rate_for <- function(ctry) {
  ms <- if (!is.na(mprico_share[ctry])) mprico_share[ctry] else mprico_default
  RETENTION_RATE * if (is.na(ms)) mprico_default else ms
}

housing_norm_for <- function(entity, gperc_idx) {
  wd <- wealth_dist_2025[wealth_dist_2025$country == entity, ]
  n  <- length(gperc_idx)
  if (nrow(wd) == 0) return(rep(0, n))
  p1_to_gp <- function(x)
    ifelse(x < 99,       round(x) + 1,
    ifelse(x < 99.9,  100 + round((x - 99)  * 10),
    ifelse(x < 99.99, 109 + round((x - 99.9) * 100),
                      118 + round((x - 99.99) * 1000))))
  wd$gp <- p1_to_gp(wd$p1)
  sw  <- wd$shweal[match(gperc_idx, wd$gp)]; sw[is.na(sw)] <- 0
  dif <- wd$diff  [match(gperc_idx, wd$gp)]; dif[is.na(dif)] <- 0.01
  H   <- housing_gradient(gperc_to_lb(gperc_idx))
  den <- sum(sw * H * dif, na.rm = TRUE)
  if (den <= 0) return(rep(0, n))
  sw * H / den
}

macro25     <- unique(simul[simul$year == 2025, c("country","nni","gdp","cfc")])
nni_2025    <- setNames(macro25$nni,                  macro25$country)
cfc_per_cap <- setNames(macro25$cfc * macro25$gdp,    macro25$country)
ypt_2025    <- simul[simul$year == 2025, c("country","p1","ypt")]
wealth_dist_2025 <- simul[simul$year == 2025, c("country","p1","shweal","diff")]
wealth_dist_2025$shweal <- ifelse(is.na(wealth_dist_2025$shweal), 0, wealth_dist_2025$shweal)

# Per-(country, gperc) dimensionless components, NNI-normalised
compute_factors <- function(sub) {
  mu_n <- sum(sub$a_pre     * sub$weight) / sum(sub$weight)
  mu_c <- sum(sub$a_pre_cap * sub$weight) / sum(sub$weight)
  if (mu_n <= 0) return(NULL)
  data.frame(
    gperc = sub$gperc, weight = sub$weight,
    pre = sub$a_pre / mu_n,
    dir = (sub$tax_dir_pit + sub$tax_dir_wea + sub$tax_cit) / mu_n,
    soc = sub$tax_soc / mu_n,
    ind = sub$tax_ind / mu_n,
    trn = sub$gov_soc / mu_n,
    cap_share_g = if (mu_c > 0) sub$a_pre_cap / mu_c else rep(0, nrow(sub)))
}

# (a) 48 main countries
main_rows <- do.call(rbind, lapply(main_countries, function(ctry) {
  sub <- fg[fg$iso == ctry, ]; if (nrow(sub) == 0) return(NULL)
  f <- compute_factors(sub); if (is.null(f)) return(NULL)
  nni <- nni_2025[ctry]; cfc <- cfc_per_cap[ctry]
  if (is.na(nni) || is.na(cfc)) return(NULL)
  re_r   <- re_rate_for(ctry)
  h_norm <- housing_norm_for(ctry, f$gperc)
  cash_eur <- with(f, (pre - dir - soc - ind + trn) * nni
                      - re_r * cap_share_g * nni
                      - RENTAL_YIELD * h_norm * nni
                      + cap_share_g * cfc)
  y_c <- ypt_2025[ypt_2025$country == ctry, ]
  ypt_v <- y_c$ypt[match(f$gperc, sapply(y_c$p1, function(x) {
    if (x < 99)       round(x) + 1
    else if (x < 99.9)  100 + round((x - 99)  * 10)
    else if (x < 99.99) 109 + round((x - 99.9) * 100)
    else                118 + round((x - 99.99) * 1000)
  }))]
  ypt_v[is.na(ypt_v)] <- 0
  data.frame(country = ctry, gperc = f$gperc, cash_income_2025 = cash_eur - ypt_v)
}))

# (b) 9 residual regions: FG-population-weighted average factor across constituent
#     countries, scaled by Bothe NNI for the WID region.
residual_rows <- do.call(rbind, lapply(names(residual_def), function(r) {
  isos <- intersect(residual_def[[r]], unique(fg$iso))
  if (length(isos) == 0) return(NULL)
  nni <- nni_2025[r]; cfc <- cfc_per_cap[r]
  if (is.na(nni) || is.na(cfc)) return(NULL)
  pieces <- do.call(rbind, lapply(isos, function(c) {
    f <- compute_factors(fg[fg$iso == c, ]); if (is.null(f)) return(NULL)
    f$base_factor <- with(f, pre - dir - soc - ind + trn)
    f$re_factor   <- re_rate_for(c) * f$cap_share_g
    f
  }))
  agg <- aggregate(cbind(base_w = base_factor * weight, re_w = re_factor * weight,
                          cap_w = cap_share_g * weight, w = weight) ~ gperc,
                   data = pieces, FUN = sum)
  h_norm <- housing_norm_for(r, agg$gperc)
  data.frame(country = r, gperc = agg$gperc,
             cash_income_2025 = (agg$base_w/agg$w - agg$re_w/agg$w) * nni
                                - RENTAL_YIELD * h_norm * nni
                                + agg$cap_w/agg$w * cfc)
}))

ci25 <- rbind(main_rows, residual_rows)
ci25$gpercentile <- gperc_to_lb(ci25$gperc)
ci25 <- ci25[order(ci25$country, ci25$gpercentile), ]
ci25 <- sort_bottom99(ci25, "cash_income_2025")

# ── 3. cash_income[c, gp, y]  =  cash_income_2025 × income_y / income_2025 ──
message("Building cash_income (2025-2100)...")
ci_wide <- merge(inc_wide, ci25[, c("country","gpercentile","cash_income_2025")],
                 by = c("country","gpercentile"), all.x = TRUE)
ci_wide$ratio <- with(ci_wide, ifelse(is.finite(income_2025) & income_2025 > 0,
                                       cash_income_2025 / income_2025, NA_real_))
cash_cols <- paste0("cash_income_", yrs_inc)
for (i in seq_along(yrs_inc))
  ci_wide[[cash_cols[i]]] <- ci_wide[[paste0("income_", yrs_inc[i])]] * ci_wide$ratio
ci_wide <- ci_wide[!is.na(ci_wide$ratio), ]
ci_wide <- ci_wide[order(ci_wide$country, ci_wide$gpercentile), ]
ci_wide <- sort_bottom99(ci_wide, cash_cols)

# ── 4. Populations and PI per-capita-GDP growth from Chancel ───────────────
# Scenario-specific populations: SC = Z0a (GJP path, accelerated ABR decline);
# PI = Z0b (UN Medium variant). 2025 values are essentially identical, but they
# diverge by 2100 (Z0a World 2100 ≈ 9.41 B vs Z0b ≈ 10.18 B).
z0a  <- read_chancel_ts("Z0a")
z0b  <- read_chancel_ts("Z0b")
a0pi <- read_chancel_ts("A0pi")   # GDP per capita PPP, PI scenario
growth_pi_2025_2100 <- as.numeric(a0pi["2100", ]) / as.numeric(a0pi["2025", ])
names(growth_pi_2025_2100) <- colnames(a0pi)
pop_sc <- function(y) setNames(as.numeric(z0a[as.character(y), ]), colnames(z0a))
pop_pi <- function(y) setNames(as.numeric(z0b[as.character(y), ]), colnames(z0b))
pop_sc_2025 <- pop_sc(2025); pop_sc_2100 <- pop_sc(2100)
pop_pi_2100 <- pop_pi(2100)

# ── 5. avg_income / avg_cash_income per country×year (within country: width-
#       weighted mean of percentile means; World: population-weighted mean of
#       country means) ─────────────────────────────────────────────────────
country_avg <- function(df, ycol) {
  num <- tapply(df[[ycol]] * gp_width(df$gpercentile), df$country, sum)
  den <- tapply(gp_width(df$gpercentile),               df$country, sum)
  num / den
}
world_avg <- function(cmeans, pop_y) {
  cs <- intersect(names(cmeans), names(pop_y))
  sum(cmeans[cs] * pop_y[cs]) / sum(pop_y[cs])
}
avg_with_world <- function(df, ycol, y) {
  # inc_wide and ci_wide are SC-scenario series → use SC populations (Z0a).
  cm <- country_avg(df, ycol)
  c(cm, World = unname(world_avg(cm, pop_sc(y))))
}
avg_inc  <- setNames(lapply(yrs_inc, function(y) avg_with_world(inc_wide, paste0("income_", y),       y)), as.character(yrs_inc))
avg_cash <- setNames(lapply(yrs_inc, function(y) avg_with_world(ci_wide,  paste0("cash_income_", y), y)), as.character(yrs_inc))

message("avg_cash_income / avg_income (EUR PPP 2025 per adult per year):")
for (y in c(2025, 2100)) for (k in c("IT","World"))
  message(sprintf("  %-5s %d:  cash=%8.0f   income=%8.0f",
                  k, y, avg_cash[[as.character(y)]][k], avg_inc[[as.character(y)]][k]))

# ── 5b. Extra tax to finance higher educ/health/PS spending (2100 vs 2025) ─
# G5s = share of educ+health+public-services spending in GNE (SC scenario);
# G5p = same share under PI and PC scenarios (they share the trajectory).
# G0p / G0pc / G0pi = per-capita GNE under SC / PC / PI in EUR PPP 2025/year.
# Per country/region X and scenario S in {sc, pc, pi}:
#   extra_share_S[X]   = G5[2100, X] − G5[2025, X]         (% of GNE)
#   extra_tax_eur_S[X] = extra_share_S[X] × G0_S[2100, X]  (EUR / adult / year)
#   extra_tax_S[X]     = extra_tax_eur_S[X] / avg_cash_income[2100, X]
# In SC, the share grows substantially (~22%→41%); in PC/PI it is ~flat.
G5s  <- read_chancel_ts("G5s")
G5p  <- read_chancel_ts("G5p")
G0p  <- read_chancel_ts("G0p")
G0pc <- read_chancel_ts("G0pc")
G0pi <- read_chancel_ts("G0pi")

# Restrict to columns present in every sheet (G0pc / G0pi lack a couple of
# regional aggregates that G5s / G5p / G0p carry, e.g. "Western Europe").
ctry_cols <- Reduce(intersect, list(colnames(G5s), colnames(G5p),
                                     colnames(G0p), colnames(G0pc), colnames(G0pi)))
extra_share_sc <- setNames(as.numeric(G5s["2100", ctry_cols]) -
                             as.numeric(G5s["2025", ctry_cols]), ctry_cols)
extra_share_p  <- setNames(as.numeric(G5p["2100", ctry_cols]) -
                             as.numeric(G5p["2025", ctry_cols]), ctry_cols)
extra_tax_eur_sc <- setNames(extra_share_sc * as.numeric(G0p ["2100", ctry_cols]), ctry_cols)
extra_tax_eur_pc <- setNames(extra_share_p  * as.numeric(G0pc["2100", ctry_cols]), ctry_cols)
extra_tax_eur_pi <- setNames(extra_share_p  * as.numeric(G0pi["2100", ctry_cols]), ctry_cols)

# Scenario-specific avg_cash_income at 2100 (pre-tax — used as the denominator
# of the flat-rate tax in each scenario):
#   ac100_sc = our cash-series mean (built on the Bothe SC nni trajectory).
#   ac100_pi[X] = pop-weighted mean of avg_cash_2025[c] × growth_pi[c]
#                 over all FG countries pooled (Bothe pop weights at 2100).
#   ac100_pc[X] = 2 × ac100_sc[X], matching PC = 2 × SC2 in ineq_2100.
ac100_sc <- avg_cash[["2100"]]
ac25     <- avg_cash[["2025"]]
pi_per_country <- ac25[names(ac25) %in% names(growth_pi_2025_2100)] *
                  growth_pi_2025_2100[names(ac25)[names(ac25) %in% names(growth_pi_2025_2100)]]
# World-aggregate by PI-scenario 2100 pop (Z0b), then named vector with IT, World, etc.
pi_world_avg <- sum(pi_per_country * pop_pi_2100[names(pi_per_country)], na.rm = TRUE) /
                sum(pop_pi_2100[names(pi_per_country)], na.rm = TRUE)
ac100_pi <- c(pi_per_country, World = unname(pi_world_avg))
ac100_pc <- 2 * ac100_sc

shrd <- function(v, ref) v[intersect(names(v), names(ref))] / ref[intersect(names(v), names(ref))]
extra_tax_sc <- shrd(extra_tax_eur_sc, ac100_sc)
extra_tax_pc <- shrd(extra_tax_eur_pc, ac100_pc)
extra_tax_pi <- shrd(extra_tax_eur_pi, ac100_pi)

message("Extra tax for educ/health/PS (2100 vs 2025), in EUR and as % of",
        " scenario avg_cash_income 2100:")
for (k in c("IT","World")) message(sprintf(
  "  %-5s: SC %5.0f EUR (%5.1f%% of %.0f) | PC %5.0f EUR (%4.1f%% of %.0f) | PI %5.0f EUR (%4.1f%% of %.0f)",
  k, extra_tax_eur_sc[k], 100*extra_tax_sc[k], ac100_sc[k],
     extra_tax_eur_pc[k], 100*extra_tax_pc[k], ac100_pc[k],
     extra_tax_eur_pi[k], 100*extra_tax_pi[k], ac100_pi[k]))

# ── 6. ineq_2100.csv: 21 brackets × 14 cols ────────────────────────────────
message("Building ineq_2100.csv...")

# Pool (country, gperc) cells weighted by gp_width × country pop, sort by
# value, and return a length-`n_bins` vector of mean income within each
# global percentile bin. Robust to cells whose cumulative-weight extent
# spans more than one bin: each cell's weighted income is *split* across
# the bins it crosses via the cw-overlap, so no bin is ever skipped. Any
# residual missing bin (e.g. extreme tails) is filled by linear
# interpolation on the bin index (`rule = 2` carries endpoints flat).
build_world_dist <- function(df, val_col, gp_col, pop_y, n_bins = 100) {
  d <- data.frame(v = df[[val_col]],
                  w = gp_width(df[[gp_col]]) * pop_y[df$country])
  d <- d[is.finite(d$v) & d$v > 0 & is.finite(d$w) & d$w > 0, ]
  d <- d[order(d$v), ]
  W       <- sum(d$w)
  d$cw_hi <- cumsum(d$w) / W
  d$cw_lo <- c(0, head(d$cw_hi, -1))
  bin_lo <- (0:(n_bins - 1)) / n_bins
  bin_hi <- (1:n_bins)       / n_bins
  res <- vapply(seq_len(n_bins), function(p) {
    ov <- pmax(0, pmin(d$cw_hi, bin_hi[p]) - pmax(d$cw_lo, bin_lo[p]))
    s  <- sum(ov)
    if (s > 0) sum(d$v * ov) / s else NA_real_
  }, numeric(1))
  if (any(is.na(res))) {
    ok <- which(!is.na(res))
    if (length(ok) >= 2) res <- approx(ok, res[ok], xout = seq_len(n_bins), rule = 2)$y
  }
  res
}

# Income concepts used in ineq_2100:
#   SC / PC / SC1 / SC45k / SC30k / SC15k → Bothe SC "income" = sdiinc*nni/diff − ypt + dividend
#       (post-GIT + dividend, already in inc_wide as income_2100).
#   PI → cash_income_2025 × growth_pi[c] (per-country PI growth from A0pi). We
#       cannot use Bothe SC's sdiinc*nni/diff at 2100 because that scenario
#       fully converges (sdiinc, nni become identical across countries by 2100),
#       collapsing IT and World PI distributions to the same vector.
# All 2100 values are then uniformly inflated by avg_cash_2025[IT] / avg_inc_2025[IT]
# (the IT cash/income ratio at 2025), including the World columns.

# IT 127-grid: gpercentile vector + per-distribution value vectors
gp_IT       <- ci25$gpercentile[ci25$country == "IT"]
ci25_IT     <- ci25$cash_income_2025[ci25$country == "IT"]
inc_IT_2100 <- inc_wide$income_2100[inc_wide$country == "IT"]
stopifnot(isTRUE(all.equal(gp_IT, inc_wide$gpercentile[inc_wide$country == "IT"])))

# Country-specific PI base for 2100 = cash_income_2025 × growth_pi[c]
pi_pool      <- ci25
pi_pool$v_pi <- pi_pool$cash_income_2025 * growth_pi_2025_2100[pi_pool$country]
pi_IT_2100   <- pi_pool$v_pi[pi_pool$country == "IT"]

# World 100-grid distributions — scenario-specific population weighting
inc_World_2100 <- build_world_dist(inc_wide, "income_2100", "gpercentile", pop_sc_2100)
pi_World_2100  <- build_world_dist(pi_pool,  "v_pi",       "gpercentile", pop_pi_2100)

# Uniform inflation factor (IT 2025 cash/income ratio), applied to all distributions
ratio_IT <- as.numeric(avg_cash[["2025"]]["IT"] / avg_inc[["2025"]]["IT"])

# Build the pre-bracket distributions (extra educ/health/PS tax NOT applied).
sc2_IT        <- inc_IT_2100    * ratio_IT
sc2_World     <- inc_World_2100 * ratio_IT
pi_IT_dist    <- pi_IT_2100    * ratio_IT
pi_World_dist <- pi_World_2100 * ratio_IT

# 21 brackets
bracket_lo <- c(seq(0, 90, 5), 95, 99)
bracket_hi <- c(seq(5, 95, 5), 99, 100)
bracket_names <- paste0("p", bracket_lo, "p", bracket_hi)

# IT: 127-grid mean within [pL, pH), weight = gp_width; pH=100 → inclusive
bracket_avg_IT <- function(v) vapply(seq_along(bracket_lo), function(i) {
  m <- gp_IT >= bracket_lo[i] &
       (if (bracket_hi[i] >= 100) TRUE else gp_IT < bracket_hi[i])
  w <- gp_width(gp_IT[m]); sum(v[m] * w) / sum(w)
}, numeric(1))
# World: 100-row distribution. Bin k = (k-1, k]% of pop → bracket rows (lo+1):hi
bracket_avg_World <- function(v) vapply(seq_along(bracket_lo), function(i)
  mean(v[(bracket_lo[i] + 1):bracket_hi[i]], na.rm = TRUE), numeric(1))

ineq2100 <- data.frame(
  bracket     = bracket_names,
  IT_PI       = bracket_avg_IT(pi_IT_dist),
  IT_PC       = bracket_avg_IT(2.0  * sc2_IT),
  IT_SC1      = bracket_avg_IT(sc2_IT),
  IT_SC2      = bracket_avg_IT(sc2_IT),
  IT_SC45k    = bracket_avg_IT(0.75 * sc2_IT),
  IT_SC30k    = bracket_avg_IT(0.5  * sc2_IT),
  IT_SC15k    = bracket_avg_IT(0.25 * sc2_IT),
  World_PI    = bracket_avg_World(pi_World_dist),
  World_PC    = bracket_avg_World(2.0  * sc2_World),
  World_SC1   = bracket_avg_World(sc2_World),
  World_SC2   = bracket_avg_World(sc2_World),
  World_SC45k = bracket_avg_World(0.75 * sc2_World),
  World_SC30k = bracket_avg_World(0.5  * sc2_World),
  World_SC15k = bracket_avg_World(0.25 * sc2_World))
# Round income values to integer EUR (no fractional cents in exported CSVs)
ineq2100[, -1] <- lapply(ineq2100[, -1], round, digits = 0)
write.csv(ineq2100, "../data/ineq_2100.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ../data/ineq_2100.csv (%d rows × %d cols)",
                nrow(ineq2100), ncol(ineq2100)))

# ── 7. ineq_IT_2035.csv: 127 gpercentiles × 7 cols ─────────────────────────
# Per-capita GDP PPP for IT in EUR PPP 2025/year, taken from
# Chanceletal2026Appendix_MacroScenarios sheets A0 (SC), A0pi (PI), A0pc (PC).
# Used here only to set the SC45k / SC30k / SC15k scaling and to motivate the
# 1.4× and 1.3× multipliers (gdp_it_pi_2035 / gdp_it_2025 ≈ 1.4,
# gdp_it_pc_2035 / gdp_it_2025 ≈ 1.3).
gdp_it_2025    <- 41346
gdp_it_sc_2035 <- 47519
gdp_it_pi_2035 <- 57503   # source: sheet A0pi col IT row 2035; 1.4 ≈ 57503/41346
gdp_it_pc_2035 <- 55073   # source: sheet A0pc col IT row 2035; 1.3 ≈ 55073/41346

sc2_2035_IT <- ci_wide$cash_income_2035[ci_wide$country == "IT"]
gp_IT2      <- ci_wide$gpercentile[ci_wide$country == "IT"]
stopifnot(isTRUE(all.equal(gp_IT, gp_IT2)))

ineq_IT_2035 <- data.frame(
  gpercentile = gp_IT,
  PI    = 1.4 * ci25_IT,
  PC    = 1.3 * ci25_IT,
  SC1   = sc2_2035_IT,
  SC2   = sc2_2035_IT,
  SC45k = (gdp_it_2025        / gdp_it_sc_2035) * sc2_2035_IT,
  SC30k = (0.95 * gdp_it_2025 / gdp_it_sc_2035) * sc2_2035_IT,
  SC15k = (0.9  * gdp_it_2025 / gdp_it_sc_2035) * sc2_2035_IT)
ineq_IT_2035[, -1] <- lapply(ineq_IT_2035[, -1], round, digits = 0)
write.csv(ineq_IT_2035, "../data/ineq_IT_2035.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ../data/ineq_IT_2035.csv (%d rows × %d cols)",
                nrow(ineq_IT_2035), ncol(ineq_IT_2035)))

# ── 8. Figure: World PI distribution at 2100 ───────────────────────────────
# Two curves: (a) PI World aggregated with country-specific growth (used in
# ineq_2100), (b) uniform-growth approximation cash_income_world × growth_pi[World].
cash_world_2025 <- build_world_dist(ci25, "cash_income_2025", "gpercentile", pop_sc_2025)
uniform_world   <- cash_world_2025 * growth_pi_2025_2100["World"]

png("../data/world_pi_2100.png", width = 900, height = 520)
op <- par(mar = c(4.5, 5, 3, 1))
ylim_top <- 1.15 * max(pi_World_dist[1:99], uniform_world[1:99], na.rm = TRUE)
plot(1:100, pi_World_dist, type = "l", lwd = 2.2, col = "firebrick",
     xlab = "World gpercentile",
     ylab = "Income (EUR PPP 2025 / adult / year)",
     main = "World PI distribution at 2100",
     ylim = c(0, ylim_top))
lines(1:100, uniform_world, lwd = 2.2, col = "steelblue", lty = 2)
legend("topleft", lty = c(1, 2), col = c("firebrick", "steelblue"), lwd = 2.2,
       legend = c("PI World (country-specific growth, ineq_2100)",
                  "cash_income_world × growth_pi[\"World\"] (uniform growth)"),
       bty = "n")
par(op); dev.off()
message("Wrote ../data/world_pi_2100.png")
