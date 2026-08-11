# =============================================================================
# Part 6 - Figures (Q5)
# =============================================================================
#
# Figure (i): share of cases where respondents choose the
# scenario with the preferred value on each of the seven displayed
# attributes (excluding cases with equal values / ties).
#
# "Preferred" direction: the value that matches BC's own parameter choice 
# (BC is the study's own baseline/"good" scenario:
#   - temperature: LOW preferred (BC = fast decarbonization -> low temp)
#   - NetIncome: HIGH preferred (continuous; standard assumption - BC's
#     specific 60k income class doesn't work as a high/low threshold)
#   - hoursPerWeek: 36h preferred (BC's own value)
#   - publicServices: "increased" preferred (BC = expanded services)
#   - beefAndFlights: MORE cuts preferred (BC cuts both beef and flights;
#     scored 0/1/1/2 by number of things cut - beef vs flights pairs tie at
#     1 and are excluded, consistent with the "excluding ties" rule)
#   - nationalRedistribution: "SN" preferred (BC = national redistribution on)
#   - globalRedistribution: "GIT" preferred (BC = global redistribution on)
#
# Supplementary figures: 
# the same computation using literal highest instead of preferred - which
# differs from the above only for temperature (opposite direction) and
# hours (44h, not 36h, is "highest"); identical for the other 5 attributes,
# since BC's own choice already happens to be the highest-scored level for
# those.
# =============================================================================

library(dplyr)
library(ggplot2)
library(cjoint)

# Human-readable labels, consistent with build_h1h4_table()'s attr_labels
figure_attr_labels <- c(
  temperature             = "Temperature",
  NetIncome               = "Income",
  hoursPerWeek            = "Working hours",
  publicServices          = "Public services",
  beefAndFlights          = "Beef & flights",
  nationalRedistribution  = "National redistribution",
  globalRedistribution    = "Global redistribution"
)

# -----------------------------------------------------------------------------
# 1. Attribute scoring: "preferred" (BC-referenced) and "highest value"
# -----------------------------------------------------------------------------

#' Add score_preferred_* and score_highest_* columns for all 7 displayed
#' attributes, used to determine which side of a profile pair "wins" the
#' comparison for each attribute
#' @param model_data output of build_primary_vars() (Part 2)
build_attribute_scores <- function(model_data) {
  model_data %>%
    mutate(
      hours_numeric = as.numeric(as.character(hoursPerWeek_f)),
      cuts_score    = case_when(
        beefAndFlights == "none" ~ 0,
        beefAndFlights %in% c("beef", "flights") ~ 1,
        beefAndFlights == "both" ~ 2
      ),

      # --- "preferred" (BC-referenced) scores ---
      score_preferred_temperature            = -temperature,
      score_preferred_NetIncome               = NetIncome,
      score_preferred_hoursPerWeek            = -abs(hours_numeric - 36),
      score_preferred_publicServices          = as.numeric(publicServices == "increased"),
      score_preferred_beefAndFlights          = cuts_score,
      score_preferred_nationalRedistribution  = as.numeric(nationalRedistribution == "SN"),
      score_preferred_globalRedistribution    = as.numeric(globalRedistribution == "GIT"),

      # --- "highest value" scores (supplementary) ---
      score_highest_temperature            = temperature,
      score_highest_NetIncome               = NetIncome,
      score_highest_hoursPerWeek            = hours_numeric,
      score_highest_publicServices          = as.numeric(publicServices == "increased"),
      score_highest_beefAndFlights          = cuts_score,
      score_highest_nationalRedistribution  = as.numeric(nationalRedistribution == "SN"),
      score_highest_globalRedistribution    = as.numeric(globalRedistribution == "GIT")
    )
}

# -----------------------------------------------------------------------------
# 2. Share computation
# -----------------------------------------------------------------------------

#' For each of the 7 attributes, compute the share of profile pairs where
#' the respondent chose the side with the higher score (excluding ties),
#' with a normal-approximation 95% CI
#' @param scored_data output of build_attribute_scores()
#' @param score_prefix "score_preferred" or "score_highest"
compute_attribute_share <- function(scored_data, score_prefix) {
  purrr::map_dfr(names(figure_attr_labels), function(attr) {
    score_col <- paste0(score_prefix, "_", attr)
    scored_data %>%
      select(pair_id, side, selected, score = all_of(score_col)) %>%
      group_by(pair_id) %>%
      filter(n() == 2, !anyNA(score)) %>%
      summarise(
        score_L = score[side == "L"],
        score_R = score[side == "R"],
        chose_L = selected[side == "L"] == 1,
        .groups = "drop"
      ) %>%
      filter(score_L != score_R) %>%
      mutate(chose_higher = ifelse(score_L > score_R, chose_L, !chose_L)) %>%
      summarise(
        attribute = attr,
        label = unname(figure_attr_labels[attr]),
        n = dplyr::n(),
        share = mean(chose_higher),
        se = sqrt(share * (1 - share) / n)
      )
  }) %>%
    mutate(
      ci_low  = pmax(0, share - 1.96 * se),
      ci_high = pmin(1, share + 1.96 * se)
    )
}

