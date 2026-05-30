# code_simulator/prepare_data.R
# Generates:
#   - *_legacy.csv (income, income_world, income_pre_git, wealth, wealth_world)
#     from Bothe et al. (2026) Appendix Distribution (xlsx) using the spliced
#     parametric model below.
#   - income.csv from distribution_simul.dta (the Bothe Stata simulator output),
#     deducting Global Income Tax and Global Wealth Tax and adding back an
#     equal per-capita lump-sum funded by their global revenues.
#
# Income methodology (legacy): spliced parametric model from Appendix A of Bothe et al.
#   For every year (including 2025), in every country, we fit a 4-parameter
#   distribution to the 8 non-overlapping post-GIT bracket means derived from
#   the I9 series. The model is Type II Pareto below p_splice = 0.999 and
#   exponential above, joined continuously at the splice point. Parameters
#   (x_m, alpha, beta, lambda) are estimated by minimising the relative
#   squared error on the 8 bracket means (after rescaling the model to mean=1
#   for scale invariance), then bracket means for all 127 gpercentile groups
#   are evaluated analytically and re-scaled by the country-year overall mean
#   (I9i). This yields smooth, monotonic distributions and avoids the
#   non-monotonicities of group-level flat scaling.
# Wealth methodology: group-level scaling using K2 group average series.

library(readxl)

BOTHE <- "../data/Bothe/Botheetal2026AppendixDistribution.xlsx"
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
i2i  <- read_ts("I2i")   # average posttax net income (pre-GIT; for income_pre_git.csv)
i1a  <- read_ts("I1a")   # T10 share (pre-GIT; for income_pre_git.csv)
i1b  <- read_ts("I1b")   # B50 share
i1c  <- read_ts("I1c")   # T1 share
i1e  <- read_ts("I1e")   # B10 share
i1h  <- read_ts("I1h")   # M40 share (used for wealth)
# I5 threshold series (ratio to average income): used for income_pre_git.csv only
i5e  <- read_ts("I5e")   # P10
i5b  <- read_ts("I5b")   # P50
i5c  <- read_ts("I5c")   # P99
# I9 post-GIT group average series: 8 brackets used as income.csv anchors
i9i  <- read_ts("I9i")   # overall average (post-GIT)
i9e  <- read_ts("I9e")   # B10  avg (post-GIT): bracket [0, 0.10]
i9b  <- read_ts("I9b")   # B50  avg (post-GIT): bracket [0, 0.50]
i9h  <- read_ts("I9h")   # M40  avg (post-GIT): bracket [0.50, 0.90]
i9a  <- read_ts("I9a")   # T10  avg (post-GIT): bracket [0.90, 1.00]
i9c  <- read_ts("I9c")   # T1   avg (post-GIT): bracket [0.99, 1.00]
i9d  <- read_ts("I9d")   # top 0.1%  avg (post-GIT): bracket [0.999, 1.00]
i9f  <- read_ts("I9f")   # top 0.01% avg (post-GIT): bracket [0.9999, 1.00]
i9g  <- read_ts("I9g")   # top 0.001% avg (post-GIT): bracket [0.99999, 1.00]

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
i9i  <- align_ts(i9i)
i9e  <- align_ts(i9e)
i9b  <- align_ts(i9b)
i9h  <- align_ts(i9h)
i9a  <- align_ts(i9a)
i9c  <- align_ts(i9c)
i9d  <- align_ts(i9d)
i9f  <- align_ts(i9f)
i9g  <- align_ts(i9g)

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

fine_rows   <- p1e[100:127, , drop = FALSE]
fine_names  <- rownames(fine_rows)

# derive population width from the percentile label (used for world CSV aggregation)
parse_width <- function(label) {
  parts <- strsplit(label, "p")[[1]]
  parts <- parts[parts != ""]
  lo <- as.numeric(parts[1])
  hi <- as.numeric(parts[2])
  (hi - lo) / 100
}

fine_widths <- sapply(fine_names, parse_width)
weights     <- fine_widths / sum(fine_widths)

