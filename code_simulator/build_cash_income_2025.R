# code_simulator/build_cash_income_2025.R
#
# Produce data/cash_income_2025.csv: per-capita "cash purchasing-power after
# all taxes" income by country × gpercentile for 2025, in EUR PPP 2025/year.
#
# Method (dimensionless-factor approach)
# --------------------------------------
# For each (country c, gpercentile g) we compute a dimensionless factor —
# i.e. a share of country NNI — from FG 2023 and multiply by Bothe's 2025
# NNI per capita to get an EUR-PPP-2025 value:
#
#   factor[c,g] = (a_pre[c,g] − tax_dir[c,g] − tax_soc[c,g] − tax_ind[c,g]
#                 + gov_soc[c,g] − imputed_frac[c] · a_pre_cap[c,g]) / mean_FG[c]
#               + (a_pre_cap[c,g] / mean_cap_FG[c]) · cfc_per_cap_Bothe[c] / NNI_Bothe[c]
#
# Note: we use only gov_soc (cash social transfers: pensions, UI, family benefits),
# NOT gov_oth ("Other Government Expenditure" in FG = imputed collective consumption,
# allocated proportional to consumption — defense, justice, infrastructure, etc.
# See FG 2025 Appendix B.6 "Other Government Expenditure Distributed as a Lump Sum").
# Including gov_oth would double-count non-cash imputed components on top of the
# 0.33 imputed-rent + retained-earnings adjustment.
#
#   cash_income[c,g] = factor[c,g] · NNI_Bothe_2025[c] − ypt_Bothe_2025[c,g]
#
# Why dimensionless: the FG components are in 2023 LCU. Dividing by FG's own
# country mean (in the same LCU) gives a unit-free ratio. Multiplying by
# Bothe's 2025 NNI per capita (EUR PPP 2025) puts the result in EUR PPP 2025
# without needing an explicit LCU→EUR-PPP conversion.
#
# Aggregate-consistency check (see README "Verification" section): with this
# construction the country-aggregate cash income equals
#   Bothe NNI 2025 × (1 − net-wedge),
# where the net wedge is the FG-derived ratio
#   (taxes − transfers + 0.33·a_pre_cap − cap_share·cfc) / NNI,
# all computed at the FG country aggregate. So country-level totals match
# Bothe exactly up to that wedge. The distribution shape at each percentile
# is FG's (which differs slightly from Bothe's at extreme tails — see README
# for details).
#
# 0.33 imputed-rent + retained-earnings fraction: average across PSZ 2018
# (US), GGLP 2018 (FR), BCG 2022 (EU pooled), BFPJZ 2024 (world). See README.
#
# Residual WID regions: dimensionless factor approach extended via
# population-weighting across FG-covered constituent countries of each WID
# region, then scaled by Bothe's NNI for the region.

suppressPackageStartupMessages({library(haven)})

# Country-specific "imputed fraction of capital income"
# ─────────────────────────────────────────────────────
# Per country c, the share of capital income that is *imputed* (not received
# as cash by the household) is the sum of:
#   • Retained-earnings share of NNI ≈ RETENTION_RATE · mprico[c] / NNI[c]
#     where mprico is corporate primary income (WID) and RETENTION_RATE ≈ 0.5
#     reflects a typical dividend payout ratio (~50%).
#   • Imputed-rent share of NNI = IMPUTED_RENT_SHARE_NNI ≈ 4 % (PSZ 2018,
#     GGLP 2018 averages).
#
# Divide by the country's capital share of NNI (from FG) to express this as a
# fraction of a_pre_cap, the form the formula consumes:
#
#   imputed_frac[c] = (RETENTION_RATE · mprico[c]/NNI[c] + IMPUTED_RENT_SHARE_NNI)
#                     / capital_share_FG[c]
#
# For countries without WID mprico (20 of 48 mainly EM/LIC), fallback to the
# median mprico/NNI across the 28 countries we do have (~0.135). The result is
# capped at [0.10, 0.60] to avoid extreme values.
#
# The uniform 0.33 was the previous default (PSZ 2018 US value); per-country
# variation around it is ±0.10 typically. See README "Comparison with the WID
# Comparator methodology" for full derivation.

