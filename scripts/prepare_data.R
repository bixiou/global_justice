# prepare_data.R
# Generates income.csv, income_world.csv, wealth.csv, wealth_world.csv
# from Bothe et al. (2026) Appendix Distribution data.
#
# Income methodology: anchor-based log-interpolation.
#   2025 levels from P1e. Future/past years scaled using I5 threshold anchors
#   (p1, p10, p50, p99, p100) with geometric interpolation between anchors.
# Wealth methodology: group-level scaling using K2 group average series.

library(readxl)

BOTHE <- "data/Bothe/Botheetal2026AppendixDistribution.xlsx"
INCOME_YEARS <- 2020:2100          # all years for income.csv / income_world.csv
TARGET_YEARS <- c(2025, 2030, 2035, 2050, 2080, 2100)  # wealth only


# ── helpers ──────────────────────────────────────────────────────────────────

#' Read a standard time-series sheet (4 header rows, years 1800-2100 in col 1)
read_ts <- function(sheet, file = BOTHE) {
  df <- suppressMessages(read_excel(file, sheet = sheet, col_names = FALSE))
  ctries <- unlist(df[4, -1], use.names = FALSE) |> as.character()
  years  <- unlist(df[-(1:4), 1], use.names = FALSE) |> as.numeric()
  vals   <- df[-(1:4), -1] |> apply(2, as.numeric) |> as.data.frame()
  rownames(vals) <- as.character(years)
  colnames(vals) <- ctries
  vals
}

#' Read a P-series sheet (4 header rows, percentile groups in col 1)
read_ps <- function(sheet, file = BOTHE) {
  df <- suppressMessages(read_excel(file, sheet = sheet, col_names = FALSE))
  ctries <- unlist(df[4, -1], use.names = FALSE) |> as.character()
  groups <- unlist(df[-(1:4), 1], use.names = FALSE) |> as.character()
  vals   <- df[-(1:4), -1] |> apply(2, as.numeric) |> as.data.frame()
  rownames(vals) <- groups
  colnames(vals) <- ctries
  vals
}

#' Extract a single year's row from a time-series data frame
get_year <- function(ts_df, yr) ts_df[as.character(yr), , drop = FALSE]


# ── load income data ──────────────────────────────────────────────────────────

message("Loading income data...")
p1e  <- read_ps("P1e")   # 2025 income levels: 127 gp groups × 67 countries
i2i  <- read_ts("I2i")   # average posttax net income
i1a  <- read_ts("I1a")   # T10 share
i1b  <- read_ts("I1b")   # B50 share
i1c  <- read_ts("I1c")   # T1 share
i1e  <- read_ts("I1e")   # B10 share
i1h  <- read_ts("I1h")   # M40 share (used for wealth; kept for parity)
# I5 threshold series (ratio to average income): used as anchors for scaling
i5e  <- read_ts("I5e")   # P10
i5b  <- read_ts("I5b")   # P50
i5c  <- read_ts("I5c")   # P99

# keep only the valid country columns (first 67, before "diff" and "2100")
# p1e has cols: World, Europe, ..., OI, diff, 2100
valid_cols <- colnames(p1e)[!colnames(p1e) %in% c("diff", "2100", NA) & !is.na(colnames(p1e))]
p1e  <- p1e[, valid_cols, drop = FALSE]

# align I-series country columns to p1e (same first 67 countries)
# I-series has extra pop-weighted region cols at the end - drop them
align_ts <- function(ts) {
  shared <- intersect(valid_cols, colnames(ts))
  # fall back to positional matching for slightly different region names
  if (length(shared) < length(valid_cols)) {
    ts_trimmed <- ts[, seq_len(length(valid_cols)), drop = FALSE]
    colnames(ts_trimmed) <- valid_cols
    return(ts_trimmed)
  }
  ts[, shared, drop = FALSE]
}

