# =============================================================================
# Part 3 - Estimation of the primary specification (H1-H4)
# =============================================================================
#
# Model: linear probability model (lm), NOT cjoint::amce(). Coefficients are
# interpreted as AMCEs following Hainmueller et al. (2014), but estimated via
# a standard regression with attribute dummies as regressors. cjoint::amce()
# isn't used here because it assumes a single randomized design per call, so
# it can't natively estimate the mandatory hours x growth interaction (H3) -
# growth is fixed within each task, so that interaction requires pooling
# Task 2 and Task 3 together - or a term for future_income_above_current
# (H4), a respondent-level derived comparison, not a native design
# attribute. cluster-robust SE, no weights here as per this pre-registration.
#
# Formula:
#   selected ~ temperature + NetIncome + hoursPerWeek_f + publicServices +
#              beefAndFlights + nationalRedistribution + globalRedistribution +
#              growth + hours_x_growth + future_income_above_current
#
# Notes on the specification:
#   - temperature, NetIncome: numeric (not dummy)
#   - hoursPerWeek_f, publicServices, beefAndFlights, nationalRedistribution,
#     globalRedistribution: categorical, entered as factors (R expands to
#     dummy sets automatically, reference = first level)
#   - growth: added as its own main-effect covariate (not only through the
#     interaction), to avoid omitted-variable bias in the hours x growth
#     interaction coefficient. This is a control, not an estimand in itself.
#   - hours_x_growth: mandatory interaction term (H3)
#   - future_income_above_current: dummy (H4), estimated controlling for
#     NetIncome (future income level), as required by H4's wording
#
# Clustering: standard errors clustered by respondent (resp_id), since each
# respondent contributes profiles from 2 pairs (Task 2 + Task 3).
#
# No survey weights (confirmed: no weight variable in the data, and none
# specified in the pre-registration).
# =============================================================================

library(dplyr)
library(sandwich)
library(lmtest)
library(car)

# -----------------------------------------------------------------------------
# 1. Fit the primary model
# -----------------------------------------------------------------------------

#' Fit the primary H1-H4 linear probability model
#' NetIncome_1k = NetIncome / 1,000 (see build_primary_vars(), Part 2) - the
#' natural unit, since NetIncome is on the same monthly scale as the
#' respondent's own current_income
#' @param model_data output of build_primary_vars() (Part 2), Task 2+3 pooled
fit_primary_model <- function(model_data) {
  lm(
    selected ~ temperature + NetIncome_1k + hoursPerWeek_f + publicServices +
      beefAndFlights + nationalRedistribution + globalRedistribution +
      growth + hours_x_growth + future_income_above_current,
    data = model_data
  )
}

#' Cluster-robust variance-covariance matrix, clustered by respondent
#' (HC1-type cluster-robust SE via sandwich::vcovCL; standard approximation,
#' residual model df used for the t-reference distribution - a CR2 / Satterthwaite
#' refinement via clubSandwich could be added later as a robustness check).
cluster_vcov <- function(model, data) {
  sandwich::vcovCL(model, cluster = data$resp_id, type = "HC1")
}

# -----------------------------------------------------------------------------
# 2. Build the pre-registered test table (H1-H4) with FDR correction
# -----------------------------------------------------------------------------

#' One-sided p-value from a fitted coefficient, using the model's residual df
#' @param est point estimate
#' @param se cluster-robust SE
#' @param df residual degrees of freedom of the model (approximation; see
#'   note above on CR1 vs CR2)
#' @param direction "negative" or "positive": the pre-registered expected sign
one_sided_p <- function(est, se, df, direction = c("negative", "positive")) {
  direction <- match.arg(direction)
  t_stat <- est / se
  if (direction == "negative") {
    pt(t_stat, df = df, lower.tail = TRUE)
  } else {
    pt(t_stat, df = df, lower.tail = FALSE)
  }
}

#' Significance stars from an (FDR-adjusted) p-value
#' Convention: *** p<0.01, ** p<0.05, * p<0.1
sig_stars <- function(p) {
  ifelse(is.na(p), "",
    ifelse(p < 0.01, "***",
      ifelse(p < 0.05, "**",
        ifelse(p < 0.1, "*", ""))))
}

