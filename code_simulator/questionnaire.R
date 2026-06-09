# code_simulator/questionnaire.R
# Exports for the conjoint analysis questionnaire:
#   ../distributions/ineq_IT_2035.csv      127 rows × 14 cols
#   ../distributions/ineq_2100.csv          21 rows × 21 cols
#   ../data/temp100.csv                     34+ rows × 5 cols
#   ../distributions/conjoint_constants.csv key-value constants for conjoint.js
#
# Reads raw data only (Bothe .dta/.xlsx, Chancel .xlsx, FG .dta, WID .csv) plus
# chancel_temp2100_completed.csv (pre-computed from Chancel emission output).
# Working directory assumed: code_simulator/

suppressPackageStartupMessages({ library(haven); library(readxl) })
dir.create("../distributions", showWarnings = FALSE)

CHANCEL  <- "../data/Chancel/Chanceletal2026Appendix_MacroScenarios.xlsx"
MACRO    <- "../data/Bothe/Botheetal2026AppendixMacro.xlsx"
SIMUL    <- "../data/Bothe/distribution_simul_extract.dta"
FG       <- "../data/FisherGethin/fisher-gethin-2023-slim.dta"
WID      <- "../data/WID/wid-mprico-nni.csv"
TEMP_OBS <- "../data/chancel_temp2100_completed.csv"

DECARB_FACTOR <- c(SD = 1.00, ID = 0.99, FD = 0.97)  # income cost of decarbonization at 2035
B_GROWTH_RATE <- 0.01    # yearly productivity growth of B scenarios 2025-2035 (replaces avg 2025-2100 rate)
RETENTION_RATE <- 0.50   # fraction of capital income retained (not paid out)
RENTAL_YIELD <- 0.035    # imputed rent rate on net housing wealth (PSZ/GGLP/BCG average)

##### 1. Helper functions #####

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
  yrs  <- yrs[!is.na(yrs)]
  v <- suppressWarnings(apply(body, 2, as.numeric))
  if (is.null(dim(v))) v <- matrix(v, nrow = 1)
  colnames(v) <- hdr[-1]
  df <- as.data.frame(v); rownames(df) <- as.character(yrs); df
}

# Pool (country, gpercentile) cells by income value, weight by gp_width × population,
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
  bks  <- c(0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 99.5, 99.9)
  vals <- c(0.000, 0.001, 0.016, 0.299, 0.619, 0.708, 0.732, 0.707, 0.641,
            0.540, 0.422, 0.319, 0.230, 0.102)
  vals[findInterval(gp_lb, bks)]
}

# Match Bothe simul rows (identified by p1 lower-bound) to FG gperc order (1-127 index)
match_by_gperc_index <- function(simul_rows, value_col, fg_gperc_vec) {
  simul_rows$gperc_idx <- p1_to_gperc_index(simul_rows$p1)
  simul_rows[[value_col]][match(fg_gperc_vec, simul_rows$gperc_idx)]
}

##### 2. Bothe simul: income and yp_recomp by (country, gpercentile, year) #####
message("Reading Bothe simul...")
simul <- as.data.frame(read_dta(SIMUL))
for (v in c("sdiinc", "nni", "diff", "ypt", "pop"))
  simul[[v]] <- ifelse(is.na(simul[[v]]), 0, simul[[v]])
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
inc_wide <- reshape_wide("income")     # full income (post-GIT + dividend) for all countries/years
yp_wide  <- reshape_wide("yp_recomp") # pre-GIT national secondary income

stopifnot(identical(inc_wide$country, yp_wide$country) &&
          identical(inc_wide$gpercentile, yp_wide$gpercentile))

macro_2025 <- unique(simul[simul$year == 2025, c("country", "nni", "gdp", "cfc")])
nni_2025           <- setNames(macro_2025$nni, macro_2025$country)
cfc_per_adult_2025 <- setNames(macro_2025$cfc * macro_2025$gdp, macro_2025$country)

##### 3. Populations (Z0a, Z0b) and PI-scenario per-capita-GDP growth (A0pi) #####
z0a <- read_chancel_ts("Z0a"); z0b <- read_chancel_ts("Z0b")
pop_sc_2100 <- setNames(as.numeric(z0a["2100", ]), colnames(z0a))  # SC family: GJP path
pop_pi_2100 <- setNames(as.numeric(z0b["2100", ]), colnames(z0b))  # PI family: UN medium
a0pi <- read_chancel_ts("A0pi")
growth_pi_by_country <- setNames(
  as.numeric(a0pi["2100", ]) / as.numeric(a0pi["2025", ]), colnames(a0pi))

##### 4. cash_income_2025 for Italy from Fisher-Gethin 2023 + Bothe NNI 2025 #####
message("Building IT cash_income_2025 from Fisher-Gethin...")
# Retained-earnings deduction rate for Italy
wid <- read.csv(WID)
mprico_it <- wid$mprico_share[wid$country == "IT"]
if (!length(mprico_it) || is.na(mprico_it[1]))
  mprico_it <- median(wid$mprico_share, na.rm = TRUE)
re_rate_it <- RETENTION_RATE * mprico_it[1]

fg <- as.data.frame(read_dta(FG))
fg_it <- fg[fg$year == 2023 & fg$iso == "IT", ]
for (v in c("a_pre","a_pre_cap","tax_dir_pit","tax_dir_wea","tax_cit",
            "tax_soc","tax_ind","gov_soc","weight"))
  fg_it[[v]] <- ifelse(is.na(fg_it[[v]]), 0, fg_it[[v]])
fg_it <- fg_it[order(fg_it$gperc), ]          # sort by bracket index 1-127
gp_IT <- gperc_to_lb(fg_it$gperc)             # 127 lower-bound percentiles for Italy

# Wealth shares for Italy at 2025 (needed for housing imputed rent normalization)
wealth_it_2025 <- simul[simul$year == 2025 & simul$country == "IT", c("p1","shweal","diff")]
wealth_it_2025$shweal <- ifelse(is.na(wealth_it_2025$shweal), 0, wealth_it_2025$shweal)
wealth_it_2025$gperc_idx <- p1_to_gperc_index(wealth_it_2025$p1)
sw_it  <- wealth_it_2025$shweal[match(fg_it$gperc, wealth_it_2025$gperc_idx)]
sw_it[is.na(sw_it)] <- 0
dif_it <- wealth_it_2025$diff[match(fg_it$gperc, wealth_it_2025$gperc_idx)]
dif_it[is.na(dif_it)] <- 0.01
H_it <- housing_wealth_share(gp_IT)
den_h <- sum(sw_it * H_it * dif_it, na.rm = TRUE)
housing_norm_it <- if (den_h > 0) sw_it * H_it / den_h else rep(0, nrow(fg_it))

# GIT already paid in 2025 (subtract to get cash income net of global tax)
ypt_it_2025 <- match_by_gperc_index(
  simul[simul$year == 2025 & simul$country == "IT", c("p1","ypt")], "ypt", fg_it$gperc)
ypt_it_2025[is.na(ypt_it_2025)] <- 0