RETENTION_RATE          <- 0.5     # share of corporate primary income retained
IMPUTED_RENT_SHARE_NNI  <- 0.04    # owner-occupied imputed rent (~ 4% of NNI)
IMPUTED_FRAC_FLOOR      <- 0.10
IMPUTED_FRAC_CEILING    <- 0.60
IMPUTED_FRAC_FALLBACK   <- 0.33    # used when neither WID nor capital share is computable

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
  OC = setdiff(WEUR, main_countries),
  QM = EEUR,
  OH = setdiff(NAOC, main_countries),
  OD = setdiff(LATA, main_countries),
  OE = setdiff(MENA, main_countries),
  OJ = setdiff(SSAF, main_countries),
  OA = setdiff(RUCA, main_countries),
  OB = setdiff(EASA, main_countries),
  OI = setdiff(SSEA, main_countries))

# ── FG 2023 (slim if available, full otherwise) ───────────────────────────
fg_path <- "../data/FisherGethin/fisher-gethin-2023-slim.dta"
if (!file.exists(fg_path)) fg_path <- "../data/FisherGethin/fisher-gethin-redistribution.dta"
message("Reading FG: ", fg_path)
fg <- as.data.frame(read_dta(fg_path))
if ("year" %in% names(fg)) fg <- fg[fg$year == 2023, ]

zero_na <- function(x) ifelse(is.na(x), 0, x)
for (v in c("a_pre","a_pre_cap","mean","tax_dir_pit","tax_dir_wea","tax_cit","tax_soc","tax_ind",
            "gov_soc","gov_oth","weight"))
  fg[[v]] <- zero_na(fg[[v]])

# WID mprico/NNI (= corporate primary income / NNI) per country, latest year ≤ 2023
wid_path <- "../data/WID/wid-mprico-nni.csv"
mprico_share <- if (file.exists(wid_path)) {
  w <- read.csv(wid_path)
  setNames(w$mprico_share, w$country)
} else {
  warning("WID mprico file not found at ", wid_path, "; falling back to uniform 0.33")
  numeric(0)
}
# Fallback for missing countries: median across available
mprico_share_default <- if (length(mprico_share) > 0) median(mprico_share) else NA_real_

# Country capital share of NNI (FG-derived)
cap_share_fg <- aggregate(cbind(cap_w = a_pre_cap * weight, pre_w = a_pre * weight) ~ iso,
                          data = fg, FUN = sum)
cap_share_fg$cap_share <- cap_share_fg$cap_w / cap_share_fg$pre_w
cap_share_country <- setNames(cap_share_fg$cap_share, cap_share_fg$iso)

# Imputed fraction of capital income, country-specific
imputed_frac_country <- function(ctry) {
  ms <- if (!is.na(mprico_share[ctry])) mprico_share[ctry] else mprico_share_default
  cs <- cap_share_country[ctry]
  if (is.na(ms) || is.na(cs) || cs <= 0) return(IMPUTED_FRAC_FALLBACK)
  frac <- (RETENTION_RATE * ms + IMPUTED_RENT_SHARE_NNI) / cs
  pmin(pmax(frac, IMPUTED_FRAC_FLOOR), IMPUTED_FRAC_CEILING)
}

# ── Bothe 2025 macro and ypt ──────────────────────────────────────────────
message("Reading Bothe 2025...")
simul   <- as.data.frame(read_dta("../data/Bothe/distribution_simul.dta"))
macro25 <- unique(simul[simul$year == 2025, c("country","nni","gdp","cfc")])
macro25$cfc_per_cap  <- macro25$cfc * macro25$gdp
nni_2025    <- setNames(macro25$nni, macro25$country)
cfc_per_cap <- setNames(macro25$cfc_per_cap, macro25$country)

ypt_2025 <- simul[simul$year == 2025, c("country","p1","ypt")]
ypt_2025$ypt <- zero_na(ypt_2025$ypt)

