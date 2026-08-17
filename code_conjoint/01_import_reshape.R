# =============================================================================
# Part 1 - Import raw wave data and reshape into analysis-ready formats
# Project: Preferences for the future - alternative scenarios for the XXI century
# =============================================================================
#
# This script:
#   1. Imports a raw .sav wave file (Bilendi export, already "qualified":
#      attention check, bot/AI check, completion-time and
#      open-ended screens already applied upstream).
#   2. Builds the "current declared income" variable used for H4.
#   3. Reshapes Task 2 (ANY, growth = 1.5%) and Task 3 (ANY2, growth = 3%)
#      from wide (1 row per respondent) to long (1 row per profile shown).
#      "I don't know" pairs are KEPT (selected = 0.5, i.e. indifference,
#      per the pre-registration) and also flagged/routed to a separate
#      "idk" dataset for the secondary analysis of "I don't know" responses.
#      cjoint::amce() cannot accept a non-binary outcome, so the one figure
#      that uses it (fit_amce_by_task(), Part 6) filters "I don't know" back
#      out for that specific call only.
#   4. Reshapes Task 1 (FEW, named scenarios) into a pair-level dataset,
#      used later both for the 7 BC-vs-alternative regressions (H5-H11)
#      and for the exploratory Bradley-Terry ranking of the 12 named
#      scenarios.
#
# IMPORTANT: for ANY/ANY2, we use the NON-underscored attribute columns
# (e.g. ANYLhoursPerWeek, ANYLtemperature...), which are the final,
# human-readable attribute values shown to the respondent (retrieved from
# window.conjointExport). The underscored columns (e.g. ANY_LhoursPerWeek)
# are raw randomizer codes and are kept only for optional robustness checks
# of the randomization procedure, not used in the main analysis.
# =============================================================================

library(haven)
library(dplyr)
library(tidyr)
library(purrr)
library(stringr)

# -----------------------------------------------------------------------------
# 0. Project directories
# -----------------------------------------------------------------------------

# Raw .sav wave files (Bilendi exports) live here.
# NOTE: the OneDrive folder name resolved dynamically (rather than
# hardcoded) to avoid a Unicode normalization mismatch (NFC vs NFD) in the
# accented "à" between how CloudStorage names the folder on disk and how a
# literal string is typically written/saved in this script.
cloud_storage_dir <- "/Users/viola/Library/CloudStorage"
onedrive_dir <- list.files(cloud_storage_dir, pattern = "^OneDrive-Raccoltecondivise", full.names = TRUE)[1]
RAW_DATA_DIR <- file.path(onedrive_dir, "Riccardo Ghidoni - PE9_GRINS_rawdata/Follow-up/raw")

# Reshaped/derived datasets (raw_data_combined, amce_data, idk_data, few_pairs,
# model_data_h1h4) go here
DATA_DIR <- "/Users/viola/Dropbox/DCE conjoint analysis/data"

# Results tables (results_h1h4, results_h5h11, bt_ranking_table) go here
OUTPUT_DIR <- "/Users/viola/Dropbox/DCE conjoint analysis/output"

# -----------------------------------------------------------------------------
# 1. Import
# -----------------------------------------------------------------------------

#' Import one raw .sav wave file and tag it with a batch label
#'
#' @param path path to the .sav file
#' @param batch_label character, e.g. "soft_launch_1", "soft_launch_2", "full_partial"
#' @param no_income_filter logical, TRUE for the 100 soft-launch respondents
#'   who were fielded without the income screening filter
import_wave <- function(path, batch_label, no_income_filter = FALSE) {
  df <- haven::read_sav(path)
  df$batch <- batch_label
  df$no_income_filter <- no_income_filter
  # respondent-level unique id: combine batch and record to avoid collisions
  # across files once we start appending waves
  df$resp_id <- paste0(batch_label, "_", df$record)
  df
}

