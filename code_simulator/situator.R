# code_simulator/situator.R
#
# Self-contained builder for the Global Justice Situator (index.html / js/main.js).
# Exports, under the Sustainable Convergence (SC) scenario:
#   data/cash_income.csv        country × gpercentile × income_2025 … income_2100
#   data/cash_income_world.csv  world gpercentile (1..100) × income_{2025,2030,2035,2050,2100}
# All values in EUR PPP 2025 per adult per year.
#
# The cash-income concept matches questionnaire.R (sections 4-6): FG fiscal incidence,
# net of all taxes (incl. VAT), retained earnings and imputed rent, gross of CFC, net of GIT;
# generalised from Italy to every country/region. The 2025 level is projected to 2025-2100 with
# Bothe's SC full-income dynamics (income_y / income_2025) at each percentile.
#
# Reads raw data only (Bothe .dta/.xlsx, FG .dta, WID .csv). Working directory: code_simulator/

suppressPackageStartupMessages({ library(haven); library(readxl) })
dir.create("data", showWarnings = FALSE)

SIMUL <- "../data/Bothe/distribution_simul_extract.dta"
MACRO <- "../data/Bothe/Botheetal2026AppendixMacro.xlsx"
FG    <- "../data/FisherGethin/fisher-gethin-2023-slim.dta"
WID   <- "../data/WID/wid-mprico-nni.csv"

RETENTION_RATE <- 0.50    # fraction of corporate primary income retained (not paid out)
RENTAL_YIELD   <- 0.035   # imputed rent rate on net housing wealth
DIST_YEARS     <- c(2025, 2030, 2035, 2050, 2100)   # world-distribution snapshot years (match main.js)

##### 1. Helper functions (shared with questionnaire.R) #####
gp_width <- function(g) ifelse(g < 99, 0.01,
  ifelse(g < 99.9, 0.001, ifelse(g < 99.99, 0.0001, 0.00001)))

gperc_to_lb <- function(g) ifelse(g <= 99, g - 1,
  ifelse(g <= 108, 99 + (g - 100) * 0.1,
  ifelse(g <= 117, 99.9 + (g - 109) * 0.01,
  ifelse(g <= 126, 99.99 + (g - 118) * 0.001, 99.999))))

p1_to_gperc_index <- function(x) ifelse(x < 99, round(x) + 1,
  ifelse(x < 99.9, 100 + round((x - 99) * 10),
  ifelse(x < 99.99, 109 + round((x - 99.9) * 100),
  118 + round((x - 99.99) * 1000))))

enforce_monotone_below_99 <- function(v, gp) {
  idx <- gp < 99 & !is.na(v); v[idx] <- sort(v[idx]); v
}

# Net housing wealth / total wealth by gpercentile lower bound (France 2014, Garbinti et al. 2021)
housing_wealth_share <- function(gp_lb) {
  bks  <- c(0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 99.5, 99.9)
  vals <- c(0.000, 0.001, 0.016, 0.299, 0.619, 0.708, 0.732, 0.707, 0.641,
            0.540, 0.422, 0.319, 0.230, 0.102)
  vals[findInterval(gp_lb, bks)]
}

# Pool (entity, gpercentile) cells into a 100-bin equal-population world distribution.
build_world_dist <- function(value, width, pop_by_entity, entity, n_bins = 100) {
  d <- data.frame(v = value, w = width * pop_by_entity[entity])
  d <- d[is.finite(d$v) & d$v > 0 & is.finite(d$w) & d$w > 0, ]
  d <- d[order(d$v), ]; W <- sum(d$w)
  d$cw_hi <- cumsum(d$w) / W; d$cw_lo <- c(0, head(d$cw_hi, -1))
  bin_lo <- (0:(n_bins - 1)) / n_bins; bin_hi <- (1:n_bins) / n_bins
  res <- vapply(seq_len(n_bins), function(p) {
    ov <- pmax(0, pmin(d$cw_hi, bin_hi[p]) - pmax(d$cw_lo, bin_lo[p]))
    s <- sum(ov); if (s > 0) sum(d$v * ov) / s else NA_real_
  }, numeric(1))
  if (any(is.na(res))) {
    ok <- which(!is.na(res))
    if (length(ok) >= 2) res <- approx(ok, res[ok], xout = seq_len(n_bins), rule = 2)$y
  }
  res
}

