# code_simulator/conjoint_world.R
# Exports, for all countries/regions:
#   ../distributions/ineq_2035_full.csv         (country, gpercentile, income25, cash_GR35,
#                                                 income35, and all 44 scenario cols)
#   ../distributions/ineq_2100_countries.csv    (bracket, country, SC, SG, SN, SI)
#   ../distributions/conjoint_world_constants.csv (country, extra_tax_rate, ratio)
# Reproduces questionnaire.R §4-9, §14 generalised to every Bothe simul country.
# Working directory assumed: code_simulator/

suppressPackageStartupMessages({ library(haven); library(readxl) })
dir.create("../distributions", showWarnings = FALSE)

CHANCEL <- "../data/Chancel/Chanceletal2026Appendix_MacroScenarios.xlsx"
SIMUL   <- "../data/Bothe/distribution_simul_extract.dta"
FG      <- "../data/FisherGethin/fisher-gethin-2023-slim.dta"
WID     <- "../data/WID/wid-mprico-nni.csv"

# Existing practice (commented out): DECARB_FACTOR <- c(SD = 1.00, ID = 0.98, FD = 0.96)
DECARB_FACTOR  <- c(SD = 1.00, ID = 0.99, FD = 0.97)  # aligned with questionnaire.R (income cost of decarbonization)
# B_GROWTH_RATE  <- 0.01  # (unused: B uses the country-specific F0a growth avg_pg_c^10, see below)
RETENTION_RATE <- 0.50
RENTAL_YIELD   <- 0.035

##### 1. Helper functions (shared with questionnaire.R / situator.R) #####

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

housing_wealth_share <- function(gp_lb) {
  bks  <- c(0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 99.5, 99.9)
  vals <- c(0.000, 0.001, 0.016, 0.299, 0.619, 0.708, 0.732, 0.707, 0.641,
            0.540, 0.422, 0.319, 0.230, 0.102)
  vals[findInterval(gp_lb, bks)]
}

read_chancel_ts <- function(sheet) {
  d <- suppressMessages(read_excel(CHANCEL, sheet = sheet, col_names = FALSE))
  hdr <- as.character(unlist(d[4, ]))
  yrs <- suppressWarnings(as.numeric(unlist(d[-(1:4), 1])))
  body <- d[-(1:4), -1][!is.na(yrs), ]
  yrs <- yrs[!is.na(yrs)]
  v <- suppressWarnings(apply(body, 2, as.numeric))
  if (is.null(dim(v))) v <- matrix(v, nrow = 1)
  colnames(v) <- hdr[-1]
  df <- as.data.frame(v); rownames(df) <- as.character(yrs); df
}

# Weighted mean over gperc grid
wmean_gp <- function(v, gp) sum(v * gp_width(gp), na.rm = TRUE)

# Match simul p1 rows to a FG gperc index vector → vector of values
match_gp <- function(sub, col, gperc_idx) {
  sub$gi <- p1_to_gperc_index(sub$p1)
  sub[[col]][match(gperc_idx, sub$gi)]
}

##### 2. Load raw data #####
message("Reading data...")
simul <- as.data.frame(read_dta(SIMUL))
for (v in c("sdiinc","nni","diff","ypt","pop","shweal"))
  simul[[v]] <- ifelse(is.na(simul[[v]]), 0, simul[[v]])
simul$yp_recomp <- with(simul, ifelse(diff > 0, sdiinc * nni / diff, NA_real_))

macro_2025 <- unique(simul[simul$year == 2025, c("country","nni","gdp","cfc")])
nni_2025           <- setNames(macro_2025$nni, macro_2025$country)
cfc_per_adult_2025 <- setNames(macro_2025$cfc * macro_2025$gdp, macro_2025$country)

e3bp <- suppressMessages(read_excel("../data/Bothe/Botheetal2026AppendixMacro.xlsx",
                                    sheet = "E3bp", col_names = FALSE))
dividend_by_year <- setNames(
  suppressWarnings(as.numeric(unlist(e3bp[-(1:4), 2]))),
  as.character(suppressWarnings(as.numeric(unlist(e3bp[-(1:4), 1])))))
simul$income <- simul$yp_recomp - simul$ypt + dividend_by_year[as.character(simul$year)]

