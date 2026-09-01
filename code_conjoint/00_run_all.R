# =============================================================================
# 00_run_all.R - Master script
# =============================================================================
#
# Sources Parts 1-4 and runs the full pipeline end-to-end, from the three raw
# .sav wave files in RAW_DATA_DIR to the H1-H4, H5-H11 and Bradley-Terry
# result tables in OUTPUT_DIR.
#
# Intended use: run interactively in RStudio (objects stay in memory for the
# session), with save_dataset() checkpoints written to disk (RDS + .dta) at
# each major stage - so you always have a persisted, inspectable version of
# every intermediate dataset, without needing each script to be a standalone
# read-from-disk / write-to-disk unit.
#
# =============================================================================
# -----------------------------------------------------------------------------
# Load Parts 1-4: this runs each file's full content (function definitions
# only, no top-level execution) into this same session, so their functions
# become callable below as if defined here directly
# -----------------------------------------------------------------------------

source("01_import_reshape.R")
source("02_build_primary_vars.R")
source("03_estimate_h1h4.R")
source("04_h5h11_bradleyterry.R")
source("05_secondary_specification.R")
source("06_figures.R")
source("07_heterogeneity.R")
source("08_idk_analysis.R")

# -----------------------------------------------------------------------------
# Stage 0: Import raw waves - Partial_3 is a cumulative export that already
# contains Partial_1 and Partial_2 in full (verified byte-for-byte on all
# shared columns), so it is used alone as the data; batch/no_income_filter
# are derived by record-ID membership rather than by file. See
# import_raw_waves()'s doc comment in Part 1 for the full verification.
# -----------------------------------------------------------------------------

raw_data <- import_raw_waves(
  file.path(RAW_DATA_DIR, "Partial_1.sav"),
  file.path(RAW_DATA_DIR, "Partial_2.sav"),
  file.path(RAW_DATA_DIR, "Partial_3.sav")
)
raw_data <- add_current_income(raw_data)
raw_data <- flag_high_income(raw_data)
raw_data <- build_covariates(raw_data)

cat("Total N respondents (all batches):", nrow(raw_data), "\n")
cat("By batch:\n"); print(table(raw_data$batch))
cat("Flagged (income > Italian P99, per-adult):", sum(raw_data$income_flag_p99, na.rm = TRUE), "\n")

save_dataset(raw_data, "raw_data_combined")

# -----------------------------------------------------------------------------
# Stage 1: Reshape Task 2 (ANY) and Task 3 (ANY2) -> long profile-level data
# -----------------------------------------------------------------------------

task2 <- reshape_random_task(raw_data, prefix = "ANY",  dce_var = "ANY_DCE",  growth_value = 1.5)
task3 <- reshape_random_task(raw_data, prefix = "ANY2", dce_var = "ANY2_DCE", growth_value = 3.0)

amce_data <- bind_rows(task2$long, task3$long)
idk_data  <- bind_rows(task2$idk,  task3$idk)

cat("\namce_data rows:", nrow(amce_data), " | idk_data pairs:", nrow(idk_data), "\n")

save_dataset(amce_data, "amce_data")
save_dataset(idk_data,  "idk_data")

# -----------------------------------------------------------------------------
# Stage 2: Reshape Task 1 (FEW) -> pair-level named-scenario data
# -----------------------------------------------------------------------------

few_pairs <- reshape_named_task(raw_data)
cat("\nfew_pairs rows:", nrow(few_pairs), " | idk:", sum(few_pairs$is_idk), "\n")

save_dataset(few_pairs, "few_pairs")

# -----------------------------------------------------------------------------
# Stage 3: Build primary-specification variables (H1-H4)
# -----------------------------------------------------------------------------

model_data <- build_primary_vars(amce_data)
save_dataset(model_data, "model_data_h1h4")

# -----------------------------------------------------------------------------
# Stage 3b: Figure (i) - descriptive share choosing the preferred value on
# each attribute (pre-registered), plus a supplementary "highest value"
# version (not pre-registered, added on request)
# -----------------------------------------------------------------------------

scored_data <- build_attribute_scores(model_data)