i2i  <- align_ts(i2i)
i1a  <- align_ts(i1a)
i1b  <- align_ts(i1b)
i1c  <- align_ts(i1c)
i1e  <- align_ts(i1e)
i1h  <- align_ts(i1h)
i5e  <- align_ts(i5e)
i5b  <- align_ts(i5b)
i5c  <- align_ts(i5c)

ctries <- valid_cols  # 67 country/region names


# ── aggregate P1e 127 groups → 100 percentiles ───────────────────────────────
#
# Rows 1-99 in p1e (p0p1 to p98p99) → percentiles 1-99 (1-indexed)
# Rows 100-127 (p99pX to p99.999p100) → percentile 100 (weighted average)
#
# Population widths for rows 100+:
# p99p99.1 → 0.001 (0.1%)  … p99.8p99.9 → 0.001  (9 rows × 0.001 = 0.009)
# p99.9p99.91 → 0.0001     … p99.98p99.99 → 0.0001 (9 rows × 0.0001 = 0.0009)
# p99.99p99.991 → 0.00001  … p99.998p99.999 → 0.00001 (9 rows)
# p99.999p100 → 0.00001
# Total = 0.01 ✓

fine_rows  <- p1e[100:127, , drop = FALSE]
fine_names <- rownames(fine_rows)

# derive population width from the percentile label
parse_width <- function(label) {
  parts <- strsplit(label, "p")[[1]]
  parts <- parts[parts != ""]
  lo <- as.numeric(parts[1])
  hi <- as.numeric(parts[2])
  (hi - lo) / 100  # convert from percentage-points to fraction
}

fine_widths <- sapply(fine_names, parse_width)  # should sum to 0.01
weights <- fine_widths / sum(fine_widths)
top1_avg <- as.data.frame(t(colSums(as.matrix(fine_rows) * weights)))
rownames(top1_avg) <- "p99p100"

# Build 100-row income matrix
income_2025 <- rbind(p1e[1:99, , drop = FALSE], top1_avg)
rownames(income_2025) <- as.character(1:100)


# ── compute income for each target year ──────────────────────────────────────
#
# Method: anchor-based log-interpolation.
# Anchor percentiles: 1 (B10 avg), 10 (P10 threshold), 50 (P50), 99 (P99), 100 (T1 avg)
# Scale at anchor = abs_income_yr / abs_income_2025 for that anchor.
# Scale at intermediate p = geometric interpolation between bracketing anchors.

message("Computing income by year...")

