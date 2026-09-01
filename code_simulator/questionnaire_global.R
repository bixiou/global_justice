# code_simulator/questionnaire_global.R
# Multi-country version of questionnaire.R. Builds every data file behind the Global Justice
# conjoint question for ALL countries of ../data/country_parameters.xlsx at once, bundling them
# into the same number of CSVs as the Italian survey (one extra leading `country` column).
#
# Differences with questionnaire.R (which is Italy-only):
#   - hours classes are country-specific: ref_hours-8 / ref_hours-4 / ref_hours / ref_hours+4
#     (column `ref_hours` of the workbook; Italy 40 => 32/36/40/44, i.e. the Italian grid)
#   - the two B-scenario productivity growth rates are country-specific: `growth1` (dataset 1,
#     ineq_2035.csv) and `growth2` (dataset 2, ineq2_2035.csv), read from the workbook
#     (Italy 1.5% and 3%, i.e. the Italian values)
#   - the hours CLASS, not the hour count, carries the 2100 GDP target: ref_hours-8 -> 45k,
#     ref_hours-4 -> 60k (SC), ref_hours -> 90k, ref_hours+4 -> 120k. So a 48h-country's classes
#     mean the same living standards as Italy's, at its own working times.
#
# Outputs (written to global_survey/data/), all bundled across countries:
#   ineq_2035.csv           country x 127 gpercentiles x 2035 cash-income scenario columns (growth1)
#   ineq2_2035.csv          same, B scenarios at growth2 (for the _any2 task)
#   ineq_2100.csv           country x 21 brackets x 2100 income columns (national and World)
#   conjoint_constants.csv  country/name/value scalars read by the survey JavaScript
#
# Reads raw data only (Bothe .dta/.xlsx, Chancel .xlsx, FG .dta, WID .csv) plus
# chancel_temp2100_completed.csv and ../data/country_parameters.xlsx.
# Working directory assumed: code_simulator/

suppressPackageStartupMessages({ library(haven); library(readxl) })

CHANCEL <- "../data/Chancel/Chanceletal2026Appendix_MacroScenarios.xlsx"
MACRO <- "../data/Bothe/Botheetal2026AppendixMacro.xlsx"
SIMUL <- "../data/Bothe/distribution_simul_extract.dta"
FG <- "../data/FisherGethin/fisher-gethin-2023-slim.dta"
WID <- "../data/WID/wid-mprico-nni.csv"
TEMP_OBS <- "../data/chancel_temp2100_completed.csv"
PARAMS_XLSX <- "../data/country_parameters.xlsx"
OUT_DIR <- "global_survey/data"

DECARB_FACTOR <- c(SD = 1.00, ID = 0.99, FD = 0.97) # income cost of decarbonization at 2035
RETENTION_RATE <- 0.50 # fraction of capital income retained (not paid out)
RENTAL_YIELD <- 0.035 # imputed rent rate on net housing wealth (PSZ/GGLP/BCG average)
B90K_COEF_2100 <- 1.5 # 2100 GDP target of the ref_hours class (90k) relative to SC (60k)

# 2100 GDP-per-capita target (k EUR/adult) of each hours class, and the implied coefficient on the
# SC (60k) distribution. Attached to the CLASS, not to the hour count, so that they are comparable
# across countries with different ref_hours.
CLASS_GDP_GIT <- c(B45k = 45, B = 60, B90k = 90, B120k = 120)
CLASS_GDP_NOGIT <- c(B45k = 37.5, B = 50, B90k = 75, B120k = 100)
CLASS_COEF_2100 <- CLASS_GDP_GIT / 60
CLASSES <- names(CLASS_GDP_GIT) # ref-8, ref-4, ref, ref+4
SCOPE_SUFFIX <- c(C = "SC", G = "SG", N = "SN", I = "SI") # redistribution scope -> base column

# Countries without their own Chancel column / Bothe simul rows borrow the macro trajectory of the
# regional aggregate they belong to. Their own Fisher-Gethin survey still supplies the 2025
# within-country distribution, so only the macro path is borrowed.
FILL_FROM <- c(PE = "OD") # Peru -> Rest of Latin America

# Main language of each country, i.e. the column of global_survey/data/translations.csv the survey
# defaults to. Overridable per respondent with the ?lang= URL parameter. Languages are named with
# QUALTRICS codes (EN, PT-BR, ZH-S, ZH-T ...), the single convention used across the project.
# India defaults to English (the HI column stays available through ?lang=HI); its number grouping
# still follows fmt.locale.IN = HI, i.e. the lakh grouping Indian English uses too.
COUNTRY_LANG <- c(IT = "IT", BR = "PT-BR", CN = "ZH-S", IN = "EN", US = "EN", CA = "EN", DE = "DE",
                  PE = "ES", JP = "JA", AU = "EN", KR = "KO", ID = "ID", ZA = "EN", TR = "TR",
                  NG = "EN", FR = "FR", RU = "RU", ES = "ES", GB = "EN", SA = "AR", EG = "AR",
                  MX = "ES", PK = "UR", TW = "ZH-T", VN = "VI", BD = "BN", ET = "AM",
                  KE = "SW", CD = "FR")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