# Keep all 127 groups from P1e; lower bound (%) used as gpercentile in income.csv
income_2025  <- p1e[1:127, , drop = FALSE]
lower_bounds <- sapply(rownames(income_2025), function(lbl) {
  parts <- strsplit(lbl, "p")[[1]]
  parts <- parts[parts != ""]
  as.numeric(parts[1])
}, USE.NAMES = FALSE)


# ── compute income for each year via spliced parametric model ────────────────
#
# Spliced model (Bothe et al. 2026, Appendix A):
#   - Below p_splice = 0.999: Type II Pareto with CDF
#       F(x) = 1 - (beta / (x - x_m + beta))^alpha,  x > x_m
#   - Above p_splice: exponential tail with rate lambda, starting at
#       q_splice = Q(p_splice).
#   Continuity at the splice point gives the overall income distribution.
#
# Per (country, year): fit (x_m, alpha, beta, lambda) by minimising the
# relative squared error on the 8 non-overlapping bracket means derived from
# the I9 post-GIT series (B10, p10-50, M40, p90-99, p99-99.9, p99.9-99.99,
# p99.99-99.999, p99.999-100). The model is rescaled to mean=1 inside the
# objective, and observations are normalised by I9i (overall mean) so the
# fit is scale-free. After fitting we evaluate analytical bracket means for
# all 127 gpercentile groups and multiply by I9i to restore actual income.
#
# Row → bracket mapping (127 rows): same boundaries as `lower_bounds`.

message("Computing income by year (spliced Pareto / exponential fit)...")

# splice point
P_SPLICE <- 0.999

#' Type II Pareto quantile.  p in [0, 1].
q_p2 <- function(p, xm, al, be) xm + be * ((1 - p)^(-1 / al) - 1)

#' Type II Pareto partial mean M(p) = int_0^p Q(u) du.
m_p2 <- function(p, xm, al, be) {
  xm * p + be / (al - 1) * (1 - al * (1 - p)^((al - 1) / al)) + be * (1 - p)
}

#' Pareto bracket mean E[W | p_L < U < p_H] for p_L, p_H both <= p_splice.
bm_p2 <- function(pL, pH, xm, al, be) {
  (m_p2(pH, xm, al, be) - m_p2(pL, xm, al, be)) / (pH - pL)
}

#' Exponential-tail bracket mean for p_L, p_H both >= p_splice.
bm_exp <- function(pL, pH, q_splice, la, p_splice = P_SPLICE) {
  if (pH >= 1 - 1e-15) {
    # closed form for p_H = 1
    yL <- -log((1 - pL) / (1 - p_splice)) / la
    return(q_splice + yL + 1 / la)
  }
  yL <- -log((1 - pL) / (1 - p_splice)) / la
  yH <- -log((1 - pH) / (1 - p_splice)) / la
  eL <- exp(-la * yL)
  eH <- exp(-la * yH)
  q_splice + ((yL + 1 / la) * eL - (yH + 1 / la) * eH) / (eL - eH)
}

#' Bracket mean for an arbitrary [pL, pH], handling crossings of p_splice.
bm_any <- function(pL, pH, xm, al, be, la, p_splice = P_SPLICE) {
  q_splice <- q_p2(p_splice, xm, al, be)
  if (pH <= p_splice) {
    return(bm_p2(pL, pH, xm, al, be))
  }
  if (pL >= p_splice) {
    return(bm_exp(pL, pH, q_splice, la, p_splice))
  }
  # mixed bracket: weight Pareto part [pL, p_splice] and exp part [p_splice, pH]
  w_lo <- (p_splice - pL) / (pH - pL)
  w_hi <- (pH - p_splice) / (pH - pL)
  mean_lo <- bm_p2(pL, p_splice, xm, al, be)
  mean_hi <- bm_exp(p_splice, pH, q_splice, la, p_splice)
  w_lo * mean_lo + w_hi * mean_hi
}

#' Overall mean of the spliced distribution.
mu_spliced <- function(xm, al, be, la, p_splice = P_SPLICE) {
  q_splice <- q_p2(p_splice, xm, al, be)
  m_p2(p_splice, xm, al, be) + (1 - p_splice) * (q_splice + 1 / la)
}