# ── Per-country dimensionless components ──────────────────────────────────
compute_components <- function(sub) {
  mean_nni <- sum(sub$a_pre     * sub$weight) / sum(sub$weight)
  mean_cap <- sum(sub$a_pre_cap * sub$weight) / sum(sub$weight)
  if (mean_nni <= 0) return(NULL)
  data.frame(
    gperc       = sub$gperc,
    factor_pre  = sub$a_pre        / mean_nni,
    factor_cap  = sub$a_pre_cap    / mean_nni,
    factor_dir  = (sub$tax_dir_pit + sub$tax_dir_wea + sub$tax_cit) / mean_nni,
    factor_soc  = sub$tax_soc      / mean_nni,
    factor_ind  = sub$tax_ind      / mean_nni,
    factor_trn  = sub$gov_soc / mean_nni,
    cap_share_g = if (mean_cap > 0) sub$a_pre_cap / mean_cap else rep(0, nrow(sub)),
    weight      = sub$weight)
}

# ── 48 main countries ─────────────────────────────────────────────────────
message("Computing 48 main countries...")
main_rows <- do.call(rbind, lapply(main_countries, function(ctry) {
  sub <- fg[fg$iso == ctry, ]
  if (nrow(sub) == 0) { warning("FG missing for ", ctry); return(NULL) }
  comp <- compute_components(sub)
  if (is.null(comp)) return(NULL)
  nni25 <- nni_2025[ctry];   cfc25 <- cfc_per_cap[ctry]
  if (is.na(nni25) || is.na(cfc25)) { warning("Bothe macro missing for ", ctry); return(NULL) }

  imp_frac <- imputed_frac_country(ctry)
  cash_factor <- with(comp,
    factor_pre - factor_dir - factor_soc - factor_ind +
    factor_trn - imp_frac * factor_cap)
  cash_eur <- cash_factor * nni25 + comp$cap_share_g * cfc25

  ypt_c <- ypt_2025[ypt_2025$country == ctry, ]
  ypt_v <- ypt_c$ypt[match(comp$gperc, sapply(ypt_c$p1, function(x) {
    if (x < 99) round(x) + 1
    else if (x < 99.9)  100 + round((x - 99)  * 10)
    else if (x < 99.99) 109 + round((x - 99.9) * 100)
    else                118 + round((x - 99.99) * 1000)
  }))]
  ypt_v[is.na(ypt_v)] <- 0
  cash_eur <- cash_eur - ypt_v

  # imputed component (added back in imputed_income_2025.csv)
  imputed_eur <- imp_frac * comp$factor_cap * nni25

  data.frame(country = ctry, gperc = comp$gperc,
             cash_income_2025 = cash_eur,
             imputed_component = imputed_eur)
}))

# ── 9 residual regions ────────────────────────────────────────────────────
message("Computing 9 residual regions...")
residual_rows <- do.call(rbind, lapply(names(residual_def), function(rcode) {
  isos <- intersect(residual_def[[rcode]], unique(fg$iso))
  if (length(isos) == 0) { warning("region ", rcode, " has no FG cs"); return(NULL) }
  nni25 <- nni_2025[rcode];   cfc25 <- cfc_per_cap[rcode]
  if (is.na(nni25) || is.na(cfc25)) { warning("Bothe macro missing for ", rcode); return(NULL) }

  pieces <- lapply(isos, function(ctry) {
    sub <- fg[fg$iso == ctry, ]
    cc  <- compute_components(sub)
    if (is.null(cc)) return(NULL)
    imp_frac <- imputed_frac_country(ctry)
    cc$cash_factor   <- with(cc,
      factor_pre - factor_dir - factor_soc - factor_ind +
      factor_trn - imp_frac * factor_cap)
    cc$imputed_factor <- imp_frac * cc$factor_cap
    cc
  })
  pc <- do.call(rbind, pieces)
  if (is.null(pc)) return(NULL)

  agg <- aggregate(cbind(cash_w = cash_factor * weight,
                         imp_w  = imputed_factor * weight,
                         w_sum  = weight,
                         cap_w  = cap_share_g * weight) ~ gperc,
                   data = pc, FUN = sum)
  agg$cash_factor_avg <- agg$cash_w / agg$w_sum
  agg$imp_factor_avg  <- agg$imp_w  / agg$w_sum
  agg$cap_share_avg   <- agg$cap_w  / agg$w_sum

  cash_eur    <- agg$cash_factor_avg * nni25 + agg$cap_share_avg * cfc25
  imputed_eur <- agg$imp_factor_avg  * nni25
  data.frame(country = rcode, gperc = agg$gperc,
             cash_income_2025 = cash_eur,
             imputed_component = imputed_eur)
}))