# WID region aggregates → constituent FG ISO codes (for the 9 residual "Other X" regions)
main_countries <- c(
  "DE","DK","ES","FR","GB","IT","NL","NO","SE","US","CA","AU","NZ",
  "AR","BR","CL","CO","MX","AE","DZ","EG","IR","MA","SA","TR",
  "CD","CI","ET","KE","ML","NE","NG","RW","SD","ZA","RU","CN","JP","KR","TW",
  "BD","IN","ID","MM","PK","PH","TH","VN")
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

##### 2. Bothe simul: SC full income (post-GIT + dividend) per country × gpercentile × year #####
message("Reading Bothe simul...")
simul <- as.data.frame(read_dta(SIMUL))
for (v in c("sdiinc", "nni", "diff", "ypt", "pop", "shweal"))
  simul[[v]] <- ifelse(is.na(simul[[v]]), 0, simul[[v]])
simul$yp_recomp <- with(simul, ifelse(diff > 0, sdiinc * nni / diff, NA_real_))

e3bp <- suppressMessages(read_excel(MACRO, sheet = "E3bp", col_names = FALSE))
dividend_by_year <- setNames(
  suppressWarnings(as.numeric(unlist(e3bp[-(1:4), 2]))),
  as.character(suppressWarnings(as.numeric(unlist(e3bp[-(1:4), 1])))))
simul$income <- simul$yp_recomp - simul$ypt + dividend_by_year[as.character(simul$year)]

yrs_inc <- sort(unique(simul$year))                      # 2025 … 2100 (76 years)
year_cols <- paste0("income_", yrs_inc)
inc_wide <- reshape(simul[, c("country", "p1", "year", "income")],
  idvar = c("country", "p1"), timevar = "year", v.names = "income", direction = "wide")
names(inc_wide) <- c("country", "gpercentile", year_cols)
inc_wide <- inc_wide[order(inc_wide$country, inc_wide$gpercentile), ]

##### 3. cash_income_2025 per country/region (questionnaire.R definition, generalised) #####
message("Building cash_income_2025 for all countries...")
macro_2025 <- unique(simul[simul$year == 2025, c("country", "nni", "gdp", "cfc")])
nni_2025           <- setNames(macro_2025$nni, macro_2025$country)
cfc_per_adult_2025 <- setNames(macro_2025$cfc * macro_2025$gdp, macro_2025$country)

wid <- read.csv(WID)
mprico_share   <- setNames(wid$mprico_share, wid$country)
mprico_default <- median(wid$mprico_share, na.rm = TRUE)
re_rate_for <- function(ctry) {
  ms <- mprico_share[ctry]
  RETENTION_RATE * (if (length(ms) && !is.na(ms)) ms else mprico_default)
}

fg <- as.data.frame(read_dta(FG)); fg <- fg[fg$year == 2023, ]
for (v in c("a_pre","a_pre_cap","tax_dir_pit","tax_dir_wea","tax_cit",
            "tax_soc","tax_ind","gov_soc","weight"))
  fg[[v]] <- ifelse(is.na(fg[[v]]), 0, fg[[v]])

wealth_2025 <- simul[simul$year == 2025, c("country", "p1", "shweal", "diff")]
wealth_2025$gp_idx <- p1_to_gperc_index(wealth_2025$p1)
ypt_2025 <- simul[simul$year == 2025, c("country", "p1", "ypt")]
ypt_2025$gp_idx <- p1_to_gperc_index(ypt_2025$p1)