#' Map unconstrained parameter vector to (xm, al, be, la) with constraints
#'   al > 1.001, be > 0, la > 0  (xm unconstrained).
unpack_par <- function(par) {
  list(
    xm = par[1],
    al = 1.001 + exp(par[2]),
    be = exp(par[3]),
    la = exp(par[4])
  )
}

#' Default starting points (unconstrained: xm, log(al-1.001), log(be), log(la)).
#' Cover a wide range of inequality levels; the data-driven start (below) takes
#' priority but these are used as fallbacks.
DEFAULT_STARTS <- list(
  c( 0.00,  0.50,  0.00,  0.00),   # lambda ~ 1    (low inequality / post-SC)
  c( 0.00,  0.50,  0.00, -3.00),   # lambda ~ 0.05 (moderate inequality)
  c( 0.00,  0.50,  0.00, -6.00),   # lambda ~ 0.002 (high pre-SC inequality)
  c( 0.20,  0.50, -0.70, -4.50),   # lambda ~ 0.01
  c(-0.30,  1.00,  0.00, -1.50),   # lambda ~ 0.22
  c( 0.10,  0.00, -0.50, -0.50)    # alternative shape
)

#' Analytical starting estimate for log(lambda) from the two top I9 brackets.
#'
#' The exponential tail formula gives:
#'   E[W | 0.999, 1] = q_splice + 1/lambda
#'   E[W | 0.99999, 1] = q_splice + 4.605/lambda + 1/lambda
#' Subtracting: 1/lambda = (obs6 - obs8_... wait, obs[8]-obs[6]) / 4.605
#' where obs[6] = [0.999,1.0] mean and obs[8] = [0.99999,1.0] mean (normalised).
analytical_la_start <- function(obs_bm_norm) {
  # obs_bm_norm[6] = top-0.1%  (bracket [0.999,   1.0])
  # obs_bm_norm[8] = top-0.001% (bracket [0.99999, 1.0])
  A <- obs_bm_norm[6]; B <- obs_bm_norm[8]
  if (!is.finite(A) || !is.finite(B) || B <= A) return(NULL)
  inv_la <- (B - A) / 4.605        # 1/lambda in normalised units
  log_la <- log(1 / max(inv_la, 1e-6))
  # rough x_m from B10 mean; rough beta from M40/B10 ratio
  b10 <- obs_bm_norm[1]; m40 <- obs_bm_norm[3]
  log_al <- if (b10 > 0 && m40 > b10) pmin(pmax(log(m40/b10) * 0.5, -1), 3) else 0.5
  c(xm = -0.2, log_al = log_al, log_be = -0.5, log_la = log_la)
}