wid <- read.csv(WID)
mprico_share   <- setNames(wid$mprico_share, wid$country)
mprico_default <- median(wid$mprico_share, na.rm = TRUE)
re_rate <- function(c) RETENTION_RATE * (if (!is.na(mprico_share[c])) mprico_share[[c]] else mprico_default)

fg <- as.data.frame(read_dta(FG)); fg <- fg[fg$year == 2023, ]
for (v in c("a_pre","a_pre_cap","tax_dir_pit","tax_dir_wea","tax_cit","tax_soc","tax_ind","gov_soc","weight"))
  fg[[v]] <- ifelse(is.na(fg[[v]]), 0, fg[[v]])

# Chancel scenario sheets
G5s  <- read_chancel_ts("G5s");  G0p  <- read_chancel_ts("G0p")
a0   <- read_chancel_ts("A0");   a0p  <- read_chancel_ts("A0p");  a0pi <- read_chancel_ts("A0pi")
e0h  <- read_chancel_ts("E0h");  e0k  <- read_chancel_ts("E0k");  f0a  <- read_chancel_ts("F0a")
e0a  <- read_chancel_ts("E0a")   # per-worker economic labour hours, SC scenario
z0a  <- read_chancel_ts("Z0a");  z0b  <- read_chancel_ts("Z0b");  a0pi_ts <- read_chancel_ts("A0pi")
growth_pi <- setNames(as.numeric(a0pi_ts["2100",]) / as.numeric(a0pi_ts["2025",]), colnames(a0pi_ts))

