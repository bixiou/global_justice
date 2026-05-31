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
SIMUL   <- "../data/Bothe/distribution_simul_extract.dta"
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
# Net housing wealth / total wealth, by wealth percentile group (France 2014,
# GGLP 2021 Appendix B; data/garbinti_etal_2021_wealth_compo_appB.xlsx, col
# sh_patfon_netXX). Bottom 30% ≈ 0 (debt offsets property); peaks at P60-P70.
housing_gradient <- function(gp) {
  brks <- c(0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 99.5, 99.9)
  vals <- c(0.000, 0.001, 0.016, 0.299, 0.619, 0.708, 0.732, 0.707, 0.641,
            0.540, 0.422, 0.319, 0.230, 0.102)
  vals[findInterval(gp, brks)]
}

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

# ── 3. cash_income[c, gp, y]  =  income_y × cash_income_2025 / income_2025 ──
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

# ── 5b. Flat tax to finance higher educ/health/PS spending (2035 vs 2025) ─
# G5s = share of educ+health+public-services spending in GNE (SC scenario).
# G0p = per-capita GNE under SC in EUR PPP 2025/year.
# Per country/region X:
#   extra_share_sc_2035[X]    = G5s[2035, X] − G5s[2025, X]              (% of GNE)
#   extra_tax_eur_sc_2035[X]  = extra_share_sc_2035[X] × G0p[2035, X]    (EUR/adult/year)
#   extra_tax_rate_sc_2035[X] = extra_tax_eur_sc_2035[X] / avg_cash_income[2035, X]
# Applied in section 7 as a flat-rate reduction (same proportion at every
# percentile) to the SC 2035 IT cash-income distribution.
G5s <- read_chancel_ts("G5s")
G0p <- read_chancel_ts("G0p")

ctry_cols <- intersect(colnames(G5s), colnames(G0p))
extra_share_sc_2035   <- setNames(as.numeric(G5s["2035", ctry_cols]) -
                                    as.numeric(G5s["2025", ctry_cols]), ctry_cols)
extra_tax_eur_sc_2035 <- setNames(extra_share_sc_2035 * as.numeric(G0p["2035", ctry_cols]), ctry_cols)

ac35_sc <- avg_cash[["2035"]]
shrd <- function(v, ref) v[intersect(names(v), names(ref))] / ref[intersect(names(v), names(ref))]
extra_tax_rate_sc_2035 <- shrd(extra_tax_eur_sc_2035, ac35_sc)

message("Flat-rate tax for extra educ/health/PS (2035 vs 2025), EUR and % of",
        " SC avg_cash_income 2035:")
for (k in c("IT","World")) message(sprintf(
  "  %-5s: %5.0f EUR (%5.2f%% of %.0f)",
  k, extra_tax_eur_sc_2035[k], 100*extra_tax_rate_sc_2035[k], ac35_sc[k]))

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

sc2_2035_IT_gross <- ci_wide$cash_income_2035[ci_wide$country == "IT"]
sc2_2035_IT       <- sc2_2035_IT_gross * (1 - as.numeric(extra_tax_rate_sc_2035["IT"]))
gp_IT2            <- ci_wide$gpercentile[ci_wide$country == "IT"]
stopifnot(isTRUE(all.equal(gp_IT, gp_IT2)))

