# Global Justice Situator

A webpage that shows users how their income evolves under the **Sustainable Convergence (SC)** scenario from Chancel et al. (2026) and Bothe et al. (2026), part of the Global Justice Report.

## Language and tooling

- **Data processing**: R (readxl). Entry point: `code_simulator/prepare_data.R`
- **Webpage**: HTML / CSS / JavaScript (vanilla)
- **Local testing**: XAMPP on Windows 10

## Key concepts

| Term | Definition |
|------|------------|
| **gpercentile** | Within-country income percentile group, represented by its lower-bound percentage (0, 1, …, 98 for standard groups; 99, 99.1, …, 99.999 for fine top-1% groups) |
| **SC scenario** | Sustainable Convergence: global policies reduce inequality to k=5 (T10/B10 ≈ 5) by 2100; world average income converges to ~60,000 EUR PPP 2025 |
| **GIT** | Global Income Transfers — international lump-sum per-capita redistribution mechanism in the SC scenario |
| **posttax income** | After domestic taxes and transfers; "income" in this project also adds GIT (post-GIT) |
| **EUR PPP 2025** | All monetary values in constant 2025 purchasing-power-parity euros |
| **k value** | Inequality parameter: k = T10/B10 ratio; k=5 is the SC 2100 target |

## Data sources

Fetched 2026-05-24:

- **Chancel et al. (2026)** — macro scenarios: `data/Chancel/Chanceletal2026Appendix_MacroScenarios.xlsx`
- **Bothe et al. (2026)** — within-country distributions: `data/Bothe/Botheetal2026AppendixDistribution.xlsx`

### Key sheets in Botheetal2026AppendixDistribution.xlsx

| Sheet | Content |
|-------|---------|
| **P1e** | 2025 average posttax income by gpercentile group (127 groups × 67 countries). Values in EUR PPP 2025/year. Used as starting distribution. |
| **I2i** | SC scenario: average posttax net income time series 1800–2100 (years × 67 countries). |
| **I1a** | SC scenario: T10 income share time series. |
| **I1b** | SC scenario: B50 income share time series. |
| **I1c** | SC scenario: T1 income share time series. |
| **I1e** | SC scenario: B10 income share time series. |
| **I1h** | SC scenario: M40 income share time series. |
| **I5e** | SC scenario: P10 income threshold as ratio to average income (pre-GIT, time series). |
| **I5b** | SC scenario: P50 income threshold as ratio to average income (pre-GIT, time series). |
| **I5c** | SC scenario: P99 income threshold as ratio to average income (pre-GIT, time series). |
| **I5d** | SC scenario: P99.9 threshold as ratio to average income (pre-GIT). |
| **I5f** | SC scenario: P99.99 threshold as ratio to average income (pre-GIT). |
| **I5g** | SC scenario: P99.999 threshold as ratio to average income (pre-GIT). |
| **I9i** | SC scenario: average posttax net income (post-GIT, time series). |
| **I9e** | SC scenario: B10 average income (post-GIT, time series). Bracket [0, 0.10]. |
| **I9b** | SC scenario: B50 average income (post-GIT). Bracket [0, 0.50]. |
| **I9h** | SC scenario: M40 average income (post-GIT). Bracket [0.50, 0.90]. |
| **I9a** | SC scenario: T10 average income (post-GIT). Bracket [0.90, 1.00]. |
| **I9c** | SC scenario: T1 average income (post-GIT). Bracket [0.99, 1.00]. |
| **I9d** | SC scenario: top 0.1% average income (post-GIT). Bracket [0.999, 1.00]. |
| **I9f** | SC scenario: top 0.01% average income (post-GIT). Bracket [0.9999, 1.00]. |
| **I9g** | SC scenario: top 0.001% average income (post-GIT). Bracket [0.99999, 1.00]. |
| **K1a/K2a** | SC scenario: T10 wealth share / average (time series). |
| **K1b/K2b** | B50 wealth share / average. |
| **K1c/K2c** | T1 wealth share / average. |
| **K1e/K2e** | B10 wealth share / average. |
| **K1h/K2h** | M40 wealth share / average. |
| **H1** | SC 2100 target distribution shape (k=5): B50=37.7%, M40=44.1%, T10=18.1%, T1=2.6%. |
| **P1a/P1b** | Target distribution shapes at various k values (k=1..100). |
| **H3b** | Global 2025 income and wealth distribution by global percentile (for reference). |

I9 series (I9a–I9i, all post-GIT group averages) are used as anchors for income.csv. I5 (pre-GIT threshold ratios) is used only for income_pre_git.csv. I10 contains post-GIT inequality ratios (T10/B50 etc.), not group averages, so it is not used.

## Generated data files

### `data/income_pre_git.csv`

Posttax income thresholds at 6 key percentiles, **before** Global Income Transfers, for each country and each year 2020–2100.