# Residual region → constituent FG ISOs (from situator.R)
main_countries <- c("DE","DK","ES","FR","GB","IT","NL","NO","SE","US","CA","AU","NZ",
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

##### 3. Build FG-based cash_income_2025 and gperc ordering per country #####
wealth_2025 <- simul[simul$year == 2025, c("country","p1","shweal","diff")]
wealth_2025$gi <- p1_to_gperc_index(wealth_2025$p1)
ypt_2025     <- simul[simul$year == 2025, c("country","p1","ypt")]
ypt_2025$gi  <- p1_to_gperc_index(ypt_2025$p1)

housing_norm <- function(ctry, gi) {
  wd <- wealth_2025[wealth_2025$country == ctry, ]
  if (!nrow(wd)) return(rep(0, length(gi)))
  sw  <- wd$shweal[match(gi, wd$gi)]; sw[is.na(sw)] <- 0
  dif <- wd$diff[match(gi, wd$gi)];   dif[is.na(dif)] <- 0.01
  H   <- housing_wealth_share(gperc_to_lb(gi))
  den <- sum(sw * H * dif, na.rm = TRUE)
  if (den <= 0) rep(0, length(gi)) else sw * H / den
}
ypt_for <- function(ctry, gi) {
  yp <- ypt_2025[ypt_2025$country == ctry, ]
  v  <- yp$ypt[match(gi, yp$gi)]; v[is.na(v)] <- 0; v
}

# Returns list(gperc = 1:127 indices, cash25 = 127-vector) or NULL
fg_country_data <- function(ctry) {
  if (ctry %in% main_countries) {
    sub <- fg[fg$iso == ctry, ]; if (!nrow(sub)) return(NULL)
    mu_n <- sum(sub$a_pre * sub$weight) / sum(sub$weight)
    mu_c <- sum(sub$a_pre_cap * sub$weight) / sum(sub$weight)
    if (mu_n <= 0) return(NULL)
    nni <- nni_2025[ctry]; cfc <- cfc_per_adult_2025[ctry]
    if (is.na(nni) || is.na(cfc)) return(NULL)
    base      <- (sub$a_pre - sub$tax_dir_pit - sub$tax_dir_wea - sub$tax_cit
                  - sub$tax_soc - sub$tax_ind + sub$gov_soc) / mu_n
    cap_share <- if (mu_c > 0) sub$a_pre_cap / mu_c else rep(0, nrow(sub))
    cash <- base * nni - re_rate(ctry) * cap_share * nni -
            RENTAL_YIELD * housing_norm(ctry, sub$gperc) * nni +
            cap_share * cfc - ypt_for(ctry, sub$gperc)
    return(list(gperc = sub$gperc, cash25 = cash))
  }
  isos <- intersect(residual_def[[ctry]], unique(fg$iso)); if (!length(isos)) return(NULL)
  nni <- nni_2025[ctry]; cfc <- cfc_per_adult_2025[ctry]
  if (is.na(nni) || is.na(cfc)) return(NULL)
  pieces <- do.call(rbind, lapply(isos, function(iso) {
    s <- fg[fg$iso == iso, ]; if (!nrow(s)) return(NULL)
    mu_n <- sum(s$a_pre * s$weight) / sum(s$weight); if (mu_n <= 0) return(NULL)
    mu_c <- sum(s$a_pre_cap * s$weight) / sum(s$weight)
    data.frame(gperc = s$gperc,
      base = (s$a_pre - s$tax_dir_pit - s$tax_dir_wea - s$tax_cit
              - s$tax_soc - s$tax_ind + s$gov_soc) / mu_n,
      cap_share = if (mu_c > 0) s$a_pre_cap / mu_c else 0,
      re = re_rate(iso) * (if (mu_c > 0) s$a_pre_cap / mu_c else 0),
      weight = s$weight)
  })); if (is.null(pieces)) return(NULL)
  agg <- aggregate(cbind(base_w = base * weight, re_w = re * weight,
                         cap_w = cap_share * weight, w = weight) ~ gperc, pieces, sum)
  cash <- (agg$base_w - agg$re_w) / agg$w * nni -
          RENTAL_YIELD * housing_norm(ctry, agg$gperc) * nni +
          agg$cap_w / agg$w * cfc - ypt_for(ctry, agg$gperc)
  list(gperc = agg$gperc, cash25 = cash)
}

##### 4. Scenario constants used in ineq_2035_full construction #####
# SECTORAL_CHANGE2_COLS <- c("SC","SC45k","SC15k","SI","SN","SG","MC","MC45k","MC30k","MC15k","WC","MC_SD")
SECTORAL_CHANGE2_COLS <- c("SC","SC45k","SC15k","SI","SN","SG","B90kC","B45kC","B30kC","B15kC","B120kC","B90kC_SD",
                "B","BG","BN","BI")
scen_name <- function(cls, sc) {
  if (cls %in% c("S45k","S15k")) paste0("S", sc, sub("^S", "", cls))
  else if (cls == "B90k") paste0("B90k", sc)
  else paste0(substr(cls, 1, 1), sc)
}
# hours_classes <- list(P = 44, M = 40, S = 36, S45k = 32, S15k = 24)
hours_classes <- list(P = 44, B90k = 40, S = 36, S45k = 32, S15k = 28)
scopes <- list(C = c(g = "GIT", n = "SN"), G = c(g = "GIT", n = "current"),
               N = c(g = "current", n = "SN"), I = c(g = "current", n = "current"))

##### 5. Build per-country 2035 distributions #####
message("Building ineq_2035_full for all countries...")
all_countries <- sort(unique(simul$country))
rows2035 <- list()
constants_list <- list()

for (ctry in all_countries) {
  fd_data <- fg_country_data(ctry)
  if (is.null(fd_data)) { message("  Skipping ", ctry, " (no FG data)"); next }
  gperc_vec <- fd_data$gperc
  cash25    <- fd_data$cash25
  gp_C      <- gperc_to_lb(gperc_vec)

  # Full income 2025/2035/ypt from simul matched to FG gperc ordering
  s25 <- simul[simul$year == 2025 & simul$country == ctry, c("p1","income")]
  s35 <- simul[simul$year == 2035 & simul$country == ctry, c("p1","income","ypt")]
  inc25_f <- match_gp(s25, "income", gperc_vec)
  inc35_f <- match_gp(s35, "income", gperc_vec)
  ypt35_c <- match_gp(s35, "ypt", gperc_vec); ypt35_c[is.na(ypt35_c)] <- 0

  cash25       <- enforce_monotone_below_99(cash25, gp_C)   # enforce BEFORE the ratio, as in questionnaire.R
  cash_ratio_c <- ifelse(is.finite(inc25_f) & inc25_f > 0, cash25 / inc25_f, NA_real_)
  c35          <- enforce_monotone_below_99(inc35_f * cash_ratio_c, gp_C)
  cash_gr35_c  <- (dividend_by_year["2035"] - ypt35_c) * cash_ratio_c

  avg_c35 <- wmean_gp(c35, gp_C)
  ratio_c <- wmean_gp(cash25, gp_C) / wmean_gp(inc25_f, gp_C)

  # Extra PS tax rate
  dps_c <- as.numeric(G5s["2035", ctry]) - as.numeric(G5s["2025", ctry])
  extra_tax_c <- dps_c * as.numeric(G0p["2035", ctry]) / avg_c35

  # B90k / B120k scale (country-specific per-worker hours from E0a)
  # hours_c_25  <- as.numeric(e0h["2025", ctry])
  # hours_c_35  <- as.numeric(e0h["2035", ctry])
  hours_pw_c_25 <- as.numeric(e0a["2025", ctry])
  hours_pw_c_35 <- as.numeric(e0a["2035", ctry])
  prod_c_25   <- as.numeric(f0a["2025", ctry])
  prod_c_35   <- as.numeric(f0a["2035", ctry])
  # B uses the country's ACTUAL 2025-2035 productivity growth from Chancel sheet F0a
  # (prod_c_35/prod_c_25), not the smoothed 2025-2100 average. This cancels SC's productivity term,
  # so the 35h B equals SC and B90k equals SC with per-worker hours held at the 2025 level.
  # avg_pg_c   <- (125 / prod_c_25)^(1 / 75)   # 2025-2100 average growth (no longer used)
  b90k_scale_c <- (prod_c_35 / prod_c_25) / ((hours_pw_c_35 / hours_pw_c_25) * (prod_c_35 / prod_c_25))
  b_scale_c    <- (prod_c_35 / prod_c_25) / (prod_c_35 / prod_c_25)
  # Flat-growth version (commented out): (1 + B_GROWTH_RATE)^10 instead of the F0a country growth.
  # b90k_scale_c <- (1 + B_GROWTH_RATE)^10 / ((hours_pw_c_35 / hours_pw_c_25) * (prod_c_35 / prod_c_25))
  # b_scale_c    <- (1 + B_GROWTH_RATE)^10 / (prod_c_35 / prod_c_25)
  # wc_scale_c  <- (45 / 40) * mc_scale_c
  b120k_scale_c <- (44 / 40) * b90k_scale_c   # B120k class: 44 worked hours in 2035

  # SC45k/SC15k GDP-based scales
  sc45k_sc <- as.numeric(a0["2025", ctry]) / as.numeric(a0["2035", ctry])
  sc30k_sc <- 0.95 * sc45k_sc; sc15k_sc <- 0.9 * sc45k_sc

  # SI scale (PI per-capita GDP at 2035, adjusted for per-worker hours)
  gdppc_sc25   <- as.numeric(a0p["2025", ctry])
  gdppc_pi35   <- as.numeric(a0pi["2035", ctry])
  hours_c_35   <- as.numeric(e0h["2035", ctry])  # per-capita hours used for SI scale
  hours_pi35_c <- as.numeric(e0k["2035", ctry])
  si_scale_c   <- gdppc_pi35 * (hours_c_35 / hours_pi35_c) / gdppc_sc25
  si0_c        <- cash25 * si_scale_c
  avg_si0_c    <- wmean_gp(si0_c, gp_C)

  # Base scenario data frame (mirroring ineq_IT_2035, §9 of questionnaire.R)
  fd  <- DECARB_FACTOR["FD"]
  ps  <- 1 - extra_tax_c
  base <- data.frame(
    gpercentile = gp_C,
    income25    = cash25,
    cash_GR35   = cash_gr35_c,
    income35    = c35,
    SCmat       = c35 * fd,
    B90kMat     = c35 * b90k_scale_c * fd,
    Bmat        = c35 * b_scale_c * fd,
    PC          = c35 * 1.15 * fd,
    PI          = cash25 * 1.4 * fd,
    SC45k       = c35 * sc45k_sc * fd * ps,
    SC15k       = c35 * sc15k_sc * fd * ps,
    SI          = si0_c * fd * ps,
    SC          = c35 * fd * ps,
    SN          = (c35 - cash_gr35_c) * (avg_si0_c / avg_c35) * fd * ps,
    SG          = (si0_c + cash_gr35_c) * (avg_c35 / avg_si0_c) * fd * ps,
    B90kC       = c35 * b90k_scale_c * fd * ps,
    B120kC      = c35 * b120k_scale_c * fd * ps,
    B           = c35 * b_scale_c * fd * ps,
    B45kC       = c35 * b90k_scale_c * (32 / 40) * fd * ps,   # B45k class: 32 worked hours in 2035
    B90kC_SD    = c35 * b90k_scale_c * DECARB_FACTOR["SD"] * ps)

  for (col in setdiff(names(base), c("gpercentile","cash_GR35")))
    base[[col]] <- enforce_monotone_below_99(base[[col]], gp_C)

  # Rounded weighted averages (for redistScale in dist_c_2035 below)
  avg_r <- setNames(
    sapply(setdiff(names(base), c("gpercentile","cash_GR35","income25","income35")),
           function(col) round(wmean_gp(base[[col]], gp_C))),
    setdiff(names(base), c("gpercentile","cash_GR35","income25","income35")))
  ps_exp <- 1 - round(extra_tax_c, 6)

  # dist_c_2035: same logic as questionnaire.R §14 dist_2035()
  dist_c_2035 <- function(h, gR, nR, decarb = "FD", pubS = "increased") {
    hasGIT <- gR == "GIT"; hasNat <- nR == "SN"; rscale <- 1
    if (h == 44) {
      if      (hasGIT && hasNat)   colN <- "PC"
      else if (!hasGIT && !hasNat) colN <- "PI"
      else if (hasGIT && !hasNat)  { colN <- "SG"; rscale <- avg_r["PC"] / avg_r["SC"] }
      else                         { colN <- "SN"; rscale <- avg_r["PI"] / avg_r["SN"] }
    } else if (h == 36) {
      colN <- if (hasGIT && hasNat) "SC" else if (hasGIT && !hasNat) "SG" else
              if (!hasGIT && hasNat) "SN" else "SI"
    } else {
      # cC <- c("24" = "SC15k", "32" = "SC45k", "40" = "MC")[[as.character(h)]]
      cC <- c("28" = "SC15k", "32" = "B45kC", "40" = "B90kC")[[as.character(h)]]
      coefC <- avg_r[cC] / avg_r["SC"]
      if      (hasGIT && hasNat)   { colN <- cC }
      else if (hasGIT && !hasNat)  { colN <- "SG"; rscale <- coefC }
      else if (!hasGIT && hasNat)  { colN <- "SN"; rscale <- coefC * avg_r["SI"] / avg_r["SN"] }
      else                         { colN <- "SI"; rscale <- coefC }
    }
    epf <- if (colN %in% SECTORAL_CHANGE2_COLS) ps_exp else 1
    dr  <- DECARB_FACTOR[[decarb]] / DECARB_FACTOR[["FD"]]
    psU <- if (pubS == "increased") ps_exp else 1
    base[[colN]] * dr * (psU / epf) * as.numeric(rscale)
  }

  # Build full variant set (§14 of questionnaire.R)
  full <- base[, c("gpercentile","income25","cash_GR35","income35","SCmat","B90kMat")]
  for (cls in names(hours_classes)) for (sc in names(scopes)) {
    ps_arg <- if (cls == "P") "stable" else "increased"
    full[[scen_name(cls, sc)]] <- round(dist_c_2035(
      hours_classes[[cls]], scopes[[sc]]["g"], scopes[[sc]]["n"], "FD", ps_arg))
  }
  # B120k class: B120kC from base; B120kG/B120kN/B120kI = B90k{scope} × (44/40) (45h class, 44 worked hours in 2035)
  full[["B120kC"]] <- round(base[["B120kC"]])
  for (sl in c("G","N","I"))
    full[[paste0("B120k", sl)]] <- round(full[[paste0("B90k", sl)]] * (44 / 40))
  # B90k hours sub-variants: B{sl}{xxk} = B90k{sl} × (worked_hours / 40)
  # 2035 worked hours: B45k(30h class)=32, B30k(29h class)=28, B15k(28h class)=24.
  for (sl in c("C","G","N","I")) {
    full[[paste0("B45k", sl)]] <- round(full[[paste0("B90k", sl)]] * (32 / 40))
    full[[paste0("B30k", sl)]] <- round(full[[paste0("B90k", sl)]] * (28 / 40))
    full[[paste0("B15k", sl)]] <- round(full[[paste0("B90k", sl)]] * (24 / 40))
  }
  # B class: C scope from base; B{G/N/I} = S{scope} × b_scale_c
  full[["B"]] <- round(base[["B"]])
  for (sl in c("G","N","I"))
    full[[paste0("B", sl)]] <- round(full[[paste0("S", sl)]] * b_scale_c)
  # Bbeef/Bflights: sectoral_change=2 income at 2035 = B (not B90kC) — must come after B is set
  full[["Bbeef"]]    <- full[["B"]]
  full[["Bflights"]] <- full[["B"]]
  # B90kC_SD standalone
  full[["B90kC_SD"]] <- round(base[["B90kC_SD"]])
  # Bmat from base
  full[["Bmat"]] <- round(base[["Bmat"]])
  # B90kC_SD and B90kMat
  full[["income25"]] <- round(full[["income25"]])
  full[["cash_GR35"]] <- round(full[["cash_GR35"]])
  full[["income35"]] <- round(full[["income35"]])
  full[["SCmat"]]  <- round(full[["SCmat"]])
  full[["B90kMat"]]  <- round(full[["B90kMat"]])

  rows2035[[ctry]] <- cbind(country = ctry, full)
  constants_list[[ctry]] <- data.frame(country = ctry,
    extra_tax_rate = round(extra_tax_c, 6), ratio = round(ratio_c, 6))
  message(sprintf("  %s: extra_tax=%.4f  b90k_scale=%.4f  hours_pw_2025=%.1f",
                  ctry, extra_tax_c, b90k_scale_c, hours_pw_c_25))
}

ineq_2035_full <- do.call(rbind, rows2035)
write.csv(ineq_2035_full, "../distributions/ineq_2035_full.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ineq_2035_full.csv  (%d rows × %d cols)", nrow(ineq_2035_full), ncol(ineq_2035_full)))