# Housing-normalised imputed-rent weights for `entity` over a 1-127 gperc index vector.
housing_norm_for <- function(entity, gperc_idx) {
  wd <- wealth_2025[wealth_2025$country == entity, ]
  if (!nrow(wd)) return(rep(0, length(gperc_idx)))
  sw  <- wd$shweal[match(gperc_idx, wd$gp_idx)]; sw[is.na(sw)] <- 0
  dif <- wd$diff[match(gperc_idx, wd$gp_idx)];   dif[is.na(dif)] <- 0.01
  H   <- housing_wealth_share(gperc_to_lb(gperc_idx))
  den <- sum(sw * H * dif, na.rm = TRUE)
  if (den <= 0) rep(0, length(gperc_idx)) else sw * H / den
}
# GIT already paid in 2025 by `entity` over a 1-127 gperc index vector.
ypt_for <- function(entity, gperc_idx) {
  yp <- ypt_2025[ypt_2025$country == entity, ]
  v <- yp$ypt[match(gperc_idx, yp$gp_idx)]; v[is.na(v)] <- 0; v
}
# Dimensionless FG components for one ISO: base = (pretax − all taxes + cash transfers)/mean.
compute_components <- function(sub) {
  mu_n <- sum(sub$a_pre * sub$weight) / sum(sub$weight)
  mu_c <- sum(sub$a_pre_cap * sub$weight) / sum(sub$weight)
  if (mu_n <= 0) return(NULL)
  data.frame(gperc = sub$gperc,
    base = (sub$a_pre - sub$tax_dir_pit - sub$tax_dir_wea - sub$tax_cit
            - sub$tax_soc - sub$tax_ind + sub$gov_soc) / mu_n,
    cap_share = if (mu_c > 0) sub$a_pre_cap / mu_c else rep(0, nrow(sub)),
    weight = sub$weight)
}

# Direct country: cash = base·NNI − RE − imputed rent + CFC gross-up − GIT.
cash_one <- function(ctry) {
  sub <- fg[fg$iso == ctry, ]; if (!nrow(sub)) return(NULL)
  comp <- compute_components(sub); if (is.null(comp)) return(NULL)
  nni <- nni_2025[ctry]; cfc <- cfc_per_adult_2025[ctry]
  if (is.na(nni) || is.na(cfc)) return(NULL)
  cash <- comp$base * nni - re_rate_for(ctry) * comp$cap_share * nni -
          RENTAL_YIELD * housing_norm_for(ctry, comp$gperc) * nni +
          comp$cap_share * cfc - ypt_for(ctry, comp$gperc)
  data.frame(country = ctry, gperc = comp$gperc, cash_income_2025 = cash)
}

# Residual region: population-weight FG components across constituent ISOs, then apply the
# region's own Bothe NNI/CFC, GIT and housing distribution.
cash_region <- function(rcode) {
  isos <- intersect(residual_def[[rcode]], unique(fg$iso)); if (!length(isos)) return(NULL)
  nni <- nni_2025[rcode]; cfc <- cfc_per_adult_2025[rcode]
  if (is.na(nni) || is.na(cfc)) return(NULL)
  pieces <- do.call(rbind, lapply(isos, function(ctry) {
    cc <- compute_components(fg[fg$iso == ctry, ]); if (is.null(cc)) return(NULL)
    cc$re <- re_rate_for(ctry) * cc$cap_share
    cc
  }))
  if (is.null(pieces)) return(NULL)
  agg <- aggregate(cbind(base_w = base * weight, re_w = re * weight,
                         cap_w = cap_share * weight, w = weight) ~ gperc, pieces, sum)
  cash <- (agg$base_w - agg$re_w) / agg$w * nni -
          RENTAL_YIELD * housing_norm_for(rcode, agg$gperc) * nni +
          agg$cap_w / agg$w * cfc - ypt_for(rcode, agg$gperc)
  data.frame(country = rcode, gperc = agg$gperc, cash_income_2025 = cash)
}