# Example (to be adapted once all three files are available):
# partial_1 <- import_wave(file.path(RAW_DATA_DIR, "partial_1.sav"), "soft_launch_1", no_income_filter = TRUE)
# partial_2 <- import_wave(file.path(RAW_DATA_DIR, "partial_2.sav"), "soft_launch_2", no_income_filter = FALSE)
# partial_3 <- import_wave(file.path(RAW_DATA_DIR, "partial_3.sav"), "full_partial",  no_income_filter = FALSE)
# raw_data  <- bind_rows(partial_1, partial_2, partial_3)  # append, not merge:
#                                                            # different respondents

# -----------------------------------------------------------------------------
# 2. Current declared income (used for H4: future income > current income)
# -----------------------------------------------------------------------------

#' Add current declared income, preferring REVISED_INCOME over income when
#' the former is non-missing (per user instruction: "confronta il reddito
#' dichiarato, net income o revised se non-missing")
add_current_income <- function(df) {
  df %>%
    mutate(
      current_income = ifelse(!is.na(REVISED_INCOME), REVISED_INCOME, income)
    )
}

# -----------------------------------------------------------------------------
# 2b. Pre-registered robustness check: flag declared income above the 99th
# percentile of the Italian income distribution (Q6)
# -----------------------------------------------------------------------------

# 99th-percentile threshold of annual per-adult income, from the "IT25"
# column (current/2025 Italian income distribution) in
# https://github.com/bixiou/global_justice/blob/main/code_simulator/IT_survey/data/ineq_IT_2035.csv
# (gpercentile == 99 row) - this is the same reference table the survey's
# own scenarios.js (findPercentileInIT25()) uses to compute
# *RespondentPercentile. Formula verified empirically: recomputing
# current_income * 12 / n_adults and looking it up in this table reproduces
# the survey's own ANYLRespondentPercentile exactly (0 mismatches across all
# 3555 respondents) - confirming both the formula and this threshold.
ITALY_INCOME_P99_ANNUAL_PER_ADULT <- 134640

#' Flag respondents whose declared current income, annualized and adjusted
#' for household size, exceeds the 99th percentile of the (2025) Italian
#' income distribution - pre-registered as a data-quality robustness check
#' (Q6: "declared income values above the 99th percentile... will be flagged
#' as potentially erroneous and reported as a robustness check")
#'
#' @param df data frame with `current_income` (monthly) and `couple`
#'   (1 = in a couple -> 2 adults in household; else 1 adult)
flag_high_income <- function(df) {
  df %>%
    mutate(
      n_adults = ifelse(couple == 1, 2, 1),
      annual_income_per_adult = current_income * 12 / n_adults,
      income_flag_p99 = annual_income_per_adult > ITALY_INCOME_P99_ANNUAL_PER_ADULT
    )
}

# -----------------------------------------------------------------------------
# 2c. Respondent covariates for heterogeneity/subgroup analyses (Q5, Q8)
# -----------------------------------------------------------------------------