##### 1. Helper functions (identical to questionnaire.R) #####

# Replace NA with 0 (most monetary fields treat missing as absent => zero)
na0 <- function(x) ifelse(is.na(x), 0, x)

# Population-share width of each gpercentile lower-bound bracket
gp_width <- function(g) ifelse(g < 99, 0.01,
  ifelse(g < 99.9, 0.001, ifelse(g < 99.99, 0.0001, 0.00001)))

# Convert FG/Bothe 1-127 bracket index to percentile lower bound (0, 1, ..., 99.999)
gperc_to_lb <- function(g) ifelse(g <= 99, g - 1,
  ifelse(g <= 108, 99 + (g - 100) * 0.1,
  ifelse(g <= 117, 99.9 + (g - 109) * 0.01,
  ifelse(g <= 126, 99.99 + (g - 118) * 0.001, 99.999))))

# Convert Bothe p1 lower-bound back to 1-127 bracket index (inverse of gperc_to_lb)
p1_to_gperc_index <- function(x) ifelse(x < 99, round(x) + 1,
  ifelse(x < 99.9, 100 + round((x - 99) * 10),
  ifelse(x < 99.99, 109 + round((x - 99.9) * 100),
  118 + round((x - 99.99) * 1000))))

# Sort values at gpercentile < 99 ascending; enforces monotonicity for bottom 99%
enforce_monotone_below_99 <- function(v, gp) {
  idx <- gp < 99 & !is.na(v); v[idx] <- sort(v[idx]); v
}

# Read a Chancel macro-scenario sheet (rows = years, cols = countries/regions)
read_chancel_ts <- function(sheet, file = CHANCEL) {
  d <- suppressMessages(read_excel(file, sheet = sheet, col_names = FALSE))
  hdr <- as.character(unlist(d[4, ]))
  yrs <- suppressWarnings(as.numeric(unlist(d[-(1:4), 1])))
  body <- d[-(1:4), -1][!is.na(yrs), ]
  yrs <- yrs[!is.na(yrs)]
  v <- suppressWarnings(apply(body, 2, as.numeric))
  if (is.null(dim(v))) v <- matrix(v, nrow = 1)
  colnames(v) <- hdr[-1]
  df <- as.data.frame(v); rownames(df) <- as.character(yrs); df
}