#' Fit spliced model to normalised bracket means.
#'
#' @param obs_pL Numeric vector of 8 lower bounds.
#' @param obs_pH Numeric vector of 8 upper bounds.
#' @param obs_bm_norm Numeric vector of 8 observed bracket means (divided by
#'   overall mean so true mean of observations ≈ 1).
#' @param par0 Warm-start in unconstrained space
#'   (xm, log(al-1.001), log(be), log(la)).
#' @return Named numeric vector c(xm, al, be, la, par_raw_*), rescaled so the
#'   model distribution has mean = 1.  Returns NULL if no good fit found.
fit_spliced_normed <- function(obs_pL, obs_pH, obs_bm_norm, par0) {
  obj <- function(par) {
    p <- unpack_par(par)
    if (!is.finite(p$xm) || !is.finite(p$al) || !is.finite(p$be) || !is.finite(p$la)) {
      return(1e12)
    }
    bm_mod <- vapply(seq_along(obs_pL),
                     function(i) bm_any(obs_pL[i], obs_pH[i],
                                        p$xm, p$al, p$be, p$la),
                     numeric(1))
    mu_m <- mu_spliced(p$xm, p$al, p$be, p$la)
    if (!is.finite(mu_m) || mu_m <= 1e-6) return(1e12)
    bm_mod_n <- bm_mod / mu_m
    if (any(!is.finite(bm_mod_n))) return(1e12)
    denom <- ifelse(abs(obs_bm_norm) < 1e-12, 1e-12, obs_bm_norm)
    sum(((bm_mod_n - obs_bm_norm) / denom)^2)
  }

  run_optim <- function(p0) {
    tryCatch(
      optim(p0, obj, method = "Nelder-Mead",
            control = list(maxit = 5000, reltol = 1e-8)),
      error = function(e) NULL
    )
  }

  # Candidates: analytical data-driven start, then warm-start, then defaults
  la_start <- tryCatch(analytical_la_start(obs_bm_norm), error = function(e) NULL)
  start_candidates <- c(
    if (!is.null(la_start)) list(la_start) else list(),
    list(par0),
    DEFAULT_STARTS
  )

  best <- NULL
  for (p0 in start_candidates) {
    fit <- run_optim(p0)
    if (is.null(fit) || !is.finite(fit$value)) next
    if (is.null(best) || fit$value < best$value) best <- fit
    # if any start already gives an excellent fit, stop trying
    if (!is.null(best) && best$value < 0.01) break
  }
  if (is.null(best)) return(NULL)

  p_hat  <- unpack_par(best$par)
  mu_hat <- mu_spliced(p_hat$xm, p_hat$al, p_hat$be, p_hat$la)
  if (!is.finite(mu_hat) || mu_hat <= 1e-6) return(NULL)

  # rescale so model has mean = 1 (xm scales, be scales, q_splice scales,
  # and the exponential rate transforms as la_new = la_old * mu_hat).
  c(
    xm  = p_hat$xm / mu_hat,
    al  = p_hat$al,
    be  = p_hat$be / mu_hat,
    la  = p_hat$la * mu_hat,
    par_raw_xm = best$par[1],   # warm-start params (raw scale) for next year
    par_raw_la = best$par[2],
    par_raw_lb = best$par[3],
    par_raw_ll = best$par[4],
    obj_value  = best$value
  )
}