#' Build clean covariate factors from the raw demographic variables, for the
#' H1-H4 heterogeneity analysis (age/income/political orientation/education,
#' Part 7) and the IDK secondary analysis (Part 8).
#'
#' PLACEHOLDER (2026-08-04): only 4 covariates are available in the current
#' dataset - AGE_BRACKETS, Gender, Macro_areas, EDUCATION. Political
#' orientation, explicitly required by the pre-registration for the
#' heterogeneity analysis, is NOT yet available and will be added once
#' merged with the wave 1 survey data. Gender's third level ("Other") has
#' only N=4 respondents - too small for a stable subgroup/interaction
#' estimate on its own; flagged here rather than silently collapsed, so the
#' analysis scripts using this can decide (e.g. drop or pool with a wider
#' category) explicitly rather than by default.
#' @param df data frame with the raw AGE_BRACKETS/Gender/Macro_areas/
#'   EDUCATION columns (haven_labelled, from the .sav import)
build_covariates <- function(df) {
  df %>%
    mutate(
      age_bracket = factor(
        haven::as_factor(AGE_BRACKETS),
        levels = c("18-34", "35-54", "55 e oltre"),
        labels = c("18-34", "35-54", "55+")
      ),
      gender = factor(
        haven::as_factor(Gender),
        levels = c("Femmina", "Maschio", "Non mi identifico con nessuna delle categorie precedenti"),
        labels = c("Female", "Male", "Other")
      ),
      macro_area = factor(
        haven::as_factor(Macro_areas),
        levels = c("Nord Ovest", "Nord Est", "Centro", "Sud", "Isole"),
        labels = c("Northwest", "Northeast", "Center", "South", "Islands")
      ),
      education = factor(
        haven::as_factor(EDUCATION),
        levels = c("Licenza elementare o media", "Diploma di scuola superiore",
                   "Laurea universitaria, master o dottorato"),
        labels = c("Compulsory/lower secondary", "Upper secondary", "Tertiary")
      )
    )
}

# -----------------------------------------------------------------------------
# 3. Reshape ANY / ANY2 tasks (Task 2 / Task 3) to long profile-level format
# -----------------------------------------------------------------------------

# Displayed attribute suffixes shared by ANY / ANY2 (non-underscored columns)
displayed_attrs <- c(
  "workedHours", "hoursPerWeek", "decarbonization", "redistribution",
  "nationalRedistribution", "globalRedistribution", "publicServices",
  "beefAndFlights", "NetIncome", "RespondentPercentile", "temperature",
  "bottom10World", "medianWorld", "top10World",
  "bottom10Italy", "medianItaly", "top10Italy"
)

# Respondent-level (non attribute-specific) columns to carry into the long
# format. Extend this list once more covariates are available (see
# build_covariates()'s placeholder note - political orientation still missing).
respondent_cols <- c("resp_id", "batch", "no_income_filter", "current_income",
                      "income", "REVISED_INCOME", "income_flag_p99",
                      "age_bracket", "gender", "macro_area", "education")