# ── Convert gperc index → Bothe lower-bound, export ───────────────────────
gperc_to_lb <- function(g) {
  if (g <= 99) g - 1                              # 1..99   → 0,1,...,98
  else if (g <= 108) 99   + (g - 100) * 0.1       # 100..108 → 99, 99.1,...,99.8
  else if (g <= 117) 99.9 + (g - 109) * 0.01      # 109..117 → 99.9, 99.91,...,99.98
  else if (g <= 126) 99.99 + (g - 118) * 0.001    # 118..126 → 99.99, 99.991,...,99.998
  else 99.999                                     # 127      → 99.999
}
all_rows <- rbind(main_rows, residual_rows)
all_rows$gpercentile <- sapply(all_rows$gperc, gperc_to_lb)
all_rows <- all_rows[order(all_rows$country, all_rows$gpercentile), ]

# Enforce monotonicity on bottom 99 percentiles per country: the raw FG data
# has local non-monotonicities at decile boundaries (e.g. IT g=10, g=20). We
# sort the values at gpercentile < 99 ascending within each country, keeping
# the gpercentile labels and the top-1% breakdown untouched. `tied_cols` are
# reordered on the same permutation as `value_cols[1]` so paired columns
# stay aligned; remaining `value_cols` are sorted independently.
sort_bottom99 <- function(d, value_cols, tied_cols = character(),
                          p_col = "gpercentile", country_col = "country") {
  for (ctry in unique(d[[country_col]])) {
    r <- which(d[[country_col]] == ctry & d[[p_col]] < 99)
    for (vc in value_cols) {
      ord <- order(d[r, vc], na.last = TRUE)
      d[r, vc] <- d[r, vc][ord]
      if (vc == value_cols[1])
        for (tc in tied_cols) d[r, tc] <- d[r, tc][ord]
    }
  }
  d
}
all_rows <- sort_bottom99(all_rows, "cash_income_2025",
                          tied_cols = "imputed_component")

# (1) cash_income_2025.csv (income values rounded to integer EUR)
out <- all_rows[, c("country","gpercentile","cash_income_2025")]
out$cash_income_2025 <- round(out$cash_income_2025, 0)
write.csv(out, "../data/cash_income_2025.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote data/cash_income_2025.csv: %d rows (%d countries)",
                nrow(out), length(unique(out$country))))

# (2) imputed_income_2025.csv  =  cash_income_2025  +  imputed_frac · a_pre_cap
all_rows$imputed_income_2025 <- all_rows$cash_income_2025 + all_rows$imputed_component
out_imp <- all_rows[, c("country","gpercentile","imputed_income_2025")]
out_imp$imputed_income_2025 <- round(out_imp$imputed_income_2025, 0)
write.csv(out_imp, "../data/imputed_income_2025.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote data/imputed_income_2025.csv: %d rows", nrow(out_imp)))

# (3) cash_income.csv  — time series 2025–2100, anchored to Bothe SC projection
#     cash[c,p,t] = cash_income_2025[c,p] × (income_post_GIT[c,p,t] / income_post_GIT[c,p,2025])
#     Uses Bothe SC inequality dynamics through income.csv (post-GIT, all years).
message("Building cash_income.csv time series 2025-2100...")
# Prefer income.csv if regenerated via prepare_data.R, else fall back to
# income_full_revenues.csv (same 57 territories, post-GIT with full GJF revenue
# distributed). Either captures the Bothe SC scenario inequality dynamics.
post_GIT_path <- if (file.exists("../data/income.csv")) "../data/income.csv" else "../data/income_full_revenues.csv"
message("Reading post-GIT income from: ", post_GIT_path)
inc_post_GIT <- read.csv(post_GIT_path, check.names = FALSE)
yr_cols <- grep("^income_", colnames(inc_post_GIT), value = TRUE)
yrs     <- as.integer(sub("income_", "", yr_cols))

# Join cash_income_2025 onto income.csv by (country, gpercentile)
inc_post_GIT$cash_2025 <- all_rows$cash_income_2025[match(
  paste(inc_post_GIT$country, inc_post_GIT$gpercentile),
  paste(all_rows$country,      all_rows$gpercentile))]

