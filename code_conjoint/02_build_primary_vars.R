# =============================================================================
# Part 2 - Derived variables for the primary specification (H1-H4)
# =============================================================================
#
# Input: amce_data, the long profile-level data frame produced in Part 1
#        (bind_rows(task2$long, task3$long)).
#
# Builds the variables needed for the pre-registered primary specification:
#   temperature and income as numeric variables, categorical attributes as
#    sets of dummy variables, and a mandatory hours x growth interaction
#    term, controlling for future income
#
# NOTE on modeling approach: cjoint::amce() does support numeric/continuous
# attributes natively (as a linear term), so "mixing numeric and factor
# attributes" alone isn't why it's unsuited here. The real reason: amce()
# assumes a single randomized design per call, so it can't natively estimate
# the mandatory hours x growth interaction (growth is fixed within each
# task - the interaction requires pooling Task 2 and Task 3) or
# future_income_above_current (a respondent-level derived comparison, not a
# native design attribute). The primary H1-H4 specification is therefore a
# standard regression (lm) with cluster-robust SE by respondent.
# cjoint::amce() is instead used for the fully non-parametric AMCE figures
# (Task 2 & 3 superimposed, all attributes as factors, estimated separately
# per task so growth is naturally out of the picture). This script prepares
# variables usable for BOTH approaches (numeric + factor versions kept side
# by side), so the choice can be made explicitly in Part 3.
# =============================================================================

library(dplyr)

#' Build all derived variables for the primary H1-H4 specification
#'
#' @param amce_data long profile-level data frame from Part 1
#'   (columns: temperature, NetIncome, hoursPerWeek, publicServices,
#'   beefAndFlights, nationalRedistribution, globalRedistribution, growth,
#'   current_income, selected, pair_id, resp_id, task, side, ...)
build_primary_vars <- function(amce_data) {

  amce_data %>%
    mutate(
      # --- numeric attributes (primary spec: numeric, not dummy) ---
      temperature = as.numeric(temperature),
      NetIncome   = as.numeric(NetIncome),     # "income" attribute (2035);
                                                # kept in raw units for the
                                                # future_income_above_current
                                                # comparison below
      # per-1000 version for the regression: NetIncome is on the same
      # monthly scale as the respondent's own current_income (median 2792 vs
      # 2500), so "per 1,000 EUR/month" is the natural, interpretable unit -
      # unlike an arbitrarily large scale (e.g. per 100k) chosen only to
      # force visibility. The resulting coefficient is still tiny (as it
      # genuinely is - see build_h1h4_table()'s scientific-notation
      # formatting for this row) - rescaling doesn't change
      # significance/p-values, only the coefficient's units
      NetIncome_1k = NetIncome / 1000,
      hours_num   = as.numeric(hoursPerWeek),  # numeric version, for the
                                                # hours x growth interaction

      # --- categorical attributes, as factors (dummy sets in the model) ---
      # reference levels chosen as the "current" / status-quo / no-cut option
      hoursPerWeek_f = factor(hoursPerWeek, levels = c("32", "36", "40", "44")),
      publicServices = factor(publicServices, levels = c("stable", "increased")),
      beefAndFlights = factor(beefAndFlights, levels = c("none", "beef", "flights", "both")),
      nationalRedistribution = factor(nationalRedistribution, levels = c("current", "SN")),
      globalRedistribution   = factor(globalRedistribution,   levels = c("current", "GIT")),

      # --- mandatory hours x growth interaction (H3) ---
      # growth already numeric (1.5 for Task 2 / ANY, 3 for Task 3 / ANY2)
      hours_x_growth = hours_num * growth,

      # --- future income dummy (H4) ---
      # 1 if the scenario's projected 2035 income exceeds the respondent's
      # declared current income (current_income = REVISED_INCOME if
      # non-missing, else income; built in Part 1)
      future_income_above_current = as.numeric(NetIncome > current_income)
    )
}

# Example usage:
# amce_data <- bind_rows(task2$long, task3$long)   # from Part 1
# model_data <- build_primary_vars(amce_data)
# save_dataset(model_data, "model_data_h1h4")       # RDS + .dta, via Part 1's save_dataset()

# -----------------------------------------------------------------------------
# Sanity checks to run once model_data is built (kept here as a documented
# checklist rather than executed automatically, since they require a live
# dataset):
#
#   - range(model_data$temperature, na.rm = TRUE)   # expect roughly 1.5-5 C
#   - range(model_data$NetIncome,   na.rm = TRUE)    # expect plausible EUR/month
#   - table(model_data$hoursPerWeek_f, useNA = "ifany")   # 4 levels, no NA
#   - table(model_data$future_income_above_current, useNA = "ifany")
#     -> NA expected only where current_income is missing (soft-launch
#        respondents without the income filter, if they skipped the item)
#   - table(model_data$growth, model_data$task)     # 1.5<->ANY, 3<->ANY2 only
# =============================================================================
# End of Part 2
# =============================================================================