mu_n <- sum(fg_it$a_pre * fg_it$weight) / sum(fg_it$weight)
mu_c <- sum(fg_it$a_pre_cap * fg_it$weight) / sum(fg_it$weight)
cap_share_it <- if (mu_c > 0) fg_it$a_pre_cap / mu_c else rep(0, nrow(fg_it))

# Cash income = pretax net of all taxes + govt transfers - imputed rent - retained earnings + CFC - GIT
it_cash_income_2025 <- enforce_monotone_below_99(
  (fg_it$a_pre / mu_n
   - (fg_it$tax_dir_pit + fg_it$tax_dir_wea + fg_it$tax_cit) / mu_n
   - fg_it$tax_soc / mu_n - fg_it$tax_ind / mu_n + fg_it$gov_soc / mu_n) * nni_2025["IT"]
  - re_rate_it * cap_share_it * nni_2025["IT"]
  - RENTAL_YIELD * housing_norm_it * nni_2025["IT"]
  + cap_share_it * cfc_per_adult_2025["IT"]
  - ypt_it_2025, gp_IT)

##### 5. ratio_IT (scalar) and per-percentile cash_ratio for Italy 2025 #####
income_it_2025 <- match_by_gperc_index(
  simul[simul$year == 2025 & simul$country == "IT", c("p1","income")], "income", fg_it$gperc)
cash_ratio_it <- ifelse(is.finite(income_it_2025) & income_it_2025 > 0,
                        it_cash_income_2025 / income_it_2025, NA_real_)
avg_cash_it_2025   <- sum(it_cash_income_2025 * gp_width(gp_IT))
avg_income_it_2025 <- sum(income_it_2025 * gp_width(gp_IT), na.rm = TRUE)
# ratio_IT ≈ 0.69: rescales 2100 full-income distributions to be comparable with cash income
ratio_IT <- avg_cash_it_2025 / avg_income_it_2025
message(sprintf("ratio_IT = %.4f  (avg cash %.0f / avg full income %.0f, IT 2025)",
                ratio_IT, avg_cash_it_2025, avg_income_it_2025))

##### 6. IT35 (SC1_SD base = gross cash income 2035) and cash_GR35 #####
# IT35: Bothe SC income at 2035, rescaled to cash units via per-percentile cash_ratio.
# This equals gross cash income under SC1_SD (slow decarb, no structural change, no extra PS tax).
income_it_2035 <- match_by_gperc_index(
  simul[simul$year == 2035 & simul$country == "IT", c("p1","income")], "income", fg_it$gperc)
it35 <- enforce_monotone_below_99(income_it_2035 * cash_ratio_it, gp_IT)

# cash_GR35[p] = (global dividend 2035 - GIT tax paid by percentile p) × cash_ratio[p]
# Positive for low incomes (net receivers), negative for high incomes (net contributors).
ypt_it_2035 <- match_by_gperc_index(
  simul[simul$year == 2035 & simul$country == "IT", c("p1","ypt")], "ypt", fg_it$gperc)
ypt_it_2035[is.na(ypt_it_2035)] <- 0
cash_gr35 <- (dividend_by_year["2035"] - ypt_it_2035) * cash_ratio_it

##### 7. Extra public-services tax rate for Italy 2035 (G5s, G0p) #####
# Flat-rate tax needed to finance the expansion of public spending from 2025 to 2035 in SC.
G5s <- read_chancel_ts("G5s"); G0p <- read_chancel_ts("G0p") # GNE shares and GNE
extra_ps_spending_share_it <- as.numeric(G5s["2035","IT"]) - as.numeric(G5s["2025","IT"])
extra_ps_eur_per_adult_it  <- extra_ps_spending_share_it * as.numeric(G0p["2035","IT"])
avg_it35 <- sum(it35 * gp_width(gp_IT), na.rm = TRUE)
it_extra_tax_rate <- extra_ps_eur_per_adult_it / avg_it35
message(sprintf("IT extra PS tax rate 2035: %.4f  (%.0f EUR / avg IT35 = %.0f EUR)",
                it_extra_tax_rate, extra_ps_eur_per_adult_it, avg_it35))

##### 8. Chancel GDP for Italy + B90k-scenario productivity parameters (F0a, E0h, E0a) #####
a0 <- read_chancel_ts("A0")
gdp_it_2025    <- as.numeric(a0["2025","IT"])   # EUR PPP 2025 per adult
gdp_it_sc_2035 <- as.numeric(a0["2035","IT"])
# Per-capita GDP (EUR PPP 2025/adult): A0p = SC scenario, A0pi = PI scenario. Used for the
# N/G-scope rescalings so GDP_PI and GDP_SC are in the same (per-capita) units. (A0 is *total*
# GDP and must not be mixed with A0pi.)
a0p <- read_chancel_ts("A0p")
gdp_pc_it_2025    <- as.numeric(a0p["2025","IT"])   # GDP_IT25 (SC per capita, 2025)
gdp_pc_it_pi_2035 <- as.numeric(a0pi["2035","IT"])  # GDP_PI0  (PI per capita, 2035)

# B90k (formerly MC, moderate convergence, 40h constant): same long-run productivity path as SC
# (converging to 125 EUR/h by 2100), but with per-worker hours fixed at their 2025 level.
f0a <- read_chancel_ts("F0a")   # hourly labour productivity (EUR/hour) by country and year
e0h <- read_chancel_ts("E0h")   # per-capita economic labour hours, SC scenario
e0k <- read_chancel_ts("E0k")   # per-capita economic labour hours, PC/PI scenarios
e0a <- read_chancel_ts("E0a")   # per-worker economic labour hours, SC scenario
prod_it_2025        <- as.numeric(f0a["2025","IT"])
prod_it_2035        <- as.numeric(f0a["2035","IT"])
hours_pc_it_2025    <- as.numeric(e0h["2025","IT"])
hours_pc_it_2035    <- as.numeric(e0h["2035","IT"])
hours_pc_it_pi_2035 <- as.numeric(e0k["2035","IT"])  # PI per-capita hours, 2035
hours_pw_it_2025    <- as.numeric(e0a["2025","IT"])
hours_pw_it_2035    <- as.numeric(e0a["2035","IT"])
avg_prod_growth_it <- (125 / prod_it_2025)^(1 / 75)           # constant annual growth to 125 EUR/h (former practice, unused)
prod_growth_2035_it  <- prod_it_2035 / prod_it_2025            # actual SC productivity growth 2025-2035
# change_hours_pc_it   <- hours_pc_it_2035 / hours_pc_it_2025   # < 1 (hours fall in SC by 2035)
change_hours_pw_it   <- hours_pw_it_2035 / hours_pw_it_2025   # per-worker hours change 2025-2035 (E0a)
# B scenarios grow at a flat 1% yearly 2025-2035 (B_GROWTH_RATE), replacing the former practice of
# using the average 2025-2100 productivity growth rate avg_prod_growth_it^10 (which front-loads SC growth).
b_growth_10y <- function(rate) (1 + rate)^10               # 10-year cumulative B-scenario growth at `rate`
# B90k is THE baseline (40h, constant per-worker hours): all other B-class 2035 incomes are B90k × (hours/40),
# where 2035 worked hours are 28/32/36/40/44 for classes 29/30/35/40/45.
# B90k income scale relative to IT35: corrects for SC's front-loaded productivity and per-worker hours change.
# Former practice: b90k_scale_it <- avg_prod_growth_it^10 / (change_hours_pw_it * prod_growth_2035_it)
b90k_scale_it <- b_growth_10y(B_GROWTH_RATE) / (change_hours_pw_it * prod_growth_2035_it)
# B (35h class) income scale: B90k × the actual SC per-worker hours change 2025-2035 (E0a), i.e.
# b_scale = (1+g)^10 / prod_growth_2035 — the 35h class is the real SC trajectory, so it uses the
# modelled per-worker hours rather than a flat ratio. Matches conjoint_world.R's b_scale_c.
# Former practice: b_scale_it <- avg_prod_growth_it^10 / prod_growth_2035_it
# Existing practice (commented out): flat 36/40 (36 worked hours in 2035 vs B90k's 40)
# b_scale_it <- (36 / 40) * b90k_scale_it
b_scale_it <- change_hours_pw_it * b90k_scale_it
# B120k (45h class) income scale: B90k × (44/40) — 44 worked hours in 2035
# Former practice: b120k_scale_it <- (45 / 40) * b90k_scale_it
b120k_scale_it <- (44 / 40) * b90k_scale_it

