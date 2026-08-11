# =============================================================================
# Part 8 - "I don't know" secondary analysis (Q8)
# =============================================================================
#
# Analyze the frequency and sociodemographic predictors of 'I don't know' responses as
# a secondary outcome, to explore whether uncertainty in scenario
# preferences is systematically related to respondent characteristics or
# scenario features.
#
# Built directly from the raw DCE choice variables (ANY_DCE, ANY2_DCE,
# FEW_DCE; value 3 = "Non lo so") rather than from idk_data/few_pairs,
# since those already dropped the non-IDK rows - here we need the full
# denominator (every respondent shown each task) to compute rates and fit
# predictors of the IDK indicator itself.
#
# PLACEHOLDER: same 4 demographics as Part 7 (age_bracket,
# gender excl. "Other" N=4, macro_area, education) - political orientation
# pending wave 1 merge.
# =============================================================================

library(dplyr)

#' Build a respondent-level "I don't know" dataset: one row per respondent,
#' with a binary IDK indicator for each of the 3 DCE tasks plus demographics
#' @param raw_data output of build_covariates(raw_data) (Part 1) - must
#'   have ANY_DCE, ANY2_DCE, FEW_DCE and the 4 demographic covariates
build_idk_data <- function(raw_data) {
  raw_data %>%
    transmute(
      resp_id, batch, age_bracket, gender, macro_area, education,
      idk_task2 = ANY_DCE == 3,
      idk_task3 = ANY2_DCE == 3,
      idk_task1 = FEW_DCE == 3
    ) %>%
    mutate(
      n_idk   = idk_task2 + idk_task3 + idk_task1,
      any_idk = n_idk > 0
    )
}

#' Descriptive frequency table: IDK rate per task, and "any of the 3 tasks"
#' @param idk_data output of build_idk_data()
idk_frequency_table <- function(idk_data) {
  n_idk <- c(sum(idk_data$idk_task1), sum(idk_data$idk_task2),
             sum(idk_data$idk_task3), sum(idk_data$any_idk))
  n <- nrow(idk_data)
  share <- n_idk / n
  se <- sqrt(share * (1 - share) / n)

  tibble::tibble(
    Task     = c("Task 1 (FEW)", "Task 2 (ANY)", "Task 3 (ANY2)", "Any of the 3 tasks"),
    N        = n,
    "N (IDK)" = n_idk,
    estimate = paste0(sprintf("%.1f", 100 * share), "\\%"),
    se       = paste0("(", sprintf("%.1f", 100 * se), "\\%)")
  )
}

#' Long-format IDK data (1 row per respondent x task) for the pooled
#' predictors regression - lets task/scenario differences ("scenario
#' features" per the pre-registration) and demographic predictors be
#' estimated together, with SE clustered by respondent
#' @param idk_data output of build_idk_data()
build_idk_long <- function(idk_data) {
  idk_data %>%
    tidyr::pivot_longer(
      cols = c(idk_task1, idk_task2, idk_task3),
      names_to = "task", names_prefix = "idk_",
      values_to = "idk"
    ) %>%
    mutate(
      idk  = as.numeric(idk),
      task = factor(task, levels = c("task2", "task1", "task3"),
                    labels = c("Task 2 (ANY)", "Task 1 (FEW)", "Task 3 (ANY2)"))
      # Task 2 as reference: the "default" numeric-attribute task with the
      # lower growth rate (1.5%), a natural baseline to compare Task 1
      # (named scenarios) and Task 3 (higher growth) against
    )
}

#' Fit the pooled IDK-predictors model: idk ~ demographics + task, cluster-
#' robust (respondent-level) SE, formatted results table
#' @param idk_long output of build_idk_long()
fit_idk_predictors <- function(idk_long) {
  data <- idk_long %>% filter(gender != "Other")
  data$gender <- droplevels(data$gender)

  model <- lm(idk ~ age_bracket + gender + macro_area + education + task, data = data)
  vcov_mat <- sandwich::vcovCL(model, cluster = data$resp_id, type = "HC1")
  ct <- lmtest::coeftest(model, vcov = vcov_mat)

  coef_names <- rownames(ct)[rownames(ct) != "(Intercept)"]
  stars <- sig_stars(ct[coef_names, "Pr(>|t|)"])

  table <- tibble::tibble(
    " " = prettify_idk_term(coef_names),
    estimate = paste0(sprintf("%.4f", ct[coef_names, "Estimate"]), stars),
    se       = paste0("(", sprintf("%.4f", ct[coef_names, "Std. Error"]), ")")
  )
  attr(table, "N")  <- length(unique(data$resp_id))
  attr(table, "R2") <- round(summary(model)$r.squared, 3)
  table
}

#' Human-readable labels for fit_idk_predictors()'s coefficient names
prettify_idk_term <- function(term) {
  dplyr::case_when(
    term == "age_bracket35-54"                    ~ "Age: 35-54 (vs. 18-34)",
    term == "age_bracket55+"                       ~ "Age: 55+ (vs. 18-34)",
    term == "genderMale"                           ~ "Gender: Male (vs. Female)",
    term == "macro_areaNortheast"                  ~ "Region: Northeast (vs. Northwest)",
    term == "macro_areaCenter"                     ~ "Region: Center (vs. Northwest)",
    term == "macro_areaSouth"                      ~ "Region: South (vs. Northwest)",
    term == "macro_areaIslands"                    ~ "Region: Islands (vs. Northwest)",
    term == "educationUpper secondary"             ~ "Education: Upper secondary (vs. Compulsory/lower)",
    term == "educationTertiary"                    ~ "Education: Tertiary (vs. Compulsory/lower)",
    term == "taskTask 1 (FEW)"                     ~ "Task: 1/FEW (vs. Task 2/ANY)",
    term == "taskTask 3 (ANY2)"                    ~ "Task: 3/ANY2 (vs. Task 2/ANY)",
    TRUE ~ term
  )
}

# Example usage:
# raw_data <- build_covariates(raw_data)                    # Part 1
# idk_data <- build_idk_data(raw_data)
# results_idk_frequency <- idk_frequency_table(idk_data)
# save_table(results_idk_frequency, "results_idk_frequency")
#
# idk_long <- build_idk_long(idk_data)
# results_idk_predictors <- fit_idk_predictors(idk_long)
# save_table(results_idk_predictors, "results_idk_predictors")

# =============================================================================
# End of Part 8
# =============================================================================