share_preferred <- compute_attribute_share(scored_data, "score_preferred") %>% arrange(share)
cat("\n=== Figure (i): share choosing the preferred value ===\n")
print(as.data.frame(share_preferred), digits = 3)
attribute_order <- share_preferred$label
fig1 <- plot_attribute_share(share_preferred, "Share choosing the preferred (BC-referenced) value", attribute_order)
save_figure(fig1, "fig1_share_preferred_value")

share_highest <- compute_attribute_share(scored_data, "score_highest")
cat("\n=== Supplementary: share choosing the highest value ===\n")
print(as.data.frame(share_highest), digits = 3)
fig1b <- plot_attribute_share(share_highest, "Share choosing the highest value", attribute_order)
save_figure(fig1b, "fig1b_share_highest_value")

# -----------------------------------------------------------------------------
# Stage 3c: Figure (ii) - AMCEs for Task 2 and Task 3 (via cjoint::amce(),
# temperature/NetIncome binned into quartiles), superimposed
# -----------------------------------------------------------------------------

fig2 <- plot_amce_by_task(model_data)
cat("\n=== Figure (ii): AMCE Task 2 vs Task 3 ===\n")
print(as.data.frame(fig2$data), digits = 3)
save_figure(fig2$plot, "fig2_amce_task2_vs_task3", width = 9, height = 8)

# -----------------------------------------------------------------------------
# Stage 3d: Figure (iii) - primary specification + growth x attribute
# interactions for all 7 displayed attributes
# -----------------------------------------------------------------------------

fig3 <- plot_growth_interactions(model_data)
cat("\n=== Figure (iii): growth x attribute interactions ===\n")
print(as.data.frame(fig3$data), digits = 3)
save_figure(fig3$plot, "fig3_growth_interactions", width = 8, height = 6)

# -----------------------------------------------------------------------------
# Stage 3e: Supplementary exploratory table - hoursPerWeek x growth as a
# full categorical grid (requested by Adrien), complementing (not
# replacing) H3/Table 3's linear hours_num x growth interaction
# -----------------------------------------------------------------------------

growth_hours_grid <- fit_growth_hours_grid(model_data)
results_growth_hours_grid <- build_growth_hours_grid_table(growth_hours_grid)
cat("\n=== Working hours x growth, categorical grid ===\n")
print(as.data.frame(results_growth_hours_grid), digits = 3)
save_table(results_growth_hours_grid, "table13", group_by = "Growth level",
           caption = "Working hours $\\times$ growth, as a full categorical grid.",
           notes = "Exploratory complement to Table~\\ref{tab:table3}'s H3 (linear hours $\\times$ growth interaction, unchanged there) - same underlying model, cell-level effects instead of one pooled slope. All cells relative to the single reference cell low\\_growth $\\times$ 40h (Task 2, 1.5\\% growth, 40h/week). Cluster-robust (respondent-level) SE in parentheses. *** p$<$0.01, ** p$<$0.05, * p$<$0.1 (unadjusted; descriptive, not part of the FDR-corrected pre-registered family).")

# -----------------------------------------------------------------------------
# Stage 4: Estimate the primary H1-H4 model
# -----------------------------------------------------------------------------

primary_model <- fit_primary_model(model_data)
vcov_mat <- cluster_vcov(primary_model, model_data)
n_participants_h1h4 <- length(unique(model_data$resp_id))
results_h1h4 <- build_h1h4_table(primary_model, vcov_mat, n_participants_h1h4)

cat("\n=== H1-H4 results ===\n")
print(as.data.frame(results_h1h4), digits = 3)

save_table(results_h1h4, "table3",
           caption = "H1--H4: primary specification results.",
           notes = "Cluster-robust (respondent-level) SE in parentheses. *** p$<$0.01, ** p$<$0.05, * p$<$0.1. Main-attribute and hypothesis rows: FDR-adjusted (10-test pre-registered family; the one-sided Temperature test is part of this family but not shown as its own row, since it duplicates the two-sided Temperature row above). Indented individual dummy-level rows: descriptive detail, unadjusted p-values.")

# -----------------------------------------------------------------------------
# Stage 4a2: Heterogeneity (Q5) - AMCEs interacted with respondent
# characteristics, one at a time (age_bracket, gender excl. "Other",
# macro_area, education - political orientation still a placeholder,
# pending wave 1 merge). Primary specification.
# -----------------------------------------------------------------------------