##### 9. ineq_IT_2035: 127 gpercentiles × 14 cols #####
# Scenario key: {type}_{sectoral_change}_{decarb} e.g. SC2_FD.
# sectoral_change=1: public services stable (no extra PS tax); sectoral_change=2: increased PS (extra tax applied).
# decarb: SD=×1.00, ID=×0.99, FD=×0.97 (income cost of decarbonization).
# Exported columns = selected scenarios: all _2_FD (sectoral_change=2, fast decarb) except IT35 (SC1_SD)
# and SCmat (SC1_FD) which have sectoral_change=1.
message("Building ineq_IT_2035...")
fd        <- DECARB_FACTOR["FD"]           # 0.96

sc45k_scale_2035 <- gdp_it_2025 / gdp_it_sc_2035        # ≈ 0.87: SC45k relative to IT35
sc30k_scale_2035 <- 0.95 * sc45k_scale_2035              # 30k target extra penalty (interpolated)
sc15k_scale_2035 <- 0.9 * sc45k_scale_2035               # 25h scenario extra penalty
# SI 2035 (method line 151): IT25 rescaled to the no-global GDP level = PI per-capita GDP
# adjusted for SC working hours: gdp_PI_2035 × (hours_pc_SC / hours_pc_PI) / gdp_2025.
si_scale_2035 <- gdp_pc_it_pi_2035 * (hours_pc_it_2035 / hours_pc_it_pi_2035) / gdp_pc_it_2025
si0_2035      <- it_cash_income_2025 * si_scale_2035
avg_si0_2035  <- sum(si0_2035 * gp_width(gp_IT), na.rm = TRUE)  # GDP_SI0 (2035)

ineq_IT_2035 <- data.frame(
  gpercentile = gp_IT,
  IT25        = it_cash_income_2025,                                      # 2025 cash income (reference)
  cash_GR35   = cash_gr35,                                                # GR net transfer at 2035 (cash units)
  IT35        = it35,                                                     # SC1_SD: base, no decarb cost, no PS tax
  SCmat       = it35 * fd,                                                # SC1_FD: FD decarb, no PS tax
  SC          = it35 * fd * (1 - it_extra_tax_rate),                                    # SC2_FD: FD decarb + PS tax
  PC          = it35 * 1.15 * fd,                                         # PC1_FD: 45h, 15% richer than SC
  PI          = it_cash_income_2025 * 1.4 * fd,                           # PI1_FD: 45h no GIT, 40% growth
  SC45k       = it35 * sc45k_scale_2035 * fd * (1 - it_extra_tax_rate),                 # SC45k2_FD: 30h + GIT
  SC15k       = it35 * sc15k_scale_2035 * fd * (1 - it_extra_tax_rate),                 # SC15k2_FD: 25h + GIT
  SI          = si0_2035 * fd * (1 - it_extra_tax_rate),                                          # SI2_FD: 35h, no redistribution
  SN          = (it35 - cash_gr35) * (avg_si0_2035 / avg_it35) * fd * (1 - it_extra_tax_rate),     # SN2_FD: national only, (IT35−GR35)×GDP_SI0/avg_SC
  SG          = (si0_2035 + cash_gr35) * (avg_it35 / avg_si0_2035) * fd * (1 - it_extra_tax_rate),  # SG2_FD: global only, (GDP_SC/GDP_SI0)×(SI0+GR35)
  B90kC       = it35 * b90k_scale_it * fd * (1 - it_extra_tax_rate),               # B90kC2_FD: 40h + GIT constant hours (formerly MC)
  B90kMat     = it35 * b90k_scale_it * fd,                                          # B90kC1_FD: 40h + GIT, no PS tax (formerly MCmat)
  Bmat        = it35 * b_scale_it * fd,                                              # B1_FD: 35h + GIT, no PS tax (B without PS)
  B120kC      = it35 * b120k_scale_it  * fd * (1 - it_extra_tax_rate),                # B120kC2_FD: 45h + GIT constant-growth (formerly WC)
  B           = it35 * b_scale_it      * fd * (1 - it_extra_tax_rate),               # B2_FD: 35h + GIT, constant-growth (formerly M60k)
  B45kC       = it35 * b90k_scale_it * (32 / 40) * fd * (1 - it_extra_tax_rate),    # B45kC2_FD: 30h class, 32 worked hours in 2035 (B90k × 32/40; formerly MC45k/SC45k analog)
  B90kC_SD    = it35 * b90k_scale_it * DECARB_FACTOR["SD"] * (1 - it_extra_tax_rate)) # B90kC2_SD: slow decarb (formerly MC_SD)

income_cols_2035 <- setdiff(names(ineq_IT_2035), "gpercentile")
# cash_GR35 is a net-transfer distribution (positive for poor, negative for rich) — not monotone.
# IT25 was already sorted during construction. Sort all remaining income columns.
cols_to_sort <- setdiff(income_cols_2035, "cash_GR35")
for (col in cols_to_sort)
  ineq_IT_2035[[col]] <- enforce_monotone_below_99(ineq_IT_2035[[col]], gp_IT)
ineq_IT_2035[, income_cols_2035] <- lapply(ineq_IT_2035[, income_cols_2035], round, digits = 0)
# ineq_IT_2035.csv (filtered export) is written after §14 when scope variants are available.