#' Reshape one randomized task (ANY or ANY2) from wide to long
#'
#' @param data wide data frame (1 row per respondent)
#' @param prefix column prefix, "ANY" or "ANY2"
#' @param dce_var name of the choice column, e.g. "ANY_DCE" / "ANY2_DCE"
#'   (values: 1 = Scenario A / side L, 2 = Scenario B / side R, 3 = Non lo so)
#' @param growth_value numeric, annual productivity growth fixed for this
#'   task (1.5 for ANY / Task 2, 3 for ANY2 / Task 3), used later for the
#'   hours x growth interaction (H3)
#'
#' @return a list with two elements:
#'   - long: profile-level long data (1 row per profile shown), ready for
#'     the lm()-based H1-H4 model. "I don't know" pairs are KEPT here, with
#'     selected = 0.5 on both profiles - per the pre-registration ("'I don't
#'     know'... will be treated as indifference between the two options"),
#'     not dropped. The `is_idk` flag is kept on these rows so any code that
#'     structurally cannot handle a non-binary outcome (e.g. cjoint::amce(),
#'     which requires a strict 0/1 matched pair) can filter them back out
#'     explicitly - see fit_amce_by_task() and compute_attribute_share() in
#'     Part 6.
#'   - idk: pair-level data flagging "I don't know" responses, for the
#'     secondary IDK analysis (Part 8)
reshape_random_task <- function(data, prefix, dce_var, growth_value) {

  stopifnot(dce_var %in% names(data))

  # Build one side (L or R) in long format
  build_side <- function(side) {
    side_cols <- paste0(prefix, side, displayed_attrs)
    side_cols <- side_cols[side_cols %in% names(data)]
    present_attrs <- displayed_attrs[paste0(prefix, side, displayed_attrs) %in% names(data)]

    out <- data %>%
      select(all_of(respondent_cols), all_of(dce_var), all_of(side_cols))

    # rename attribute columns to plain attribute names
    names(out)[match(side_cols, names(out))] <- present_attrs

    out %>%
      mutate(
        side       = side,
        task       = prefix,
        growth     = growth_value,
        pair_id    = paste0(resp_id, "_", prefix),
        dce_choice = .data[[dce_var]] 
      )
  }

  long_L <- build_side("L")
  long_R <- build_side("R")

  both <- bind_rows(long_L, long_R) %>%
    mutate(is_idk = dce_choice == 3)

  # 'selected' logic (explicit, non-overlapping):
  #   side == L & choice == 1 (A)  -> selected = 1
  #   side == L & choice == 2 (B)  -> selected = 0
  #   side == R & choice == 2 (B)  -> selected = 1
  #   side == R & choice == 1 (A)  -> selected = 0
  #   choice == 3 (Non lo so)      -> selected = 0.5 on BOTH profiles
  #     (indifference, per the pre-registration - kept in the regression,
  #     not dropped)
  both <- both %>%
    mutate(
      selected = case_when(
        is_idk ~ 0.5,
        side == "L" & dce_choice == 1 ~ 1,
        side == "L" & dce_choice == 2 ~ 0,
        side == "R" & dce_choice == 2 ~ 1,
        side == "R" & dce_choice == 1 ~ 0,
        TRUE ~ NA_real_
      )
    )

  idk_pairs <- both %>%
    filter(is_idk) %>%
    distinct(resp_id, task, batch, no_income_filter, current_income, pair_id)

  # long_main KEEPS the "I don't know" rows (selected = 0.5) - only
  # dce_choice is dropped (no longer needed once 'selected'/'is_idk' are
  # derived from it). `is_idk` is kept so downstream code that cannot
  # accept a non-binary outcome can filter it back out explicitly.
  long_main <- both %>%
    select(-dce_choice)

  list(long = long_main, idk = idk_pairs)
}

# Example usage once raw_data (appended waves) is built:
# task2 <- reshape_random_task(raw_data, prefix = "ANY",  dce_var = "ANY_DCE",  growth_value = 1.5)
# task3 <- reshape_random_task(raw_data, prefix = "ANY2", dce_var = "ANY2_DCE", growth_value = 3.0)
# amce_data <- bind_rows(task2$long, task3$long)   # for figure (ii): AMCE Task 2 & 3 superimposed
# idk_data  <- bind_rows(task2$idk,  task3$idk)    # secondary IDK analysis

# -----------------------------------------------------------------------------
# 4. Reshape FEW task (Task 1, named scenarios) to pair-level format
# -----------------------------------------------------------------------------

# The 7 named scenarios contrasted against BC in H5-H11 (pre-registered)
h5_h11_contrasts <- c("BI", "BG", "BN", "BC_SD", "BCmat", "BCflight", "BCbeef")

# All 12 named scenarios used in the exploratory Bradley-Terry ranking
bt_scenarios <- c("BC", h5_h11_contrasts, "BC45k", "BC90k", "BC120k", "BI120k")

few_attrs <- c(
  "scenario", "label", "hoursPerWeek", "nationalRedistribution",
  "globalRedistribution", "decarbonization", "publicServices",
  "beefAndFlights", "NetIncome", "RespondentPercentile", "temperature",
  "bottom10World", "medianWorld", "top10World",
  "bottom10Italy", "medianItaly", "top10Italy"
)

