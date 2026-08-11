# =============================================================================
# Part 4 - Task 1 (FEW): H5-H11 named-scenario contrasts + Bradley-Terry
# =============================================================================
#
# Input: few_pairs, the pair-level Task 1 data frame from Part 1
#        (reshape_named_task(raw_data)).
#
# H5-H11: for each of the 7 pre-registered contrasts (BC vs BI/BG/BN/BC_SD/
# BCmat/BCflight/BCbeef), a separate regression restricted to respondents who
# were actually shown that specific pair, DV = chose_BC (0/1), "I don't know"
# dropped (routed to the IDK analysis instead). Each respondent is drawn into
# at most one of the 7 contrasts in Task 1 (they see exactly one named pair),
# so no within-contrast clustering is needed; we use heteroskedasticity-
# robust (HC1) SE.
#
# One-sided test direction (per the pre-registration text):
#   - H5-H9 (BI, BG, BN, BC_SD, BCmat): "BC is preferred" -> H0: P(choose BC)
#     <= 0.5 vs H1: > 0.5
#   - H10-H11 (BCflight, BCbeef): the alternative is hypothesized to be
#     preferred ("the alternative scenario BCflights/BCbeef is preferred to
#     BC") -> H0: P(choose BC) >= 0.5 vs H1: < 0.5 - the opposite direction
#     from H5-H9. Getting this backwards would flip which contrasts count as
#     supporting their hypothesis (e.g. BC vs BCflight's raw 0.781 share
#     strongly rejects H10 as pre-registered, even though it would look
#     highly "significant" under the wrong H5-H9-style direction).
# FDR (Benjamini-Hochberg) correction is applied across exactly these 7
# tests, as pre-registered ("FDR correction is applied across the seven
# tests"), separately from the H1-H4 family (Part 3).
#
# Bradley-Terry: exploratory ranking of all 12 named scenarios (the 7 H5-H11
# alternatives + BC + the 4 income variants BC45k/BC90k/BC120k/BI120k), using
# BradleyTerry2::BTm() on all named-pair contests (Task 1), "I don't know"
# dropped.
# =============================================================================

library(dplyr)
library(sandwich)
library(lmtest)
library(BradleyTerry2)

# -----------------------------------------------------------------------------
# 1. H5-H11: BC vs each of the 7 named alternatives
# -----------------------------------------------------------------------------

# H10-H11: the two contrasts where the pre-registered hypothesis is that the
# ALTERNATIVE (not BC) is preferred, so the one-sided test direction flips
h5_h11_alt_preferred <- c("BCflight", "BCbeef")

#' One-sided p-value that the mean of a 0/1 outcome (share choosing BC) is
#' above or below 0.5
#' @param est intercept estimate (= sample mean of chose_BC in this design)
#' @param se robust SE of the intercept
#' @param df residual degrees of freedom
#' @param direction "above" (H0: <=0.5 vs H1: >0.5, H5-H9) or "below"
#'   (H0: >=0.5 vs H1: <0.5, H10-H11 - alternative scenario preferred)
one_sided_p_share <- function(est, se, df, direction = c("above", "below")) {
  direction <- match.arg(direction)
  t_stat <- (est - 0.5) / se
  pt(t_stat, df = df, lower.tail = (direction == "below"))
}

#' Fit one H5-H11 contrast: BC vs alt_scenario
#' @param few_pairs pair-level Task 1 data (Part 1 output)
#' @param alt_scenario one of the 7 named alternatives (e.g. "BI")
fit_one_contrast <- function(few_pairs, alt_scenario) {
  contrast_data <- few_contrast_data(few_pairs, alt_scenario)  # from Part 1

  model <- lm(chose_BC ~ 1, data = contrast_data)
  vcov_hc <- sandwich::vcovHC(model, type = "HC1")
  ct <- lmtest::coeftest(model, vcov = vcov_hc)

  est <- ct["(Intercept)", "Estimate"]
  se  <- ct["(Intercept)", "Std. Error"]
  df_resid <- model$df.residual
  direction <- if (alt_scenario %in% h5_h11_alt_preferred) "below" else "above"
  t_stat <- (est - 0.5) / se

  tibble::tibble(
    contrast = paste0("BC vs ", latex_escape_underscore(alt_scenario)),
    N = nrow(contrast_data),   # = respondents shown this pair (1 row/respondent)
    estimate = est,
    se = se,
    # R2 = 0 by construction (intercept-only model: fitted = mean, so
    # RSS = TSS); kept for column consistency with the other results tables
    R2 = summary(model)$r.squared,
    p_value_raw = one_sided_p_share(est, se, df_resid, direction),
    direction = direction,
    # two-sided p-value, used only to flag contrasts where the effect is
    # significant but in the direction OPPOSITE the pre-registered
    # hypothesis - otherwise a strong "wrong-direction" effect (e.g.
    # BCflight) would be invisible, showing no stars as if there were no
    # effect at all, rather than a real effect that contradicts the
    # hypothesis (raised as a concern: a one-sided-only test can hide this)
    p_value_two_sided = 2 * pt(-abs(t_stat), df = df_resid)
  )
}