##### 10. ineq_2100: 21 brackets × 21 cols #####
# All 2100 base distributions computed in full-income units; ratio_IT applied as final step.
# SC45k/SC15k/B90kC/PC derived by scaling the SC base (same distributional shape, different GDP level).
# SI = 0.5 × PI; SN = (SC − GR) × GDP_SI0/GDP_SC. The G scope keeps the I (no-redistribution)
# shape and applies a GLOBAL taxG schedule that is a function of N income (taxG = (SN − SC)/SN, read
# off the world SN→SC distributions), evaluated at each cell's I (SI) income: SG = SI × (1 − taxG).
# GDP_SC and GDP_SI0 are gp_width-weighted means of the SC and SI (=½PI) distributions, so SN
# lands at the SI/no-global GDP level.
# World populations follow whether the scenario has global redistribution (GIT): SC/SG/B90kC/PC use
# SC pop (Z0a, Convergence); PI/SI/SN (no GIT) use PI pop (Z0b, Inequality).
message("Building ineq_2100...")
dividend_2100 <- dividend_by_year["2100"]

# IT 2100: aligned to FG gperc ordering via bracket-index matching
income_it_2100 <- match_by_gperc_index(
  simul[simul$year == 2100 & simul$country == "IT", c("p1","income")], "income", fg_it$gperc)
# PI base uses yp_recomp_2025 (pre-GIT national income): PI scenario has no global redistribution
yp_recomp_it_2025 <- match_by_gperc_index(
  simul[simul$year == 2025 & simul$country == "IT", c("p1","yp_recomp")], "yp_recomp", fg_it$gperc)
pi_it_2100_base <- yp_recomp_it_2025 * growth_pi_by_country["IT"]

# GDP_SC = avg(SC), GDP_SI0 = avg(SI0 = ½PI): gp_width-weighted means ("GDP" of each scenario).
avg_sc_it_2100  <- sum(income_it_2100 * gp_width(gp_IT), na.rm = TRUE)
avg_si0_it_2100 <- sum(0.5 * pi_it_2100_base * gp_width(gp_IT), na.rm = TRUE)

sc_it_2100 <- income_it_2100                                                       # SC (full income, post-GIT + dividend)
sn_it_2100 <- (income_it_2100 - dividend_2100) * (avg_si0_it_2100 / avg_sc_it_2100) # SN = (SC − GR) × GDP_SI0/GDP_SC
si_it_2100 <- 0.5 * pi_it_2100_base                                                # SI = half PI (no redistribution)
# sg_it_2100 (G scope) is built below, once the world-level taxG-by-income schedule exists.

# World 2100: per-country columns added to inc_wide/pi_pool, then pooled and sorted globally
# PI uses yp_recomp_2025 (pre-GIT income) since PI scenario has no global redistribution
inc_wide$pi_income_2100 <- yp_wide$yp_recomp_2025 * growth_pi_by_country[inc_wide$country]
# Per-country GDP_SC and GDP_SI0 (gp_width-weighted means) for the N/G rescalings
gw_world       <- gp_width(inc_wide$gpercentile)
avg_sc_2100_c  <- tapply(inc_wide$income_2100 * gw_world,          inc_wide$country, sum)
avg_si0_2100_c <- tapply(0.5 * inc_wide$pi_income_2100 * gw_world, inc_wide$country, sum)
inc_wide$sn_income_2100 <- yp_wide$yp_recomp_2100 *
  (avg_si0_2100_c[inc_wide$country] / avg_sc_2100_c[inc_wide$country])              # SN = (SC − GR) × GDP_SI0/GDP_SC
pi_pool <- inc_wide[, c("country","gpercentile")]
pi_pool$si_income_2100 <- 0.5 * inc_wide$pi_income_2100

world_SC <- build_world_dist(inc_wide, "income_2100",    pop_sc_2100)
world_SN <- build_world_dist(inc_wide, "sn_income_2100", pop_pi_2100)  # SN at no-global GDP level → PI pop (Z0b)
world_PI <- build_world_dist(inc_wide, "pi_income_2100", pop_pi_2100)
world_SI <- build_world_dist(pi_pool,  "si_income_2100", pop_pi_2100)

# G scope: taxG is a GLOBAL tax schedule that is a function of N (national, pre-global) INCOME, read
# off the world SN→SC distributions — at world percentile g, the N income world_SN[g] faces rate
# (SN−SC)/SN. The schedule is then evaluated at each unit's I (SI) income and applied to the SI base:
# SG = SI × (1 − taxG(SI_income)). Hence SG keeps the I shape and the identity SG = SI·(SC/SN) holds at
# the WORLD level but NOT within IT (IT borrows the global N-income→rate map, read at its I income).
taxg_rate <- ifelse(world_SN > 0, (world_SN - world_SC) / world_SN, 0)             # rate as a function of N income world_SN[g]
taxg_at   <- function(income) approx(world_SN, taxg_rate, xout = income, rule = 2, ties = mean)$y  # domain = N income
sg_it_2100 <- si_it_2100 * (1 - taxg_at(si_it_2100))                               # evaluated at IT's I (SI) income
pi_pool$sg_income_2100 <- pi_pool$si_income_2100 * (1 - taxg_at(pi_pool$si_income_2100))  # at World I income
world_SG <- build_world_dist(pi_pool, "sg_income_2100", pop_sc_2100)  # SG has GIT → SC pop (Z0a)

# 2100 hours→income coefs (vs SC = 60k convergence): each hours level maps to a fixed
# 2100 GDP-per-capita target (k€), so coef = target / 60. B30k(29h)=30k→0.5, B45k(30h)=45k→0.75,
# B(35h)=60k→1.0, B90k(40h)=90k→1.5, B120k(45h)=120k→2.0. (Replaces the per-worker E0a ratio.)
B90K_COEF_2100 <- 1.5

bracket_lo <- c(seq(0, 90, 5), 95, 99); bracket_hi <- c(seq(5, 95, 5), 99, 100)
bracket_names <- paste0("p", bracket_lo, "p", bracket_hi)

# IT: weighted mean over 127-grid per bracket
bracket_avg_IT <- function(v) vapply(seq_along(bracket_lo), function(i) {
  m <- gp_IT >= bracket_lo[i] & (if (bracket_hi[i] >= 100) TRUE else gp_IT < bracket_hi[i])
  w <- gp_width(gp_IT[m]); sum(v[m] * w, na.rm = TRUE) / sum(w)
}, numeric(1))
# World: mean over equal-population 100-grid bins per bracket
bracket_avg_World <- function(v) vapply(seq_along(bracket_lo), function(i)
  mean(v[(bracket_lo[i] + 1):bracket_hi[i]], na.rm = TRUE), numeric(1))