#' Reshape Task 1 (FEW) to a pair-level data frame: 1 row per respondent
#' with both named scenarios shown, the chosen one, and a BC-choice
#' indicator ready for filtering into the 7 H5-H11 regressions.
reshape_named_task <- function(data, dce_var = "FEW_DCE") {

  l_cols <- paste0("FEWL", few_attrs)
  r_cols <- paste0("FEWR", few_attrs)
  l_cols <- l_cols[l_cols %in% names(data)]
  r_cols <- r_cols[r_cols %in% names(data)]

  out <- data %>%
    select(all_of(respondent_cols), all_of(dce_var), all_of(l_cols), all_of(r_cols))

  names(out)[match(l_cols, names(out))] <- paste0("L_", few_attrs[paste0("FEWL", few_attrs) %in% l_cols])
  names(out)[match(r_cols, names(out))] <- paste0("R_", few_attrs[paste0("FEWR", few_attrs) %in% r_cols])

  out %>%
    mutate(
      task = "FEW",
      is_idk = .data[[dce_var]] == 3,
      chosen_side = case_when(
        is_idk ~ NA_character_,
        .data[[dce_var]] == 1 ~ "L",
        .data[[dce_var]] == 2 ~ "R"
      ),
      chosen_scenario = case_when(
        is_idk ~ NA_character_,
        chosen_side == "L" ~ L_scenario,
        chosen_side == "R" ~ R_scenario
      ),
      unchosen_scenario = case_when(
        is_idk ~ NA_character_,
        chosen_side == "L" ~ R_scenario,
        chosen_side == "R" ~ L_scenario
      )
    )
}

#' From the FEW pair-level data, build the analysis dataset for one
#' H5-H11 contrast (BC vs alt_scenario): keeps only respondents who were
#' actually shown that specific pair, and computes chose_BC (0/1, or 0.5
#' for "I don't know" - indifference, per the pre-registration - kept in
#' the regression rather than dropped; fit_one_contrast()'s intercept-only
#' lm() just needs a numeric outcome, so this requires no other change).
few_contrast_data <- function(few_pairs, alt_scenario) {
  few_pairs %>%
    filter((L_scenario == "BC" & R_scenario == alt_scenario) |
           (L_scenario == alt_scenario & R_scenario == "BC")) %>%
    mutate(
      chose_BC = case_when(
        is_idk ~ 0.5,
        chosen_scenario == "BC" ~ 1,
        TRUE ~ 0
      )
    )
}

# Example usage:
# few_pairs <- reshape_named_task(raw_data)
# idk_few   <- few_pairs %>% filter(is_idk) %>%
#                select(resp_id, batch, L_scenario, R_scenario)
# h5_data   <- few_contrast_data(few_pairs, "BI")     # H5: BC vs BI
# h8_data   <- few_contrast_data(few_pairs, "BC_SD")  # H8: BC vs BC_SD
# ... one call per contrast in h5_h11_contrasts

# Bradley-Terry input: one row per pair with named scenarios on both sides
# (winner/loser), restricted to the 12-scenario list, "I don't know" dropped
# few_bt_data <- few_pairs %>%
#   filter(!is_idk, L_scenario %in% bt_scenarios, R_scenario %in% bt_scenarios) %>%
#   transmute(resp_id, winner = chosen_scenario, loser = unchosen_scenario)

# -----------------------------------------------------------------------------
# 5. Export reshaped datasets (RDS + Stata .dta)
# -----------------------------------------------------------------------------
#
# RDS preserves the R object exactly as-is (types, factor levels, NAs) and is
# used for the R analysis pipeline (cjoint, glmnet, BradleyTerry2...).
# .dta (Stata) is exported in parallel for cross-checking / sharing with
# Stata. Note: .dta has stricter constraints than RDS (variable names <= 32
# chars, no native support for nested lists), so any R-specific structure
# must be flattened before writing - the functions below already return
# plain data frames, so this is not an issue here.

library(haven)

