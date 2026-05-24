# Global Justice Situator

A webpage that shows users how their income evolves under the **Sustainable Convergence (SC)** scenario from Chancel et al. (2026) and Bothe et al. (2026), part of the Global Justice Report.

## Language and tooling

- **Data processing**: R (readxl). Entry point: `scripts/prepare_data.R`
- **Webpage**: HTML / CSS / JavaScript (vanilla)
- **Local testing**: XAMPP on Windows 10

## Key concepts

| Term | Definition |
|------|------------|
| **gpercentile** | Within-country income (or wealth) percentile rank, 1–100 |
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
| **I5e** | SC scenario: P10 income threshold as ratio to average income (time series). |
| **I5b** | SC scenario: P50 income threshold as ratio to average income (time series). |
| **I5c** | SC scenario: P99 income threshold as ratio to average income (time series). |
| **I5d** | SC scenario: P99.9 threshold as ratio to average income. |
| **I5f** | SC scenario: P99.99 threshold as ratio to average income. |
| **I5g** | SC scenario: P99.999 threshold as ratio to average income. |
| **K1a/K2a** | SC scenario: T10 wealth share / average (time series). |
| **K1b/K2b** | B50 wealth share / average. |
| **K1c/K2c** | T1 wealth share / average. |
| **K1e/K2e** | B10 wealth share / average. |
| **K1h/K2h** | M40 wealth share / average. |
| **H1** | SC 2100 target distribution shape (k=5): B50=37.7%, M40=44.1%, T10=18.1%, T1=2.6%. |
| **P1a/P1b** | Target distribution shapes at various k values (k=1..100). |
| **H3b** | Global 2025 income and wealth distribution by global percentile (for reference). |

I-series sheets I8a–I9i correspond to the **PC (Productivist Convergence)** scenario and are not used here.

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

SC scenario posttax income (approximation of post-GIT), all 100 gpercentiles, all years 2020–2100.

| Column | Description |
|--------|-------------|
| `country` | Country/region code |
| `gpercentile` | Within-country income percentile rank, 1–100 |
| `income_2020` … `income_2100` | Income in EUR PPP 2025/year for each year |

**Methodology**: Starting from P1e 2025 distribution, each year is computed by anchor-based log-interpolation using 5 anchors per country:
- p1 anchor: B10 group average (I2i × I1e / 0.1)
- p10 anchor: I5e × I2i
- p50 anchor: I5b × I2i
- p99 anchor: I5c × I2i
- p100 anchor: T1 group average (I2i × I1c / 0.01)

Between anchors, the scale factor is geometrically interpolated (log-linear). This preserves the P1e starting-distribution shape while correctly tracking the SC scenario convergence at anchor percentiles.

**Note**: GIT lump-sum distributional adjustment within each country is not yet explicitly modelled; the I2i series (post-GIT country average) is used as the anchor level.

Dimensions: 6,600 rows × 83 columns.

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

Individual countries: AE, AR, AU, BD, BR, CA, CD, CI, CL, CN, CO, DE, DK, DZ, EG, ES, ET, FR, GB, ID, IN, IR, IT, JP, KE, KR, MA, ML, MM, MX, NE, NG, NL, NO, NZ, OA, OB, OC, OD, OE, OH, OI, OJ, PH, PK, QM, RU, RW, SA, SD, SE, TH, TR, TW, US, VN, ZA

Aggregate regions: East Asia, Europe, Latin America, Middle East North Africa, North America Oceania, Russia Central Asia, South & South-East Asia, Sub-Saharan Africa

Plus: World

## Running the data pipeline

```r
# in R, from the project root:
Rscript --vanilla scripts/prepare_data.R
```

Outputs all five CSV files to `data/`. Runtime: ~2 minutes.

## Local testing

Place the project folder under XAMPP's `htdocs/` and access via `http://localhost/global_justice/`.