ineq_2100 <- data.frame(bracket = bracket_names,
  IT_PI    = bracket_avg_IT(pi_it_2100_base   * ratio_IT),
  IT_PC    = bracket_avg_IT(sc_it_2100        * ratio_IT * 2.0),
  IT_SC    = bracket_avg_IT(sc_it_2100        * ratio_IT),
  IT_SCmat = bracket_avg_IT(sc_it_2100        * ratio_IT),         # = IT_SC (struct change ≠ 2100 income)
  IT_SC45k = bracket_avg_IT(sc_it_2100        * ratio_IT * 0.75),
  IT_SC15k = bracket_avg_IT(sc_it_2100        * ratio_IT * 0.25),
  IT_B90kC = bracket_avg_IT(sc_it_2100        * ratio_IT * B90K_COEF_2100),  # 40h → 90k target (1.5×SC)
  IT_SI    = bracket_avg_IT(si_it_2100        * ratio_IT),
  IT_SN    = bracket_avg_IT(sn_it_2100        * ratio_IT),
  IT_SG    = bracket_avg_IT(sg_it_2100        * ratio_IT),
  World_PI    = bracket_avg_World(world_PI    * ratio_IT),
  World_PC    = bracket_avg_World(world_SC    * ratio_IT * 2.0),
  World_SC    = bracket_avg_World(world_SC    * ratio_IT),
  World_SCmat = bracket_avg_World(world_SC    * ratio_IT),
  World_SC45k = bracket_avg_World(world_SC    * ratio_IT * 0.75),
  World_SC15k = bracket_avg_World(world_SC    * ratio_IT * 0.25),
  World_B90kC = bracket_avg_World(world_SC    * ratio_IT * B90K_COEF_2100),  # 40h → 90k target (1.5×SC)
  World_SI    = bracket_avg_World(world_SI    * ratio_IT),
  World_SN    = bracket_avg_World(world_SN    * ratio_IT),
  World_SG    = bracket_avg_World(world_SG    * ratio_IT),
  # B120k class: same coef as P (2.0) at 2100; differs from P only in 2035 income path (formerly WC)
  IT_B120kC       = bracket_avg_IT(sc_it_2100    * ratio_IT * 2.0),
  World_B120kC    = bracket_avg_World(world_SC   * ratio_IT * 2.0))

ineq_2100[, -1] <- lapply(ineq_2100[, -1], round, digits = 0)
# ineq_2100.csv (filtered export) is written after §13 when scope variants are available.

##### 11. temp100: chancel_temp2100_completed + new rows for SI/SN/SG/B90kC #####
# GDP-based no-emissions regression predicts temperature for scenario types not in Chancel data.
# SI/SN (35h, no GIT): GDP = 50k€/cap × 9.41B = 470.5 T€
# SG  (35h, GIT):      GDP = 60k€/cap × 9.41B = 564.6 T€ (same as SC)
# B90kC (40h, GIT):    GDP = 1.5 × 60 × 9.41 T€ (90k target)
message("Building temp100...")
temp_chancel <- read.csv(TEMP_OBS, na.strings = "")
obs_temp <- temp_chancel[!is.na(temp_chancel$temp_observed), ]
obs_temp$decarb <- factor(obs_temp$decarb, levels = c("FD","ID","SD"))
fit_noem_gdp <- lm(temp_observed ~ gdp * decarb + decarb:sectoral_change, data = obs_temp)
message(sprintf("No-emissions regression: adj-R2 = %.4f", summary(fit_noem_gdp)$adj.r.squared))

gdp_si_sn <- 50 * 9.41; gdp_sg <- 60 * 9.41; gdp_b90k <- B90K_COEF_2100 * 60 * 9.41
new_temp_rows <- do.call(rbind, lapply(
  list(c("SI", gdp_si_sn), c("SN", gdp_si_sn), c("SG", gdp_sg), c("B90kC", gdp_b90k)),
  function(s) expand.grid(base = s[1], gdp = as.numeric(s[2]),
    decarb = c("FD","ID","SD"), sectoral_change_code = c("1","2"), stringsAsFactors = FALSE)))
# sectoral_change_code is the 1/2 scenario-modality label (Chancel naming, e.g. SC2_FD); the
# regression predictor sectoral_change is its 0/1 dummy (name locked by chancel_temp2100_completed.csv).
new_temp_rows$scenario <- paste0(new_temp_rows$base, new_temp_rows$sectoral_change_code, "_", new_temp_rows$decarb)
new_temp_rows$sectoral_change <- as.integer(new_temp_rows$sectoral_change_code == "2")
new_temp_rows$decarb_f <- factor(new_temp_rows$decarb, levels = c("FD","ID","SD"))
new_temp_rows$temp_final <- round(predict(fit_noem_gdp,
  data.frame(gdp = new_temp_rows$gdp, decarb = new_temp_rows$decarb_f,
             sectoral_change = new_temp_rows$sectoral_change)), 1)

temp100 <- rbind(
  temp_chancel[, c("scenario","gdp","sectoral_change","decarb","temp_final")],
  new_temp_rows[, c("scenario","gdp","sectoral_change","decarb","temp_final")])
write.csv(temp100, "../data/temp100.csv", row.names = FALSE, quote = FALSE, na = "")
message(sprintf("Wrote temp100.csv  (%d rows: %d Chancel + %d new)",
                nrow(temp100), nrow(temp_chancel), nrow(new_temp_rows)))

##### 12. conjoint_constants.csv: key-value table for conjoint.js #####
message("Building conjoint_constants.csv...")

# Scenario weighted-average incomes from ineq_IT_2035 (for JS income scaling)
avg_it2035 <- setNames(
  sapply(income_cols_2035, function(col) sum(ineq_IT_2035[[col]] * gp_width(gp_IT), na.rm = TRUE)),
  income_cols_2035)

# Scenario average incomes from ineq_2100 World (population-weighted via bracket widths)
bracket_widths <- bracket_hi - bracket_lo   # sums to 100
world_cols_2100 <- grep("^World_", names(ineq_2100), value = TRUE)
avg_world2100 <- setNames(
  sapply(world_cols_2100, function(col) sum(ineq_2100[[col]] * bracket_widths) / 100),
  sub("^World_", "", world_cols_2100))
# 2100 hours coefs are fixed GDP targets (vs SC=60k): B45kC(30h)=45k→0.75, B30kC(29h)=30k→0.5.
# Exported as avg_World2100_B45kC / avg_World2100_B30kC and used by dist_2100() and the JS.
avg_world2100["B45kC"] <- avg_world2100["SC"] * 0.75
avg_world2100["B30kC"] <- avg_world2100["SC"] * 0.5

# No-emissions regression coefficients (for JS temperature computation)
noem_coefs <- coef(fit_noem_gdp)
noem_keys  <- paste0("noem_", gsub("[^a-zA-Z0-9]", "_", gsub("^_+|_+$", "",
              gsub("[(]|[)]", "", names(noem_coefs)))))

# avg_IT2035_B45kC/B30kC: add to avg_it2035 for consistent naming in constants export
# (avg_world2100["B45kC"/"B30kC"] were already added above)
avg_it2035["B45kC"] <- avg_it2035["B90kC"] * (32 / 40)   # 30h class: 32 worked hours in 2035
avg_it2035["B30kC"] <- avg_it2035["B90kC"] * (28 / 40)   # 29h class: 28 worked hours in 2035