conjoint_world_constants <- do.call(rbind, constants_list)
write.csv(conjoint_world_constants, "../distributions/conjoint_world_constants.csv",
          row.names = FALSE, quote = FALSE)
message("Wrote conjoint_world_constants.csv")

##### 6. Build per-country 2100 bracket distributions (SC, SG, SN, SI) #####
message("Building ineq_2100_countries...")

pop_sc_2100 <- setNames(as.numeric(z0a["2100", ]), colnames(z0a))
pop_pi_2100 <- setNames(as.numeric(z0b["2100", ]), colnames(z0b))
dividend_2100 <- dividend_by_year["2100"]

# World distributions needed for taxG schedule
inc_wide <- reshape(simul[simul$year %in% c(2025, 2100), c("country","p1","year","income","yp_recomp")],
  idvar = c("country","p1"), timevar = "year", v.names = c("income","yp_recomp"), direction = "wide")
# reshape() interleaves v.names within each year: income.2025, yp_recomp.2025, income.2100, yp_recomp.2100
names(inc_wide)[3:6] <- c("income_2025","yprecomp_2025","income_2100","yprecomp_2100")
yp_wide <- reshape(simul[simul$year %in% c(2025, 2100), c("country","p1","year","yp_recomp")],
  idvar = c("country","p1"), timevar = "year", v.names = "yp_recomp", direction = "wide")
