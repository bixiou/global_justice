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

# Non-cash components of a_pre_cap: retained earnings + imputed rent
# ──────────────────────────────────────────────────────────────────
# Two distinct components, treated separately:
#
# 1. Retained earnings: proportional to capital income a_pre_cap.
#    RE[c,g] = RETENTION_RATE · mprico[c]/NNI[c] · NNI[c] · cap_share_g[g]
#    where mprico (WID) = corporate primary income, RETENTION_RATE ≈ 0.5
#    (typical payout ratio). Fallback: median mprico/NNI ≈ 0.135.
#
# 2. Imputed rent: proportional to housing wealth, not capital income.
#    IR[c,g] = RENTAL_YIELD · NNI[c] · housing_norm[c,g]
#    where RENTAL_YIELD = 3.5 % of NNI (PSZ 2018, GGLP 2018, BCG 2022 avg)
#    and housing_norm[c,g] = shweal[c,g] · H(gp[g]) / Σ_j[shweal[c,j]·H(gp[j])·diff[j]]
#    so that Σ_g IR[c,g]·diff[g] = RENTAL_YIELD · NNI[c] exactly.
#    shweal (wealth shares) from Bothe distribution_simul.dta 2025.
#    H(gp) = net housing share of wealth at gpercentile g — empirical, France
#    2014, from Garbinti-Goupille-Lebret-Piketty 2021 (JEEA) Appendix B
#    (data/garbinti_etal_2021_wealth_compo_appB.xlsx, column sh_patfon_netXX).

RETENTION_RATE <- 0.5     # corporate dividend payout ≈ 50%, so retained ≈ 50% of mprico
RENTAL_YIELD   <- 0.035   # imputed rent ≈ 3.5% of NNI (PSZ 2018 3.5%, GGLP 2018 3.6%, BCG 2022 3.5%)

# Convert gperc index (1..127) → Bothe lower-bound (0, 1, ..., 99.999).
# Defined here because housing_norm_for (below) uses it.
gperc_to_lb <- function(g) {
  if (g <= 99) g - 1                              # 1..99   → 0,1,...,98
  else if (g <= 108) 99   + (g - 100) * 0.1       # 100..108 → 99, 99.1,...,99.8
  else if (g <= 117) 99.9 + (g - 109) * 0.01      # 109..117 → 99.9, 99.91,...,99.98
  else if (g <= 126) 99.99 + (g - 118) * 0.001    # 118..126 → 99.99, 99.991,...,99.998
  else 99.999                                     # 127      → 99.999
}

# Net housing wealth / total wealth, by wealth percentile group (France 2014,
# GGLP 2021 Appendix B). Bottom 30% has near-zero net housing (debt offsets
# property); peaks at P60-P70 (73%); declines to 10% for top 0.1%.
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

# Retained-earnings rate: RETENTION_RATE × mprico/NNI for country/region
re_rate_for <- function(entity) {
  ms <- if (!is.na(mprico_share[entity])) mprico_share[entity] else mprico_share_default
  RETENTION_RATE * if (is.na(ms)) mprico_share_default else ms
}

# Housing-wealth normalised weights for distributing imputed rent across gpercentiles.
# Returns a vector of length(gperc_idx) such that Σ_g housing_norm[g]*diff[g] = 1,
# so RENTAL_YIELD * NNI * housing_norm[g] gives per-adult imputed rent at gperc g.
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
  H   <- housing_gradient(sapply(gperc_idx, gperc_to_lb))
  den <- sum(sw * H * dif, na.rm = TRUE)
  if (den <= 0) return(rep(0, n))
  sw * H / den
}

# ── Bothe 2025 macro and ypt ──────────────────────────────────────────────
message("Reading Bothe 2025...")
simul   <- as.data.frame(read_dta("../data/Bothe/distribution_simul_extract.dta"))
macro25 <- unique(simul[simul$year == 2025, c("country","nni","gdp","cfc")])
macro25$cfc_per_cap  <- macro25$cfc * macro25$gdp
nni_2025    <- setNames(macro25$nni, macro25$country)
cfc_per_cap <- setNames(macro25$cfc_per_cap, macro25$country)