# Pool (country, gpercentile) cells by income value, weight by gp_width x population,
# return a 100-bin vector of mean income per global percentile bin.
build_world_dist <- function(df, value_col, pop_by_country, n_bins = 100) {
  d <- data.frame(v = df[[value_col]],
                  w = gp_width(df$gpercentile) * pop_by_country[df$country])
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

# Net housing wealth / total wealth by gpercentile lower bound (France 2014, Garbinti et al. 2021)
housing_wealth_share <- function(gp_lb) {
  bks <- c(0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 99.5, 99.9)
  vals <- c(0.000, 0.001, 0.016, 0.299, 0.619, 0.708, 0.732, 0.707, 0.641,
            0.540, 0.422, 0.319, 0.230, 0.102)
  vals[findInterval(gp_lb, bks)]
}

# Match Bothe simul rows (identified by p1 lower-bound) to FG gperc order (1-127 index)
match_by_gperc_index <- function(simul_rows, value_col, fg_gperc_vec) {
  simul_rows$gperc_idx <- p1_to_gperc_index(simul_rows$p1)
  simul_rows[[value_col]][match(fg_gperc_vec, simul_rows$gperc_idx)]
}

# 10-year cumulative growth factor at a flat yearly rate
b_growth_10y <- function(rate) (1 + rate)^10

##### 2. Country table: ref_hours and the two growth rates #####
message("Reading country parameters...")
params <- as.data.frame(read_excel(PARAMS_XLSX, "data"))
stopifnot(all(c("iso2", "ref_hours", "growth1", "growth2") %in% names(params)))
params <- params[!is.na(params$ref_hours) & !is.na(params$growth1) & !is.na(params$growth2), ]
params$growth1 <- params$growth1 / 100 # workbook stores %/yr
params$growth2 <- params$growth2 / 100

##### 3. Bothe simul: income and yp_recomp by (country, gpercentile, year) #####
message("Reading Bothe simul...")
simul <- as.data.frame(read_dta(SIMUL))
for (v in c("sdiinc", "nni", "diff", "ypt", "pop")) simul[[v]] <- na0(simul[[v]])
# yp_recomp = national secondary income per adult (after national redistribution, before global GIT)
simul$yp_recomp <- with(simul, ifelse(diff > 0, sdiinc * nni / diff, NA_real_))

# Global per-adult dividend (uniform worldwide, from Bothe sheet E3bp column 2 = World)
e3bp <- suppressMessages(read_excel(MACRO, sheet = "E3bp", col_names = FALSE))
dividend_by_year <- setNames(
  suppressWarnings(as.numeric(unlist(e3bp[-(1:4), 2]))),
  as.character(suppressWarnings(as.numeric(unlist(e3bp[-(1:4), 1])))))
# income = full income = national secondary income - GIT paid + global dividend received
simul$income <- simul$yp_recomp - simul$ypt + dividend_by_year[as.character(simul$year)]

yrs_inc <- sort(unique(simul$year))
reshape_wide <- function(col) {
  w <- reshape(simul[, c("country", "p1", "year", col)],
               idvar = c("country", "p1"), timevar = "year", v.names = col, direction = "wide")
  names(w) <- c("country", "gpercentile", paste0(col, "_", yrs_inc))
  w[order(w$country, w$gpercentile), ]
}
inc_wide <- reshape_wide("income")
yp_wide <- reshape_wide("yp_recomp")
stopifnot(identical(inc_wide$country, yp_wide$country) &&
          identical(inc_wide$gpercentile, yp_wide$gpercentile))

macro_2025 <- unique(simul[simul$year == 2025, c("country", "nni", "gdp", "cfc")])
nni_2025 <- setNames(macro_2025$nni, macro_2025$country)
cfc_per_adult_2025 <- setNames(macro_2025$cfc * macro_2025$gdp, macro_2025$country)

##### 4. Chancel sheets, populations, and PI-scenario growth #####
message("Reading Chancel sheets...")
z0a <- read_chancel_ts("Z0a"); z0b <- read_chancel_ts("Z0b")
pop_sc_2100 <- setNames(as.numeric(z0a["2100", ]), colnames(z0a)) # SC family: GJP path
pop_pi_2100 <- setNames(as.numeric(z0b["2100", ]), colnames(z0b)) # PI family: UN medium
a0pi <- read_chancel_ts("A0pi")
growth_pi_by_country <- setNames(
  as.numeric(a0pi["2100", ]) / as.numeric(a0pi["2025", ]), colnames(a0pi))
a0 <- read_chancel_ts("A0"); a0p <- read_chancel_ts("A0p")
g5s <- read_chancel_ts("G5s"); g0p <- read_chancel_ts("G0p")
f0a <- read_chancel_ts("F0a") # hourly labour productivity (EUR/hour)
e0h <- read_chancel_ts("E0h") # per-capita economic labour hours, SC
e0k <- read_chancel_ts("E0k") # per-capita economic labour hours, PC/PI
e0a <- read_chancel_ts("E0a") # per-worker economic labour hours, SC

# Keep only countries that exist in every source (Chancel columns, Bothe simul, FG micro-data)
fg_all <- as.data.frame(read_dta(FG))
fg_all <- fg_all[fg_all$year == 2023, ]
wid <- read.csv(WID)
mprico_median <- median(wid$mprico_share, na.rm = TRUE)

# Macro source of each country: itself, or the aggregate named in FILL_FROM
params$macro_iso <- ifelse(params$iso2 %in% names(FILL_FROM),
                           unname(FILL_FROM[params$iso2]), params$iso2)
has_fg <- params$iso2 %in% unique(fg_all$iso)
has_macro <- params$macro_iso %in% colnames(a0) & params$macro_iso %in% unique(simul$country)
dropped <- params$iso2[!(has_fg & has_macro)]
if (length(dropped))
  message("Dropped (no Fisher-Gethin micro-data, or no Chancel/Bothe macro even after FILL_FROM): ",
          paste(dropped, collapse = ", "))
params <- params[has_fg & has_macro, ]
countries <- params$iso2
borrowed <- params$iso2[params$iso2 != params$macro_iso]
if (length(borrowed))
  message("Macro borrowed: ", paste(sprintf("%s <- %s", borrowed,
          params$macro_iso[params$iso2 != params$macro_iso]), collapse = ", "))
message(sprintf("Building %d countries: %s", length(countries), paste(countries, collapse = ", ")))

##### 5. World 2100 distributions and the global taxG schedule (country-invariant) #####
message("Building World 2100 distributions...")
dividend_2100 <- dividend_by_year["2100"]
inc_wide$pi_income_2100 <- yp_wide$yp_recomp_2025 * growth_pi_by_country[inc_wide$country]
gw_world <- gp_width(inc_wide$gpercentile)
avg_sc_2100_c <- tapply(inc_wide$income_2100 * gw_world, inc_wide$country, sum)
avg_si0_2100_c <- tapply(0.5 * inc_wide$pi_income_2100 * gw_world, inc_wide$country, sum)
inc_wide$sn_income_2100 <- yp_wide$yp_recomp_2100 *
  (avg_si0_2100_c[inc_wide$country] / avg_sc_2100_c[inc_wide$country])
pi_pool <- inc_wide[, c("country", "gpercentile")]
pi_pool$si_income_2100 <- 0.5 * inc_wide$pi_income_2100

world_SC <- build_world_dist(inc_wide, "income_2100", pop_sc_2100)
world_SN <- build_world_dist(inc_wide, "sn_income_2100", pop_pi_2100)
world_PI <- build_world_dist(inc_wide, "pi_income_2100", pop_pi_2100)
world_SI <- build_world_dist(pi_pool, "si_income_2100", pop_pi_2100)

# G scope: taxG is a GLOBAL rate schedule expressed as a function of N (pre-global) income, read off
# the world SN->SC distributions, then evaluated at each unit's I (SI) income.
taxg_rate <- ifelse(world_SN > 0, (world_SN - world_SC) / world_SN, 0)
taxg_at <- function(income) approx(world_SN, taxg_rate, xout = income, rule = 2, ties = mean)$y
pi_pool$sg_income_2100 <- pi_pool$si_income_2100 * (1 - taxg_at(pi_pool$si_income_2100))
world_SG <- build_world_dist(pi_pool, "sg_income_2100", pop_sc_2100)

bracket_lo <- c(seq(0, 90, 5), 95, 99); bracket_hi <- c(seq(5, 95, 5), 99, 100)
bracket_names <- paste0("p", bracket_lo, "p", bracket_hi)
bracket_widths <- bracket_hi - bracket_lo # sums to 100

# World: mean over equal-population 100-grid bins per bracket
bracket_avg_world <- function(v) vapply(seq_along(bracket_lo), function(i)
  mean(v[(bracket_lo[i] + 1):bracket_hi[i]], na.rm = TRUE), numeric(1))
world_brackets <- list(SC = bracket_avg_world(world_SC), SG = bracket_avg_world(world_SG),
                       SN = bracket_avg_world(world_SN), SI = bracket_avg_world(world_SI))

##### 6. Temperature: regression on the Chancel no-emissions runs (country-invariant) #####
message("Fitting the no-emissions temperature regression...")
temp_chancel <- read.csv(TEMP_OBS, na.strings = "")
obs_temp <- temp_chancel[!is.na(temp_chancel$temp_observed), ]
obs_temp$decarb <- factor(obs_temp$decarb, levels = c("FD", "ID", "SD"))
fit_noem_gdp <- lm(temp_observed ~ gdp * decarb + decarb:sectoral_change, data = obs_temp)
message(sprintf("No-emissions regression: adj-R2 = %.4f", summary(fit_noem_gdp)$adj.r.squared))
noem_coefs <- coef(fit_noem_gdp)
noem_keys <- paste0("noem_", gsub("[^a-zA-Z0-9]", "_", gsub("^_+|_+$", "",
             gsub("[(]|[)]", "", names(noem_coefs)))))
# temp100.csv is NOT re-exported here: questionnaire.R already writes ../data/temp100.csv and the
# regression is country-invariant, so the browser only needs the noem_* coefficients below.

##### 7. Per-country builder #####
# Returns the 2035 distribution table, the 2100 bracket table and the constants of one country.
# Mirrors questionnaire.R sections 4-10 and 14, with `40` replaced by ref_hours and B_GROWTH_RATE
# replaced by growth1.
build_country <- function(iso, macro_iso, ref_hours, growth1, growth2) {
  hours_of <- c(B45k = ref_hours - 8, B = ref_hours - 4, B90k = ref_hours, B120k = ref_hours + 4)

  ##### 7a. cash_income_2025 from Fisher-Gethin + Bothe NNI #####
  mprico <- wid$mprico_share[wid$country == iso]
  re_rate <- RETENTION_RATE * (if (!length(mprico) || is.na(mprico[1])) mprico_median else mprico[1])

  fg_c <- fg_all[fg_all$iso == iso, ]
  for (v in c("a_pre", "a_pre_cap", "tax_dir_pit", "tax_dir_wea", "tax_cit",
              "tax_soc", "tax_ind", "gov_soc", "weight")) fg_c[[v]] <- na0(fg_c[[v]])
  fg_c <- fg_c[order(fg_c$gperc), ] # sort by bracket index 1-127
  gp <- gperc_to_lb(fg_c$gperc)
  stopifnot(length(gp) == 127)

  # Macro/distributional series come from macro_iso (= iso, except for FILL_FROM countries)
  c_simul <- function(year, col) match_by_gperc_index(
    simul[simul$year == year & simul$country == macro_iso, c("p1", col)], col, fg_c$gperc)

  # Wealth shares at 2025 (needed for the housing imputed-rent normalization)
  wealth_2025 <- simul[simul$year == 2025 & simul$country == macro_iso, c("p1", "shweal", "diff")]
  wealth_2025$shweal <- na0(wealth_2025$shweal)
  wealth_2025$gperc_idx <- p1_to_gperc_index(wealth_2025$p1)
  sw <- na0(wealth_2025$shweal[match(fg_c$gperc, wealth_2025$gperc_idx)])
  dif <- wealth_2025$diff[match(fg_c$gperc, wealth_2025$gperc_idx)]
  dif[is.na(dif)] <- 0.01
  hh <- housing_wealth_share(gp)
  den_h <- sum(sw * hh * dif, na.rm = TRUE)
  housing_norm <- if (den_h > 0) sw * hh / den_h else rep(0, nrow(fg_c))

  ypt_2025 <- na0(c_simul(2025, "ypt"))
  mu_n <- sum(fg_c$a_pre * fg_c$weight) / sum(fg_c$weight)
  mu_c <- sum(fg_c$a_pre_cap * fg_c$weight) / sum(fg_c$weight)
  cap_share <- if (mu_c > 0) fg_c$a_pre_cap / mu_c else rep(0, nrow(fg_c))

  # Cash income = pretax net of all taxes + govt transfers - imputed rent - retained earnings + CFC - GIT
  cash_income_2025 <- enforce_monotone_below_99(
    (fg_c$a_pre / mu_n
     - (fg_c$tax_dir_pit + fg_c$tax_dir_wea + fg_c$tax_cit) / mu_n
     - fg_c$tax_soc / mu_n - fg_c$tax_ind / mu_n + fg_c$gov_soc / mu_n) * nni_2025[macro_iso]
    - re_rate * cap_share * nni_2025[macro_iso]
    - RENTAL_YIELD * housing_norm * nni_2025[macro_iso]
    + cap_share * cfc_per_adult_2025[macro_iso]
    - ypt_2025, gp)

  ##### 7b. ratio (cash / full income) and per-percentile cash_ratio #####
  income_2025 <- c_simul(2025, "income")
  cash_ratio <- ifelse(is.finite(income_2025) & income_2025 > 0, cash_income_2025 / income_2025, NA_real_)
  avg_cash_2025 <- sum(cash_income_2025 * gp_width(gp))
  avg_income_2025 <- sum(income_2025 * gp_width(gp), na.rm = TRUE)
  ratio <- avg_cash_2025 / avg_income_2025

  ##### 7c. C35 (SC1_SD base = gross cash income 2035) and cash_GR35 #####
  income_2035 <- c_simul(2035, "income")
  c35 <- enforce_monotone_below_99(income_2035 * cash_ratio, gp)
  ypt_2035 <- na0(c_simul(2035, "ypt"))
  cash_gr35 <- (dividend_by_year["2035"] - ypt_2035) * cash_ratio

  ##### 7d. Extra public-services tax rate at 2035 (G5s, G0p) #####
  extra_ps_share <- as.numeric(g5s["2035", macro_iso]) - as.numeric(g5s["2025", macro_iso])
  extra_ps_eur <- extra_ps_share * as.numeric(g0p["2035", macro_iso])
  avg_c35 <- sum(c35 * gp_width(gp), na.rm = TRUE)
  extra_tax_rate <- extra_ps_eur / avg_c35

  ##### 7e. B-family productivity/hours scales (growth1) #####
  gdp_pc_2025 <- as.numeric(a0p["2025", macro_iso])
  gdp_pc_pi_2035 <- as.numeric(a0pi["2035", macro_iso])
  hours_pc_2035 <- as.numeric(e0h["2035", macro_iso])
  hours_pc_pi_2035 <- as.numeric(e0k["2035", macro_iso])
  gdp_sc_2035 <- as.numeric(a0["2035", macro_iso]); gdp_2025 <- as.numeric(a0["2025", macro_iso])
  prod_growth_2035 <- as.numeric(f0a["2035", macro_iso]) / as.numeric(f0a["2025", macro_iso])
  change_hours_pw <- as.numeric(e0a["2035", macro_iso]) / as.numeric(e0a["2025", macro_iso])

  # B90k = ref_hours class: same long-run productivity path as SC, hours fixed at their 2025 level.
  b90k_scale <- b_growth_10y(growth1) / (change_hours_pw * prod_growth_2035)
  b_scale <- change_hours_pw * b90k_scale # ref-4 class: real SC hours trajectory (E0a change)
  b45k_scale <- b90k_scale * hours_of["B45k"] / ref_hours
  b120k_scale <- b90k_scale * hours_of["B120k"] / ref_hours

  ##### 7f. 2035 base columns #####
  fd <- DECARB_FACTOR["FD"]
  ps_factor <- 1 - extra_tax_rate
  sc45k_scale_2035 <- gdp_2025 / gdp_sc_2035
  sc15k_scale_2035 <- 0.9 * sc45k_scale_2035
  si_scale_2035 <- gdp_pc_pi_2035 * (hours_pc_2035 / hours_pc_pi_2035) / gdp_pc_2025
  si0_2035 <- cash_income_2025 * si_scale_2035
  avg_si0_2035 <- sum(si0_2035 * gp_width(gp), na.rm = TRUE)

  base <- data.frame(
    gpercentile = gp,
    inc25 = cash_income_2025, # 2025 cash income (percentile lookup)
    cash_GR35 = cash_gr35,
    C35 = c35, # SC1_SD: base, no decarb cost, no PS tax
    SCmat = c35 * fd,
    SC = c35 * fd * ps_factor,
    PC = c35 * 1.15 * fd,
    PI = cash_income_2025 * 1.4 * fd,
    SC45k = c35 * sc45k_scale_2035 * fd * ps_factor,
    SC15k = c35 * sc15k_scale_2035 * fd * ps_factor,
    SI = si0_2035 * fd * ps_factor,
    SN = (c35 - cash_gr35) * (avg_si0_2035 / avg_c35) * fd * ps_factor,
    SG = (si0_2035 + cash_gr35) * (avg_c35 / avg_si0_2035) * fd * ps_factor,
    B90kC = c35 * b90k_scale * fd * ps_factor,
    B120kC = c35 * b120k_scale * fd * ps_factor,
    B45kC = c35 * b45k_scale * fd * ps_factor,
    B = c35 * b_scale * fd * ps_factor)
  income_cols <- setdiff(names(base), c("gpercentile", "cash_GR35"))
  for (col in setdiff(income_cols, "inc25"))
    base[[col]] <- enforce_monotone_below_99(base[[col]], gp)
  base[, income_cols] <- lapply(base[, income_cols], round, digits = 0)

  ##### 7g. Scope variants, exactly as questionnaire.R section 14 #####
  # Weighted-average incomes, rounded as the JS reads them from conjoint_constants.csv
  avg_of <- function(col) sum(base[[col]] * gp_width(gp), na.rm = TRUE)
  avg35 <- setNames(vapply(income_cols, avg_of, 0), income_cols)
  avg_r <- round(avg35)
  # As in questionnaire.R section 12, the B45k average is the B90k average scaled by the worked-hours
  # ratio (not the average of the B45k column), so that it matches the exported B45k columns.
  avg35["B45kC"] <- avg35["B90kC"] * unname(hours_of["B45k"] / ref_hours)

  out <- data.frame(gpercentile = gp, inc25 = base$inc25)
  # S family (ref-4 hours, i.e. the SC scenario): hours-agnostic scope columns
  s_cols <- c(C = "SC", G = "SG", N = "SN", I = "SI")
  # B90k (ref hours): C from its own column; G/N/I from the S columns rescaled by coefC
  coef_90k <- avg_r["B90kC"] / avg_r["SC"]
  b90k <- list(C = base$B90kC,
               G = base$SG * coef_90k,
               N = base$SN * coef_90k * avg_r["SI"] / avg_r["SN"],
               I = base$SI * coef_90k)
  for (sl in names(b90k)) out[[paste0("B90k", sl)]] <- round(b90k[[sl]])
  # B (ref-4 hours): C from its own column; G/N/I = S{scope} x b_scale
  out[["B"]] <- round(base$B)
  for (sl in c("G", "N", "I")) out[[paste0("B", sl)]] <- round(base[[s_cols[sl]]] * b_scale)
  # B45k / B120k: derived from the ROUNDED B90k columns by the worked-hours ratio. The factor is
  # formed FIRST (x * (h/ref), not x * h / ref) so that half-integers land the same way as in
  # questionnaire.R, where the factor is the literal 32/40 or 44/40.
  f45 <- unname(hours_of["B45k"] / ref_hours)
  f120 <- unname(hours_of["B120k"] / ref_hours)
  for (sl in c("C", "G", "N", "I")) {
    out[[paste0("B45k", sl)]] <- round(out[[paste0("B90k", sl)]] * f45)
    out[[paste0("B120k", sl)]] <- round(out[[paste0("B90k", sl)]] * f120)
  }
  # B120kC keeps its own base column (built from c35 directly, like Italy's B120kC). B45kC does NOT:
  # it stays derived from the rounded B90kC, as in questionnaire.R section 14.
  out[["B120kC"]] <- round(base$B120kC)

  ##### 7h. 2100 national distributions #####
  income_2100 <- c_simul(2100, "income")
  yp_recomp_2025 <- c_simul(2025, "yp_recomp")
  pi_2100_base <- yp_recomp_2025 * growth_pi_by_country[macro_iso]
  avg_sc_2100 <- sum(income_2100 * gp_width(gp), na.rm = TRUE)
  avg_si0_2100 <- sum(0.5 * pi_2100_base * gp_width(gp), na.rm = TRUE)
  sc_2100 <- income_2100
  sn_2100 <- (income_2100 - dividend_2100) * (avg_si0_2100 / avg_sc_2100)
  si_2100 <- 0.5 * pi_2100_base
  sg_2100 <- si_2100 * (1 - taxg_at(si_2100))

  bracket_avg_nat <- function(v) vapply(seq_along(bracket_lo), function(i) {
    m <- gp >= bracket_lo[i] & (if (bracket_hi[i] >= 100) TRUE else gp < bracket_hi[i])
    w <- gp_width(gp[m]); sum(v[m] * w, na.rm = TRUE) / sum(w)
  }, numeric(1))

  n2100 <- data.frame(bracket = bracket_names,
    SC = round(bracket_avg_nat(sc_2100 * ratio)),
    SG = round(bracket_avg_nat(sg_2100 * ratio)),
    SN = round(bracket_avg_nat(sn_2100 * ratio)),
    SI = round(bracket_avg_nat(si_2100 * ratio)))
  for (s in names(world_brackets))
    n2100[[paste0("World_", s)]] <- round(world_brackets[[s]] * ratio)

  ##### 7i. Constants #####
  avg_world2100 <- vapply(c("SC", "SG", "SN", "SI"),
    function(s) sum(n2100[[paste0("World_", s)]] * bracket_widths) / 100, 0)
  cst <- c(
    ratio = round(ratio, 6), extra_tax_rate = round(extra_tax_rate, 6),
    ref_hours = ref_hours, growth1 = growth1, growth2 = growth2,
    hours_B45k = hours_of["B45k"], hours_B = hours_of["B"],
    hours_B90k = hours_of["B90k"], hours_B120k = hours_of["B120k"],
    gdp_pc_SC_2025 = round(gdp_pc_2025, 1), gdp_pc_PI_2035 = round(gdp_pc_pi_2035, 1),
    hours_pc_SC_2035 = round(hours_pc_2035, 2), hours_pc_PI_2035 = round(hours_pc_pi_2035, 2),
    si_scale_2035 = round(si_scale_2035, 6),
    setNames(round(avg35), paste0("avg_2035_", names(avg35))),
    setNames(round(avg_world2100), paste0("avg_World2100_", names(avg_world2100))))
  names(cst) <- sub("\\.(B45k|B|B90k|B120k)$", "", names(cst)) # drop hours_of() name suffixes

  list(ineq2035 = out, ineq2100 = n2100, constants = cst,
       # scalars needed for the growth2 variant and for reporting
       b_growth1 = b_growth_10y(growth1), b_growth2 = b_growth_10y(growth2),
       prod_growth_2035 = prod_growth_2035, change_hours_pw = change_hours_pw)
}

##### 8. Run every country and bundle the outputs #####
res <- list()
for (i in seq_len(nrow(params))) {
  p <- params[i, ]
  res[[p$iso2]] <- build_country(p$iso2, p$macro_iso, p$ref_hours, p$growth1, p$growth2)
  res[[p$iso2]]$constants["ppp_rate"] <- p$ppp_rate
  message(sprintf("  %s done (ref_hours = %g, growth1 = %.1f%%, growth2 = %.1f%%, ppp_rate = %g%s)",
                  p$iso2, p$ref_hours, 100 * p$growth1, 100 * p$growth2, p$ppp_rate,
                  if (p$iso2 != p$macro_iso) paste0(", macro from ", p$macro_iso) else ""))
}

bind_country <- function(field) do.call(rbind, lapply(names(res), function(k)
  cbind(country = k, res[[k]][[field]])))

ineq_2035 <- bind_country("ineq2035")
ineq_2100 <- bind_country("ineq2100")

# Dataset 2: every B-family column scaled by the ratio of the two 10-year growth factors.
# All B columns are proportional to the B growth factor, so this is exact.
ineq2_2035 <- ineq_2035
b_cols <- grep("^B", names(ineq2_2035), value = TRUE)
for (k in names(res)) {
  m <- ineq2_2035$country == k
  k2 <- res[[k]]$b_growth2 / res[[k]]$b_growth1
  ineq2_2035[m, b_cols] <- lapply(ineq2_2035[m, b_cols], function(v) round(v * k2))
}

# Constants: one row per (country, name), plus country-invariant rows under country = "ALL"
# Values are written as text so that the numeric parameters and the two string ones (currency,
# lang) can share one file; the JS keeps a cell as a number when it parses as one, else as text.
fmt_val <- function(x) vapply(x, function(v) format(v, scientific = FALSE, digits = 15, trim = TRUE), "")
const_country <- do.call(rbind, lapply(names(res), function(k) {
  pk <- params[params$iso2 == k, ]
  rbind(data.frame(country = k, name = names(res[[k]]$constants),
                   value = fmt_val(as.numeric(res[[k]]$constants)),
                   row.names = NULL, stringsAsFactors = FALSE),
        data.frame(country = k, name = c("currency", "lang"),
                   value = c(pk$currency, unname(COUNTRY_LANG[k])), stringsAsFactors = FALSE))
}))
const_global <- data.frame(country = "ALL",
  name = c("decarb_SD", "decarb_ID", "decarb_FD",
           "temp_beef_reduction_C", "temp_flights_reduction_C",
           "temp_ps_coef_a", "temp_ps_coef_b", "temp_ps_coef_c",
           paste0("gdp_pc_GIT_", CLASSES), paste0("gdp_pc_noGIT_", CLASSES),
           paste0("coef2100_", CLASSES),
           "pop_sc_2100_B", "pop_pi_2100_B", noem_keys),
  value = c(1.00, 0.99, 0.97,
            0.24, 0.155,
            67.25, 2.06, 0.0004875,
            unname(CLASS_GDP_GIT), unname(CLASS_GDP_NOGIT), unname(CLASS_COEF_2100),
            9.41, 10.18, round(unname(noem_coefs), 8)))
const_global$value <- fmt_val(const_global$value)
constants <- rbind(const_global, const_country)

write.csv(ineq_2035, file.path(OUT_DIR, "ineq_2035.csv"), row.names = FALSE, quote = FALSE)
write.csv(ineq2_2035, file.path(OUT_DIR, "ineq2_2035.csv"), row.names = FALSE, quote = FALSE)
write.csv(ineq_2100, file.path(OUT_DIR, "ineq_2100.csv"), row.names = FALSE, quote = FALSE)
write.csv(constants, file.path(OUT_DIR, "conjoint_constants.csv"), row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ineq_2035.csv (%d rows x %d cols), ineq2_2035.csv, ineq_2100.csv (%d rows), conjoint_constants.csv (%d rows)",
                nrow(ineq_2035), ncol(ineq_2035), nrow(ineq_2100), nrow(constants)))