constants <- data.frame(
  name = c(
    "ratio_IT", "extra_tax_rate_IT",
    "decarb_SD", "decarb_ID", "decarb_FD",
    "temp_beef_reduction_C", "temp_flights_reduction_C",
    "temp_ps_coef_a", "temp_ps_coef_b", "temp_ps_coef_c",
    # 2100 GDP per capita (k€/adult) by hours × global redistribution (matches Table tab:hours in conjoint.tex)
    "gdp_pc_GIT_29h","gdp_pc_GIT_30h","gdp_pc_GIT_35h","gdp_pc_GIT_40h","gdp_pc_GIT_45h",
    "gdp_pc_noGIT_29h","gdp_pc_noGIT_30h","gdp_pc_noGIT_35h","gdp_pc_noGIT_40h","gdp_pc_noGIT_45h",
    "pop_sc_2100_B", "pop_pi_2100_B",
    # SI-2035 construction inputs: per-capita GDP (A0p/A0pi), per-capita hours (E0h/E0k), derived scale
    "gdp_pc_IT_SC_2025", "gdp_pc_IT_PI_2035",
    "hours_pc_IT_SC_2035", "hours_pc_IT_PI_2035", "si_scale_2035",
    noem_keys,
    paste0("avg_IT2035_", names(avg_it2035)),
    paste0("avg_World2100_", names(avg_world2100))),
  value = c(
    round(ratio_IT, 6), round(it_extra_tax_rate, 6),
    1.00, 0.99, 0.97,
    0.24, 0.155,         # beef / flights temperature reductions (°C)
    67.25, 2.06, 0.0004875,  # PS temperature adjustment: 0.0004875*(a + b*gdp_pc)
    30, 45, 60, 90, 120,    # GIT GDP pc (k€): 29/30/35/40/45h → 30/45/60/90/120k (= income targets, Table tab:hours)
    25, 37.5, 50, 75, 100,  # no-GIT GDP pc (k€): 29/30/35/40/45h → 25/37.5/50/75/100k
    9.41, 10.18,
    round(gdp_pc_it_2025, 1), round(gdp_pc_it_pi_2035, 1),
    round(hours_pc_it_2035, 2), round(hours_pc_it_pi_2035, 2), round(si_scale_2035, 6),
    round(unname(noem_coefs), 8),
    round(unname(avg_it2035), 0),
    round(unname(avg_world2100), 0)))

write.csv(constants, "../distributions/conjoint_constants.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote conjoint_constants.csv  (%d rows)", nrow(constants)))

##### 13. ineq_2100_full.csv: ineq_2100 plus every redistribution-scope variant #####
# Scenario distribution given the underlying parameters, translated from scenarios.js
# get2100Distributions(): the 2100 bracket distribution of a scenario is its base redistribution-scope
# column (SC/SG/SN/SI for C/G/N/I) scaled by the hours coef = avg World income of the class's
# C-scenario / avg(SC). Couple, decarbonization, public services and beef/flights do NOT affect the
# 2100 distribution — only the hours class and the redistribution scope do (couple assumed FALSE).
message("Building ineq_2100_full...")
scope_base <- c("GIT-SN" = "SC", "GIT-current" = "SG", "current-SN" = "SN", "current-current" = "SI")
# hours_ccol: maps hoursPerWeek → column name for coef calculation
# hours_ccol <- c("25" = "SC15k", "30" = "SC45k", "35" = "SC", "40" = "MC", "45" = "PC")
hours_ccol <- c("29" = "SC15k", "30" = "B45kC", "35" = "SC", "40" = "B90kC", "45" = "PC")
dist_2100 <- function(region, hoursPerWeek, globalRedistribution, nationalRedistribution) {
  base <- scope_base[paste0(globalRedistribution, "-", nationalRedistribution)]
  # coef uses the ROUNDED avg World incomes, exactly as scenarios.js reads them from
  # conjoint_constants.csv (so the table reproduces the JS bit-for-bit).
  coef <- if (hoursPerWeek == 35) 1 else
    as.numeric(round(avg_world2100[hours_ccol[as.character(hoursPerWeek)]]) / round(avg_world2100["SC"]))
  ineq_2100[[paste0(region, "_", base)]] * coef
}

# All 5 hours classes × 4 scopes (C/G/N/I). Scenario name embeds the scope into the class label
# (S45k → SC45k/SG45k/…, P → PC/PG/…, B90k → B90kC/B90kG/…, S → SC/SG/…), as in method_questionnaire.md.
# hours_classes <- list(P = 45, M = 40, S = 35, S45k = 30, S15k = 25)
hours_classes <- list(P = 45, B90k = 40, S = 35, S45k = 30, S15k = 29)
scopes <- list(C = c(g = "GIT",     n = "SN"),      G = c(g = "GIT",     n = "current"),
               N = c(g = "current", n = "SN"),      I = c(g = "current", n = "current"))
scen_name <- function(cls, sc) {
  if (cls %in% c("S45k", "S15k")) paste0("S", sc, sub("^S", "", cls))
  else if (cls == "B90k") paste0("B90k", sc)
  else paste0(substr(cls, 1, 1), sc)
}

# Start from ineq_2100 (keeps the bracket column and SCmat), then (re)compute every class×scope
# distribution with the scenarios.js formula so the table coincides exactly with what the JS shows.
ineq_2100_full <- ineq_2100
for (cls in names(hours_classes)) for (sc in names(scopes)) {
  nm <- scen_name(cls, sc)
  for (region in c("IT", "World"))
    ineq_2100_full[[paste0(region, "_", nm)]] <- round(dist_2100(region, hours_classes[[cls]],
                                                                 scopes[[sc]]["g"], scopes[[sc]]["n"]))
}
# B hours sub-variants at 2100: fixed GDP-target coefs vs the scope base column (SC/SG/SN/SI):
# B45k(30h)=45k→0.75, B30k(29h)=30k→0.5, B15k(28h)=15k→0.25. (B90k(40h)=1.5 from the loop above.)
for (sc in names(scopes)) {
  base_col <- scope_base[paste0(scopes[[sc]]["g"], "-", scopes[[sc]]["n"])]  # SC/SG/SN/SI
  for (region in c("IT", "World")) {
    sd <- ineq_2100_full[[paste0(region, "_", base_col)]]
    ineq_2100_full[[paste0(region, "_B45k", sc)]] <- round(sd * 0.75)
    ineq_2100_full[[paste0(region, "_B30k", sc)]] <- round(sd * 0.5)
    ineq_2100_full[[paste0(region, "_B15k", sc)]] <- round(sd * 0.25)
  }
}
# Food variants at 2100: Bbeef/Bflights/Bmat = SC (B=SC at 2100, sectoral_change does not affect 2100 income)
# Formerly: MCbeef/MCflights/MCmat = MC at 2100
for (nm in c("Bbeef", "Bflights", "Bmat")) {
  for (region in c("IT", "World"))
    ineq_2100_full[[paste0(region, "_", nm)]] <- ineq_2100_full[[paste0(region, "_SC")]]
}
# B120k class at 2100: same as P (coef = 2) — B120k and P differ only in their 2035 income path (formerly W class)
for (sc in names(scopes)) {
  nm_p <- scen_name("P", sc)  # PC / PG / PN / PI
  nm_b120k <- paste0("B120k", sub("^P", "", nm_p))   # B120kC / B120kG / B120kN / B120kI
  for (region in c("IT", "World"))
    ineq_2100_full[[paste0(region, "_", nm_b120k)]] <- ineq_2100_full[[paste0(region, "_", nm_p)]]
}
# 2025 world cash income distribution (bracket anchor for §13 visualisation)
cash_w25 <- read.csv("../distributions/cash_income_world.csv")
cash_w25 <- cash_w25[order(cash_w25$gpercentile), "income_2025"]
ineq_2100_full[["World_cash2025"]] <- round(bracket_avg_World(cash_w25))
write.csv(ineq_2100_full, "../distributions/ineq_2100_full.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ineq_2100_full.csv  (%d rows × %d cols)", nrow(ineq_2100_full), ncol(ineq_2100_full)))