# Compute ratio cash_2025 / income_2025 (post-GIT); guard against zero/NA
inc_post_GIT$ratio <- with(inc_post_GIT,
  ifelse(is.finite(income_2025) & income_2025 > 0,
         cash_2025 / income_2025, NA_real_))

# Apply ratio to all year columns
for (col in yr_cols) {
  inc_post_GIT[[col]] <- inc_post_GIT[[col]] * inc_post_GIT$ratio
}

# Drop countries where no cash_income_2025 was computed
inc_post_GIT <- inc_post_GIT[!is.na(inc_post_GIT$ratio), ]

ts_out <- inc_post_GIT[, c("country","gpercentile", yr_cols)]
# Re-sort bottom 99 percentiles per (country, year) — the cash-2025 anchor
# was already sorted, but multiplying by income.csv ratios can re-introduce
# small local crossings if income.csv ratios are non-monotone across percentiles.
ts_out <- sort_bottom99(ts_out, yr_cols)
ts_out[, yr_cols] <- lapply(ts_out[, yr_cols], round, digits = 0)
write.csv(ts_out, "../data/cash_income.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote data/cash_income.csv: %d rows × %d cols", nrow(ts_out), ncol(ts_out)))

# (4) cash_income_world.csv  — global distribution at 100 percentile ranks × DIST_YEARS
#     Pool the country×gperc cells (weighted by gperc width × country population),
#     sort by income, derive 100 g-percentile cutpoints by cumulative population share.
message("Building cash_income_world.csv (global distribution)...")
DIST_YEARS <- c(2025, 2030, 2035, 2050, 2080, 2100)

# Get country populations from Bothe simul for each year
suppressPackageStartupMessages(library(haven))
simul_pop <- as.data.frame(read_dta("../data/Bothe/distribution_simul.dta"))
simul_pop <- unique(simul_pop[, c("country","year","pop")])

# gpercentile width (within-country share of population)
gp_width <- function(gp) {
  if (gp < 99)       0.01
  else if (gp < 99.9)  0.001
  else if (gp < 99.99) 0.0001
  else                 0.00001
}
ts_out$width <- sapply(ts_out$gpercentile, gp_width)

world_dist <- lapply(DIST_YEARS, function(yr) {
  col <- paste0("income_", yr)
  if (!col %in% names(ts_out)) return(NULL)
  pop_yr <- setNames(simul_pop$pop[simul_pop$year == yr], simul_pop$country[simul_pop$year == yr])
  d <- data.frame(income = ts_out[[col]],
                  weight = ts_out$width * pop_yr[ts_out$country])
  d <- d[!is.na(d$income) & d$income > 0 & !is.na(d$weight) & d$weight > 0, ]
  d <- d[order(d$income), ]
  W       <- sum(d$weight)
  d$cw_hi <- cumsum(d$weight) / W
  d$cw_lo <- c(0, head(d$cw_hi, -1))
  # Overlap-based binning: a cell that spans more than one bin contributes
  # to each bin in proportion to its cw-overlap, so no bin is ever empty.
  bin_lo <- (0:99) / 100; bin_hi <- (1:100) / 100
  out <- vapply(1:100, function(p) {
    ov <- pmax(0, pmin(d$cw_hi, bin_hi[p]) - pmax(d$cw_lo, bin_lo[p]))
    s  <- sum(ov)
    if (s > 0) sum(d$income * ov) / s else NA_real_
  }, numeric(1))
  if (any(is.na(out))) {
    ok <- which(!is.na(out))
    if (length(ok) >= 2) out <- approx(ok, out[ok], xout = 1:100, rule = 2)$y
  }
  out
})
names(world_dist) <- paste0("income_", DIST_YEARS)
world_df <- data.frame(gpercentile = 1:100, world_dist, check.names = FALSE)
wld_inc_cols <- grep("^income_", names(world_df), value = TRUE)
world_df[, wld_inc_cols] <- lapply(world_df[, wld_inc_cols], round, digits = 0)
write.csv(world_df, "../data/cash_income_world.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote data/cash_income_world.csv: 100 rows × %d cols", ncol(world_df)))
# TODO! add SI? Change scenarios?