# -----------------------------------------------------------------------------
# 3. Plot
# -----------------------------------------------------------------------------

#' Coefficient-style plot: share choosing the higher-scored side per
#' attribute, with 95% CI and a reference line at 0.5
#' @param share_table output of compute_attribute_share()
#' @param x_label x-axis label (differs for "preferred" vs "highest value")
#' @param level_order optional character vector of `label` values giving
#'   the y-axis attribute order; defaults to sorting by this table's own
#'   share. Pass the same order explicitly across multiple related figures
#'   (e.g. the "preferred" and "highest value" versions) so they stay
#'   visually comparable instead of each re-sorting independently
plot_attribute_share <- function(share_table, x_label, level_order = NULL) {
  if (is.null(level_order)) {
    share_table <- share_table %>% arrange(share)
    level_order <- share_table$label
  }
  ggplot(share_table, aes(x = share, y = factor(label, levels = level_order))) +
    geom_vline(xintercept = 0.5, linetype = "dashed", color = "grey50") +
    geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.2, orientation = "y") +
    geom_point(size = 3) +
    scale_x_continuous(limits = c(0, 1)) +
    labs(x = x_label, y = NULL) +
    theme_minimal(base_size = 12)
}

#' Save a ggplot to <name>.png in out_dir (default OUTPUT_DIR)
save_figure <- function(plot, name, out_dir = OUTPUT_DIR, width = 7, height = 5) {
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  path <- file.path(out_dir, paste0(name, ".png"))
  ggsave(path, plot, width = width, height = height, dpi = 300)
  invisible(path)
}

# Example usage:
# scored_data <- build_attribute_scores(model_data)                 # this file
# share_preferred <- compute_attribute_share(scored_data, "score_preferred")
# share_highest   <- compute_attribute_share(scored_data, "score_highest")
# fig1 <- plot_attribute_share(share_preferred, "Share choosing the preferred value")
# fig1b <- plot_attribute_share(share_highest, "Share choosing the highest value")
# save_figure(fig1, "fig1_share_preferred_value")
# save_figure(fig1b, "fig1b_share_highest_value")

# -----------------------------------------------------------------------------
# Figure (ii): AMCEs for Task 2 and Task 3, estimated separately via
# cjoint::amce(), superimposed on the same plot to compare the effect of
# growth (1.5% in Task 2 / "ANY", 3% in Task 3 / "ANY2")
# -----------------------------------------------------------------------------
#
# temperature and NetIncome are binned into quartiles (fully non-parametric
# treatment, per the original design note) using breakpoints computed on
# the POOLED Task 2 + Task 3 distribution, so both tasks use identical bin
# boundaries and are directly comparable. Each task is fit as its own
# amce() call (a single call can't span two different randomization
# designs/growth rates) - see 02_build_primary_vars.R's note on why this
# figure (not the pooled lm() used for H1-H4) is the natural place for
# cjoint::amce().

#' Add temperature_bin / NetIncome_bin (quartile factors, pooled cut points)
#' to model_data, for the non-parametric AMCE figures
#' @param model_data output of build_primary_vars() (Part 2)
build_amce_bins <- function(model_data) {
  temp_breaks   <- quantile(model_data$temperature, probs = seq(0, 1, 0.25), na.rm = TRUE)
  income_breaks <- quantile(model_data$NetIncome, probs = seq(0, 1, 0.25), na.rm = TRUE)
  bin_labels <- c("Q1 (low)", "Q2", "Q3", "Q4 (high)")

  model_data %>%
    mutate(
      temperature_bin = cut(temperature, breaks = temp_breaks, include.lowest = TRUE, labels = bin_labels),
      NetIncome_bin   = cut(NetIncome, breaks = income_breaks, include.lowest = TRUE, labels = bin_labels)
    )
}