build_income_anchored <- function(base, avg_ts, sh_b10, sh_t1,
                                   thr_p10, thr_p50, thr_p99,
                                   years = TARGET_YEARS) {
  result <- list()
  result[["2025"]] <- base

  yr_str <- as.character(2025)
  avg_25 <- as.numeric(avg_ts[yr_str, ctries])
  b10_25 <- as.numeric(sh_b10[yr_str, ctries])
  t1_25  <- as.numeric(sh_t1[yr_str,  ctries])
  p10_25 <- as.numeric(thr_p10[yr_str, ctries]) * avg_25
  p50_25 <- as.numeric(thr_p50[yr_str, ctries]) * avg_25
  p99_25 <- as.numeric(thr_p99[yr_str, ctries]) * avg_25
  B10_25 <- avg_25 * b10_25 / 0.1
  T1_25  <- avg_25 * t1_25  / 0.01

  log_lerp <- function(lo, hi, t) exp((1 - t) * log(pmax(lo, 1e-9)) +
                                            t  * log(pmax(hi, 1e-9)))

  for (yr in years[years != 2025]) {
    yr_s <- as.character(yr)
    avg_yr <- as.numeric(avg_ts[yr_s, ctries])
    b10_yr <- as.numeric(sh_b10[yr_s, ctries])
    t1_yr  <- as.numeric(sh_t1[yr_s,  ctries])
    p10_yr <- as.numeric(thr_p10[yr_s, ctries]) * avg_yr
    p50_yr <- as.numeric(thr_p50[yr_s, ctries]) * avg_yr
    p99_yr <- as.numeric(thr_p99[yr_s, ctries]) * avg_yr
    B10_yr <- avg_yr * b10_yr / 0.1
    T1_yr  <- avg_yr * t1_yr  / 0.01

    s1   <- ifelse(B10_25 == 0 | is.na(B10_25), 1, B10_yr  / B10_25)
    s10  <- ifelse(p10_25 == 0 | is.na(p10_25), 1, p10_yr  / p10_25)
    s50  <- ifelse(p50_25 == 0 | is.na(p50_25), 1, p50_yr  / p50_25)
    s99  <- ifelse(p99_25 == 0 | is.na(p99_25), 1, p99_yr  / p99_25)
    s100 <- ifelse(T1_25  == 0 | is.na(T1_25),  1, T1_yr   / T1_25)

    scale_mat <- matrix(NA_real_, 100, length(ctries), dimnames = list(NULL, ctries))
    for (p in 1:100) {
      if (p == 1) {
        scale_mat[p, ] <- s1
      } else if (p <= 10) {
        t <- (p - 1) / 9
        scale_mat[p, ] <- log_lerp(s1, s10, t)
      } else if (p <= 50) {
        t <- (p - 10) / 40
        scale_mat[p, ] <- log_lerp(s10, s50, t)
      } else if (p <= 99) {
        t <- (p - 50) / 49
        scale_mat[p, ] <- log_lerp(s50, s99, t)
      } else {
        scale_mat[p, ] <- s100
      }
    }

    result[[as.character(yr)]] <- as.data.frame(as.matrix(base) * scale_mat)
  }
  result
}

inc_by_year <- build_income_anchored(income_2025, i2i, i1e, i1c, i5e, i5b, i5c,
                                      years = INCOME_YEARS)


# ── write income.csv ─────────────────────────────────────────────────────────
# Wide format: one row per (country, gpercentile), one col per year 2020-2100

message("Writing income.csv...")
year_cols <- setNames(
  lapply(as.character(INCOME_YEARS), function(y) inc_by_year[[y]]),
  paste0("income_", INCOME_YEARS)
)
rows <- do.call(rbind, lapply(ctries, function(ctry) {
  yr_vals <- lapply(year_cols, function(m) m[[ctry]])
  as.data.frame(c(list(country = ctry, gpercentile = 1:100), yr_vals),
                stringsAsFactors = FALSE)
}))
write.csv(rows, "data/income.csv", row.names = FALSE)


# ── write income_world.csv ────────────────────────────────────────────────────
# Distribution chart: 100 world percentiles × target years

message("Writing income_world.csv...")
dist_years <- c(2025, 2030, 2035, 2050, 2080, 2100)
wld_cols <- setNames(
  lapply(as.character(dist_years), function(y) inc_by_year[[y]][["World"]]),
  paste0("income_", dist_years)
)
world_df <- as.data.frame(c(list(gpercentile = 1:100), wld_cols))
write.csv(world_df, "data/income_world.csv", row.names = FALSE)


# ── write income_pre_git.csv ──────────────────────────────────────────────────
# I5 sheets: Px threshold as ratio to average income (SC scenario, 1800-2100)
# income_pre_git = I5x × I2i  for each country and year 2020-2100

message("Writing income_pre_git.csv...")
# i5e, i5b, i5c already loaded; load the remaining fine-top thresholds
i5d  <- align_ts(read_ts("I5d"))   # P99.9
i5f  <- align_ts(read_ts("I5f"))   # P99.99
i5g  <- align_ts(read_ts("I5g"))   # P99.999

pre_git_years <- as.character(2020:2100)

make_threshold <- function(ratio_ts, avg_ts) {
  ratio_ts[pre_git_years, , drop = FALSE] *
    avg_ts[pre_git_years, , drop = FALSE]
}