ci25 <- rbind(
  do.call(rbind, lapply(main_countries, cash_one)),
  do.call(rbind, lapply(names(residual_def), cash_region)))
ci25$gpercentile <- gperc_to_lb(ci25$gperc)
for (ctry in unique(ci25$country)) {
  r <- ci25$country == ctry
  ci25$cash_income_2025[r] <- enforce_monotone_below_99(ci25$cash_income_2025[r], ci25$gpercentile[r])
}
message(sprintf("  cash_income_2025: %d rows, %d entities", nrow(ci25), length(unique(ci25$country))))

##### 4. Per-country cash/full ratio; cash trajectory; FULL-income world distribution #####
# Cash income = full income × a per-country cash/full ratio (uniform across percentiles; = ratio_IT
# for Italy). For the WORLD distribution we DON'T pool heterogeneous per-country cash (that lets a
# rich country's low cash share drag the bottom down once SC has converged full income). Instead we
# export Bothe's FULL-income world distribution — which converges correctly across countries — and
# the page rescales it by the *user's own* country ratio (the world shown "in your cash terms"; the
# user's global rank is unaffected since the ratio cancels).
message("Building cash_income.csv, full_income_world.csv, cash_ratios.csv...")
key_ci <- paste(ci25$country, round(ci25$gpercentile, 5))
inc_wide$cash_2025 <- ci25$cash_income_2025[
  match(paste(inc_wide$country, round(inc_wide$gpercentile, 5)), key_ci)]
w_iw    <- gp_width(inc_wide$gpercentile)
num_c   <- tapply(inc_wide$cash_2025  * w_iw, inc_wide$country, sum, na.rm = TRUE)
den_c   <- tapply(inc_wide$income_2025 * w_iw, inc_wide$country, sum, na.rm = TRUE)
ratio_c <- num_c / den_c                                  # per-country cash/full ratio (IT ≈ ratio_IT)
rc_vec  <- ratio_c[inc_wide$country]

# (a) FULL-income world distribution (pre-ratio): pooled with SC population, 100 ranks × DIST_YEARS.
simul_pop <- unique(simul[, c("country", "year", "pop")])
ok        <- is.finite(rc_vec)
world_cols <- setNames(lapply(DIST_YEARS, function(yr) {
  pop_yr <- setNames(simul_pop$pop[simul_pop$year == yr], simul_pop$country[simul_pop$year == yr])
  round(build_world_dist(inc_wide[[paste0("income_", yr)]][ok], w_iw[ok],
                         pop_yr, inc_wide$country[ok]), 0)
}), paste0("income_", DIST_YEARS))
write.csv(data.frame(gpercentile = 1:100, world_cols, check.names = FALSE),
          "data/full_income_world.csv", row.names = FALSE, quote = FALSE)

# (b) Per-country cash trajectory: cash[c,g,y] = full income_y × ratio_c (for the evolution chart).
for (col in year_cols) inc_wide[[col]] <- inc_wide[[col]] * rc_vec
cash_ts <- inc_wide[is.finite(inc_wide$income_2100), c("country", "gpercentile", year_cols)]
for (ctry in unique(cash_ts$country)) {
  r <- which(cash_ts$country == ctry)
  for (col in year_cols)
    cash_ts[r, col] <- enforce_monotone_below_99(cash_ts[r, col], cash_ts$gpercentile[r])
}
cash_ts[, year_cols] <- lapply(cash_ts[, year_cols], round, digits = 0)
write.csv(cash_ts, "data/cash_income.csv", row.names = FALSE, quote = FALSE)

# (c) Per-country cash/full ratios — the page rescales full_income_world by ratio[user's country].
write.csv(data.frame(country = names(ratio_c), ratio = round(as.numeric(ratio_c), 4)),
          "data/cash_ratios.csv", row.names = FALSE, quote = FALSE)
message(sprintf("  Wrote cash_income.csv (%d rows), full_income_world.csv (100), cash_ratios.csv (%d)",
                nrow(cash_ts), length(ratio_c)))
message("Done.")
