# Global Justice Situator

claude --resume c37a0008-f864-4c88-b557-fb500f7d7c70

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
| **I8c** | SC scenario: T1 income share (post-GIT, time series). |
| **I8e** | SC scenario: B10 income share (post-GIT, time series). |
| **I9i** | SC scenario: average posttax net income (post-GIT, time series). |
| **K1a/K2a** | SC scenario: T10 wealth share / average (time series). |
| **K1b/K2b** | B50 wealth share / average. |
| **K1c/K2c** | T1 wealth share / average. |
| **K1e/K2e** | B10 wealth share / average. |
| **K1h/K2h** | M40 wealth share / average. |
| **H1** | SC 2100 target distribution shape (k=5): B50=37.7%, M40=44.1%, T10=18.1%, T1=2.6%. |
| **P1a/P1b** | Target distribution shapes at various k values (k=1..100). |
| **H3b** | Global 2025 income and wealth distribution by global percentile (for reference). |

I-series sheets **I8c**, **I8e**, **I9i** (post-GIT) are used as anchors for income.csv. I10 contains post-GIT inequality ratios (T10/B50 etc.), not threshold ratios, so I5 (pre-GIT threshold ratios) is reused as an approximation for the intermediate anchors.

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
2. **Other years**: for each year t ≠ 2025, compute a **scale factor** at 5 anchor rows as the ratio of the anchor's value in year t to its 2025 value. Log-interpolate between bracketing anchors; multiply by the P1e base value at each row.

   | Anchor row | Lower bound | Reference value | Series used |
   |---|---|---|---|
   | 1 | 0 | B10 avg = I9i × I8e / 0.1 | I9i (post-GIT avg), I8e (post-GIT B10 share) |
   | 10 | 9 | P10 threshold = I5e × I9i | I5e (pre-GIT P10 ratio), I9i |
   | 50 | 49 | P50 threshold = I5b × I9i | I5b (pre-GIT P50 ratio), I9i |
   | 99 | 98 | P99 threshold = I5c × I9i | I5c (pre-GIT P99 ratio), I9i |
   | 100–127 | 99–99.999 | T1 avg = I9i × I8c / 0.01 | I9i (post-GIT avg), I8c (post-GIT T1 share) |

   Rows 2–10 are log-interpolated (implicitly assuming a reciprocal income distribution) between anchors 1 and 10; rows 11–50 between 10 and 50; rows 51–99 between 50 and 99; rows 100–127 between 99 and the T1 anchor by their position in [99, 100].

   I9i is the post-GIT average from Bothe et al. and is used directly — no manual GIT computation is needed. The intermediate threshold anchors (rows 10, 50, 99) use pre-GIT I5 ratios scaled by the post-GIT average I9i, since no post-GIT threshold ratio series is available (I10 contains inequality ratios, not threshold ratios).

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
