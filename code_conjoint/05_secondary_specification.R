# =============================================================================
# Part 5 - Secondary/alternative specification search (H1-H4 family)
# =============================================================================
#
# Select the specification with the highest adjusted R2 among a set of alternative
# specifications that vary along three dimensions: (a) inclusion or exclusion
# of the income regressor; (b) interaction terms beyond the hours x growth
# term; (c) functional form of income, temperature, and working hours,
# including quadratic terms, pair-wise binary variables, and threshold-based
# dummy variables (e.g. income > current income, income > 1.1 x current
# income, income < 0.9 x current income; analogous thresholds for
# temperature and working hours)."
#
# Design choices:
#   - (b) candidate extra interaction: growth x income (in addition to the
#     mandatory hours x growth term, which is always included)
#   - (c) "analogous thresholds" for temperature/hours: relative to the
#     sample median of the value shown in the DCE profiles (temperature,
#     hours_num)
#   - (c) "pair-wise binary variables": interpreted as tercile bins (low/
#     mid/high, cut at the sample 33rd/67th percentiles) entered as dummies
#     vs. the low tercile - the continuous-variable analogue of how
#     hoursPerWeek is already entered as a factor in the primary spec.
#     Applied to income, temperature AND hours (the pre-registration lists
#     all three under this functional-form dimension), even though hours
#     already has a natural small set of DCE-native levels
#
# This script builds all candidate specifications, fits each by OLS, and
# selects the one with the highest adjusted R2. The winning specification is
# then re-estimated with cluster-robust (respondent-level) SE and reported
# as a descriptive table (feeds figure (iv): "AMCEs from the best-fitting
# alternative specification"). This is NOT a pre-registered hypothesis-test
# table (no FDR correction) - it is a single best-fitting model, selected by
# adjusted R2, reported for the figure/robustness purpose described above.
# =============================================================================

library(dplyr)

# -----------------------------------------------------------------------------
# 1. Candidate variable construction
# -----------------------------------------------------------------------------

#' Add all candidate functional-form variables for temperature, hours,
#' income used by the specification grid below
#' @param model_data output of build_primary_vars() (Part 2)
build_secondary_vars <- function(model_data) {
  temp_med  <- median(model_data$temperature, na.rm = TRUE)
  hours_med <- median(model_data$hours_num, na.rm = TRUE)

  # tercile cut points, for the "pair-wise binary" functional form: bin the
  # variable into 3 ordered groups (low/mid/high) and enter them as dummies
  # vs. the low tercile - the continuous-variable analogue of how
  # hoursPerWeek is already entered as a 4-level factor in the primary spec
  tercile_factor <- function(x, labels) {
    breaks <- quantile(x, probs = c(0, 1/3, 2/3, 1), na.rm = TRUE)
    list(
      factor = cut(x, breaks = breaks, include.lowest = TRUE, labels = labels),
      breaks = breaks
    )
  }

  temperature_tf <- tercile_factor(model_data$temperature, c("low", "mid", "high"))
  hours_tf       <- tercile_factor(model_data$hours_num, c("low", "mid", "high"))
  income_tf      <- tercile_factor(model_data$NetIncome_1k, c("low", "mid", "high"))

  # stash the tercile cut points in a global so prettify_secondary_term()
  # can label the mid/high dummy rows with their actual value range (in
  # natural units - degC/h/EUR) instead of the abstract "tercile" name;
  # set as a side effect here since this is the only place the breakpoints
  # are computed and prettify_secondary_term() is a pure name->label lookup
  tercile_breaks <<- list(
    temperature = temperature_tf$breaks,
    hours       = hours_tf$breaks,
    income      = income_tf$breaks
  )

  model_data %>%
    mutate(
      # --- temperature: quadratic / threshold (vs. sample median) / tercile ---
      temperature_sq            = temperature^2,
      temperature_above_median  = as.numeric(temperature > temp_med),
      temperature_tercile       = temperature_tf$factor,

      # --- hours: quadratic / threshold (vs. sample median) / tercile ---
      hours_sq            = hours_num^2,
      hours_above_median  = as.numeric(hours_num > hours_med),
      hours_tercile        = hours_tf$factor,

      # --- income: quadratic / threshold-based dummies (vs. respondent's
      # own current_income) / tercile ---
      NetIncome_1k_sq       = NetIncome_1k^2,
      # income_above_current is identical to future_income_above_current
      # (H4's dummy) - reused here under an explicit name for clarity
      income_above_current      = future_income_above_current,
      income_above_1p1_current  = as.numeric(NetIncome > 1.1 * current_income),
      income_below_0p9_current  = as.numeric(NetIncome < 0.9 * current_income),
      income_tercile             = income_tf$factor,

      # --- candidate extra interaction (beyond mandatory hours x growth) ---
      growth_x_income = growth * NetIncome_1k
    )
}