#' Fit cjoint::amce() on one task's data (all 7 displayed attributes,
#' temperature/NetIncome binned into quartiles) and return a tidy results
#' data frame with an added `task` label column
#' @param binned_data output of build_amce_bins()
#' @param task_value "ANY" (Task 2) or "ANY2" (Task 3)
#' @param task_label human-readable label for the task column (e.g. "Task 2 (growth 1.5%)")
fit_amce_by_task <- function(binned_data, task_value, task_label) {
  task_data <- binned_data %>% filter(task == task_value) %>% mutate(selected = as.numeric(selected))

  fit <- cjoint::amce(
    selected ~ temperature_bin + NetIncome_bin + hoursPerWeek_f + publicServices +
      beefAndFlights + nationalRedistribution + globalRedistribution,
    data = task_data, cluster = TRUE, respondent.id = "resp_id"
  )
  s <- summary(fit)$amce

  tibble::tibble(
    attribute = s$Attribute,
    level     = s$Level,
    estimate  = s$Estimate,
    se        = s$`Std. Err`,
    task      = task_label
  )
}

#' Build figure (ii): AMCE coefficient plot for Task 2 and Task 3
#' superimposed, one panel per attribute
#' @param model_data output of build_primary_vars() (Part 2)
plot_amce_by_task <- function(model_data) {
  binned_data <- build_amce_bins(model_data)

  amce_task2 <- fit_amce_by_task(binned_data, "ANY",  "Task 2 (growth 1.5%)")
  amce_task3 <- fit_amce_by_task(binned_data, "ANY2", "Task 3 (growth 3%)")
  amce_both <- bind_rows(amce_task2, amce_task3) %>%
    mutate(
      # amce()'s $Attribute column uses the exact regressor name passed in
      # the formula (temperature_bin, NetIncome_bin, hoursPerWeek_f) -
      # strip those suffixes back to the plain attribute name before
      # looking up the human-readable label
      attribute_key   = gsub("_bin$|_f$", "", attribute),
      attribute_label = unname(figure_attr_labels[attribute_key]),
      attribute_label = ifelse(is.na(attribute_label), attribute, attribute_label),
      ci_low  = estimate - 1.96 * se,
      ci_high = estimate + 1.96 * se
    )

  plot <- ggplot(amce_both, aes(x = estimate, y = level, color = task)) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
    geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.2,
                  orientation = "y", position = position_dodge(width = 0.5)) +
    geom_point(size = 2.5, position = position_dodge(width = 0.5)) +
    facet_wrap(~attribute_label, scales = "free_y", ncol = 2) +
    labs(x = "AMCE (change in probability of profile being chosen)", y = NULL, color = NULL) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "top")

  list(data = amce_both, plot = plot)
}

# Example usage:
# fig2 <- plot_amce_by_task(model_data)
# save_figure(fig2$plot, "fig2_amce_task2_vs_task3", width = 9, height = 8)

# -----------------------------------------------------------------------------
# Figure (iii): AMCEs from the main (primary) specification, adding
# growth x attribute interaction terms for all 7 displayed attributes
# (hours already has its mandatory growth interaction, hours_x_growth,
# in the primary spec; this adds the same idea to the other 6)
# -----------------------------------------------------------------------------
#
# Unlike figure (ii), this must be a pooled lm() over Task 2 + Task 3
# together (growth only varies across tasks, not within one), matching the
# primary specification's own approach to H3's hours x growth term - see
# 02_build_primary_vars.R's note on why cjoint::amce() can't do this
# (single-design-per-call).