t10   <- make_threshold(i5e, i2i)
t50   <- make_threshold(i5b, i2i)
t99   <- make_threshold(i5c, i2i)
t99_9 <- make_threshold(i5d, i2i)
t9999 <- make_threshold(i5f, i2i)
t99999 <- make_threshold(i5g, i2i)

pre_git_rows <- do.call(rbind, lapply(ctries, function(ctry) {
  data.frame(
    country       = ctry,
    year          = 2020:2100,
    p10           = t10[, ctry],
    p50           = t50[, ctry],
    p99           = t99[, ctry],
    p99.9         = t99_9[, ctry],
    p99.99        = t9999[, ctry],
    p99.999       = t99999[, ctry],
    stringsAsFactors = FALSE
  )
}))
write.csv(pre_git_rows, "data/income_pre_git.csv", row.names = FALSE)


# ── load wealth data ──────────────────────────────────────────────────────────

message("Loading wealth data...")
k1a  <- read_ts("K1a"); k1a  <- align_ts(k1a)   # T10 wealth share
k1b  <- read_ts("K1b"); k1b  <- align_ts(k1b)   # B50
k1c  <- read_ts("K1c"); k1c  <- align_ts(k1c)   # T1
k1e  <- read_ts("K1e"); k1e  <- align_ts(k1e)   # B10
k1h  <- read_ts("K1h"); k1h  <- align_ts(k1h)   # M40
k2a  <- read_ts("K2a"); k2a  <- align_ts(k2a)   # T10 avg wealth
k2b  <- read_ts("K2b"); k2b  <- align_ts(k2b)   # B50 avg wealth
k2c  <- read_ts("K2c"); k2c  <- align_ts(k2c)   # T1 avg wealth
k2e  <- read_ts("K2e"); k2e  <- align_ts(k2e)   # B10 avg wealth
k2h  <- read_ts("K2h"); k2h  <- align_ts(k2h)   # M40 avg wealth


# ── build 2025 wealth starting distribution ───────────────────────────────────
# Group averages: p1-10 = K2e, p11-50 = (K2b*0.5 - K2e*0.1)/0.4, etc.

wlth_2025_base <- function(yr = 2025) {
  b10   <- as.numeric(get_year(k2e, yr)[, ctries])
  b50   <- as.numeric(get_year(k2b, yr)[, ctries])
  m40   <- as.numeric(get_year(k2h, yr)[, ctries])
  t10   <- as.numeric(get_year(k2a, yr)[, ctries])
  t1    <- as.numeric(get_year(k2c, yr)[, ctries])
  p10_50 <- (b50 * 0.5 - b10 * 0.1) / 0.4
  t10_t1 <- (t10 * 0.1 - t1 * 0.01) / 0.09

  # matrix: 100 rows × length(ctries) cols
  mat <- matrix(NA_real_, 100, length(ctries), dimnames = list(1:100, ctries))
  mat[1:10,  ] <- matrix(b10,    10, length(ctries), byrow = TRUE)
  mat[11:50, ] <- matrix(p10_50, 40, length(ctries), byrow = TRUE)
  mat[51:90, ] <- matrix(m40,    40, length(ctries), byrow = TRUE)
  mat[91:99, ] <- matrix(t10_t1, 9,  length(ctries), byrow = TRUE)
  mat[100,   ] <- matrix(t1,     1,  length(ctries), byrow = TRUE)
  as.data.frame(mat)
}

wealth_2025 <- wlth_2025_base(2025)


# ── compute wealth for each target year ──────────────────────────────────────

# Group label for each percentile (used only in wealth builder)
grp <- c(rep("B10", 10), rep("p10_50", 40), rep("M40", 40),
         rep("T10_T1", 9), rep("T1", 1))

message("Computing wealth by year...")

