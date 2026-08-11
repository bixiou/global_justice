# =============================================================================
# Part 7 - Heterogeneity: AMCEs interacted with respondent characteristics (Q5)
# =============================================================================
#
# interact AMCEs with respondent characteristics
# (age, income level, political orientation, education) to explore
# preference heterogeneity."
#
# PLACEHOLDER (2026-08-04): political orientation not yet available (will
# be added once merged with wave 1 data - see build_covariates(), Part 1).
# Income is already part of the primary/secondary specs themselves (not a
# separate interaction here). Available demographics used here:
# age_bracket, gender (excluding the N=4 "Other" level, too small for a
# stable interaction), macro_area, education.
#
# Design choice: one demographic characteristic interacted at a time 
# (4 separate models per base spec.
#
# Applied to BOTH the primary specification (H1-H4) and the secondary
# (best-fitting) specification from Part 5.
# =============================================================================

library(dplyr)

# The 4 available demographics (placeholder list - extend once wave 1 is
# merged and political orientation becomes available)
heterogeneity_demographics <- c("age_bracket", "gender", "macro_area", "education")

# Rows to exclude per demographic, before fitting (too-small subgroup)
heterogeneity_exclusions <- list(
  age_bracket = NULL, gender = "Other", macro_area = NULL, education = NULL
)

# The 7 displayed attributes' regressor terms, for the PRIMARY specification
primary_attribute_terms <- c(
  "temperature", "NetIncome_1k", "hoursPerWeek_f", "publicServices",
  "beefAndFlights", "nationalRedistribution", "globalRedistribution"
)

#' Attribute terms for the SECONDARY (best-fitting) specification, derived
#' from the winning grid row (Part 5) - reuses income_variants/
#' temperature_variants/hours_variants so this always matches whichever
#' functional form actually won, without hardcoding it
#' @param grid_ranked output of fit_specification_grid() (Part 5)
get_secondary_attribute_terms <- function(grid_ranked) {
  best <- grid_ranked[1, ]
  c(
    temperature_variants[[best$temperature]],
    hours_variants[[best$hours]],
    income_variants[[best$income]],
    "publicServices", "beefAndFlights", "nationalRedistribution", "globalRedistribution"
  )
}

#' Baseline (reference) level for each demographic - the level all
#' interaction coefficients for that demographic are measured against,
#' since it's the first level in build_covariates()'s factor() call (the
#' implicit regression baseline). "Other" is excluded from gender before
#' fitting (see heterogeneity_exclusions), so "Female" remains its baseline.
heterogeneity_baselines <- c(
  age_bracket = "18-34",
  gender      = "Female",
  macro_area  = "Northwest",
  education   = "Compulsory/lower secondary"
)

# Human-readable, LaTeX-safe labels for the demographic variable names
# (their raw names contain underscores, which would break LaTeX table
# compilation if printed as-is - see build_heterogeneity_table())
heterogeneity_labels <- c(
  age_bracket = "Age",
  gender      = "Gender",
  macro_area  = "Region",
  education   = "Education"
)

#' Split a raw interaction coefficient name into its attribute and
#' demographic-level parts (e.g. "temperature:age_bracket35-54" ->
#' attribute "temperature", level "35-54"). The baseline each demographic
#' level is measured against (heterogeneity_baselines) is constant within a
#' demographic, so it's stated once (in the table caption) rather than
#' repeated on every row.
#' @param term raw coefficient name
#' @param demographic_var the demographic variable for this term (its name
#'   is the right-hand side's prefix, stripped to get just the level)
split_heterogeneity_term <- function(term, demographic_var) {
  attribute_part   <- sub(":.*$", "", term)
  demographic_part <- sub("^.*:", "", term)
  level <- sub(paste0("^", demographic_var), "", demographic_part)
  list(attribute = attribute_part, level = level)
}