# SC* columns use sc2_2035_IT (net of the flat extra-spending tax from section 5b).
# PC is the gross 2035 SC cash income scaled by 1.15, with NO extra-tax subtraction.
ineq_IT_2035 <- data.frame(
  gpercentile = gp_IT,
  PI    = 1.4 * ci25_IT,
  PC    = 1.15 * sc2_2035_IT_gross, # 1.3 * ci25_IT,
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

# ── 9. Figure: IT 2025 cash_income / income ratio by gpercentile ───────────
ci_it_2025  <- ci25$cash_income_2025[ci25$country == "IT"]
inc_it_2025 <- inc_wide$income_2025[inc_wide$country == "IT"]
ratio_g_IT  <- ci_it_2025 / inc_it_2025

png("../data/cash_over_income_IT_2025.png", width = 900, height = 520)
op <- par(mar = c(4.5, 5, 3, 1))
plot(gp_IT, ratio_g_IT, type = "l", lwd = 2.2, col = "steelblue",
     xlab = "gpercentile", ylab = "cash_income_2025 / income_2025",
     main = "IT 2025: cash_income / income, by gpercentile",
     ylim = c(0.5, 1.2))
abline(h = .69,        col = "grey60",  lty = 2)
abline(h = ratio_IT, col = "firebrick", lty = 2)
legend("topleft", lty = 2, col = c("grey60", "firebrick"),
       legend = c("ratio = 1", sprintf("ratio_IT = %.3f (aggregate cash / income)", ratio_IT)),
       bty = "n")
par(op); dev.off()
message("Wrote ../data/cash_over_income_IT_2025.png")

# ── 10. Report: avg income & cash income, 25/35/100, IT/World, SC/PI/PC ────
# 127-grid weighted mean (gp_width sums to 1); 100-grid is uniform → mean().
avg_127 <- function(v) sum(v * gp_width(gp_IT))
avg_100 <- function(v) mean(v, na.rm = TRUE)
pull <- function(x) if (is.null(x) || length(x) == 0 || !is.finite(x)) NA_real_ else as.numeric(x)

# 2025 baseline (SC = PI = PC).
inc_25_IT  <- avg_inc[["2025"]]["IT"];   cash_25_IT  <- avg_cash[["2025"]]["IT"]
inc_25_W   <- avg_inc[["2025"]]["World"]; cash_25_W  <- avg_cash[["2025"]]["World"]
# 2035 IT — SC net of flat tax, PI/PC as built in ineq_IT_2035.
inc_35_IT     <- avg_inc[["2035"]]["IT"]
cash_35_IT_sc <- avg_127(sc2_2035_IT)
cash_35_IT_pi <- avg_127(1.4  * ci25_IT)
cash_35_IT_pc <- avg_127(1.15 * sc2_2035_IT_gross)
# 2035 World — only SC modelled.
inc_35_W      <- avg_inc[["2035"]]["World"]
cash_35_W_sc  <- avg_cash[["2035"]]["World"]
# 2100 IT (127-grid).
inc_100_IT     <- avg_inc[["2100"]]["IT"]
cash_100_IT_sc <- avg_127(sc2_IT)
cash_100_IT_pi <- avg_127(pi_IT_dist)
cash_100_IT_pc <- avg_127(2.0 * sc2_IT)
# 2100 World (100-grid).
inc_100_W      <- avg_inc[["2100"]]["World"]
cash_100_W_sc  <- avg_100(sc2_World)
cash_100_W_pi  <- avg_100(pi_World_dist)
cash_100_W_pc  <- avg_100(2.0 * sc2_World)

report <- data.frame(
  row.names  = c("IT_SC","IT_PI","IT_PC","World_SC","World_PI","World_PC"),
  inc_2025   = c(pull(inc_25_IT),  pull(inc_25_IT), pull(inc_25_IT),
                 pull(inc_25_W),   pull(inc_25_W),  pull(inc_25_W)),
  cash_2025  = c(pull(cash_25_IT), pull(cash_25_IT),pull(cash_25_IT),
                 pull(cash_25_W),  pull(cash_25_W), pull(cash_25_W)),
  inc_2035   = c(pull(inc_35_IT),  NA, NA, pull(inc_35_W), NA, NA),
  cash_2035  = c(pull(cash_35_IT_sc), pull(cash_35_IT_pi), pull(cash_35_IT_pc),
                 pull(cash_35_W_sc),  NA, NA),
  inc_2100   = c(pull(inc_100_IT), NA, NA, pull(inc_100_W), NA, NA),
  cash_2100  = c(pull(cash_100_IT_sc), pull(cash_100_IT_pi), pull(cash_100_IT_pc),
                 pull(cash_100_W_sc),  pull(cash_100_W_pi),  pull(cash_100_W_pc)))
report[] <- lapply(report, function(x) ifelse(is.na(x), "—", formatC(x, format = "d", big.mark = "")))

cat("\nAvg income & cash income (EUR PPP 2025/adult/year):\n")
print.data.frame(report, right = TRUE)

# ── 11. Figures: all simulator distributions per (region, year) ────────────
# Each plot overlays the 6 distributions used by the simulator at that
# (region, year) along with the IT 2025 reference (ci25_IT).
plot_dists <- function(x, dists, ref_x, ref_v, title, fname, ylim_override = NULL) {
  cols <- c("firebrick","steelblue","darkgreen","goldenrod","darkmagenta","tomato")
  if (!is.null(ylim_override)) {
    ymax <- ylim_override
  } else {
    # Clip y at max value over gpercentile <= 95 (×1.3 headroom) so the steep
    # top-1% spike doesn't crush the rest of the curves on a linear scale.
    cap <- function(v, axis) max(v[axis <= 95], na.rm = TRUE)
    ymax <- 1.3 * max(c(sapply(dists, cap, axis = x), cap(ref_v, gp_IT)), na.rm = TRUE)
  }
  png(fname, width = 1000, height = 600)
  op <- par(mar = c(4.5, 5, 3, 1))
  plot(x, dists[[1]], type = "l", lwd = 2, col = cols[1],
       xlab = "gpercentile", ylab = "Income (EUR PPP 2025/adult/year)",
       main = title, ylim = c(0, ymax))
  for (i in seq_along(dists)[-1]) lines(x, dists[[i]], lwd = 2, col = cols[i])
  lines(ref_x, ref_v, lwd = 2, col = "black", lty = 3)
  legend("topleft", legend = c(names(dists), "IT 2025"),
         col = c(cols[seq_along(dists)], "black"),
         lty = c(rep(1, length(dists)), 3), lwd = 2, bty = "n", cex = 0.9)
  par(op); dev.off()
  message("Wrote ", fname)
}

# Step-function variant: mean income per vingtile (5% bracket).
# 20 equal vingtiles; the top 5% is treated like any other vingtile.
# (Previous version split the top 5% into p95-p99 and p99-p100 → 21 brackets:
# bracket_lo_v <- c(seq(0, 90, 5), 95, 99)
# bracket_hi_v <- c(seq(5, 95, 5), 99, 100))
bracket_lo_v <- seq(0, 95, 5)
bracket_hi_v <- seq(5, 100, 5)

bracket_avg_IT_v <- function(v) vapply(seq_along(bracket_lo_v), function(i) {
  m <- gp_IT >= bracket_lo_v[i] &
       (if (bracket_hi_v[i] >= 100) TRUE else gp_IT < bracket_hi_v[i])
  w <- gp_width(gp_IT[m]); sum(v[m] * w) / sum(w)
}, numeric(1))
bracket_avg_World_v <- function(v) vapply(seq_along(bracket_lo_v), function(i)
  mean(v[(bracket_lo_v[i] + 1):bracket_hi_v[i]], na.rm = TRUE), numeric(1))

plot_dists_step <- function(dists_b, ref_b, title, fname, ylim_override = NULL) {
  cols <- c("firebrick","steelblue","darkgreen","goldenrod","darkmagenta","tomato")
  if (!is.null(ylim_override)) {
    ymax <- ylim_override
  } else {
    # Exclude the last bracket from the y-cap; ×1.3 headroom.
    cap <- function(v) max(v[seq_len(length(bracket_lo_v) - 1)], na.rm = TRUE)
    ymax <- 1.3 * max(c(sapply(dists_b, cap), cap(ref_b)), na.rm = TRUE)
  }
  png(fname, width = 1000, height = 600)
  op <- par(mar = c(4.5, 5, 3, 1))
  plot(NA, xlim = c(0, 100), ylim = c(0, ymax),
       xlab = "gpercentile bracket", ylab = "Mean income (EUR PPP 2025/adult/year)",
       main = title)
  # Horizontal segments per bracket + vertical connectors at bracket boundaries.
  draw_steps <- function(v, col, lty = 1) {
    n <- length(v)
    for (i in seq_len(n)) {
      segments(bracket_lo_v[i], v[i], bracket_hi_v[i], v[i],
               col = col, lwd = 2.4, lty = lty)
      if (i < n)
        segments(bracket_hi_v[i], v[i], bracket_hi_v[i], v[i + 1],
                 col = col, lwd = 2.4, lty = lty)
    }
  }
  for (i in seq_along(dists_b)) draw_steps(dists_b[[i]], cols[i])
  draw_steps(ref_b, "black", lty = 3)
  legend("topleft", legend = c(names(dists_b), "IT 2025"),
         col = c(cols[seq_along(dists_b)], "black"),
         lty = c(rep(1, length(dists_b)), 3), lwd = 2.4, bty = "n", cex = 0.9)
  par(op); dev.off()
  message("Wrote ", fname)
}

# (a) World 2100 (100-grid, gpercentile 1..100)
plot_dists(
  x = 1:100,
  dists = list(
    PI    = pi_World_dist,
    PC    = 2.0  * sc2_World,
    SC1_2 = sc2_World,
    SC45k = 0.75 * sc2_World,
    SC30k = 0.5  * sc2_World,
    SC15k = 0.25 * sc2_World),
  ref_x = gp_IT, ref_v = ci25_IT,
  title = "World 2100 distributions (IT 2025 reference dotted)",
  fname = "../data/dist_World_2100.png",
  ylim_override = 200000)

# (b) IT 2100 (127-grid)
plot_dists(
  x = gp_IT,
  dists = list(
    PI    = pi_IT_dist,
    PC    = 2.0  * sc2_IT,
    SC1_2 = sc2_IT,
    SC45k = 0.75 * sc2_IT,
    SC30k = 0.5  * sc2_IT,
    SC15k = 0.25 * sc2_IT),
  ref_x = gp_IT, ref_v = ci25_IT,
  title = "IT 2100 distributions (IT 2025 reference dotted)",
  fname = "../data/dist_IT_2100.png",
  ylim_override = 200000)

# (c) IT 2035 (127-grid) — SC* are net of flat tax; PC uses gross.
plot_dists(
  x = gp_IT,
  dists = list(
    PI    = 1.4  * ci25_IT,
    PC    = 1.15 * sc2_2035_IT_gross,
    SC1_2 = sc2_2035_IT,
    SC45k = (gdp_it_2025        / gdp_it_sc_2035) * sc2_2035_IT,
    SC30k = (0.95 * gdp_it_2025 / gdp_it_sc_2035) * sc2_2035_IT,
    SC15k = (0.9  * gdp_it_2025 / gdp_it_sc_2035) * sc2_2035_IT),
  ref_x = gp_IT, ref_v = ci25_IT,
  title = "IT 2035 distributions (IT 2025 reference dotted)",
  fname = "../data/dist_IT_2035.png")

# Step-function variants: mean income per 5% bracket (20 equal vingtiles).
# Uses bracket_avg_IT_v / bracket_avg_World_v defined alongside plot_dists_step.
ref_b_IT <- bracket_avg_IT_v(ci25_IT)

# (a') World 2100 — step
plot_dists_step(
  dists_b = list(
    PI    = bracket_avg_World_v(pi_World_dist),
    PC    = bracket_avg_World_v(2.0  * sc2_World),
    SC1_2 = bracket_avg_World_v(sc2_World),
    SC45k = bracket_avg_World_v(0.75 * sc2_World),
    SC30k = bracket_avg_World_v(0.5  * sc2_World),
    SC15k = bracket_avg_World_v(0.25 * sc2_World)),
  ref_b = ref_b_IT,
  title = "World 2100 distributions — step (IT 2025 reference dotted)",
  fname = "../data/dist_World_2100_step.png",
  ylim_override = 300000)

# (b') IT 2100 — step
plot_dists_step(
  dists_b = list(
    PI    = bracket_avg_IT_v(pi_IT_dist),
    PC    = bracket_avg_IT_v(2.0  * sc2_IT),
    SC1_2 = bracket_avg_IT_v(sc2_IT),
    SC45k = bracket_avg_IT_v(0.75 * sc2_IT),
    SC30k = bracket_avg_IT_v(0.5  * sc2_IT),
    SC15k = bracket_avg_IT_v(0.25 * sc2_IT)),
  ref_b = ref_b_IT,
  title = "IT 2100 distributions — step (IT 2025 reference dotted)",
  fname = "../data/dist_IT_2100_step.png",
  ylim_override = 300000)

# (c') IT 2035 — step
plot_dists_step(
  dists_b = list(
    PI    = bracket_avg_IT_v(1.4  * ci25_IT),
    PC    = bracket_avg_IT_v(1.15 * sc2_2035_IT_gross),
    SC1_2 = bracket_avg_IT_v(sc2_2035_IT),
    SC45k = bracket_avg_IT_v((gdp_it_2025        / gdp_it_sc_2035) * sc2_2035_IT),
    SC30k = bracket_avg_IT_v((0.95 * gdp_it_2025 / gdp_it_sc_2035) * sc2_2035_IT),
    SC15k = bracket_avg_IT_v((0.9  * gdp_it_2025 / gdp_it_sc_2035) * sc2_2035_IT)),
  ref_b = ref_b_IT,
  title = "IT 2035 distributions — step (IT 2025 reference dotted)",
  fname = "../data/dist_IT_2035_step.png",
  ylim_override = 300000)