#' Save one data frame to both <name>.rds and <name>.dta
#'
#' @param df data frame to save
#' @param name file name without extension
#' @param out_dir output directory (created if missing); defaults to DATA_DIR
#'   for reshaped/derived datasets - pass out_dir = OUTPUT_DIR for results
#'   tables
save_dataset <- function(df, name, out_dir = DATA_DIR) {
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  rds_path <- file.path(out_dir, paste0(name, ".rds"))
  dta_path <- file.path(out_dir, paste0(name, ".dta"))

  saveRDS(df, rds_path)

  # haven::write_dta requires variable names <= 32 characters and does not
  # support list-columns; our reshaped data frames are plain and should
  # write without modification. If a future variable violates this, rename
  # or drop it before calling save_dataset().
  haven::write_dta(df, dta_path)

  invisible(list(rds = rds_path, dta = dta_path))
}

#' Escape underscores for literal (non-math-mode) use in a hand-built LaTeX
#' table cell - e.g. the "BC_SD" scenario code -> "BC\\_SD". Used by
#' build_h5h11_table() and bt_ranking_table() (Part 4), since save_table()
#' turns off xtable's automatic sanitization to allow hand-written LaTeX
#' markup (stars, \\&, $\\times$...) elsewhere in those tables.
latex_escape_underscore <- function(x) gsub("_", "\\\\_", x)