# Filtered ineq_2100.csv: selected scenarios only (B90kC_SD and Bflight = B90kC at 2100).
# EXPORT_2100 <- c("MC","SC","MCmat","MC45k","WC","WI","MI","MN","MG","MCbeef","MCflight","MC_SD")
EXPORT_2100 <- c("B90kC","SC","Bmat","B45kC","B120kC","B120kI","B90kI","B90kN","B90kG","Bbeef","Bflight","B90kC_SD")
ineq_2100_export <- data.frame(bracket = ineq_2100_full$bracket)
for (scen in EXPORT_2100) {
  src <- if (scen == "Bflight") "Bflights" else scen
  b90k_col <- if (scen == "B90kC_SD") "B90kC" else src  # B90kC_SD = B90kC at 2100; Bflight uses Bflights (= SC)
  ineq_2100_export[[paste0("IT_",    scen)]] <- ineq_2100_full[[paste0("IT_",    b90k_col)]]
  ineq_2100_export[[paste0("World_", scen)]] <- ineq_2100_full[[paste0("World_", b90k_col)]]
}
# Override with actual distinct columns where they differ from B90kC
for (scen in c("SC","B45kC","B120kC","B120kI","B90kI","B90kN","B90kG","Bbeef","Bmat")) {
  ineq_2100_export[[paste0("IT_",    scen)]] <- ineq_2100_full[[paste0("IT_",    scen)]]
  ineq_2100_export[[paste0("World_", scen)]] <- ineq_2100_full[[paste0("World_", scen)]]
}
write.csv(ineq_2100_export, "../distributions/ineq_2100.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ineq_2100.csv  (%d rows × %d cols)", nrow(ineq_2100_export), ncol(ineq_2100_export)))

##### 14. ineq_IT_2035_full.csv: ineq_IT_2035 plus every redistribution-scope variant #####
# Scenario distribution given the underlying parameters, translated from scenarios.js
# getIT2035Distribution(): each scenario column is the appropriate base column rescaled by the hours
# coef and the decarbonization/public-services (sectoral_change) factors, using the ROUNDED constants exactly as
# scenarios.js reads them. Scope variants are taken at the same sectoral_change/decarb level as the class's
# exported C column: sectoral_change=1 / PS stable for the P class (like PC/PI), sectoral_change=2 / PS increased otherwise.
message("Building ineq_IT_2035_full...")
avg_it35r   <- round(avg_it2035)                 # rounded avg incomes (as in conjoint_constants.csv)
ps_exported <- 1 - round(it_extra_tax_rate, 6)   # PS factor baked into sectoral_change=2 columns
# sectoral_change2_cols: columns exported at sectoral_change=2 (carry PS tax)
sectoral_change2_cols  <- c("SC", "SC45k", "SC15k", "SI", "SN", "SG", "B90kC", "B45kC", "B120kC", "B90kC_SD", "B", "B15kC", "B30kC")
dist_2035 <- function(hoursPerWeek, globalRedistribution, nationalRedistribution, decarbonization, publicServices) {
  hasGIT <- globalRedistribution == "GIT"; hasNat <- nationalRedistribution == "SN"; redistScale <- 1
  if (hoursPerWeek == 45) {
    if (hasGIT && hasNat)        { colName <- "PC" }
    else if (!hasGIT && !hasNat) { colName <- "PI" }
    else if (hasGIT && !hasNat)  { colName <- "SG"; redistScale <- avg_it35r["PC"] / avg_it35r["SC"] }
    else                         { colName <- "SN"; redistScale <- avg_it35r["PI"] / avg_it35r["SN"] }
  } else if (hoursPerWeek == 35) {
    colName <- if (hasGIT && hasNat) "SC" else if (hasGIT && !hasNat) "SG" else if (!hasGIT && hasNat) "SN" else "SI"
  } else {
    cCol  <- unname(c("29" = "SC15k", "30" = "B45kC", "40" = "B90kC")[as.character(hoursPerWeek)])
    coefC <- avg_it35r[cCol] / avg_it35r["SC"]
    if (hasGIT && hasNat)        { colName <- cCol }
    else if (hasGIT && !hasNat)  { colName <- "SG"; redistScale <- coefC }
    else if (!hasGIT && hasNat)  { colName <- "SN"; redistScale <- coefC * avg_it35r["SI"] / avg_it35r["SN"] }
    else                         { colName <- "SI"; redistScale <- coefC }
  }
  exportedPsFactor <- if (colName %in% sectoral_change2_cols) ps_exported else 1
  decarbRatio <- as.numeric(DECARB_FACTOR[decarbonization] / DECARB_FACTOR["FD"])
  psUser <- if (publicServices == "increased") ps_exported else 1
  ineq_IT_2035[[colName]] * decarbRatio * (psUser / exportedPsFactor) * as.numeric(redistScale)
}

ineq_IT_2035_full <- ineq_IT_2035[, c("gpercentile", "IT25", "cash_GR35", "IT35", "SCmat", "B90kMat")]
# Also add B90kC_SD (standalone slow decarb), Bmat (B without PS), and rename/add columns
ineq_IT_2035_full[["B90kC_SD"]] <- round(ineq_IT_2035[["B90kC_SD"]])
ineq_IT_2035_full[["Bmat"]] <- round(ineq_IT_2035[["Bmat"]])
for (cls in names(hours_classes)) for (sc in names(scopes)) {
  ps <- if (cls == "P") "stable" else "increased"   # match the class's exported sectoral_change level
  ineq_IT_2035_full[[scen_name(cls, sc)]] <-
    round(dist_2035(hours_classes[[cls]], scopes[[sc]]["g"], scopes[[sc]]["n"], "FD", ps))
}
# B120k class: B120kC from base column; B120kG/B120kN/B120kI = B90k{scope} × (44/40) (45h class, 44 worked hours in 2035)
ineq_IT_2035_full[["B120kC"]] <- round(ineq_IT_2035[["B120kC"]])
for (sl in c("G", "N", "I"))
  ineq_IT_2035_full[[paste0("B120k", sl)]] <- round(ineq_IT_2035_full[[paste0("B90k", sl)]] * (44 / 40))