#' Build the income distribution for all years via the spliced model.
#'
#' @param ts_b10..ts_d0001 Aligned I9 group-average time-series data frames.
#' @param ts_mean Overall post-GIT mean time series (I9i).
#' @param years Vector of years to compute.
#' @return Named list (one element per year) of 127 × n_country data frames.
build_income_gpinter <- function(ts_b10, ts_b50, ts_m40, ts_t10,
                                  ts_t1, ts_d01, ts_d001, ts_d0001,
                                  ts_mean, years = INCOME_YEARS) {
  # 8 non-overlapping bracket bounds
  br_lo <- c(0,    0.10, 0.50, 0.90, 0.99, 0.999, 0.9999, 0.99999)
  br_hi <- c(0.10, 0.50, 0.90, 0.99, 0.999, 0.9999, 0.99999, 1.0)

  # output 127-group bounds (from lower_bounds and the next-row lower bound)
  out_pL <- lower_bounds / 100
  out_pH <- c(out_pL[-1], 1.0)

  # default starting point in unconstrained (log-transformed) space
  par0_default <- DEFAULT_STARTS[[1]]

  # warm-start cache: one current parameter vector per country
  warm <- setNames(replicate(length(ctries), par0_default, simplify = FALSE),
                   ctries)

  result <- setNames(vector("list", length(years)), as.character(years))

  for (yr in years) {
    yr_s <- as.character(yr)
    if ((yr - min(years)) %% 10 == 0) {
      message(sprintf("  year %d ...", yr))
    }

    b10   <- as.numeric(ts_b10[yr_s,   ctries])
    b50   <- as.numeric(ts_b50[yr_s,   ctries])
    m40   <- as.numeric(ts_m40[yr_s,   ctries])
    t10   <- as.numeric(ts_t10[yr_s,   ctries])
    t1    <- as.numeric(ts_t1[yr_s,    ctries])
    d01   <- as.numeric(ts_d01[yr_s,   ctries])
    d001  <- as.numeric(ts_d001[yr_s,  ctries])
    d0001 <- as.numeric(ts_d0001[yr_s, ctries])
    mu_yr <- as.numeric(ts_mean[yr_s,  ctries])

    # derived non-overlapping bracket averages (positive)
    eps <- 1e-9
    p10_50      <- pmax((b50  * 0.5     - b10  * 0.1)     / 0.4,    eps)
    p90_99      <- pmax((t10  * 0.1     - t1   * 0.01)    / 0.09,   eps)
    p99_999     <- pmax((t1   * 0.01    - d01  * 0.001)   / 0.009,  eps)
    p999_9999   <- pmax((d01  * 0.001   - d001 * 0.0001)  / 0.0009, eps)
    p9999_99999 <- pmax((d001 * 0.0001  - d0001* 0.00001) / 0.00009, eps)

    out_mat <- matrix(NA_real_, length(out_pL), length(ctries),
                      dimnames = list(NULL, ctries))

    for (ci in seq_along(ctries)) {
      ctry <- ctries[ci]
      mu_c <- mu_yr[ci]
      if (!is.finite(mu_c) || mu_c <= 0) {
        # no usable mean -> skip (leave NA)
        next
      }
      obs <- c(b10[ci], p10_50[ci], m40[ci], p90_99[ci],
               p99_999[ci], p999_9999[ci], p9999_99999[ci], d0001[ci])
      if (any(!is.finite(obs)) || any(obs <= 0)) next
      obs_norm <- obs / mu_c

      par0 <- warm[[ctry]]
      fit  <- tryCatch(fit_spliced_normed(br_lo, br_hi, obs_norm, par0),
                       error = function(e) NULL)
      if (is.null(fit)) next

      # remember warm-start params (raw scale) for next year
      warm[[ctry]] <- c(fit["par_raw_xm"], fit["par_raw_la"],
                        fit["par_raw_lb"], fit["par_raw_ll"])

      xm <- fit["xm"]; al <- fit["al"]; be <- fit["be"]; la <- fit["la"]
      # evaluate 127 bracket means under the mean-1 distribution
      bm_127 <- vapply(seq_along(out_pL),
                       function(i) bm_any(out_pL[i], out_pH[i],
                                          xm, al, be, la),
                       numeric(1))
      if (any(!is.finite(bm_127) | bm_127 <= 0)) next
      out_mat[, ci] <- bm_127 * mu_c
    }

    result[[yr_s]] <- as.data.frame(out_mat)
  }

  # Post-process: fill failed country-year fits by log-linear interpolation
  yr_names <- as.character(years)
  n_filled <- 0L
  for (ctry in ctries) {
    ctry_mat <- vapply(yr_names,
                       function(y) result[[y]][[ctry]],
                       numeric(length(out_pL)))
    col_ok <- which(apply(ctry_mat, 2, function(x) all(is.finite(x) & x > 0)))
    col_na <- which(apply(ctry_mat, 2, function(x) any(!is.finite(x) | x <= 0)))
    if (length(col_na) == 0 || length(col_ok) == 0) next
    for (bad in col_na) {
      yr_bad <- years[bad]
      before <- col_ok[years[col_ok] < yr_bad]
      after  <- col_ok[years[col_ok] > yr_bad]
      if (length(before) == 0 && length(after) == 0) next
      if (length(before) == 0) {
        ctry_mat[, bad] <- ctry_mat[, after[1]]
      } else if (length(after) == 0) {
        ctry_mat[, bad] <- ctry_mat[, tail(before, 1)]
      } else {
        b <- tail(before, 1); a <- after[1]
        w_a <- (yr_bad - years[b]) / (years[a] - years[b])
        v_b <- ctry_mat[, b]; v_a <- ctry_mat[, a]
        ctry_mat[, bad] <- exp((1 - w_a) * log(v_b) + w_a * log(v_a))
      }
      n_filled <- n_filled + 1L
    }
    for (j in seq_along(yr_names)) {
      result[[yr_names[j]]][[ctry]] <- ctry_mat[, j]
    }
  }
  if (n_filled > 0) message(sprintf("  interpolated %d failed country-year fits", n_filled))
  result
}