| Column | Description |
|--------|-------------|
| `country` | Country/region code (66 values incl. "World") |
| `year` | Year, 2020–2100 |
| `p10` | P10 threshold = I5e × I2i (EUR PPP 2025/year) |
| `p50` | P50 threshold = I5b × I2i |
| `p99` | P99 threshold = I5c × I2i |
| `p99.9` | P99.9 threshold = I5d × I2i |
| `p99.99` | P99.99 threshold = I5f × I2i |
| `p99.999` | P99.999 threshold = I5g × I2i |

Dimensions: 66 countries × 81 years = 5,346 rows.

### `data/income.csv`

SC scenario posttax **post-GIT** income, all 127 gpercentile groups, all years 2020–2100.

| Column | Description |
|--------|-------------|
| `country` | Country/region code |
| `gpercentile` | Lower bound (%) of the percentile bracket: 0, 1, …, 98 (standard groups, 1 pp wide), then 99, 99.1, …, 99.8 (0.1 pp), 99.9, 99.91, …, 99.98 (0.01 pp), 99.99, …, 99.999 (0.001 pp) |
| `income_2020` … `income_2100` | Income in EUR PPP 2025/year for each year |

**Methodology**:

1. **2025 base**: all 127 groups taken directly from P1e (EUR PPP 2025).
2. **Other years**: for each year t ≠ 2025, compute a **scale factor per group** as `group_avg_t / group_avg_2025`. The 2025 group average is derived from P1e (simple mean of equal-width rows within each group); the year-t group average is derived from I9 post-GIT series. All rows within a group are multiplied by the same scale factor, preserving the within-group relative income differences from P1e (consistent with the Type II Pareto intra-group functional form described in Appendix A of Bothe et al.).

   | Rows | Group | Bracket | I9 source (post-GIT) |
   |---|---|---|---|
   | 1–10 | B10 | [0, 0.10] | I9e (B10 avg) |
   | 11–50 | p10_50 | [0.10, 0.50] | (I9b×0.5 − I9e×0.1) / 0.4 |
   | 51–90 | M40 | [0.50, 0.90] | I9h (M40 avg) |
   | 91–99 | p90_99 | [0.90, 0.99] | (I9a×0.1 − I9c×0.01) / 0.09 |
   | 100–108 | p99_999 | [0.99, 0.999] | (I9c×0.01 − I9d×0.001) / 0.009 |
   | 109–117 | p999_9999 | [0.999, 0.9999] | (I9d×0.001 − I9f×0.0001) / 0.0009 |
   | 118–126 | p9999_99999 | [0.9999, 0.99999] | (I9f×0.0001 − I9g×0.00001) / 0.00009 |
   | 127 | top0001 | [0.99999, 1.00] | I9g (top 0.001% avg) |

   All anchors are post-GIT (I9 series). No pre-GIT I5 threshold ratios are used for income.csv.

Dimensions: 66 countries × 127 groups = 8,382 rows × 83 columns.

### `data/income_world.csv`

World income distribution under SC at 6 target years (2025, 2030, 2035, 2050, 2080, 2100).

| Column | Description |
|--------|-------------|
| `gpercentile` | Global income percentile rank, 1–100 |
| `income_2025` … `income_2100` | Income in EUR PPP 2025/year |

Dimensions: 100 rows × 7 columns. Used for the distribution chart on the webpage.

### `data/wealth.csv`

SC scenario wealth, all 100 gpercentiles, target years 2025–2100.

| Column | Description |
|--------|-------------|
| `country` | Country/region code |
| `gpercentile` | Within-country wealth percentile rank, 1–100 |
| `wealth_2025` … `wealth_2100` | Wealth in EUR PPP 2025 |

**Methodology**: 5-group scaling (B10, p10-50, M40, T10-T1, T1) using K2 group average series, starting from K2 group averages at 2025.

Dimensions: 6,600 rows × 8 columns.

### `data/wealth_world.csv`

World wealth distribution at 6 target years.

Dimensions: 100 rows × 7 columns.

## Countries and regions

66 values total, including "World":

Individual countries: AE, AR, AU, BD, BR, CA, CD, CI, CL, CN, CO, DE, DK, DZ, EG, ES, ET, FR, GB, ID, IN, IR, IT, JP, KE, KR, MA, ML, MM, MX, NE, NG, NL, NO, NZ, PH, PK, RU, RW, SA, SD, SE, TH, TR, TW, US, VN, ZA

Residual "other" groups (WID.world codes): OA (Other Russia/Central Asia), OB (Other East Asia), OC (Other Western Europe), OD (Other Latin America), OE (Other MENA), OH (Other North America/Oceania), OI (Other South & SE Asia), OJ (Other Sub-Saharan Africa), QM (Eastern Europe)

Aggregate regions: East Asia, Europe, Latin America, Middle East North Africa, North America Oceania, Russia Central Asia, South & South-East Asia, Sub-Saharan Africa

Plus: World

## Running the data pipeline

```r
# in R, from the project root:
Rscript --vanilla code_simulator/prepare_data.R  # run from project root
```

Outputs all five CSV files to `data/`. Runtime: ~2 minutes.

## Local testing

Place the project folder under XAMPP's `htdocs/` and access via `http://localhost/global_justice/`.