# B90k hours sub-variants: B{sl}{xxk} = B90k{sl} × (worked_hours / 40)
# 2035 worked hours: B45k(30h class)=32, B30k(29h class)=28, B15k(28h class)=24.
for (sl in c("C", "G", "N", "I")) {
  ineq_IT_2035_full[[paste0("B45k", sl)]] <- round(ineq_IT_2035_full[[paste0("B90k", sl)]] * (32 / 40))
  ineq_IT_2035_full[[paste0("B30k", sl)]] <- round(ineq_IT_2035_full[[paste0("B90k", sl)]] * (28 / 40))
  ineq_IT_2035_full[[paste0("B15k", sl)]] <- round(ineq_IT_2035_full[[paste0("B90k", sl)]] * (24 / 40))
}
# B: S-shape with constant-growth productivity (corrects SC front-loading); C scope from base col (formerly M60k)
ineq_IT_2035_full[["B"]] <- round(ineq_IT_2035[["B"]])
for (sl in c("G", "N", "I"))
  ineq_IT_2035_full[[paste0("B", sl)]] <- round(ineq_IT_2035_full[[paste0("S", sl)]] * b_scale_it)
# Bbeef/Bflights: sectoral_change=2 income at 2035 = B (not B90kC); B90kMat already in initial columns.
ineq_IT_2035_full[["Bbeef"]]    <- ineq_IT_2035_full[["B"]]  # B = 35h constant-growth
ineq_IT_2035_full[["Bflights"]] <- ineq_IT_2035_full[["B"]]
write.csv(ineq_IT_2035_full, "../distributions/ineq_IT_2035_full.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ineq_IT_2035_full.csv  (%d rows × %d cols)", nrow(ineq_IT_2035_full), ncol(ineq_IT_2035_full)))

# Filtered ineq_IT_2035.csv: selected scenarios + IT25 + GR35.
it2035_export <- data.frame(
  gpercentile = ineq_IT_2035$gpercentile,
  IT25        = ineq_IT_2035$IT25,
  cash_GR35   = ineq_IT_2035$cash_GR35,
  B90kC       = ineq_IT_2035$B90kC,
  SC          = ineq_IT_2035$SC,
  B90kMat     = ineq_IT_2035$B90kMat,
  Bmat        = ineq_IT_2035$Bmat,
  B45kC       = ineq_IT_2035_full$B45kC,
  B120kC      = ineq_IT_2035$B120kC,
  B90kI       = ineq_IT_2035_full$B90kI,
  B90kN       = ineq_IT_2035_full$B90kN,
  B90kG       = ineq_IT_2035_full$B90kG,
  B           = ineq_IT_2035$B,
  BG          = ineq_IT_2035_full$BG,
  BN          = ineq_IT_2035_full$BN,
  BI          = ineq_IT_2035_full$BI,
  Bbeef       = ineq_IT_2035$B,
  Bflight     = ineq_IT_2035$B,
  B90kC_SD    = ineq_IT_2035$B90kC_SD)
write.csv(it2035_export, "../distributions/ineq_IT_2035.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ineq_IT_2035.csv  (%d rows × %d cols)", nrow(it2035_export), ncol(it2035_export)))

##### 14b. ineq2_IT_2035: B scenarios at 2% yearly growth 2025-2035 (instead of 1%) #####
# Every B-class column is exactly proportional to the 10-year B growth factor b_growth_10y(rate)
# (all B-family columns are B90k × constant, and B90k ∝ b_growth_10y). So the 2% variant is obtained
# by scaling all B-named columns by k2 = b_growth_10y(0.02) / b_growth_10y(0.01). Non-B columns
# (IT25, cash_GR35, IT35, SC*, PC, PI, SI, SN, SG) are unaffected.
message("Building ineq2_IT_2035 (B scenarios at 2% growth)...")
k2 <- b_growth_10y(0.02) / b_growth_10y(B_GROWTH_RATE)
b_cols_full <- grep("^B", names(ineq_IT_2035_full), value = TRUE)
ineq2_IT_2035_full <- ineq_IT_2035_full
ineq2_IT_2035_full[b_cols_full] <- lapply(ineq2_IT_2035_full[b_cols_full], function(v) round(v * k2))
write.csv(ineq2_IT_2035_full, "../distributions/ineq2_IT_2035_full.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ineq2_IT_2035_full.csv  (%d rows × %d cols)", nrow(ineq2_IT_2035_full), ncol(ineq2_IT_2035_full)))
b_cols_exp <- grep("^B", names(it2035_export), value = TRUE)
ineq2_export <- it2035_export
ineq2_export[b_cols_exp] <- lapply(ineq2_export[b_cols_exp], function(v) round(v * k2))
write.csv(ineq2_export, "../distributions/ineq2_IT_2035.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ineq2_IT_2035.csv  (%d rows × %d cols)", nrow(ineq2_export), ncol(ineq2_export)))

# Web-served copies for the conjoint JS (scenarios.js fetches ineq_IT_2035.csv, ineq_2100_full.csv and
# conjoint_constants.csv from code_simulator/data/). The _full files are copied too for convenience.
dir.create("data", showWarnings = FALSE)
for (f in c("ineq_IT_2035.csv", "ineq_IT_2035_full.csv", "ineq2_IT_2035.csv", "ineq2_IT_2035_full.csv",
            "ineq_2100.csv", "ineq_2100_full.csv", "conjoint_constants.csv"))
  file.copy(file.path("../distributions", f), file.path("data", f), overwrite = TRUE)
message("Copied conjoint CSVs to data/ for the web pages.")

# Self-contained, column-trimmed copies for the IT survey pages (conjoint_any/any2/few fetch from
# IT_survey/data/ via the vendored IT_survey/scenarios.js). Only the columns that scenarios.js
# actually reads are kept, and "_full" is dropped from the file names.
dir.create("IT_survey/data", recursive = TRUE, showWarnings = FALSE)
it2035_keep <- c("gpercentile", "IT25", "SG", "SN", "SI",
                 "B", "BG", "BN", "BI", "B45kC", "B90kC", "B120kC")   # getIT2035Distribution (30/35/40/45h, B-family) + IT25 lookup
ineq2100_keep <- c("bracket", paste0("IT_", c("SC","SG","SN","SI")),
                   paste0("World_", c("SC","SG","SN","SI")))         # get2100Distributions (SC/SG/SN/SI scopes)
write.csv(ineq_IT_2035_full[, it2035_keep],  "IT_survey/data/ineq_IT_2035.csv",  row.names = FALSE, quote = FALSE)
write.csv(ineq2_IT_2035_full[, it2035_keep], "IT_survey/data/ineq2_IT_2035.csv", row.names = FALSE, quote = FALSE)
write.csv(ineq_2100_full[, ineq2100_keep],   "IT_survey/data/ineq_2100.csv",     row.names = FALSE, quote = FALSE)
# Constants: drop the B30kC rows (the 29h class is unused by the IT survey).
write.csv(constants[!grepl("B30kC", constants$name), ], "IT_survey/data/conjoint_constants.csv",
          row.names = FALSE, quote = FALSE)
message("Wrote trimmed conjoint CSVs to IT_survey/data/ (self-contained survey).")
message("Done.")