inc_by_year <- build_income_gpinter(i9e, i9b, i9h, i9a, i9c, i9d, i9f, i9g,
                                     i9i, years = INCOME_YEARS)


# ── write income.csv ─────────────────────────────────────────────────────────
# Wide format: one row per (country, gpercentile), one col per year 2020-2100

message("Writing income.csv...")
year_cols <- setNames(
  lapply(as.character(INCOME_YEARS), function(y) inc_by_year[[y]]),
  paste0("income_", INCOME_YEARS)
)
rows <- do.call(rbind, lapply(ctries, function(ctry) {
  yr_vals <- lapply(year_cols, function(m) m[[ctry]])
  as.data.frame(c(list(country = ctry, gpercentile = lower_bounds), yr_vals),
                stringsAsFactors = FALSE)
}))
inc_cols <- grep("^income_", names(rows), value = TRUE)
rows[, inc_cols] <- lapply(rows[, inc_cols], round, digits = 0)
write.csv(rows, "../data/income_legacy.csv", row.names = FALSE, quote = FALSE)


# ── write income_world.csv ────────────────────────────────────────────────────
# Distribution chart: 100 world percentiles × target years

message("Writing income_world.csv...")
dist_years <- c(2025, 2030, 2035, 2050, 2080, 2100)
# income_world keeps 100 rows: rows 1-99 direct, top-1% collapsed via pop weights
world_agg <- function(yr_s) {
  wv <- inc_by_year[[yr_s]][["World"]]
  c(wv[1:99], sum(wv[100:127] * weights))
}
wld_cols <- setNames(
  lapply(as.character(dist_years), world_agg),
  paste0("income_", dist_years)
)
world_df <- as.data.frame(c(list(gpercentile = 1:100), wld_cols))
wld_inc_cols <- grep("^income_", names(world_df), value = TRUE)
world_df[, wld_inc_cols] <- lapply(world_df[, wld_inc_cols], round, digits = 0)
write.csv(world_df, "../data/income_world_legacy.csv", row.names = FALSE, quote = FALSE)


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
pg_cols <- c("p10","p50","p99","p99.9","p99.99","p99.999")
pre_git_rows[, pg_cols] <- lapply(pre_git_rows[, pg_cols], round, digits = 0)
write.csv(pre_git_rows, "../data/income_pre_git_legacy.csv", row.names = FALSE, quote = FALSE)


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
wlth_cols <- grep("^wealth_", names(wrows), value = TRUE)
wrows[, wlth_cols] <- lapply(wrows[, wlth_cols], round, digits = 0)
write.csv(wrows, "../data/wealth_legacy.csv", row.names = FALSE, quote = FALSE)


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
wwld_cols <- grep("^wealth_", names(wworld_df), value = TRUE)
wworld_df[, wwld_cols] <- lapply(wworld_df[, wwld_cols], round, digits = 0)
write.csv(wworld_df, "../data/wealth_world_legacy.csv", row.names = FALSE, quote = FALSE)

message("Done. Legacy files written to data/")


# ── new: post-GIT income from distribution_simul.dta + country dividends ─────
#
# Reads the Bothe Stata simulator output and computes a per-adult post-GIT
# income series for every (country, year, percentile):
#
#   income = sdiinc * nni / diff  -  ypt  +  dividend[year]
#
# where:
#   - sdiinc * nni / diff = per-adult posttax disposable income at the
#     percentile (DINA broad concept; sums to NNI by construction).
#   - ypt = per-adult Global Income Tax payment at the percentile.
#   - dividend[year] = the Global Justice Fund's "Country Dividend" — an
#     equal-per-capita worldwide lump-sum (sheet E3bp), funded by GIT + GWT
#     revenue + WSF investment returns minus reinvestment.
#
# The Global Wealth Tax is NOT subtracted from income: it is a stock tax on
# wealth, not a flow tax on income, and the simulator routes it into the
# wealth equation (wp <- wp - wpt), not the income equation. Its effect on
# households' resources will surface in the (future) wealth.csv. Its revenue
# is fed back to households through `dividend[year]`.
#
# For year 2025 the simulation loop has not yet run (ypt = 0 in the .dta),
# and E3bp's dividend may or may not be zero, so 2025 = sdiinc * nni / diff
# + dividend[2025] depending on Bothe's GJF startup assumption.