##### 8b. Note on translations #####
# global_survey/data/translations.csv is a hand-maintained asset (one row per key, one column per
# language) and is NOT generated here: keeping it out of R avoids quoting problems with apostrophes
# and commas in the translated text. This script only writes the country -> language mapping into
# conjoint_constants.csv (see `lang` below), so a new language is added by adding a column there.
# The same file also carries the per-COUNTRY display conventions the JS reads (fmt.money.XX =
# currency layout, fmt.locale.XX = the language whose thousands separator the country uses,
# fmt.period.XX = month or year, i.e. the period incomes are usually quoted in). Those rows fill
# the `EN` column only, since they are not language-dependent, and a new country needs one of each.

##### 9. Check that Italy coincides with questionnaire.R / IT_survey #####
# ineq_2035 (growth1 = 1.5%) must match IT_survey/data/ineq_IT_2035.csv column by column.
# ineq2_2035 uses growth2 = 3.0% where questionnaire.R used Italy's ACTUAL F0a growth
# (2.977%/yr), so a small deliberate gap is expected there.
check_italy <- function() {
  ref_file <- "IT_survey/data/ineq_IT_2035.csv"
  if (!file.exists(ref_file)) { message("IT_survey reference not found - skipping check."); return(invisible()) }
  ref <- read.csv(ref_file)
  new <- ineq_2035[ineq_2035$country == "IT", ]
  pairs <- c(IT25 = "inc25", B = "B", BG = "BG", BN = "BN", BI = "BI",
             B45kC = "B45kC", B45kG = "B45kG", B45kN = "B45kN", B45kI = "B45kI",
             B90kC = "B90kC", B90kG = "B90kG", B90kN = "B90kN", B90kI = "B90kI",
             B120kC = "B120kC", B120kG = "B120kG", B120kN = "B120kN", B120kI = "B120kI")
  cat("\n--- Italy check: questionnaire.R (IT_survey/data) vs questionnaire_global.R ---\n")
  cat(sprintf("%-10s %10s %10s %10s\n", "column", "max|diff|", "mean|diff|", "n differing"))
  for (i in seq_along(pairs)) {
    a <- ref[[names(pairs)[i]]]; b <- new[[pairs[i]]]
    d <- abs(a - b)
    cat(sprintf("%-10s %10.4f %10.4f %10d\n", names(pairs)[i], max(d), mean(d), sum(d > 0.5)))
  }
  # 2100 brackets: IT_* and World_* columns
  r100 <- read.csv("IT_survey/data/ineq_2100.csv")
  n100 <- ineq_2100[ineq_2100$country == "IT", ]
  cat("\n2100 brackets:\n")
  for (s in c("SC", "SG", "SN", "SI")) {
    d1 <- abs(r100[[paste0("IT_", s)]] - n100[[s]])
    d2 <- abs(r100[[paste0("World_", s)]] - n100[[paste0("World_", s)]])
    cat(sprintf("%-4s national max|diff| = %6.1f   World max|diff| = %6.1f\n", s, max(d1), max(d2)))
  }

  r2 <- read.csv("IT_survey/data/ineq2_IT_2035.csv")
  n2 <- ineq2_2035[ineq2_2035$country == "IT", ]
  d2 <- abs(r2$B90kC - n2$B90kC)
  cat(sprintf("\nineq2 B90kC: max|diff| = %.1f (%.3f%% of level) - expected: growth2 is 3.0%%/yr here vs %.3f%%/yr (actual F0a) in questionnaire.R\n",
              max(d2), 100 * max(d2 / r2$B90kC), 100 * (res[["IT"]]$prod_growth_2035^0.1 - 1)))
  cst <- read.csv("IT_survey/data/conjoint_constants.csv")
  it <- constants[constants$country == "IT", ]
  num <- function(x) as.numeric(x)
  cat(sprintf("ratio_IT: %.6f vs %.6f | extra_tax_rate: %.6f vs %.6f\n",
              cst$value[cst$name == "ratio_IT"], num(it$value[it$name == "ratio"]),
              cst$value[cst$name == "extra_tax_rate_IT"], num(it$value[it$name == "extra_tax_rate"])))
  cat(sprintf("IT currency = %s, lang = %s, ppp_rate = %s\n",
              it$value[it$name == "currency"], it$value[it$name == "lang"],
              it$value[it$name == "ppp_rate"]))
}
check_italy()
message("Done.")