primary_formula_str <- deparse(formula(primary_model), width.cutoff = 500)
het_primary <- fit_all_heterogeneity(model_data, primary_formula_str, primary_attribute_terms)
results_het_primary <- build_heterogeneity_table(het_primary)
cat("\n=== Heterogeneity: primary specification ===\n")
cat("Interaction terms estimated:", nrow(results_het_primary), "\n")
print(as.data.frame(results_het_primary), digits = 3)
save_table(results_het_primary, "table9", group_by = "Demographic",
           caption = "Heterogeneity: primary specification.",
           notes = "AMCEs interacted with respondent characteristics, one demographic at a time. Baselines: Age vs. 18-34; Gender vs. Female (\"Other\", N=4, excluded); Region vs. Northwest; Education vs. Compulsory/lower secondary. Cluster-robust (respondent-level) SE in parentheses. *** p$<$0.01, ** p$<$0.05, * p$<$0.1 (unadjusted p-values - exploratory heterogeneity analysis, not part of the FDR-corrected pre-registered family). Political orientation not yet available (placeholder pending wave 1 merge).")

# -----------------------------------------------------------------------------
# Stage 4b: Robustness check (Q6) - re-estimate H1-H4 excluding respondents
# whose declared income exceeds the 99th percentile of the Italian income
# distribution (income_flag_p99, from flag_high_income() in Part 1)
# -----------------------------------------------------------------------------

model_data_robust <- model_data %>% filter(!income_flag_p99)
primary_model_robust <- fit_primary_model(model_data_robust)
vcov_mat_robust <- cluster_vcov(primary_model_robust, model_data_robust)
n_participants_robust <- length(unique(model_data_robust$resp_id))
results_h1h4_robustness_income <- build_h1h4_table(primary_model_robust, vcov_mat_robust, n_participants_robust)

cat("\n=== H1-H4 robustness (excl. income > Italian P99) ===\n")
cat("Respondents excluded:", n_participants_h1h4 - n_participants_robust, "\n")
print(as.data.frame(results_h1h4_robustness_income), digits = 3)

save_table(results_h1h4_robustness_income, "table4",
           caption = "H1--H4 robustness check: excluding income $>$ P99.",
           notes = paste0("Primary specification re-estimated excluding respondents whose declared current income, annualized and adjusted for household size, exceeds the 99th percentile of the (2025) Italian income distribution (", n_participants_h1h4 - n_participants_robust, " respondent(s) excluded; threshold = ", ITALY_INCOME_P99_ANNUAL_PER_ADULT, " EUR/year per adult). Same specification, columns and stars convention as the primary H1--H4 table - compare directly to check sensitivity to this exclusion."))

# -----------------------------------------------------------------------------
# Stage 4c: Secondary/alternative specification (Q5) - grid search over
# income inclusion/functional form, temperature/hours functional form, and
# an extra growth x income interaction; select the highest-adjusted-R2 model
# -----------------------------------------------------------------------------

model_data2 <- build_secondary_vars(model_data)
grid_ranked <- fit_specification_grid(model_data2)
results_secondary <- build_secondary_table(model_data2, grid_ranked)

cat("\n=== Secondary specification search ===\n")
cat("Specifications tested:", nrow(grid_ranked), "\n")
cat("Best (highest adj. R2):", attr(results_secondary, "formula"), "\n")
cat("adj. R2 =", attr(results_secondary, "adj_R2"), "(vs. primary spec's", round(summary(primary_model)$adj.r.squared, 3), ")\n")
print(as.data.frame(results_secondary), digits = 3)

save_table(results_secondary, "table5",
           caption = "Secondary specification (highest adjusted R\\textsuperscript{2}).",
           notes = paste0("Selected from a pre-registered grid of ", nrow(grid_ranked), " alternatives varying income inclusion/functional form, temperature/hours functional form, and an extra growth$\\times$income interaction. Cluster-robust (respondent-level) SE in parentheses. *** p$<$0.01, ** p$<$0.05, * p$<$0.1 (unadjusted p-values - this is a single selected descriptive model, not a pre-registered hypothesis-test family, so no FDR correction applies). Winning formula: ", gsub("_", "\\\\_", attr(results_secondary, "formula")), "."))

# Figure (iv): coefficient plot of this winning secondary specification
fig4 <- plot_secondary_spec(results_secondary)
save_figure(fig4$plot, "fig4_secondary_spec", width = 8, height = 6)