# -----------------------------------------------------------------------------
# 2. Specification grid
# -----------------------------------------------------------------------------

# Terms shared by every candidate specification: the 4 categorical
# attributes (always as dummy sets, per the primary spec - only income,
# temperature, hours vary in functional form here), growth main effect, and
# the mandatory hours x growth interaction
base_terms <- c(
  "publicServices", "beefAndFlights", "nationalRedistribution",
  "globalRedistribution", "growth", "hours_x_growth"
)

# Income: 5 variants (excluded, or included in one of 4 functional forms)
income_variants <- list(
  excluded         = character(0),
  linear           = "NetIncome_1k",
  quadratic        = c("NetIncome_1k", "NetIncome_1k_sq"),
  threshold        = c("income_above_current", "income_above_1p1_current", "income_below_0p9_current"),
  pairwise_binary  = "income_tercile"
)

# Temperature: 4 functional forms
temperature_variants <- list(
  linear           = "temperature",
  quadratic        = c("temperature", "temperature_sq"),
  threshold        = "temperature_above_median",
  pairwise_binary  = "temperature_tercile"
)

# Hours: 5 functional forms (categorical = the primary spec's own form,
# offered here too so the search can confirm/reject it against alternatives)
hours_variants <- list(
  categorical      = "hoursPerWeek_f",
  linear           = "hours_num",
  quadratic        = c("hours_num", "hours_sq"),
  threshold        = "hours_above_median",
  pairwise_binary  = "hours_tercile"
)

#' Build the full grid of candidate formulas (as a tibble of formula strings
#' + a label describing which grid cell they come from)
build_specification_grid <- function() {
  grid <- purrr::pmap_dfr(
    expand.grid(
      income = names(income_variants),
      temperature = names(temperature_variants),
      hours = names(hours_variants),
      extra_interaction = c("none", "growth_x_income"),
      stringsAsFactors = FALSE
    ),
    function(income, temperature, hours, extra_interaction) {
      # growth x income only meaningful if income is included
      if (extra_interaction == "growth_x_income" && income == "excluded") {
        return(NULL)
      }
      terms <- c(
        base_terms,
        temperature_variants[[temperature]],
        hours_variants[[hours]],
        income_variants[[income]],
        if (extra_interaction == "growth_x_income") "growth_x_income" else NULL
      )
      tibble::tibble(
        income = income, temperature = temperature, hours = hours,
        extra_interaction = extra_interaction,
        formula_str = paste("selected ~", paste(terms, collapse = " + "))
      )
    }
  )
  grid
}

# -----------------------------------------------------------------------------
# 3. Fit the grid, select the best-adjusted-R2 specification
# -----------------------------------------------------------------------------

#' Fit every candidate specification in the grid, record adjusted R2, and
#' return the grid ranked by adjusted R2 (best first)
#' @param model_data output of build_secondary_vars()
fit_specification_grid <- function(model_data) {
  grid <- build_specification_grid()
  grid$adj_r2 <- vapply(grid$formula_str, function(f) {
    m <- lm(as.formula(f), data = model_data)
    summary(m)$adj.r.squared
  }, numeric(1))
  grid %>% arrange(desc(adj_r2))
}