names(yp_wide)[3:4] <- c("yprecomp_2025","yprecomp_2100")

build_world_dist <- function(value, width, pop_by_entity, entity, n = 100) {
  d <- data.frame(v = value, w = width * pop_by_entity[entity])
  d <- d[is.finite(d$v) & d$v > 0 & is.finite(d$w) & d$w > 0, ]
  d <- d[order(d$v), ]; W <- sum(d$w)
  d$ch <- cumsum(d$w)/W; d$cl <- c(0, head(d$ch,-1))
  vapply(seq_len(n), function(p) {
    bh <- p/n; bl <- (p-1)/n
    ov <- pmax(0, pmin(d$ch,bh) - pmax(d$cl,bl)); s <- sum(ov)
    if (s > 0) sum(d$v * ov) / s else NA_real_
  }, numeric(1))
}

gw <- gp_width(inc_wide$income_2025)  # same width pattern — use p1 column
# Actually use the p1 as percentile lower bound directly
inc_wide$gp <- inc_wide$p1  # p1 is already the lower-bound percentile
gw <- gp_width(inc_wide$gp)

inc_wide$pi_2100 <- yp_wide$yprecomp_2025[match(paste(inc_wide$country, inc_wide$p1),
  paste(yp_wide$country, yp_wide$p1))] * growth_pi[inc_wide$country]