# Heterogeneity (Q5), same 4 demographics, applied to the secondary spec
secondary_formula_str <- grid_ranked$formula_str[1]
secondary_attribute_terms <- get_secondary_attribute_terms(grid_ranked)
het_secondary <- fit_all_heterogeneity(model_data2, secondary_formula_str, secondary_attribute_terms)
results_het_secondary <- build_heterogeneity_table(het_secondary)
cat("\n=== Heterogeneity: secondary specification ===\n")
cat("Interaction terms estimated:", nrow(results_het_secondary), "\n")
print(as.data.frame(results_het_secondary), digits = 3)
save_table(results_het_secondary, "table10", group_by = "Demographic",
           caption = "Heterogeneity: secondary (best-fitting) specification.",
           notes = "AMCEs interacted with respondent characteristics, one demographic at a time. Baselines: Age vs. 18-34; Gender vs. Female (\"Other\", N=4, excluded); Region vs. Northwest; Education vs. Compulsory/lower secondary. Cluster-robust (respondent-level) SE in parentheses. *** p$<$0.01, ** p$<$0.05, * p$<$0.1 (unadjusted p-values - exploratory heterogeneity analysis, not part of the FDR-corrected pre-registered family). Political orientation not yet available (placeholder pending wave 1 merge).")

# Transparency table: top 15 candidate specifications by adjusted R2, so the
# selection process itself is auditable (not just the winner)
grid_top15 <- grid_ranked %>%
  head(15) %>%
  mutate(
    rank = row_number(), adj_r2 = round(adj_r2, 4),
    # variant names like "pairwise_binary" contain a raw underscore, which
    # breaks LaTeX (sanitize.text.function = identity in save_table()) -
    # escape it here rather than in the grid itself, since the unescaped
    # name is also used elsewhere as a list key (income_variants[["pairwise_binary"]] etc.)
    across(c(income, temperature, hours, extra_interaction), ~ gsub("_", "\\\\_", .x))
  ) %>%
  select(Rank = rank, Income = income, Temperature = temperature, Hours = hours,
         "Extra interaction" = extra_interaction, "Adj. R2" = adj_r2)
save_table(grid_top15, "table6", digits = 4,
           caption = "Secondary specification search: top 15 candidates.",
           notes = paste0("Out of ", nrow(grid_ranked), " candidate specifications, ranked by adjusted R\\textsuperscript{2}. Q5 grid: income inclusion/functional form, temperature/hours functional form, extra growth$\\times$income interaction. Rank 1 is the winning specification reported in Table~\\ref{tab:table5}."))

# -----------------------------------------------------------------------------
# Stage 4d: Elastic Net interaction-term selection (Q5) - applied to BOTH
# the primary and the secondary (best-fitting) specification
# -----------------------------------------------------------------------------

en_terms <- select_en_interactions(model_data2)
cat("\n=== Elastic Net interaction selection ===\n")
cat("Interaction terms selected:", length(en_terms), "\n")
if (length(en_terms) > 0) print(en_terms)

results_h1h4_en <- add_en_interactions(model_data2, primary_formula_str, en_terms)
cat("\n=== Primary specification + Elastic Net interactions ===\n")
print(as.data.frame(results_h1h4_en), digits = 3)
save_table(results_h1h4_en, "table7",
           caption = "Primary specification with Elastic Net interactions.",
           notes = paste0(length(en_terms), " interaction term(s) selected via Elastic Net added to the base specification. $\\alpha$=0.5, main effects unpenalized, lambda.1se. Cluster-robust (respondent-level) SE in parentheses. *** p$<$0.01, ** p$<$0.05, * p$<$0.1 (unadjusted; descriptive, not part of the FDR-corrected pre-registered family). Compare to Table~\\ref{tab:table3} (without these interactions)."))

results_secondary_en <- add_en_interactions(model_data2, secondary_formula_str, en_terms)
cat("\n=== Secondary specification + Elastic Net interactions ===\n")
print(as.data.frame(results_secondary_en), digits = 3)
save_table(results_secondary_en, "table8",
           caption = "Secondary specification with Elastic Net interactions.",
           notes = paste0("The same ", length(en_terms), " Elastic-Net-selected interaction term(s) added to the secondary (highest adjusted R\\textsuperscript{2}) specification. Cluster-robust (respondent-level) SE in parentheses. *** p$<$0.01, ** p$<$0.05, * p$<$0.1 (unadjusted; descriptive). Compare to Table~\\ref{tab:table5} (without these interactions)."))