#' Fit one model (given as a formula string) with cluster-robust
#' (respondent-level) SE and format it as a results table - purely
#' descriptive (no FDR correction: not a pre-registered hypothesis-test
#' family), shared by build_secondary_table() and the Elastic Net step below
#' @param model_data output of build_secondary_vars()
#' Format one tercile bin's actual value range in natural units, from the
#' quantile() breakpoints stashed by build_secondary_vars() (c(0%,33%,67%,
#' 100%) cut points). tercile_idx: 1 = low, 2 = mid, 3 = high.
#' Uses \\textdegree / \\texteuro (textcomp package, added to
#' master_document.tex) rather than raw UTF-8 degree/euro glyphs, so the
#' label is safe to embed in generated .tex regardless of source encoding.
tercile_range_str <- function(breaks, tercile_idx, unit = "", digits = 1, scale = 1, big_mark = "") {
  fmt <- function(x) {
    formatC(round(x * scale, digits), format = "f", digits = digits, big.mark = big_mark)
  }
  paste0(fmt(breaks[tercile_idx]), "\\textendash{}", fmt(breaks[tercile_idx + 1]), unit)
}

#' Build a "<attribute>: <bin range> (vs. <low-tercile range>)" label for a
#' tercile mid/high dummy, using the actual breakpoints instead of the
#' abstract "mid/high tercile" wording
tercile_label <- function(attr_label, level, breaks, unit = "", digits = 1, scale = 1, big_mark = "") {
  low_str  <- tercile_range_str(breaks, 1, unit, digits, scale, big_mark)
  this_str <- tercile_range_str(breaks, if (level == "mid") 2 else 3, unit, digits, scale, big_mark)
  paste0(attr_label, ": ", this_str, " (vs. ", low_str, ")")
}

#' Human-readable label for a coefficient name from the secondary
#' specification grid (Part 5) or its growth-interaction extensions -
#' covers every term any candidate specification in the grid could produce.
#' Falls back to the raw name for anything unrecognized (e.g. a term
#' selected by Elastic Net), so this never errors on an unmapped term.
#' Tercile mid/high terms need the live breakpoints (set as a global by
#' build_secondary_vars()); if unavailable (e.g. called before that runs),
#' falls back to the abstract "mid/high tercile" wording.
prettify_secondary_term <- function(term) {
  tb <- if (exists("tercile_breaks", envir = .GlobalEnv)) get("tercile_breaks", envir = .GlobalEnv) else NULL

  dplyr::case_when(
    # income
    term == "NetIncome_1k"               ~ "Income (per 1k/month)",
    term == "NetIncome_1k_sq"            ~ "Income² (per 1k/month)",
    term == "income_above_current"       ~ "Income $>$ current",
    term == "income_above_1p1_current"   ~ "Income $>$ 1.1$\\times$ current",
    term == "income_below_0p9_current"   ~ "Income $<$ 0.9$\\times$ current",
    term == "income_tercilemid"          ~ if (!is.null(tb)) tercile_label("Income", "mid", tb$income, unit = "/month", digits = 0, scale = 1000, big_mark = ",") else "Income: mid tercile (vs. low)",
    term == "income_tercilehigh"         ~ if (!is.null(tb)) tercile_label("Income", "high", tb$income, unit = "/month", digits = 0, scale = 1000, big_mark = ",") else "Income: high tercile (vs. low)",
    # temperature
    term == "temperature"                ~ "Temperature",
    term == "temperature_sq"             ~ "Temperature\\textsuperscript{2}",
    term == "temperature_above_median"   ~ "Temperature $>$ median",
    term == "temperature_tercilemid"     ~ if (!is.null(tb)) tercile_label("Temperature", "mid", tb$temperature, unit = "\\textdegree C", digits = 1) else "Temperature: mid tercile (vs. low)",
    term == "temperature_tercilehigh"    ~ if (!is.null(tb)) tercile_label("Temperature", "high", tb$temperature, unit = "\\textdegree C", digits = 1) else "Temperature: high tercile (vs. low)",
    # hours
    term == "hours_num"                  ~ "Working hours (linear)",
    term == "hours_sq"                   ~ "Working hours\\textsuperscript{2}",
    term == "hours_above_median"         ~ "Working hours $>$ median",
    term == "hours_tercilemid"           ~ if (!is.null(tb)) tercile_label("Working hours", "mid", tb$hours, unit = "h", digits = 0) else "Working hours: mid tercile (vs. low)",
    term == "hours_tercilehigh"          ~ if (!is.null(tb)) tercile_label("Working hours", "high", tb$hours, unit = "h", digits = 0) else "Working hours: high tercile (vs. low)",
    term == "hoursPerWeek_f32"           ~ "Working hours: 32h (vs. 40h)",
    term == "hoursPerWeek_f36"           ~ "Working hours: 36h (vs. 40h)",
    term == "hoursPerWeek_f44"           ~ "Working hours: 44h (vs. 40h)",
    # categorical attributes (same levels as the primary spec)
    term == "publicServicesincreased"       ~ "Public services: increased (vs. stable)",
    term == "beefAndFlightsbeef"            ~ "Less beef (vs. none)",
    term == "beefAndFlightsflights"         ~ "Less flights (vs. none)",
    term == "beefAndFlightsboth"            ~ "Less beef \\& flights (vs. none)",
    term == "nationalRedistributionSN"      ~ "National redistribution (vs. current)",
    term == "globalRedistributionGIT"       ~ "Global redistribution (vs. current)",
    # growth terms - "growth" is displayed rescaled (x1.5, the observed
    # jump) by fit_and_format_model(); the label reflects that rescaling
    term == "growth"                     ~ "3\\% productivity growth (vs. 1.5\\%)",
    term == "hours_x_growth"             ~ "Working hours $\\times$ growth",
    term == "growth_x_income"            ~ "Growth $\\times$ Income",
    # H4 (only appears when the primary spec is the base for
    # add_en_interactions() - the secondary spec doesn't include this term)
    term == "future_income_above_current" ~ "Future income $>$ current",
    # fallback for any future/unmapped term (e.g. a new Elastic-Net-selected
    # interaction not yet added above): escape the underscore rather than
    # let it pass through raw and break LaTeX compilation
    TRUE ~ gsub("_", "\\\\_", term)
  )
}