avg_sc_2100_c  <- tapply(inc_wide$income_2100 * gw, inc_wide$country, sum, na.rm = TRUE)
avg_si0_2100_c <- tapply(0.5 * inc_wide$pi_2100 * gw, inc_wide$country, sum, na.rm = TRUE)
inc_wide$sn_2100 <- inc_wide$yprecomp_2100 *
  (avg_si0_2100_c[inc_wide$country] / avg_sc_2100_c[inc_wide$country])
inc_wide$si_2100 <- 0.5 * inc_wide$pi_2100

world_SC <- build_world_dist(inc_wide$income_2100, gw, pop_sc_2100, inc_wide$country)
world_SN <- build_world_dist(inc_wide$sn_2100,    gw, pop_pi_2100, inc_wide$country)
world_SI <- build_world_dist(inc_wide$si_2100,    gw, pop_pi_2100, inc_wide$country)

taxg_rate <- ifelse(world_SN > 0, (world_SN - world_SC) / world_SN, 0)
taxg_at   <- function(inc) approx(world_SN, taxg_rate, xout = inc, rule = 2, ties = mean)$y
inc_wide$sg_2100 <- inc_wide$si_2100 * (1 - taxg_at(inc_wide$si_2100))

bracket_lo <- c(seq(0,90,5), 95, 99); bracket_hi <- c(seq(5,95,5), 99, 100)
bracket_names <- paste0("p", bracket_lo, "p", bracket_hi)