# -----------------------------------------------------------------------------
# Stage 5: H5-H11 (Task 1 named-scenario contrasts vs BC)
# -----------------------------------------------------------------------------

results_h5h11 <- build_h5h11_table(few_pairs)

cat("\n=== H5-H11 results ===\n")
print(as.data.frame(results_h5h11), digits = 3)

save_table(results_h5h11, "table1",
           caption = "H5--H11: BC vs. named-scenario contrasts.",
           notes = "Estimate = share choosing BC (HC1-robust SE in parentheses). *** p$<$0.01, ** p$<$0.05, * p$<$0.1 (FDR-adjusted). One-sided test direction per pre-registration: H5--H9 (BI/BG/BN/BC\\_SD/BCmat) test H1: share $>$ 0.5 (BC preferred); H10--H11 (BCflight/BCbeef) test H1: share $<$ 0.5 (the alternative scenario is preferred). $^\\dagger$ = significant (two-sided, unadjusted p$<$0.1) in the direction OPPOSITE the pre-registered hypothesis - a real effect, just not the one predicted. R2 is 0 by construction (intercept-only models).")

# -----------------------------------------------------------------------------
# Stage 6: Exploratory Bradley-Terry ranking (12 named scenarios)
# -----------------------------------------------------------------------------

bt_data  <- build_bt_data(few_pairs)
bt_model <- fit_bradley_terry(bt_data)
bt_table <- bt_ranking_table(bt_model, bt_data)

cat("\n=== Bradley-Terry ranking ===\n")
print(as.data.frame(bt_table), digits = 3)

save_table(bt_table, "table2",
           caption = "Bradley--Terry ranking of the 12 named scenarios.",
           notes = "Ability = log-strength relative to BC (reference, fixed at 0); SE in parentheses. *** p$<$0.01, ** p$<$0.05, * p$<$0.1 (FDR-adjusted Wald test vs. BC). R2 = McFadden pseudo-R2. \"I don't know\" pairs excluded (Bradley-Terry requires a discrete winner); contrast with the other tables, where they are kept as indifference (selected = 0.5).")

# -----------------------------------------------------------------------------
# Stage 7: "I don't know" secondary analysis (Q8) - frequency and
# sociodemographic predictors, pooled across the 3 DCE tasks
# -----------------------------------------------------------------------------

idk_data <- build_idk_data(raw_data)

results_idk_frequency <- idk_frequency_table(idk_data)
cat("\n=== IDK frequency by task ===\n")
print(as.data.frame(results_idk_frequency))
save_table(results_idk_frequency, "table11",
           caption = "Frequency of ``I don't know'' responses.",
           notes = "By task, and for any of the 3 tasks. SE in parentheses (normal approximation).")

idk_long <- build_idk_long(idk_data)
results_idk_predictors <- fit_idk_predictors(idk_long)
cat("\n=== IDK predictors (pooled across tasks) ===\n")
print(as.data.frame(results_idk_predictors), digits = 4)
save_table(results_idk_predictors, "table12",
           caption = "Predictors of ``I don't know'' responses.",
           notes = "Sociodemographic characteristics and task/scenario features. Pooled linear probability model across the 3 DCE tasks, cluster-robust respondent-level SE in parentheses. *** p$<$0.01, ** p$<$0.05, * p$<$0.1. Baselines: Age vs. 18-34; Gender vs. Female (\"Other\", N=4, excluded); Region vs. Northwest; Education vs. Compulsory/lower secondary; Task vs. Task 2 (ANY). Political orientation not yet available (placeholder pending wave 1 merge).")

# =============================================================================
# End of 00_run_all.R - all pre-registered H1-H11 tests, the secondary/
# alternative specification + Elastic Net (Part 5), the 4 pre-registered
# figures + 2 supplementary ones (Part 6), heterogeneity (Part 7), and the
# IDK secondary analysis (Part 8) are implemented above. Remaining, per the
# gap analysis: the Italian-economists comparison sample (not yet fielded)
# and political orientation as a covariate (pending the wave 1 merge).
# =============================================================================