message("Computing post-GIT income from distribution_simul.dta + dividends (E3bp)...")
library(haven)
simul <- as.data.frame(read_dta("../data/Bothe/distribution_simul.dta"))

# Per-adult posttax disposable income at the percentile (computed for every
# year, including 2025 where the .dta stores yp = 0).
simul$yp_recomp <- with(simul,
  ifelse(is.finite(diff) & diff > 0 & is.finite(sdiinc) & is.finite(nni),
         sdiinc * nni / diff, NA_real_))

# Country dividend per adult, in EUR PPP 2025/year, from sheet E3bp of the
# Macro appendix workbook. Values are uniform across countries (equal per
# capita worldwide), so we read column "World" (col 2).
e3bp <- suppressMessages(read_excel(
  "../data/Bothe/Botheetal2026AppendixMacro.xlsx", sheet = "E3bp",
  col_names = FALSE))
e3bp_years <- suppressWarnings(as.numeric(unlist(e3bp[-(1:4), 1])))
e3bp_world <- suppressWarnings(as.numeric(unlist(e3bp[-(1:4), 2])))
dividend <- setNames(e3bp_world, as.character(e3bp_years))

simul$dividend <- dividend[as.character(simul$year)]
simul$income   <- simul$yp_recomp - simul$ypt + simul$dividend # yp_recomp = diinc

# ---- Variant: add GJF TOTAL revenues (E2), not the post-reinvestment dividend
#
# Per-adult total fund revenues (= GIT + GWT + WSF investment income, gross of
# any reinvestment into the World Sovereign Fund) in EUR PPP 2025. The Bothe
# appendix does not publish this in EUR PPP per adult directly, so we derive it
# from two %-world-GDP-MER series that share the same denominator (so the
# unit cancels in their ratio):
#
#   revenue_per_adult_PPP[y] = E3bp[y] * (E2aw_world[y] / E3bw_world[y])
#
# In the workbook layout, column 2 of every macro sheet holds the World total
# (followed by 9 regional and 57 country columns whose values double-count the
# World column), so we read col 2 directly.
#
# For years where dividends are still zero (2025 in the simulation: GJF startup,
# E3bw = 0), the ratio is undefined; we fall back to the .dta's (yt + wt)
# world-population-weighted average, which equals current-year tax revenue per
# adult (no WSF investment income yet to speak of).

read_world_col <- function(sheet) {
  d <- suppressMessages(read_excel(
    "../data/Bothe/Botheetal2026AppendixMacro.xlsx", sheet = sheet,
    col_names = FALSE))
  yr <- suppressWarnings(as.numeric(unlist(d[-(1:4), 1])))
  val <- suppressWarnings(as.numeric(unlist(d[-(1:4), 2])))
  setNames(val, as.character(yr))
}
e2aw_world <- read_world_col("E2aw")   # GJF total revenues, % world GDP MER
e3bw_world <- read_world_col("E3bw")   # GJF dividends,        % world GDP MER

# .dta-based fallback: (yt + wt) world per-adult average in EUR PPP 2025
cy <- unique(simul[, c("country", "year", "pop", "yt", "wt")])
cy$rev <- (cy$yt + cy$wt) * cy$pop
fallback_rev <- tapply(cy$rev, cy$year, sum, na.rm = TRUE) /
                tapply(cy$pop, cy$year, sum, na.rm = TRUE)

yrs_all <- as.character(sort(unique(simul$year)))
e2_per_adult <- sapply(yrs_all, function(y) {
  div <- unname(dividend[y]); r <- unname(e3bw_world[y]); tot <- unname(e2aw_world[y])
  if (!is.na(div) && !is.na(r) && !is.na(tot) && r > 1e-9) {
    div * tot / r
  } else {
    unname(fallback_rev[y])
  }
})