#' Fit all 7 H5-H11 contrasts, apply FDR correction across them, and format
#' as coefficient (with FDR-based significance stars) + SE in parentheses.
#' Contrasts where the effect is significant (two-sided, unadjusted p<0.1)
#' but in the direction opposite the pre-registered hypothesis are flagged
#' with a dagger ($^\\dagger$), so a strong "wrong-direction" result isn't
#' mistaken for "no effect".
#' N varies by contrast (different subsample per pair) and stays as a
#' column; R2 is 0 for every contrast (intercept-only models) and is
#' attached as an attribute instead (attr(..., "R2")), for the caller to
#' place in a table footer (see save_table()'s `footer` argument).
#' @param few_pairs pair-level Task 1 data (Part 1 output)
build_h5h11_table <- function(few_pairs) {
  results <- purrr::map_dfr(h5_h11_contrasts, ~ fit_one_contrast(few_pairs, .x))
  results$p_value_fdr <- p.adjust(results$p_value_raw, method = "BH")

  stars <- sig_stars(results$p_value_fdr)

  wrong_direction <- (results$direction == "above" & results$estimate < 0.5) |
                      (results$direction == "below" & results$estimate > 0.5)
  dagger <- ifelse(wrong_direction & results$p_value_two_sided < 0.1, "$^\\dagger$", "")

  out <- tibble::tibble(
    contrast = results$contrast,
    estimate = paste0(sprintf("%.3f", results$estimate), stars, dagger),
    se       = paste0("(", sprintf("%.3f", results$se), ")"),
    N        = results$N
  )
  attr(out, "R2") <- unique(round(results$R2, 3))
  out
}

# Example usage:
# few_pairs <- reshape_named_task(raw_data)               # Part 1
# results_h5h11 <- build_h5h11_table(few_pairs)
# print(results_h5h11)
# save_table(results_h5h11, "results_h5h11")               # txt + tex

# -----------------------------------------------------------------------------
# 2. Exploratory Bradley-Terry ranking of the 12 named scenarios
# -----------------------------------------------------------------------------

#' Build the contest-level data frame required by BradleyTerry2::BTm()
#' One row per Task 1 pair where both named scenarios are among the 12
#' ranked scenarios and the respondent did not answer "I don't know".
#' outcome = 1 if the "player1" (L-side) scenario was chosen, 0 otherwise.
build_bt_data <- function(few_pairs) {
  few_pairs %>%
    filter(!is_idk,
           L_scenario %in% bt_scenarios,
           R_scenario %in% bt_scenarios) %>%
    transmute(
      resp_id,
      player1 = factor(L_scenario, levels = bt_scenarios),
      player2 = factor(R_scenario, levels = bt_scenarios),
      outcome = as.numeric(chosen_scenario == L_scenario)
    )
}

#' Fit the Bradley-Terry model and return a ranked ability table
#' @param bt_data output of build_bt_data()
fit_bradley_terry <- function(bt_data) {
  model <- BradleyTerry2::BTm(
    outcome = bt_data$outcome,
    player1 = bt_data$player1,
    player2 = bt_data$player2,
    formula = ~ player,
    id = "player",
    data = bt_data
  )
  model
}

#' Ranked table of scenario abilities (higher = more preferred), with BC
#' fixed as the reference (ability = 0, se = 0 - not a testable coefficient,
#' shown as "ref.") by BTm() default. Non-reference abilities are tested
#' against 0 (Wald z-test) with FDR (Benjamini-Hochberg) correction across
#' the 11 testable scenarios, and formatted with significance stars, in
#' line with the other results tables.
#'
#' @param bt_model output of fit_bradley_terry()
#' @param bt_data output of build_bt_data() (used to count N contests per
#'   scenario, i.e. how many times each scenario was shown as either side
#'   of a pair)
bt_ranking_table <- function(bt_model, bt_data) {
  ab <- BradleyTerry2::BTabilities(bt_model)
  n_contests <- table(c(as.character(bt_data$player1), as.character(bt_data$player2)))

  is_ref <- ab[, "s.e."] == 0
  z <- ab[, "ability"] / ab[, "s.e."]
  p_raw <- ifelse(is_ref, NA_real_, 2 * pnorm(-abs(z)))
  p_fdr <- p_raw
  p_fdr[!is_ref] <- p.adjust(p_raw[!is_ref], method = "BH")
  stars <- sig_stars(p_fdr)

  # McFadden pseudo-R2: null model = all abilities equal (p = 0.5 per
  # contest), vs. this model's log-likelihood. Same for every scenario (one
  # shared model), so attached as an attribute rather than a column - see
  # save_table()'s `footer` argument.
  ll_model <- as.numeric(stats::logLik(bt_model))
  ll_null  <- nrow(bt_data) * log(0.5)
  r2_mcfadden <- round(1 - ll_model / ll_null, 3)

  out <- tibble::tibble(
    scenario = latex_escape_underscore(rownames(ab)),
    ability  = dplyr::if_else(is_ref, "ref.", paste0(sprintf("%.3f", ab[, "ability"]), stars)),
    se       = dplyr::if_else(is_ref, "", paste0("(", sprintf("%.3f", ab[, "s.e."]), ")")),
    N        = as.integer(n_contests[rownames(ab)]),
    .ability_sort = ab[, "ability"]
  ) %>%
    arrange(desc(.ability_sort)) %>%
    select(-.ability_sort)

  attr(out, "R2") <- r2_mcfadden
  out
}

# Example usage:
# bt_data <- build_bt_data(few_pairs)
# bt_model <- fit_bradley_terry(bt_data)
# bt_table <- bt_ranking_table(bt_model, bt_data)
# print(bt_table)
# save_table(bt_table, "bt_ranking_table")

# =============================================================================
# End of Part 4
# =============================================================================