#' Fit the primary specification with growth x attribute interactions added
#' for all 7 displayed attributes, and return the growth-interaction
#' coefficients as a tidy data frame ready for plotting
#' @param model_data output of build_primary_vars() (Part 2)
fit_growth_interactions <- function(model_data) {
  formula_str <- paste(
    "selected ~ temperature + NetIncome_1k + hoursPerWeek_f + publicServices +",
    "beefAndFlights + nationalRedistribution + globalRedistribution +",
    "growth + hours_x_growth + future_income_above_current +",
    "growth:temperature + growth:NetIncome_1k + growth:publicServices +",
    "growth:beefAndFlights + growth:nationalRedistribution + growth:globalRedistribution"
  )
  model <- lm(as.formula(formula_str), data = model_data)
  vcov_mat <- sandwich::vcovCL(model, cluster = model_data$resp_id, type = "HC1")
  ct <- lmtest::coeftest(model, vcov = vcov_mat)

  # R names interaction coefficients by the terms' original formula order
  # (temperature appears before growth as a main effect), so the resulting
  # coefficient is "temperature:growth", not "growth:temperature" as
  # written in the formula string above
  growth_terms <- rownames(ct)[grepl(":growth$", rownames(ct))]
  term_no_growth <- sub(":growth$", "", growth_terms)  # e.g. "temperature", "publicServicesincreased"

  attribute_key <- case_when(
    term_no_growth == "temperature"                      ~ "temperature",
    term_no_growth == "NetIncome_1k"                      ~ "NetIncome_1k",
    grepl("^publicServices",         term_no_growth)      ~ "publicServices",
    grepl("^beefAndFlights",         term_no_growth)      ~ "beefAndFlights",
    grepl("^nationalRedistribution", term_no_growth)      ~ "nationalRedistribution",
    grepl("^globalRedistribution",   term_no_growth)      ~ "globalRedistribution",
    TRUE ~ term_no_growth
  )
  # sub()'s `pattern` isn't vectorized over rows, so strip each term's own
  # attribute-key prefix via mapply rather than a single vectorized sub()
  level <- mapply(function(key, term) sub(paste0("^", key), "", term),
                   attribute_key, term_no_growth, USE.NAMES = FALSE)
  level <- ifelse(attribute_key %in% c("temperature", "NetIncome_1k"), "", level)

  tibble::tibble(
    term      = growth_terms,
    attribute_key = attribute_key,
    level     = level,
    estimate  = ct[growth_terms, "Estimate"],
    se        = ct[growth_terms, "Std. Error"],
    p_value   = ct[growth_terms, "Pr(>|t|)"]
  ) %>%
    mutate(
      attribute_label = case_when(
        attribute_key == "temperature"  ~ "Temperature",
        attribute_key == "NetIncome_1k" ~ "Income",
        TRUE ~ unname(figure_attr_labels[attribute_key])
      ),
      ci_low  = estimate - 1.96 * se,
      ci_high = estimate + 1.96 * se
    )
}

#' Build figure (iii): coefficient plot of growth x attribute interaction
#' terms from the primary specification
#' @param model_data output of build_primary_vars() (Part 2)
plot_growth_interactions <- function(model_data) {
  growth_int <- fit_growth_interactions(model_data)

  plot <- ggplot(growth_int, aes(x = estimate, y = reorder(paste(attribute_label, level), estimate))) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
    geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.2, orientation = "y") +
    geom_point(size = 2.5) +
    labs(x = "Growth x attribute interaction coefficient", y = NULL,
         title = "Figure (iii): how attribute effects change with productivity growth") +
    theme_minimal(base_size = 11)

  list(data = growth_int, plot = plot)
}

# Example usage:
# fig3 <- plot_growth_interactions(model_data)
# save_figure(fig3$plot, "fig3_growth_interactions", width = 8, height = 6)

# -----------------------------------------------------------------------------
# Figure (iv): AMCEs from the best-fitting alternative (secondary)
# specification - Part 5's grid-search winner
# -----------------------------------------------------------------------------
#
# Reuses the already-fitted model + cluster-robust vcov stored as attributes
# on results_secondary (see fit_and_format_model() in
# 05_secondary_specification.R), rather than refitting.

#' Build figure (iv): coefficient plot of the winning secondary
#' specification's coefficients
#' @param results_secondary output of build_secondary_table() (Part 5),
#'   which carries the fitted model/vcov as attributes
plot_secondary_spec <- function(results_secondary) {
  model <- attr(results_secondary, "model")
  vcov_mat <- attr(results_secondary, "vcov")
  ct <- lmtest::coeftest(model, vcov = vcov_mat)

  coef_names <- rownames(ct)[rownames(ct) != "(Intercept)"]
  coef_data <- tibble::tibble(
    term     = prettify_secondary_term_plot(coef_names),
    estimate = ct[coef_names, "Estimate"],
    se       = ct[coef_names, "Std. Error"]
  ) %>%
    mutate(
      ci_low  = estimate - 1.96 * se,
      ci_high = estimate + 1.96 * se
    )

  plot <- ggplot(coef_data, aes(x = estimate, y = reorder(term, estimate))) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
    geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.2, orientation = "y") +
    geom_point(size = 2.5) +
    labs(x = "Coefficient (change in probability of profile being chosen)", y = NULL,
         title = "Figure (iv): best-fitting alternative specification") +
    theme_minimal(base_size = 11)

  list(data = coef_data, plot = plot)
}

# Example usage:
# fig4 <- plot_secondary_spec(results_secondary)   # results_secondary from Part 5
# save_figure(fig4$plot, "fig4_secondary_spec", width = 8, height = 6)

# =============================================================================
# End of Part 6 (all four pre-registered figures i-iv)
# =============================================================================