bracket_avg_c <- function(vals, p1_vec) {
  vapply(seq_along(bracket_lo), function(i) {
    m <- p1_vec >= bracket_lo[i] & (if (bracket_hi[i] >= 100) TRUE else p1_vec < bracket_hi[i])
    w <- gp_width(p1_vec[m]); s <- sum(w); if (s > 0) sum(vals[m] * w, na.rm = TRUE) / s else NA_real_
  }, numeric(1))
}

cash_dist_2025 <- read.csv("../distributions/cash_income_2025.csv")

rows2100 <- list()
for (ctry in all_countries) {
  sub <- inc_wide[inc_wide$country == ctry, ]
  if (!nrow(sub)) next
  ratio_c <- conjoint_world_constants$ratio[conjoint_world_constants$country == ctry]
  if (!length(ratio_c)) ratio_c <- 0.7

  p1v <- sub$gp
  avg_sc_c  <- wmean_gp(sub$income_2100, p1v)
  avg_si0_c <- wmean_gp(sub$si_2100,     p1v)

  sc_vals <- sub$income_2100
  sn_vals <- sub$yprecomp_2100 * (avg_si0_c / avg_sc_c)
  si_vals <- sub$si_2100
  sg_vals <- sub$sg_2100

  cash_c <- cash_dist_2025[cash_dist_2025$country == ctry, ]
  cash_vals_c <- if (nrow(cash_c) > 0)
    cash_c$cash_income_2025[match(round(p1v, 5), round(cash_c$gpercentile, 5))]
  else rep(NA_real_, length(p1v))

  rows2100[[ctry]] <- data.frame(
    bracket = bracket_names, country = ctry,
    SC = round(bracket_avg_c(sc_vals, p1v) * ratio_c),
    SG = round(bracket_avg_c(sg_vals, p1v) * ratio_c),
    SN = round(bracket_avg_c(sn_vals, p1v) * ratio_c),
    SI = round(bracket_avg_c(si_vals, p1v) * ratio_c),
    cash2025 = round(bracket_avg_c(cash_vals_c, p1v)))
}

ineq_2100_countries <- do.call(rbind, rows2100)
write.csv(ineq_2100_countries, "../distributions/ineq_2100_countries.csv",
          row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ineq_2100_countries.csv  (%d rows × %d cols)",
                nrow(ineq_2100_countries), ncol(ineq_2100_countries)))

##### 7. Copy to data/ for JS #####
dir.create("data", showWarnings = FALSE)
for (f in c("ineq_2035_full.csv", "ineq_2100_countries.csv", "conjoint_world_constants.csv"))
  file.copy(file.path("../distributions", f), file.path("data", f), overwrite = TRUE)
message("Copied world conjoint CSVs to data/.")
message("Done.")