#' Fit one heterogeneity model: base specification + one demographic's main
#' effect + demographic x attribute interactions (for the displayed
#' attributes only, not growth/hours_x_growth/future_income), with
#' cluster-robust SE
#' @param model_data data with covariates merged in (age_bracket, gender,
#'   macro_area, education) and all attribute/functional-form columns built
#'   (build_primary_vars() + build_secondary_vars())
#' @param base_formula_str base model formula, as a string (primary or
#'   secondary spec)
#' @param attribute_terms character vector of attribute regressor names to
#'   interact with the demographic (primary_attribute_terms or
#'   get_secondary_attribute_terms())
#' @param demographic_var "age_bracket", "gender", "macro_area", or "education"
fit_heterogeneity_model <- function(model_data, base_formula_str, attribute_terms, demographic_var) {
  data <- model_data
  exclude_value <- heterogeneity_exclusions[[demographic_var]]
  if (!is.null(exclude_value)) {
    data <- data %>% filter(.data[[demographic_var]] != exclude_value)
  }
  data[[demographic_var]] <- droplevels(data[[demographic_var]])

  interaction_terms <- paste0(demographic_var, ":", attribute_terms)
  formula_str <- paste(base_formula_str, "+", demographic_var, "+", paste(interaction_terms, collapse = " + "))

  model <- lm(as.formula(formula_str), data = data)
  vcov_mat <- sandwich::vcovCL(model, cluster = data$resp_id, type = "HC1")
  ct <- lmtest::coeftest(model, vcov = vcov_mat)

  # keep only the interaction coefficients (the heterogeneity estimates
  # themselves) - main effects are already reported in the base spec's own
  # results table
  int_rows <- rownames(ct)[
    grepl(paste0("^", demographic_var, ".*:"), rownames(ct)) |
    grepl(paste0(":", demographic_var), rownames(ct))
  ]
  split <- lapply(int_rows, split_heterogeneity_term, demographic_var = demographic_var)

  tibble::tibble(
    attribute   = vapply(split, `[[`, character(1), "attribute"),
    level       = vapply(split, `[[`, character(1), "level"),
    estimate    = ct[int_rows, "Estimate"],
    se          = ct[int_rows, "Std. Error"],
    p_value     = ct[int_rows, "Pr(>|t|)"],
    demographic = demographic_var,
    n_resp      = length(unique(data$resp_id))
  )
}

#' Run all 4 heterogeneity models (one per demographic) for one base
#' specification, and combine into one tidy data frame
#' @param model_data data with covariates + attribute columns
#' @param base_formula_str base model formula, as a string
#' @param attribute_terms character vector of attribute regressor names
fit_all_heterogeneity <- function(model_data, base_formula_str, attribute_terms) {
  purrr::map_dfr(heterogeneity_demographics, function(dem) {
    fit_heterogeneity_model(model_data, base_formula_str, attribute_terms, dem)
  })
}

#' Build a results table of heterogeneity (interaction) estimates for one
#' base specification: one row per attribute x demographic-level
#' combination, columns Attribute / Demographic / Level / estimate (with
#' unadjusted-p stars) / se. A table, not a plot - with ~100+ rows split
#' across 4 demographics, a faceted coefficient plot was too dense to read;
#' each demographic's baseline (heterogeneity_baselines) is constant across
#' its rows, so it's stated once in the table caption by the caller rather
#' than repeated on every row.
#' @param het_data output of fit_all_heterogeneity()
build_heterogeneity_table <- function(het_data) {
  stars <- sig_stars(het_data$p_value)
  tibble::tibble(
    Attribute   = prettify_secondary_term(het_data$attribute),
    Demographic = unname(heterogeneity_labels[het_data$demographic]),
    Level       = het_data$level,
    estimate    = paste0(sprintf("%.3f", het_data$estimate), stars),
    se          = paste0("(", sprintf("%.3f", het_data$se), ")")
  )
}

# Example usage:
# het_primary <- fit_all_heterogeneity(model_data, primary_formula_str, primary_attribute_terms)
# results_het_primary <- build_heterogeneity_table(het_primary)
# save_table(results_het_primary, "results_heterogeneity_primary")
#
# secondary_terms <- get_secondary_attribute_terms(grid_ranked)
# het_secondary <- fit_all_heterogeneity(model_data2, secondary_formula_str, secondary_terms)
# results_het_secondary <- build_heterogeneity_table(het_secondary)
# save_table(results_het_secondary, "results_heterogeneity_secondary")

# =============================================================================
# End of Part 7
# =============================================================================