#' Plain-text version of prettify_secondary_term(), for ggplot labels -
#' plots don't render LaTeX markup, so strip the escaping back to plain
#' characters (\\& -> &, $>$/$<$ -> >/<, \\textsuperscript{2} -> superscript 2)
prettify_secondary_term_plot <- function(term) {
  prettify_secondary_term(term) %>%
    gsub("\\\\&", "&", .) %>%
    gsub("\\$>\\$", ">", .) %>%
    gsub("\\$<\\$", "<", .) %>%
    gsub("\\\\textsuperscript\\{2\\}", "²", .) %>%
    gsub("\\\\_", "_", .)
}

#' Fit one model (given as a formula string) with cluster-robust
#' (respondent-level) SE and format it as a results table
#' @param model_data output of build_secondary_vars()
#' @param formula_str model formula, as a string (e.g. "selected ~ ...")
fit_and_format_model <- function(model_data, formula_str) {
  model <- lm(as.formula(formula_str), data = model_data)
  vcov_mat <- sandwich::vcovCL(model, cluster = model_data$resp_id, type = "HC1")
  ct <- lmtest::coeftest(model, vcov = vcov_mat)

  coef_names <- rownames(ct)[rownames(ct) != "(Intercept)"]
  stars <- sig_stars(ct[coef_names, "Pr(>|t|)"])

  # growth is coded 1.5/3 (numeric, not a dummy), so its raw coefficient is
  # a per-percentage-point effect. Displayed rescaled (x1.5) to show the
  # actual observed jump (1.5% -> 3%) instead - display only, the
  # underlying model (incl. the pre-registered hours_x_growth interaction,
  # left on its original scale) is unchanged. t-stat/p-value/stars are
  # scale-invariant (estimate and SE scale together) so unaffected.
  display_estimate <- ct[coef_names, "Estimate"]
  display_se        <- ct[coef_names, "Std. Error"]
  is_growth <- coef_names == "growth"
  display_estimate[is_growth] <- display_estimate[is_growth] * 1.5
  display_se[is_growth]        <- display_se[is_growth] * 1.5

  table <- tibble::tibble(
    " " = prettify_secondary_term(coef_names),
    estimate = paste0(sprintf("%.3f", display_estimate), stars),
    se       = paste0("(", sprintf("%.3f", display_se), ")")
  )

  attr(table, "N")  <- length(unique(model_data$resp_id))
  attr(table, "R2") <- round(summary(model)$r.squared, 3)
  attr(table, "adj_R2") <- round(summary(model)$adj.r.squared, 3)
  attr(table, "formula") <- formula_str
  attr(table, "model") <- model
  attr(table, "vcov") <- vcov_mat

  table
}