build_wealth_matrix <- function(base, sh_b10, sh_b50, sh_m40, sh_t10, sh_t1,
                                 av_b10, av_b50, av_m40, av_t10, av_t1) {
  result <- list()
  result[["2025"]] <- base

  g_base <- list(
    B10    = as.numeric(get_year(av_b10, 2025)[, ctries]),
    p10_50 = (as.numeric(get_year(av_b50, 2025)[, ctries]) * 0.5 -
              as.numeric(get_year(av_b10, 2025)[, ctries]) * 0.1) / 0.4,
    M40    = as.numeric(get_year(av_m40, 2025)[, ctries]),
    T10_T1 = (as.numeric(get_year(av_t10, 2025)[, ctries]) * 0.1 -
              as.numeric(get_year(av_t1,  2025)[, ctries]) * 0.01) / 0.09,
    T1     = as.numeric(get_year(av_t1,  2025)[, ctries])
  )

  for (yr in TARGET_YEARS[TARGET_YEARS != 2025]) {
    g_yr <- list(
      B10    = as.numeric(get_year(av_b10, yr)[, ctries]),
      p10_50 = (as.numeric(get_year(av_b50, yr)[, ctries]) * 0.5 -
                as.numeric(get_year(av_b10, yr)[, ctries]) * 0.1) / 0.4,
      M40    = as.numeric(get_year(av_m40, yr)[, ctries]),
      T10_T1 = (as.numeric(get_year(av_t10, yr)[, ctries]) * 0.1 -
                as.numeric(get_year(av_t1,  yr)[, ctries]) * 0.01) / 0.09,
      T1     = as.numeric(get_year(av_t1,  yr)[, ctries])
    )

    scale_mat <- matrix(NA_real_, 100, length(ctries))
    colnames(scale_mat) <- ctries
    for (gname in c("B10", "p10_50", "M40", "T10_T1", "T1")) {
      rows_g <- which(grp == gname)
      factor <- ifelse(is.na(g_base[[gname]]) | g_base[[gname]] == 0, 1,
                       g_yr[[gname]] / g_base[[gname]])
      scale_mat[rows_g, ] <- matrix(factor, nrow = length(rows_g),
                                     ncol = length(ctries), byrow = TRUE)
    }
    result[[as.character(yr)]] <- as.data.frame(as.matrix(base) * scale_mat)
  }
  result
}

wlth_by_year <- build_wealth_matrix(wealth_2025,
                                     k1e, k1b, k1h, k1a, k1c,
                                     k2e, k2b, k2h, k2a, k2c)


# ── write wealth.csv ──────────────────────────────────────────────────────────

message("Writing wealth.csv...")
wrows <- do.call(rbind, lapply(ctries, function(ctry) {
  data.frame(
    country      = ctry,
    gpercentile  = 1:100,
    wealth_2025  = wlth_by_year[["2025"]][[ctry]],
    wealth_2030  = wlth_by_year[["2030"]][[ctry]],
    wealth_2035  = wlth_by_year[["2035"]][[ctry]],
    wealth_2050  = wlth_by_year[["2050"]][[ctry]],
    wealth_2080  = wlth_by_year[["2080"]][[ctry]],
    wealth_2100  = wlth_by_year[["2100"]][[ctry]],
    stringsAsFactors = FALSE
  )
}))
write.csv(wrows, "data/wealth.csv", row.names = FALSE)


# ── write wealth_world.csv ────────────────────────────────────────────────────

message("Writing wealth_world.csv...")
wworld_df <- data.frame(
  gpercentile  = 1:100,
  wealth_2025  = wlth_by_year[["2025"]][["World"]],
  wealth_2030  = wlth_by_year[["2030"]][["World"]],
  wealth_2035  = wlth_by_year[["2035"]][["World"]],
  wealth_2050  = wlth_by_year[["2050"]][["World"]],
  wealth_2080  = wlth_by_year[["2080"]][["World"]],
  wealth_2100  = wlth_by_year[["2100"]][["World"]]
)
write.csv(wworld_df, "data/wealth_world.csv", row.names = FALSE)

message("Done. Files written to data/")