#' Save one results table as a complete, standalone LaTeX table environment,
#' in a compact academic style (double hlines, hspace-indented rows,
#' Observations/R-squared as their own table rows, notes via
#' \\tablenotes) - written identically to both <name>.tex and <name>.txt
#' (same LaTeX content, just two extensions). Generates LaTeX directly
#' (no xtable) for full control over this exact layout.
#'
#' Requires \\usepackage{threeparttable} in the including document's
#' preamble for \\tablenotes to render (needed only when `notes` is given).
#'
#' @param df data frame to save. If it carries "N" and/or "R2" attributes
#'   (set via attr(df, "N") <- ..., as build_h1h4_table(), build_h5h11_table()
#'   and bt_ranking_table() do for values that are constant across all rows),
#'   these become their own "Observations"/"R-squared" rows instead of being
#'   repeated as columns.
#' @param name file name without extension
#' @param out_dir output directory (created if missing); defaults to OUTPUT_DIR
#' @param digits decimal places for any raw numeric column that isn't
#'   already a pre-formatted string (integer-valued columns like N print as
#'   plain integers regardless of `digits`)
#' @param caption SHORT table caption - just what the table is, not how to
#'   read it; defaults to `name` with underscores replaced by spaces. Put
#'   stars/SE/baseline/FDR explanations in `notes` instead
#' @param notes optional explanatory text (already LaTeX-escaped), rendered
#'   as a \\tablenotes block below the table (stars legend, SE convention,
#'   baselines, FDR caveats...)
#' @param group_by optional name of a column in `df` (already sorted by
#'   this column - not re-sorted here) to use as row-group headers instead
#'   of a repeated data column: e.g. a "Demographic" column with "Age"
#'   repeated on 22 rows becomes one bold "\\textbf{Age}" header row above
#'   those 22 rows, and the column itself is dropped from the table
save_table <- function(df, name, out_dir = OUTPUT_DIR, digits = 3, caption = NULL, notes = NULL, group_by = NULL) {
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  if (is.null(caption)) caption <- gsub("_", " ", name)

  n_attr  <- attr(df, "N")
  r2_attr <- attr(df, "R2")

  df <- as.data.frame(df)

  group_col <- NULL
  if (!is.null(group_by)) {
    group_col <- df[[group_by]]
    df <- df[, setdiff(names(df), group_by), drop = FALSE]
  }

  # format any raw numeric column (most columns arrive already formatted as
  # strings, e.g. "0.032***", from the build_*_table() functions) - integer-
  # valued columns (like N) print with no decimals regardless of `digits`
  df[] <- lapply(df, function(col) {
    if (is.numeric(col)) {
      if (all(col == round(col), na.rm = TRUE)) format(col, big.mark = ",", scientific = FALSE)
      else formatC(col, digits = digits, format = "f")
    } else {
      as.character(col)
    }
  })

  ncol_data <- ncol(df)
  col_spec <- paste(c("l", rep("c", max(0, ncol_data - 1))), collapse = " ")

  header_names <- names(df)
  header_names[1] <- if (grepl("^\\s*$", header_names[1])) "" else header_names[1]
  header_line <- paste0(paste(header_names, collapse = " & "), " \\\\")

  # data rows, each row-label indented with \hspace{0.05cm}; group_by
  # inserts a bold, full-width header row (with its own \hline above, except
  # before the very first group) wherever group_col's value changes
  body_lines <- character(0)
  last_group <- NULL
  for (i in seq_len(nrow(df))) {
    if (!is.null(group_col) && (is.null(last_group) || !identical(group_col[i], last_group))) {
      if (!is.null(last_group)) body_lines <- c(body_lines, "\\hline")
      body_lines <- c(body_lines, paste0("\\multicolumn{", ncol_data, "}{l}{\\textbf{", group_col[i], "}} \\\\"))
      last_group <- group_col[i]
    }
    row_vals <- as.character(unlist(df[i, ], use.names = FALSE))
    row_vals[1] <- paste0("\\hspace{0.05cm} ", row_vals[1])
    body_lines <- c(body_lines, paste0(paste(row_vals, collapse = " & "), " \\\\"))
  }

  # Observations/R-squared as their own rows (not a footnote), each value
  # centered in one merged cell spanning the data columns - unlike the
  # per-outcome-column N a multi-outcome table might show, our tables come
  # from a single shared model, so one spanning value is the natural fit
  stat_lines <- character(0)
  if (!is.null(n_attr) || !is.null(r2_attr)) {
    stat_lines <- c(stat_lines, "\\hline")
    span <- max(1, ncol_data - 1)
    if (!is.null(n_attr)) {
      stat_lines <- c(stat_lines, paste0(
        "\\hspace{0.05cm} Observations & \\multicolumn{", span, "}{c}{",
        format(n_attr, big.mark = ",", scientific = FALSE), "} \\\\"
      ))
    }
    if (!is.null(r2_attr)) {
      stat_lines <- c(stat_lines, paste0(
        "\\hspace{0.05cm} R-squared & \\multicolumn{", span, "}{c}{", r2_attr, "} \\\\"
      ))
    }
  }

  notes_block <- if (!is.null(notes)) {
    c("\\begin{tablenotes}", "\\small", paste0("\\item \\textit{Notes:} ", notes), "\\end{tablenotes}")
  } else character(0)

  latex_lines <- c(
    "\\begin{table}[H]",
    "    \\centering",
    paste0("    \\caption{", caption, "}"),
    paste0("    \\begin{tabular}{ ", col_spec, " }"),
    "\\hline \\hline",
    header_line,
    "\\hline",
    body_lines,
    stat_lines,
    "\\hline \\hline",
    "\\end{tabular}",
    notes_block,
    paste0("    \\label{tab:", name, "}"),
    "\\end{table}"
  )

  txt_path <- file.path(out_dir, paste0(name, ".txt"))
  tex_path <- file.path(out_dir, paste0(name, ".tex"))
  writeLines(latex_lines, tex_path)
  writeLines(latex_lines, txt_path)

  invisible(list(txt = txt_path, tex = tex_path))
}

# Example usage, once the reshaped datasets have been built:
#
# amce_data <- bind_rows(task2$long, task3$long)
# idk_data  <- bind_rows(task2$idk,  task3$idk)
# few_pairs <- reshape_named_task(raw_data)
#
# save_dataset(amce_data, "amce_data")   # Task 2+3, long, for cjoint::amce()
# save_dataset(idk_data,  "idk_data")    # Task 2+3, "I don't know" pairs
# save_dataset(few_pairs, "few_pairs")   # Task 1, pair-level (H5-H11 + Bradley-Terry source)
# (all written to OUTPUT_DIR by default; pass out_dir = ... to override)

# =============================================================================
# End of Part 1
# =============================================================================