#' Fit the single best (highest adjusted R2) specification from the grid
#' @param model_data output of build_secondary_vars()
#' @param grid_ranked output of fit_specification_grid()
build_secondary_table <- function(model_data, grid_ranked) {
  fit_and_format_model(model_data, grid_ranked$formula_str[1])
}

# Example usage:
# model_data2   <- build_secondary_vars(model_data)          # this file
# grid_ranked   <- fit_specification_grid(model_data2)        # this file
# results_secondary <- build_secondary_table(model_data2, grid_ranked)
# print(results_secondary)
# save_table(results_secondary, "results_secondary_best_spec")

# -----------------------------------------------------------------------------
# 4. Elastic Net interaction-term selection
# -----------------------------------------------------------------------------
#
# Pre-registration: "In addition, we will run both models [primary and
# secondary] with and without a set of interaction terms selected via
# Elastic Net model, which performs well with groups of correlated
# variables."
#
# Candidate interaction terms: all pairwise interactions among the 7
# displayed attributes + growth (the "beyond hours x growth" interaction
# space), built via model.matrix so categorical attributes expand into
# their dummy-level interactions automatically. Main effects are always
# kept in the model (penalty.factor = 0, never shrunk/dropped) - only the
# interaction terms are subject to Elastic Net selection.

#' Build the full main-effects + all-pairwise-interactions design matrix
#' for the 7 displayed attributes + growth
#' @param model_data output of build_secondary_vars()
build_interaction_candidates <- function(model_data) {
  f <- ~ (temperature + NetIncome_1k + hoursPerWeek_f + publicServices +
            beefAndFlights + nationalRedistribution + globalRedistribution +
            growth)^2
  mm <- model.matrix(f, data = model_data)
  mm[, colnames(mm) != "(Intercept)", drop = FALSE]
}

#' Select interaction terms via Elastic Net (alpha = 0.5: the standard,
#' balanced mix of Lasso/Ridge penalties - chosen per the pre-registration's
#' stated rationale of robustness to groups of correlated regressors).
#' Main effects are unpenalized (always kept); only interaction terms
#' (columns containing ":") are candidates for selection. Selection is at
#' lambda.1se (the most regularized model within 1 SE of the best
#' cross-validated fit) for a parsimonious, stable selected set.
#' @param model_data output of build_secondary_vars()
select_en_interactions <- function(model_data, alpha = 0.5, seed = 1) {
  X <- build_interaction_candidates(model_data)
  y <- model_data$selected
  is_interaction <- grepl(":", colnames(X), fixed = TRUE)
  penalty <- ifelse(is_interaction, 1, 0)

  set.seed(seed)
  cv <- glmnet::cv.glmnet(X, y, alpha = alpha, penalty.factor = penalty, family = "gaussian")
  coefs <- as.matrix(coef(cv, s = "lambda.1se"))
  selected <- rownames(coefs)[coefs[, 1] != 0]
  # interaction term names from model.matrix (e.g. "temperature:growth")
  # are already valid R formula syntax and can be pasted directly in
  selected[grepl(":", selected, fixed = TRUE)]
}

#' Add a set of (Elastic-Net-selected) interaction terms to a base
#' specification and fit/format the augmented model
#' @param model_data output of build_secondary_vars()
#' @param base_formula_str the base model's formula, as a string
#' @param en_terms character vector of interaction term names to add
add_en_interactions <- function(model_data, base_formula_str, en_terms) {
  full_formula <- if (length(en_terms) == 0) {
    base_formula_str
  } else {
    paste(base_formula_str, paste(en_terms, collapse = " + "), sep = " + ")
  }
  fit_and_format_model(model_data, full_formula)
}

# Example usage:
# en_terms <- select_en_interactions(model_data2)
# results_h1h4_en      <- add_en_interactions(model_data2, primary_formula_str, en_terms)
# results_secondary_en <- add_en_interactions(model_data2, grid_ranked$formula_str[1], en_terms)

# =============================================================================
# End of Part 5
# =============================================================================