#' Build the full table of pre-registered tests for H1-H4
#'
#' H1 (two-sided, non-zero effect), one row per displayed attribute:
#'   - numeric attributes (temperature, NetIncome): single-coefficient t-test
#'   - categorical attributes (hoursPerWeek, beefAndFlights,
#'     nationalRedistribution, globalRedistribution, publicServices): joint
#'     F-test across all dummy levels of that attribute (car::linearHypothesis)
#' H2 (one-sided, negative): temperature coefficient
#' H3 (two-sided): hours_x_growth interaction coefficient
#' H4 (one-sided, positive): future_income_above_current coefficient
#'
#' FDR (Benjamini-Hochberg) correction is applied across all rows of this
#' table jointly, per the pre-registration ("FDR correction is applied to
#' all pre-registered tests").
#'
#' Output columns: attribute (human-readable label, unlabeled header),
#' estimate (coefficient with FDR-based significance stars; for joint
#' F-test rows, "F = <stat>" since there is no single coefficient), se
#' (cluster-robust SE in parentheses; blank for joint F-test rows). N
#' (respondents) and R2 are constant across all rows (one shared model), so
#' they are NOT included as columns - they are attached as attributes
#' (attr(..., "N"), attr(..., "R2")) for the caller to place in a table
#' footer instead (see save_table()'s `footer` argument).
#'
#' @param n_participants number of unique respondents contributing to `model`
#'   (distinct from nobs(model), which counts profile-level observations -
#'   each respondent contributes up to 4 profile rows)
build_h1h4_table <- function(model, vcov_mat, n_participants) {

  ct <- lmtest::coeftest(model, vcov = vcov_mat)
  df_resid <- model$df.residual

  # Human-readable labels for the raw attribute/variable names. For the 3
  # attributes that are always single-dummy tests (publicServices,
  # nationalRedistribution, globalRedistribution - never joint F, see
  # attr_terms below), the level is stated directly in the label ("X: level
  # (vs. baseline)") so the row's sign is unambiguous without having to
  # remember which level "current"/"stable" maps to - the ambiguity that
  # caused "Inequality (national): SN" to initially read as "prefers more
  # inequality" when it actually means the opposite (SN = redistribution on)
  attr_labels <- c(
    temperature             = "Temperature",
    NetIncome               = "Income (per 1k/month)",
    hoursPerWeek            = "Working hours",
    publicServices          = "Public services: increased (vs. stable)",
    beefAndFlights          = "Beef \\& flights restrictions",
    nationalRedistribution  = "National redistribution (vs. current)",
    globalRedistribution    = "Global redistribution (vs. current)"
  )

  # Individual dummy-level labels (vs. baseline), shown as indented rows
  # right under the joint F-test row for hoursPerWeek/beefAndFlights -
  # descriptive detail only (NOT part of the FDR-corrected pre-registered
  # test family built below). hoursPerWeek_f's baseline is 40h (the 2025
  # standard work week - see build_primary_vars(), Part 2), so the 3
  # dummies are for 32/36/44h, not 36/40/44h.
  level_labels <- c(
    hoursPerWeek_f32      = "\\hspace{1em} 32h/week (vs. 40h)",
    hoursPerWeek_f36      = "\\hspace{1em} 36h/week (vs. 40h)",
    hoursPerWeek_f44      = "\\hspace{1em} 44h/week (vs. 40h)",
    beefAndFlightsbeef    = "\\hspace{1em} Less beef (vs. stable)",
    beefAndFlightsflights = "\\hspace{1em} Less flights (vs. stable)",
    beefAndFlightsboth    = "\\hspace{1em} Less beef \\& flights (vs. stable)"
  )

  # --- H1: joint/individual non-zero-effect test per attribute ---
  attr_terms <- list(
    temperature            = "temperature",
    NetIncome               = "NetIncome_1k",
    hoursPerWeek            = c("hoursPerWeek_f32", "hoursPerWeek_f36", "hoursPerWeek_f44"),
    publicServices          = "publicServicesincreased",
    beefAndFlights           = c("beefAndFlightsbeef", "beefAndFlightsflights", "beefAndFlightsboth"),
    nationalRedistribution  = "nationalRedistributionSN",
    globalRedistribution    = "globalRedistributionGIT"
  )

  h1_rows <- purrr::imap_dfr(attr_terms, function(terms, attr_name) {
    terms <- terms[terms %in% rownames(ct)]
    label <- attr_labels[[attr_name]]
    if (length(terms) == 0) {
      warning("term(s) not found in model for attribute '", attr_name, "' - check factor levels")
      return(tibble::tibble(attribute = label,
                             test_type = "missing", estimate = NA_real_, se = NA_real_,
                             p_value_raw = NA_real_))
    }
    if (length(terms) == 1) {
      tibble::tibble(
        attribute = label, test_type = "t (single dummy)",
        estimate = ct[terms, "Estimate"], se = ct[terms, "Std. Error"],
        p_value_raw = ct[terms, "Pr(>|t|)"]
      )
    } else {
      form <- paste(terms, "= 0")
      ftest <- car::linearHypothesis(model, form, vcov. = vcov_mat, test = "F")
      tibble::tibble(
        attribute = label, test_type = "joint F (multi-level)",
        estimate = ftest$F[2], se = NA_real_,
        p_value_raw = ftest$`Pr(>F)`[2]
      )
    }
  })

  # --- H2: temperature, one-sided, expected negative ---
  h2_row <- tibble::tibble(
    attribute = "Temperature (one-sided)",
    test_type = "t (one-sided)",
    estimate = ct["temperature", "Estimate"],
    se = ct["temperature", "Std. Error"],
    p_value_raw = one_sided_p(ct["temperature", "Estimate"], ct["temperature", "Std. Error"],
                               df_resid, direction = "negative")
  )

  # --- H3: hours x growth interaction, two-sided ---
  h3_row <- tibble::tibble(
    attribute = "Working hours $\\times$ growth", test_type = "t (two-sided)",
    estimate = ct["hours_x_growth", "Estimate"],
    se = ct["hours_x_growth", "Std. Error"],
    p_value_raw = ct["hours_x_growth", "Pr(>|t|)"]
  )

  # --- H4: future income dummy, one-sided, expected positive ---
  h4_row <- tibble::tibble(
    attribute = "Future income $>$ current",
    test_type = "t (one-sided)",
    estimate = ct["future_income_above_current", "Estimate"],
    se = ct["future_income_above_current", "Std. Error"],
    p_value_raw = one_sided_p(ct["future_income_above_current", "Estimate"],
                               ct["future_income_above_current", "Std. Error"],
                               df_resid, direction = "positive")
  )

  full_table <- dplyr::bind_rows(h1_rows, h2_row, h3_row, h4_row)

  # FDR (Benjamini-Hochberg) across ALL 10 pre-registered tests jointly,
  # INCLUDING H2 (one-sided temperature) - even though H2 is then dropped
  # from the displayed table below (same coefficient/sign as the two-sided
  # "Temperature" row, so redundant to show twice), it must stay in the FDR
  # family since the correction is defined over all pre-registered tests
  full_table$p_value_fdr <- p.adjust(full_table$p_value_raw, method = "BH")

  is_joint_f <- full_table$test_type == "joint F (multi-level)"
  # Income's coefficient is genuinely tiny even in its natural unit (per
  # 1,000 EUR/month, matching the respondent's own income scale) - rather
  # than inflating the unit further just to force a non-zero-looking value
  # at 3 decimals, show it in scientific notation so the real magnitude
  # stays honest and visible
  is_income <- full_table$attribute == "Income (per 1k/month)"
  stars <- sig_stars(full_table$p_value_fdr)

  main_display <- tibble::tibble(
    " " = full_table$attribute,
    estimate = dplyr::case_when(
      is_joint_f ~ paste0("F = ", sprintf("%.3f", full_table$estimate), stars),
      is_income  ~ paste0(sprintf("%.2e", full_table$estimate), stars),
      TRUE       ~ paste0(sprintf("%.3f", full_table$estimate), stars)
    ),
    se = dplyr::case_when(
      is_joint_f ~ "",
      is_income  ~ paste0("(", sprintf("%.2e", full_table$se), ")"),
      TRUE       ~ paste0("(", sprintf("%.3f", full_table$se), ")")
    )
  )

  main_display <- main_display[main_display[[1]] != "Temperature (one-sided)", ]

  # --- individual dummy-level coefficients, indented under their joint
  # F-test row. Descriptive only: stars use the RAW (unadjusted) p-value,
  # not the FDR-corrected family above
  detail_terms <- names(level_labels)
  detail_terms <- detail_terms[detail_terms %in% rownames(ct)]
  detail_rows <- tibble::tibble(
    " " = unname(level_labels[detail_terms]),
    estimate = paste0(sprintf("%.3f", ct[detail_terms, "Estimate"]),
                       sig_stars(ct[detail_terms, "Pr(>|t|)"])),
    se = paste0("(", sprintf("%.3f", ct[detail_terms, "Std. Error"]), ")")
  )

  insert_after <- function(tbl, after_label, term_names) {
    rows <- detail_rows[detail_rows[[1]] %in% unname(level_labels[term_names]), ]
    idx <- which(tbl[[1]] == after_label)
    dplyr::bind_rows(tbl[seq_len(idx), ], rows, tbl[-seq_len(idx), ])
  }

  out <- insert_after(main_display, "Working hours",
                       c("hoursPerWeek_f32", "hoursPerWeek_f36", "hoursPerWeek_f44"))
  out <- insert_after(out, "Beef \\& flights restrictions",
                       c("beefAndFlightsbeef", "beefAndFlightsflights", "beefAndFlightsboth"))

  attr(out, "N")  <- n_participants
  attr(out, "R2") <- round(summary(model)$r.squared, 3)

  out
}

# Example usage:
# model_data <- build_primary_vars(amce_data)             # Part 2
# primary_model <- fit_primary_model(model_data)
# vcov_mat <- cluster_vcov(primary_model, model_data)
# n_participants <- length(unique(model_data$resp_id))
# results_h1h4 <- build_h1h4_table(primary_model, vcov_mat, n_participants)
# print(results_h1h4)
# save_table(results_h1h4, "results_h1h4")                 # txt + tex, via Part 1

# =============================================================================
# End of Part 3 (H1-H4 primary specification)
# =============================================================================