ypt_2025 <- simul[simul$year == 2025, c("country","p1","ypt")]
ypt_2025$ypt <- zero_na(ypt_2025$ypt)
wealth_dist_2025 <- simul[simul$year == 2025, c("country","p1","shweal","diff")]
wealth_dist_2025$shweal <- zero_na(wealth_dist_2025$shweal)

# ── Per-country dimensionless components ──────────────────────────────────
compute_components <- function(sub) {
  mean_nni <- sum(sub$a_pre     * sub$weight) / sum(sub$weight)
  mean_cap <- sum(sub$a_pre_cap * sub$weight) / sum(sub$weight)
  if (mean_nni <= 0) return(NULL)
  data.frame(
    gperc       = sub$gperc,
    factor_pre  = sub$a_pre        / mean_nni,
    factor_dir  = (sub$tax_dir_pit + sub$tax_dir_wea + sub$tax_cit) / mean_nni,
    factor_soc  = sub$tax_soc      / mean_nni,
    factor_ind  = sub$tax_ind      / mean_nni,
    factor_trn  = sub$gov_soc      / mean_nni,
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

  re_r   <- re_rate_for(ctry)
  h_norm <- housing_norm_for(ctry, comp$gperc)

  cash_eur <- with(comp,
    (factor_pre - factor_dir - factor_soc - factor_ind + factor_trn) * nni25
    - re_r * cap_share_g * nni25
    - RENTAL_YIELD * h_norm * nni25
    + cap_share_g * cfc25)

  ypt_c <- ypt_2025[ypt_2025$country == ctry, ]
  ypt_v <- ypt_c$ypt[match(comp$gperc, sapply(ypt_c$p1, function(x) {
    if (x < 99) round(x) + 1
    else if (x < 99.9)  100 + round((x - 99)  * 10)
    else if (x < 99.99) 109 + round((x - 99.9) * 100)
    else                118 + round((x - 99.99) * 1000)
  }))]
  ypt_v[is.na(ypt_v)] <- 0
  cash_eur <- cash_eur - ypt_v

  imputed_eur <- (re_r * comp$cap_share_g + RENTAL_YIELD * h_norm) * nni25

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
    re_r            <- re_rate_for(ctry)
    cc$base_factor  <- with(cc, factor_pre - factor_dir - factor_soc - factor_ind + factor_trn)
    cc$re_factor    <- re_r * cc$cap_share_g
    cc
  })
  pc <- do.call(rbind, pieces)
  if (is.null(pc)) return(NULL)

  agg <- aggregate(cbind(base_w = base_factor * weight,
                         re_w   = re_factor   * weight,
                         cap_w  = cap_share_g * weight,
                         w_sum  = weight) ~ gperc,
                   data = pc, FUN = sum)

  # IR uses the residual region's own Bothe shweal distribution directly
  h_norm <- housing_norm_for(rcode, agg$gperc)

  cash_eur    <- (agg$base_w/agg$w_sum - agg$re_w/agg$w_sum) * nni25 -
                 RENTAL_YIELD * h_norm * nni25 +
                 agg$cap_w/agg$w_sum * cfc25
  imputed_eur <- (agg$re_w/agg$w_sum + RENTAL_YIELD * h_norm) * nni25

  data.frame(country = rcode, gperc = agg$gperc,
             cash_income_2025 = cash_eur,
             imputed_component = imputed_eur)
}))

# ── Convert gperc index → Bothe lower-bound, export ───────────────────────
# (gperc_to_lb is defined earlier, before housing_norm_for.)
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
simul_pop <- as.data.frame(read_dta("../data/Bothe/distribution_simul_extract.dta"))
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