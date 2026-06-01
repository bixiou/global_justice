# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Security Rules
- You are strictly confined to the current directory.
- Never attempt to read or write files outside of this folder.
- Do not use absolute paths (e.g., C:\...).
- If a task requires accessing external data, ask the user for permission or to provide the file.

## Project Overview

This is a project to create a webpage simulating the user's income in a scenario with global policies towards sustainable convergence, based on Chancel et al. (2026) and Bothe et al. (2026), both part of the Global Justice Report.

## Data sources

Data was fetched on May 24, 2026:
- Chancel et al. (2026): https://wseed.world/data.html
- Bothe et al. (2026): https://wid.world/document/replication-package-working-paper-2026-11/

## Workflow / Pipeline



## Key Data Files

- global income distribution in different scenarios, years, and countries: Chanceletal2026Appendix_MacroScenarios > sheets A
- within-country income and wealth distributions: Botheetal2026AppendixDistribution > sheets I and K.
(- global sectoral composition of GNE in different scenarios, years, and countries: Chanceletal2026Appendix_MacroScenarios > sheets G
- global temperature in different scenarios and years: Chanceletal2026Appendix_Emission_Output > sheets SC/PI/PC)

## R Code Style

- Always start an R session by running `.Rprofile` and loading `.RData` before running any script. These provide shared utility functions and pre-loaded objects used throughout.
- Use `snake_case` for all variable and function names.
- Always use the native pipe `|>` (R 4.1+), never `%>%`.
- Prefer compact, single-line expressions where readable.
- Document functions with roxygen2 style.
- Explicitly handle `NA` values.

## Key Rules

- Never read or modify `.RData` files or any file listed in `.gitignore`.
- Before writing 500+ lines of code, provide a summary of the logic first.
- After completing a TODO item, tick its checkbox in `TODO.md`.
- When referencing `@Folder`, analyze files to ensure consistency between the cleaning script and the analysis script.
- Don't compile .tex files in `/papers` but in `papers/build/`: there should be no auxiliary files in `/papers`.
- Export all income distributions .csv into `/distributions` and all figurers to `/figures`.
- Name all sections in a .R file using "##### n. Section #####".
- Always put only one space between R text and never indent/align things over different lines, e.g. write "obj <- NA" instead of "obj    <- NA".
- Always assume (or set) the following working directory: `/code_simulator`.
- When exporting a .csv, do not use quotes (unless there are commas in the data).