simul$revenue_pa <- e2_per_adult[as.character(simul$year)]
simul$income_full_rev <- simul$yp_recomp - simul$ypt + simul$revenue_pa # uses E2 instead of E3 for the dividend: E2 includes reinvested funds

# Enforce monotonicity on bottom 99 percentiles per (country, year): the FG/Bothe
# input has small local non-monotonicities at decile boundaries (visible in
# IT around g=10, g=20) which propagate downstream. We sort the values at
# gpercentile < 99 ascending within each country-year column, keeping the
# gpercentile labels fixed. The top 1% (g >= 99) is left untouched.
sort_bottom99 <- function(d, value_cols, p_col = "gpercentile",
                          country_col = "country") {
  for (ctry in unique(d[[country_col]])) {
    r <- which(d[[country_col]] == ctry & d[[p_col]] < 99)
    for (vc in value_cols) d[r, vc] <- sort(d[r, vc], na.last = TRUE)
  }
  d
}

# Wide format: one row per (country, gpercentile), one column per year.
yrs   <- sort(unique(simul$year))
wide  <- reshape(simul[, c("country", "p1", "year", "income")],
                 idvar = c("country", "p1"), timevar = "year",
                 v.names = "income", direction = "wide")
yr_cols <- paste0("income.", yrs)
wide <- wide[, c("country", "p1", yr_cols)]
names(wide) <- c("country", "gpercentile", paste0("income_", yrs))
wide <- wide[order(wide$country, wide$gpercentile), ]
wide <- sort_bottom99(wide, paste0("income_", yrs))
wide_inc_cols <- paste0("income_", yrs)
wide[, wide_inc_cols] <- lapply(wide[, wide_inc_cols], round, digits = 0)
write.csv(wide, "../data/income.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ../data/income.csv: %d rows x %d cols (post-GIT, dividend E3bp)",
                nrow(wide), ncol(wide)))

wide2 <- reshape(simul[, c("country", "p1", "year", "income_full_rev")],
                 idvar = c("country", "p1"), timevar = "year",
                 v.names = "income_full_rev", direction = "wide")
yr_cols2 <- paste0("income_full_rev.", yrs)
wide2 <- wide2[, c("country", "p1", yr_cols2)]
names(wide2) <- c("country", "gpercentile", paste0("income_", yrs))
wide2 <- wide2[order(wide2$country, wide2$gpercentile), ]
wide2 <- sort_bottom99(wide2, paste0("income_", yrs))
wide2[, wide_inc_cols] <- lapply(wide2[, wide_inc_cols], round, digits = 0)
write.csv(wide2, "../data/income_full_revenues.csv", row.names = FALSE, quote = FALSE)
message(sprintf("Wrote ../data/income_full_revenues.csv: %d rows x %d cols (post-GIT, full GJF revenue E2)",
                nrow(wide2), ncol(wide2)))


# ── copy rounded versions to code_simulator/data/ (used by the webpage) ───────

message("Writing rounded copies to code_simulator/data/...")
src_files <- list.files("../data", pattern = "\\.csv$", full.names = TRUE)
dir.create("data", showWarnings = FALSE)
for (f in src_files) {
  d <- read.csv(f, check.names = FALSE)
  num_cols <- sapply(d, is.numeric)
  d[num_cols] <- lapply(d[num_cols], round, digits = 0)
  write.csv(d, file.path("data", basename(f)), row.names = FALSE, quote = FALSE)
}
message("Done. Rounded files written to code_simulator/data/")


# SC45k = ((gdp_it_2025 * (65/75) + 45000 * (10/75)) / gdp_it_2035)*SC2
# SC30k = ((gdp_it_2025 * (65/75) + 30000 * (10/75)) / gdp_it_2035)*SC2
# SC15k = ((gdp_it_2025 * (65/75) + 15000 * (10/75)) / gdp_it_2035)*SC2
# ((gdp_it_2025 * (65/75) + 30000 * (10/75)) / gdp_it_2025)-1 # SC30k with linear convergence: -3.7%
# ((gdp_it_2025 * (65/75) + 15000 * (10/75)) / gdp_it_2025)-1 # SC15k with linear convergence: -8.5%
