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
| **GIT** | Global Income Tax |
| **posttax income** | After domestic taxes and transfers; "income" in this project also subtract GIT (post-GIT) and country dividends |
| **EUR PPP 2025** | All monetary values in constant 2025 purchasing-power-parity euros |
| **k value** | Inequality parameter: k = T10/B10 ratio; k=5 is the SC 2100 target |

## Data sources

Fetched 2026-05-24:

- **Chancel et al. (2026)** — macro scenarios: `data/Chancel/Chanceletal2026Appendix_MacroScenarios.xlsx`
- **Bothe et al. (2026)** — within-country distributions: `data/Bothe/Botheetal2026AppendixDistribution.xlsx`
- **Fisher-Post & Gethin (2025)** — *Government Redistribution and Posttax Income Inequality in 174 Countries since 1980*, WID working paper. Country-year-gpercentile decomposition of taxes (personal income, corporate income, indirect, social contributions, property/wealth) and transfers (`gov_soc` cash social, `gov_edu` in-kind education, `gov_hea` in-kind health, `gov_oth` "Other Government Expenditure" = imputed collective consumption — see "What `gov_oth` actually is" section for why we use only `gov_soc`). 1980–2023, 173 countries × 127 gperc. Original Dropbox file is 255 MB; we keep only a slim 3.6 MB subset (year 2023, 20 used columns, 173 countries) at `data/FisherGethin/fisher-gethin-2023-slim.dta`. Source: <https://amory-gethin.fr/data.html>. To regenerate the slim file: re-download from Dropbox and run the slim block in `code_simulator/build_cash_income_2025.R`.
- **WID macro** — country-level `mprico_p999i` (corporate primary income) and `mnninc_p999i` (NNI), latest year ≤ 2023, 28 of 48 main Bothe countries. Used to compute the country-specific imputed-rent + retained-earnings fraction. Stored at `data/WID/wid-mprico-nni.csv`. Fetched via the [`wid` R package](https://cran.r-project.org/package=wid): `download_wid(indicators=c("mprico","mnninc"), areas=…, perc="p0p100")`.

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

### Bothe Stata source files (`data/Bothe/`)

Raw Stata datasets that feed the appendix workbooks above. Both cover the same 57 "core territories" (48 main countries + 9 residual WID regions: OA OB OC OD OE OH OI OJ QM) and the same 127 within-country percentile groups (the `gpercentile` scheme: 100 standard 1-pp groups p0p1…p99p100, plus 9 fine top-1% groups p99p99.1…p99.8p99.9, 9 within p99.9…p99.99, 9 within p99.99…p99.999, and p99.999p100).

`distribution_proj.dta` — historical + projected within-country distributions, 1980–2100, 875,919 rows (57 × 121 × 127), 23 columns:

| Var | Description |
|-----|-------------|
| `country` | ISO-2 code or residual region code |
| `year` | 1980–2100 |
| `percentile` | Group label, e.g. `p0p1`, `p99.999p100` |
| `p1`, `p2`, `diff` | Lower bound, upper bound (pp 0–100), and width of the group |
| `pop` | Total population |
| `p_pop` | Population in the group |
| `pop_share` | Group population ÷ world population |
| `aptinc` | Average pretax national income (EUR PPP 2025/adult) |
| `adiinc` | Average posttax disposable income (EUR PPP 2025/adult) |
| `ahweal` | Average household wealth (EUR PPP 2025/adult) |
| `sptinc`, `sdiinc`, `shweal` | Within-country shares of pretax, posttax, and wealth held by the group |
| `tptinc`, `tdiinc`, `thweal` | Group thresholds (pretax, posttax, wealth) |
| `tptinc_avg`, `tdiinc_avg`, `thweal_avg` | Country averages of the threshold series |
| `cshare`, `c_income_add` | Auxiliary capital-share and additive-income fields used in projection |

`distribution_simul.dta` — output of the Stata simulator (`dogjfsimulations.txt`), 2025–2100, 550,164 rows (57 × 76 × 127), 82 columns. Built by merging a subset of `distribution_proj.dta` (`p1 diff pop_share sdiinc shweal`) with macro series, gross-saving profiles, and the global wealth/income tax schedules, then iterating year-by-year. Note `diff` is rescaled to a fraction (0.00001–0.01) here, not pp.

| Group | Vars | Description |
|-------|------|-------------|
| Keys | `year country percentile p1 diff pop pop_share` | Same definitions as above (diff in fraction, not pp) |
| Distribution input | `sdiinc sgiinc shweal` | Share of net disposable income (carried in from `proj.dta`, used as posttax/pretransfer base), share of gross national disposable income net of simulated global income tax (= `gnip·diff/Σgnip·diff`; weight for saving aggregation, **not** post-GIT income), wealth share |
| Macro (country) | `gdp ndp nni w cfc kcfc gni` | Per-adult GDP, NDP, NNDI (net national disposable income, = `(gni−cfc)·gdp`), personal wealth, CFC (% GDP), CFC (% capital stock), GNDI (% GDP, excl. GJF transfers and foreign capital income) |
| Macro (world) | `gdpw ndpw ww` | World per-adult GDP, NDP, personal wealth |
| Savings | `sgdp spgdp rs` | Gross national saving rate, percentile saving rate, relative saving profile |
| Wealth-tax schedule | `bw1…bw12`, `tw1…tw12` | Global wealth-tax bracket thresholds (× world avg wealth) and effective rates |
| Income-tax schedule | `by1…by12`, `ty1…ty12` | Global income-tax bracket thresholds (× world avg NDP per adult) and effective rates |
| Wealth-tax simulation | `wp wpt wptx wt wtx` | Per-adult wealth at the percentile, wealth-tax payment per adult, taxpayer indicator, country aggregate tax revenue and aggregate taxpayer share |
| Income-tax simulation | `yp ypt yptx yt ytx` | Per-adult posttax income at the percentile (= `sdiinc·nni/diff`), income-tax payment per adult, taxpayer indicator, country aggregate revenue and aggregate taxpayer share |

**Does this include the full posttax post-GIT distribution by country-year? No, not directly.** The files do contain a full 127-gpercentile × 57-country × year distribution of *posttax disposable* income (`sdiinc` share or, equivalently, `yp` = `sdiinc · nni / diff` in EUR PPP 2025 per adult), but the country dividends lump-sum is **not** added to these series. The simulator computes the Global Wealth Tax revenue (`wt`) and Global Income Tax revenue (`yt`) per country but does not redistribute them per capita inside the .dta. Post-GIT averages by group are only published in the appendix workbook (sheets I9a–I9i, which the R pipeline already consumes); a full 127-percentile post-GIT distribution would have to be reconstructed by combining `sdiinc`, `nni`, the world tax revenues, and world population.

**Notes on the variables and on how the data is constructed**

- *Disposable = post-tax national income, and equals net income.* "Net" (vs. "gross") means after consumption of fixed capital (depreciation) — a national-accounts distinction. "Disposable" (vs. "pretax") means after personal taxes and transfers — a distributional distinction. In Bothe et al.'s data, both apply: `adiinc` is per-adult **post-tax national income**, computed as `sdiinc · nni / diff`, and `nni` is itself net of depreciation. So `adiinc` = posttax = "net" in both senses.
- *Disposable income includes imputed collective public expenditures, and sums to NNI by construction.* This follows the Piketty-Saez-Zucman / WID Distributional National Accounts (DINA) convention: post-tax national income equals pre-tax national income minus all taxes plus all forms of government spending — cash transfers, in-kind transfers (notably **health and education**, allocated to beneficiaries by age and household composition), **and collective consumption expenditure** (defence, justice, public administration, infrastructure, …) imputed back to individuals, typically equally per capita or pro-rata to private consumption. By definition this sums to NNI. See Piketty, Saez & Zucman (2018), "Distributional National Accounts: Methods and Estimates for the United States", QJE 133(2): 553–609, esp. Section II.B and p. 567, and the WID DINA Guidelines (Blanchet, Chancel, Flores & Morgan, 2021). We verified this empirically in `distribution_proj.dta`: `sdiinc` sums to 1 within every (country, year), and `Σ_g (adiinc_g · diff_g)` equals `Σ_g (aptinc_g · diff_g)` to machine precision in every cell tested — i.e., aggregate disposable income equals aggregate pretax income equals NNI per adult. This differs from the narrower SNA "household disposable income" concept which excludes in-kind individual transfers and collective consumption.
- *The income distribution does not feed back from wealth-tax effects.* `sdiinc` is exogenous: it comes from the SC scenario projection upstream of the simulator and is **never** updated inside `dogjfsimulations.txt`. Only `shweal` (wealth share) is recomputed each year, with the wealth tax `wpt` directly netted out of the wealth-accumulation equation. So if the Global Wealth Tax depletes top wealth in year *t-1*, year *t*'s `shweal` reflects that, but year *t*'s per-percentile income `yp = sdiinc · nni / diff` does not — the corresponding reduction in capital income at the top is not modelled. The SC scenario implicitly assumes the income-share convergence path is achieved by other policy levers; the simulator only models wealth dynamics conditional on that fixed income trajectory.
- *`sdiinc` vs. `sgiinc`.* `sdiinc` is the share of (net) disposable income — input from the WID/Bothe upstream pipeline, never recomputed by the simulator. `sgiinc` is the share of *gross* (i.e., pre-depreciation) national disposable income, net of the simulated global income tax: `gnip = (sdiinc·nni + kcfc·shweal·w − ypt·diff) / diff` then `sgiinc = gnip·diff / Σ(gnip·diff)`. It is used as a weight for cross-percentile saving aggregation in the wealth-dynamics loop, **not** as a post-GIT household income measure. The simulated Global Wealth Tax `wpt` is **not** in `gnip`: it is deducted from wealth directly in the next-period wealth update, not from the income flow.
- *How the two files relate.* `distribution_proj.dta` is built upstream (WID historical microdata + Bothe et al. SC-scenario projections + macro integration in EUR PPP 2025). `distribution_simul.dta` is built **from** `distribution_proj.dta` by `dogjfsimulations.txt`: subset to the 57 core territories, keep only `country year percentile p1 diff pop_share sdiinc shweal` for years ≥ 2025, merge in macro/saving/tax tables, rescale `diff` from percentage points to a fraction (`diff = diff/100`), initialise the new variables (`yp ypt wp wpt yt wt sgiinc gnip …` = 0), then iterate the year-by-year wealth- and income-tax simulation for 2026–2100. So `sdiinc` is identical between the two files on the overlap — the simulator never touches it. For year 2025, `yp`/`ypt`/`wpt`/`yt`/`wt` remain at their initial values (0 or the wealth seed), because the simulation loop starts at `t=2026`.

## Generated data files

### `data/income.csv` (new — from `distribution_simul.dta` + sheet `E3bp`)

Posttax post global redistribution per-adult income (EUR PPP 2025/year), 57 core territories × 127 within-country gpercentiles × years 2025–2100. Built directly from the Bothe Stata simulator output and the published country-dividend series.

Per (country, year, percentile):

```
income = sdiinc · nni / diff  −  ypt  +  dividend[year]
        └─ per-adult posttax ┘    └ GIT ┘   └ Global Justice Fund ─┘
           disposable income      tax       country dividend
                                             (E3bp; equal per-capita worldwide)
```

The **Global Wealth Tax `wpt` is not subtracted from income** — it is a stock tax on wealth, not a flow tax on income, and the simulator itself routes `wpt` into the wealth equation, not the income equation. Subtracting it produced ~7,000 negative-income cells at top percentiles (where annual wealth-tax liability exceeded annual income). Its revenue is fed back to households through `dividend[year]`.

The dividend is read from sheet `E3bp` ("Global Justice Fund Expenses: Country Dividends, 2025 Euros PPP") of `Botheetal2026AppendixMacro.xlsx`. Values are uniform across countries by construction (equal-per-capita worldwide). It is funded by total GJF revenue (sheet `E2a` = Global Wealth Tax + Global Income Tax + World Sovereign Fund investment income) minus reinvestment back into the WSF (sheet `E3c`), so it captures **both** the year's tax flows **and** the investment return on the accumulated wealth-tax principal.

For year 2025 the simulation loop has not yet run, so `ypt = 0` and `dividend[2025] = 0`, and the row reduces to `sdiinc · nni / diff` (pre-tax-and-transfer disposable income).

**Why does the pop-weighted world average top out around 52 k EUR PPP in 2100, not the 60 k often quoted for SC?** The paper's ~60 k is *world GDP per adult* (sheet `A0p`, variable `gdpw` in the .dta: exactly 60,000 in 2100). DINA disposable income, by construction, aggregates to *Net* National Disposable Income per adult — i.e., NDP per adult after netting out consumption of fixed capital. In the .dta this is `ndpw ≈ 50,640` in 2100, which gives a pop-weighted world average of ~51,958 in `income.csv` (`= ndpw + dividend`) and ~53,146 in `income_full_revenues.csv` (`= ndpw + total_revenue`). The ~16 % gap from 60 k is depreciation; it never reaches households as cash income because it replaces worn-out capital.

### `data/income_full_revenues.csv` (new — counter-factual: full GJF revenues distributed)

Same structure as `data/income.csv` (57 countries × 127 gpercentiles × years 2025–2100), but the per-adult addback is the **full Global Justice Fund revenue** (sheet `E2a` = Global Wealth Tax + Global Income Tax + WSF investment income) rather than the post-reinvestment country dividend (`E3bp`):

```
income = sdiinc · nni / diff  −  ypt  +  total_revenue[year]
```

`total_revenue[year]` is in EUR PPP 2025/adult, derived as

```
total_revenue[year] = E3bp[year] · (E2aw_world[year] / E3bw_world[year])
```

`E2aw` (% world GDP MER, total fund revenues) and `E3bw` (% world GDP MER, dividends) share the same denominator, so their ratio is unit-free and the conversion factor falls out. For years where `E3bw = 0` (2025–2026: the GJF is starting up, all revenue is reinvested), we fall back to the `(yt + wt)` world-population-weighted average from `distribution_simul.dta` — current-year tax revenue per adult, with no WSF investment income yet.

The ratio total_revenue / dividend is 2.4 in 2030, 1.7 in 2050, 1.9 in 2100 — about half of total revenue is reinvested into the WSF in steady state, the other half paid out as dividends. This file represents the counter-factual where the entire fund revenue (current taxes + WSF returns) is distributed immediately rather than partly reinvested.

| Column | Description |
|--------|-------------|
| `country` | ISO-2 or residual region code (57 values, no "World") |
| `gpercentile` | Lower bound (%) of the group: 0, 1, …, 98, 99, 99.1, …, 99.999 |
| `income_2025` … `income_2100` | Post-global redistribution per-adult income, EUR PPP 2025/year |

Dimensions: 57 × 127 = 7,239 rows × 78 columns.

### Cash-income family (situator inputs)

The situator's web page (`code_simulator/index.html`) consumes four files in `code_simulator/data/` (rounded copies of the originals in `data/`):

| File | Shape | Used for |
|---|---|---|
| `cash_income_2025.csv` | 7,239 rows × 3 cols (country, gpercentile, cash_income_2025) | Finding the user's country gpercentile from their stated 2025 income |
| `cash_income.csv` | 7,238 rows × 78 cols (country, gpercentile, income_2025…income_2100) | Evolution chart — the time series at the user's country gpercentile |
| `cash_income_world.csv` | 100 rows × 7 cols (gpercentile, income_2025, _2030, _2035, _2050, _2080, _2100) | Distribution chart — world cash income distribution |
| `imputed_income_2025.csv` | 7,239 rows × 3 cols (country, gpercentile, imputed_income_2025) | Counterfactual: cash income + the imputed wedge (retained earnings + imputed rent) added back at country-specific rate |

`cash_income.csv` is derived as `cash_income_2025[c,p] × (income_post_GIT[c,p,t] / income_post_GIT[c,p,2025])` — i.e., it scales each percentile's 2025 cash income by the post-GIT trajectory from Bothe's SC scenario (via `income_full_revenues.csv`). This flows Bothe's inequality dynamics (k=5 convergence by 2100) through to cash income at each percentile while preserving the FG-derived fiscal-incidence wedge in 2025. The 2025 column of `cash_income.csv` matches `cash_income_2025.csv` exactly by construction.

`cash_income_world.csv` is built by pooling all (country, gpercentile) cells in `cash_income.csv` weighted by `width(gpercentile) × population(country, year)`, sorting by income, and partitioning into 100 equal-population bins. The income at each global percentile is the population-weighted mean within that bin.

**About using FG's `a_pdi` to simplify** (question raised during development): FG publishes `a_pdi` (Posttax Disposable Income), and one might hope to use it as `pretax − taxes + cash_transfers` directly. But empirically `a_pdi` includes part of `gov_oth` (the imputed collective-consumption residual): for FR p50, `a_pdi = €28,778` vs computed `a_pre − all taxes + cash transfers = €22,723` (off by €6,055). Using `a_pdi` directly would inflate cash income by 20–30 % per country. We therefore keep the decomposed formula `a_pre − tax_dir_pit − tax_dir_wea − tax_cit − tax_soc − tax_ind + gov_soc − imputed_frac · a_pre_cap + cap_share · CFC`. A modest simplification would be to replace the 5 individual tax variables with FG's `tax_tot_soc` aggregate (not currently in the slim file).

**Two future-projection methods (`cash_income.csv` and `cash_income_sectors.csv`):**

| Method | File | Approach |
|---|---|---|
| **Constant cash/post-GIT ratio** | `data/cash_income.csv` | `cash[c,p,t] = cash_2025[c,p] × (income_post_GIT[c,p,t] / income_post_GIT[c,p,2025])`. Captures NNI growth and SC inequality flattening via Bothe's published post-GIT trajectory. Assumes the FG fiscal-incidence wedge at each percentile is stable. 57 countries × 127 gperc × 76 years (2025–2100). |
| **Sector-based** (posttax + flat extra-HE tax) | `data/cash_income_sectors.csv` | Starts from the **constant-ratio cash income** (i.e., the posttax cash trajectory in `cash_income.csv`) and subtracts a **flat supplementary tax** that funds the country's incremental health+education spending above the 2023 baseline: `cash_sectors[c,p,t] = cash_const[c,p,t] × (1 − flat_tax_rate[c,t])`. The flat tax rate per country-year is `add_he_share[c,t] / cash_NNI_ratio[c]`, where `add_he_share[c,t] = max(0, (G2b+G2c)[c,t] − (G2b+G2c)[c,2023])` is the additional health+edu spending share of GNE, and dividing by `cash_NNI_ratio[c]` (~0.78–0.82) grosses up the rate so revenue collected on the cash-income base equals the spending increase. By construction `cash_sectors[c,p,2025] = cash_const[c,p,2025]` exactly. By starting from posttax (not pretax) we avoid the previous bug where applying 2023 tax rates to Bothe's 2100 flattened pretax produced negative incomes at the top — there are now **0 negative cells**. |

**`gov_factor` uncapped — highest projected values (2100):**

`gov_factor[c, t] = (G2b + G2c)[c, t] / (G2b + G2c)[c, 2023]` (no cap). Bothe SC has developing economies catching up to advanced-economy health+edu shares of GNE, so the factor is much larger for low-baseline countries:

| Country | gov_factor 2050 | gov_factor 2100 | he 2023 (% GNE) | add_he 2100 (% GNE) | flat_tax_rate 2100 |
|---|---:|---:|---:|---:|---:|
| SD | 12.11 | **16.88** | 2.3 % | 35.7 % | 37.9 % |
| ET | 5.45 | 7.35 | 5.2 % | 32.8 % | 38.1 % |
| PK | 5.14 | 6.92 | 5.5 % | 32.5 % | 41.6 % |
| ID | 4.53 | 6.04 | 6.3 % | 31.7 % | 30.9 % |
| CD | 4.26 | 5.66 | 6.7 % | 31.3 % | 35.9 % |
| TR | 3.64 | 4.78 | 8.0 % | 30.0 % | 38.8 % |

Across the 57 territories: median `gov_factor` 2100 = 3.45, mean = 3.85, max = 16.88 (Sudan).

For advanced economies the factor is smaller (FR ≈ 2.3, DE ≈ 2.1, SE ≈ 1.8) but `flat_tax_rate` is still meaningful because their baseline `he_2023` is higher (FR ≈ 13 % GNE → +17 pp → ~22 % flat tax on cash). The interpretation: under SC, by 2100 every country devotes ~35–40 % of GNE to health+education, and the implied additional financing significantly compresses cash income.

The two methods diverge most by 2100 for high-`gov_factor` countries. At p50 in 2100:

| Country | constant | sector (new) | ratio |
|---|---:|---:|---:|
| FR | 30,455 | 20,854 | 0.68 |
| DE | 31,006 | 21,262 | 0.69 |
| SE | 29,159 | 19,747 | 0.68 |
| NO | 33,045 | 20,957 | 0.63 |
| IT | 25,554 | 16,301 | 0.64 |
| US | 32,064 | 26,578 | 0.83 |
| CN | 40,324 | 27,121 | 0.67 |
| BR | 35,579 | 27,697 | 0.78 |

**Caveats (sector method):**
- **0 negative cells** (vs ~1.7 % in v1) — the new posttax-base formulation eliminates the top-tail negative issue entirely.
- `gov_factor` uncapped — values can exceed 16× for developing-country baselines that the SC scenario projects to converge by 2100. This is a strong Bothe scenario assumption (Wagner's law extrapolated for 75 years across the global South); the resulting `flat_tax_rate` of 30–42 % for those countries reflects implausible-but-scenario-consistent fiscal expansion.
- `cash_NNI_ratio[c]` computed once from the 2025 country averages; assumed stable over 2025–2100 (rough approximation).
- 9 residual WID regions: median `add_he` and `cash_NNI_ratio` used as fallbacks (Bothe `G2b`/`G2c` don't cover residual codes directly).
- Carry-forward applied to G-sheet values for trailing-NA years.

### Per-country distributions — Italy extracts

For convenience, every per-country distribution CSV has an `_IT.csv` companion containing only Italy rows: `cash_income_2025_IT.csv`, `cash_income_IT.csv`, `cash_income_sectors_IT.csv`, `imputed_income_2025_IT.csv`, `income_full_revenues_IT.csv`, `income_legacy_IT.csv`, `income_pre_git_legacy_IT.csv`, `wealth_legacy_IT.csv`. World-level files (`cash_income_world`, `income_world_legacy`, `wealth_world_legacy`) are unchanged.

### `data/cash_income_2025.csv` (new — cash purchasing-power after all taxes, 2025 only)

Per-capita income approximating "cash purchasing power after all taxes" — the DINA-style concept underlying what a respondent would mean by their after-tax income, with VAT subtracted (see "On VAT" below).

**Formula** (applied per country c × gpercentile g):

```
cash_income[c,g] = pretax_NI[c,g]
                  − (tax_dir_pit + tax_dir_wea + tax_cit)[c,g]   ← direct taxes (personal income, property/wealth, corporate)
                  − tax_soc[c,g]                                  ← social contributions (employee + employer)
                  − tax_ind[c,g]                                  ← indirect taxes (VAT, excise) — see note on VAT
                  + gov_soc[c,g]                                  ← monetary cash transfers (pensions, UI, family benefits)
                  − imputed_frac[c] · a_pre_cap[c,g]              ← imputed rent + retained earnings, country-specific (see below)
                  + (a_pre_cap[c,g] / mean_cap[c]) · CFC[c]       ← CFC addback (allocated proportional to capital income share)
                  − ypt[c,g]                                      ← Global Income Tax (= 0 in 2025; GJF starts in 2026)
```

All `tax_*`, `gov_*`, `a_pre`, `a_pre_cap` are from Fisher-Post & Gethin 2023 (latest available year), normalized per-capita. CFC and 2025 NNI per-capita scale come from Bothe's `distribution_simul.dta`. The 2023→2025 step computes each FG component as a dimensionless share of country NNI in 2023 LCU, then multiplies by Bothe's 2025 NNI per-capita (EUR PPP 2025) — sidestepping LCU→EUR-PPP conversion and assuming the cash-to-NNI ratio is stable over the 2-year gap.

**FG income variables (per-capita LCU at the gpercentile):**

| Variable | Meaning |
|---|---|
| `a_pre` | Pretax national income (DINA `ptinc`): labour + capital, before income tax, after employee social contributions to pensions/UI, including pension and UI benefits received. Sums to NNI across percentiles by construction. |
| `a_pre_lab` | **Labour-income** component of `a_pre`: wages and salaries (gross of employer social contributions), self-employment labour share, government wages, pension and UI benefits. |
| `a_pre_cap` | **Capital-income** component of `a_pre`: dividends, interest, rents received, **imputed rent** on owner-occupied housing, **retained corporate earnings** attributed to shareholders, the capital share of mixed (self-employment) income, imputed pension/insurance investment income, and net public-sector property income allocated to households. Identity: `a_pre = a_pre_lab + a_pre_cap` (verified to machine precision). Country-aggregate `a_pre_cap` is roughly 20–35 % of NNI; at the percentile level the capital share rises sharply with income (FR 2023: ~10 % of pretax at p50, ~30 % at p99, ~95 % at p127). |
| `a_pre_cap_crp` | **Stock** of corporate-equity wealth per capita at the gpercentile (not a flow): used in the WID Comparator's stockrate × stock-holdings imputation. Magnitude is ~10–100× annual `a_pre`. We don't use it directly because our `imputed_frac[c]` is applied to the flow `a_pre_cap`. |

**Dimensions:** 57 territories (48 main + 9 residual WID regions) × 127 gpercentiles = 7,239 rows × 3 columns: `country`, `gpercentile`, `cash_income_2025` (EUR PPP 2025/year, per capita).

#### Could we have used Bothe alone?

No. Bothe's `.dta` files contain only the *aggregate* distribution (`sptinc`, `sdiinc`) and country macro (`nni`, `cfc`, `gdp`); they do not decompose income into the tax / transfer / capital-income sub-components needed for this formula. We use Bothe for what it provides — the 2025 NNI scale, country-level CFC, the 57-territory list — and Fisher-Post & Gethin for the fiscal decomposition at the percentile level (`tax_*`, `gov_*`, `a_pre_lab`, `a_pre_cap`).

#### Residual WID regions

The 9 Bothe residual regions (OA OB OC OD OE OH OI OJ QM) are not country codes in FG, but their member countries are. For each residual region we take the FG-covered subset of its WID region (e.g. OC = Western Europe minus the 9 main territories, intersected with FG coverage), compute the dimensionless cash factor per gpercentile for each member country, population-weight to a regional factor, and then scale by Bothe's regional NNI. FG coverage of the residual regions: QM, OE, OJ, OA, OI 100 %; OC 56 %, OD 53 %, OB 50 %; OH only 1 of 16 (Papua New Guinea, but PG dominates the region's population so the proxy is reasonable).

#### On VAT — subtract it

DINA explicitly subtracts indirect taxes at the individual-posttax step (Piketty, Saez & Zucman 2018 QJE §II.B, p. 562: *"we deduct all taxes and add government transfers and public goods spending"*; Appendix Table B6 itemises consumption taxes). At the aggregate this is offset by adding collective consumption back; at the individual level, since consumption falls as a share of income with income, the VAT subtraction is mechanically regressive — and that's the point. **Yes, subtract.**

This *does* diverge from naïve survey self-report (where respondents don't subtract VAT) and from SNA "household disposable income" (which leaves VAT embedded in market-price purchases). Your formula is the DINA / cash-purchasing-power concept; it is internally consistent to subtract.

#### What `gov_oth` actually is (and why we exclude it)

FG's transfer block has four series: `gov_soc`, `gov_edu`, `gov_hea`, `gov_oth`. The labels are sparse, and we initially treated `gov_oth` as a cash "other transfers" component (along with `gov_soc`). After inspecting it, **`gov_oth` is the imputed-collective-consumption residual**, not cash. Evidence:

1. **Magnitude.** Country averages of `gov_oth` are 8–20 % of NNI (FR 20 %, CN 20 %, IN 20 %, RU 20 %, US 12.5 %, DE 19 %, SE 17 %, BR 9 %). This matches the size of total government collective consumption + the residual needed to make DINA posttax balance to NNI.
2. **Per-percentile pattern.** `gov_oth` rises strongly with pretax income (FR `gov_oth`: €1,854 at p1 → €21,578 at p99 → €3.3M at p127), with `gov_oth / a_pre ≈ 10–17 %` flat across all upper percentiles. That's the signature of allocation proportional to consumption (or pretax income), not means-tested cash transfers.
3. **FG paper Appendix B.6** is titled *"Results With Other Government Expenditure Distributed as a Lump Sum"* — so FG's own naming confirms `gov_oth` is "Other Government Expenditure", i.e., the broad collective-consumption category DINA allocates back to individuals.

By contrast, `gov_soc` (the variable we *do* include) is a true cash transfer: it's a step-function with the same flat value across the bottom decile then dropping to ≈ €0 at the top (FR: €8,472 across p1–p10, then falls steeply), consistent with means-tested benefits like unemployment insurance, pensions, family allowances, and social assistance.

Including `gov_oth` would double-count the imputed-collective-consumption portion that the user's formula explicitly excludes (alongside imputed rent and retained earnings). So we drop it from the transfer term.

#### Country-specific imputed fraction (replaces the flat 0.33)

`a_pre_cap` includes imputed rent and retained earnings (DINA convention). Neither is published per-percentile in FG, so we approximate their combined value as `imputed_frac[c] × a_pre_cap[c,g]`, with `imputed_frac[c]` computed country-by-country from WID macro data, following the WID Income & Wealth Comparator methodology (sheet `mprico_p999i` divided by `mnninc_p999i`):

```
imputed_frac[c] = (RETENTION_RATE · mprico[c]/NNI[c] + IMPUTED_RENT_SHARE_NNI) / capital_share_FG[c]
```

with `RETENTION_RATE = 0.5` (corporate dividend payout ratio ≈ 50 %, so retained earnings ≈ half of corporate primary income) and `IMPUTED_RENT_SHARE_NNI = 0.04` (PSZ 2018, GGLP 2018 average for owner-occupied imputed rent), capped to [0.10, 0.60]. `capital_share_FG[c]` is the FG country aggregate `Σ(a_pre_cap × weight) / Σ(a_pre × weight)`.

Data: `data/WID/wid-mprico-nni.csv` (28 of 48 main countries; remainder use the median `mprico/NNI = 0.137` as fallback). Fetched via the WID R package (`install.packages("wid")`, `download_wid(indicators=c("mprico","mnninc"), …)`); see `code_simulator/build_cash_income_2025.R` for the regeneration step.

Resulting `imputed_frac` across the 28 WID-covered countries:

| | Min | 1st Qu | Median | Mean | 3rd Qu | Max |
|---|---:|---:|---:|---:|---:|---:|
| `imputed_frac[c]` | 0.12 (MX, CO) | 0.28 | 0.31 | 0.35 | 0.39 | 0.60 (NO, capped) |

Sources for the 4 % imputed-rent and 50 % retention defaults:

| Source | Country / scope | Imputed rent / NNI | Retention rate (1 − payout) |
|---|---|---:|---:|
| Piketty, Saez, Zucman 2018, QJE, Tab. II | US, 1980–2014 avg | 3.5 % | ~50 % |
| Garbinti, Goupille-Lebret, Piketty 2018 | FR, 1970–2014 | 3.6 % | ~50 % |
| Blanchet, Chancel, Gethin 2022 | Europe pooled | 3.5 % | ~50 % |
| Bachas, Fisher-Post, Jensen, Zucman 2024 | World | ~3 % | ~50 % |

#### Sanity check

Pop-weighted country averages give cash/NNI ratios between 0.65 and 0.99 (median 0.81, IQR 0.75–0.86). Median cash income (p50): France ~€20,074/yr, US ~€23,454/yr, Germany ~€21,531/yr, UK ~€19,273/yr, Norway ~€34,627/yr, Sweden ~€23,412/yr, China ~€9,211/yr, India ~€2,924/yr, Brazil ~€4,443/yr, Mexico ~€4,954/yr, South Africa ~€2,375/yr, Japan ~€17,838/yr. These line up much better with typical survey-reported take-home pay than the prior numbers (which included gov_oth as if it were cash). Country-specific `imputed_frac` accounts for the rest of the cross-country spread: NO (mprico/NNI 0.34, capped at 0.60) and CN (0.55) subtract more capital income; MX (0.12) and CO (0.14) subtract less, matching their large informal sectors.

#### Why factor approach (vs rate approach)

Both approaches were tried; the factor approach is in production. The trade-off:

| | Factor approach (in use) | Rate approach (rejected) |
|---|---|---|
| **Definition** | `factor[c,g] = (a_pre − taxes + transfers − imputed)[c,g] / mean_FG[c]` then `cash = factor · NNI_Bothe[c,2025]` | `rate[c,g] = tax[c,g] / a_pre[c,g]`, then `cash = aptinc_Bothe[c,g,2025] · (1 − rates)` |
| **Distribution source** | FG (each percentile's share comes from FG) | Bothe (each percentile's pretax comes from Bothe, then scaled by FG-derived rates) |
| **Country aggregate** | Matches Bothe NNI 2025 by construction (within the dimensionless wedge) | Matches Bothe NNI 2025 by construction (= Bothe NNI × `(1 − country-avg rate)`) |
| **Bottom of distribution** | ✓ correct: at p1–p5 in FR `a_pre = 0` but `gov_soc ≈ €8,472`. Factor captures this: cash income at FR p1 ≈ €8,500 — sensible, since these people live entirely on means-tested benefits. | ✗ broken: with `a_pre = 0`, every rate (`tax/a_pre`, `gov_soc/a_pre`) divides by zero. Setting these to 0 erases both taxes AND transfers, leaving cash ≈ `aptinc_Bothe × 1`, which is ~€14/year at FR p1 — wrong. |
| **Top of distribution** | Uses FG's (lower) estimates for top 0.001 %. For e.g. IN `p127`, FG ≈ 35 % of Bothe's value. | Would use Bothe's (higher) estimates. Cleaner at the top. |
| **Distribution-shape match to Bothe** | Inherits FG shape — matches Bothe exactly for US, within 0.1–1 % at most percentiles, 30–80 % discrepancy at extreme tails for some emerging economies. | Matches Bothe shape exactly by construction. |

We pick the factor approach because **at the bottom of the distribution, transfers exceed pretax income, and the rate approach loses that information**. The cost is a less-faithful Bothe distribution shape at the extreme top — for the project's "median respondent" framing this is acceptable; for top-tail-focused analysis, a hybrid (rate approach above some pretax threshold, factor approach below) would be the way to go.

#### Verification — FG aggregates vs Bothe aggregates

*Country aggregate (NNI per capita).* By construction in the factor approach, the cash-income aggregate equals `Bothe NNI 2025 × (1 − FG-derived net wedge)`, so the country pretax aggregate matches Bothe's NNI exactly. We use Bothe's `nni` for the EUR-PPP-2025 scale; FG's `mean` (in 2023 LCU) cancels out through the dimensionless factor.

*Distribution shape per percentile.* We compared the FG-implied income share `a_pre × width / mean` against Bothe's `sptinc` at every percentile, for all 48 main countries in 2023:

- **US: exact match.** FG and Bothe use the same WID DINA microdata; deviation < 10⁻⁴ at every percentile.
- **Middle percentiles (p10–p99) of most countries: match within 0–6 %.** Typical maximum-absolute-deviation across 127 percentiles is 0.001–0.01 (i.e., 0.1–1 % of the income share).
- **Extreme tails diverge.** Particularly the top-0.001 % (`p127`): for many emerging economies FG attributes near-zero income there while Bothe's projection attributes substantially more (`p127 rel_dev ≈ −0.97` for AR/BR/CL/CO/MX/ID/NG/ZA). For the bottom 5 % of advanced economies (e.g. FR `p1`–`p5`), FG records `a_pre = 0` because those people have zero pretax income (rely entirely on transfers).

#### Comparison with the WID Income & Wealth Comparator methodology

WID's [Income & Wealth Comparator](https://github.com/world-inequality-database/wid-income-wealth-comparator) is the canonical "translate DINA to what a user would state" tool. Reading its methodology document (`methodology-version-2026.docx`) clarifies several assumptions and points to refinements for the 0.33 imputed-rent + retained-earnings parameter. Key differences:

1. **Direction of the adjustment.** WID starts from pretax national income (ptinc) and *asks the user* to add their own imputed rent and stock-attributed retained earnings, so the user's stated cash income is "completed" up to the DINA pretax concept. Our approach goes the *other* direction — subtracts these from DINA to get a cash distribution without asking. The two are conceptually equivalent and give the same percentile ranking; ours is what you compute when you want a "cash distribution" without per-user queries.

2. **Retained earnings: country-specific stockrate.** WID computes a country-specific retention rate from corporate primary income vs corporate equity. We *implemented* a parallel approach: fetch `mprico_p999i` and `mnninc_p999i` from WID, then `imputed_frac[c] = (0.5 · mprico/NNI + 0.04) / capital_share_FG[c]`. This replaces the previous flat 0.33 with country-specific values (range 0.12–0.60, median 0.31 across 28 countries with WID data; uniform 0.137 median fallback for the other 20). See "Country-specific imputed fraction" section above for details.

3. **Imputed rent.** WID asks the user directly. For a generic distribution, the WID convention has imputed rent ≈ 3–4 % of NNI worldwide (PSZ 2018, GGLP 2018), allocated proportional to housing wealth. We bundle it into `imputed_frac[c]` as a uniform `IMPUTED_RENT_SHARE_NNI = 0.04` additive term (then divided by the country's capital share). A country-specific refinement would fetch WID housing-wealth data, but the 4 % default is small enough that this is a minor effect.

4. **Production taxes (VAT).** WID only adjusts when comparing *across* countries — within a country, VAT affects everyone the same and doesn't change percentile rank. Our formula subtracts VAT always (because we're producing an absolute cash-income series, not a percentile-rank tool, and cross-country comparability matters). The mechanism is identical: WID's `coef_factorprice = 1 − yptxgo / ynninc` (production taxes ÷ NNI) is applied at the country level and uniformly across percentiles; our FG-based subtraction is at the percentile level (using FG's regressivity assumption that indirect taxes scale with consumption). The country-aggregate is the same.

5. **Pretax already excludes employee social contributions.** WID notes: "Pre-tax national income is income people receive **after paying social contributions** but before paying income tax." So when our formula subtracts `tax_soc`, we are subtracting *additional* social contributions beyond what's already netted out of pretax — primarily the employer share. (This is consistent with our intent: a user states their net wage, which excludes employer contributions.)

6. **Statistical unit.** WID uses adult-individual with equal within-household split; we follow the same convention (both Bothe and FG report per-capita on this basis).

7. **CFC / depreciation.** WID's DINA aggregates are **net** of depreciation: NNI = GNI − CFC, and distributional series (`ptinc`, `diinc`, FG's `a_pre`) all sum to NNI by construction. So depreciation is already removed at every percentile. The WID Comparator preserves this — it does **not** add CFC back at the individual level; users compare against a net-NNI distribution. **Our formula does add CFC back**, allocating it proportional to capital-income share (`cap_share[g] × country CFC`). This is an intentional divergence: a respondent answering "what's your income?" does not subtract a share of national capital depreciation from their answer (CFC is a national-accounts construct, not a household cash flow). The addback raises cash income by ~3–5 % of NNI for median percentiles and ~10–16 % for top percentiles where the capital share is high. To match WID's net-DINA convention exactly, drop the CFC term from the formula.

**Implementation status.** Items 2, 4 (production-tax framing), 5 (pretax framing), 6 (per-adult unit) are aligned with WID. Item 3 (imputed rent) uses a uniform 4 % approximation — country-specific refinement is possible but small in magnitude. Items 1 (direction of adjustment) and 7 (CFC addback) are intentionally reversed/different because we produce a *distribution* targeting naïve self-report (no per-user query, gross-of-depreciation framing).

#### Caveats

1. **Corporate income tax** is included in direct taxes (DINA attributes corp tax to shareholders). To follow a narrower "tax on me personally" reading, drop `tax_cit` from the subtraction.
2. **In-kind transfers** (`gov_edu`, `gov_hea`) and **imputed collective public consumption** (defence, infrastructure, …) are *not* added back — by design of this concept.
3. **Imputed pension/insurance investment income** (~2–4 % of NNI) stays in pretax. Your formula did not mention it; subtract another ~0.10 × `a_pre_cap` for a strict "cash only" version.
4. **Unrealized capital gains** are not in DINA pretax income by convention, so the "− unrealized capital gains" step in your formula was a no-op (and is omitted).
5. **2023 → 2025 scaling** assumes the cash/NNI structure is stable. To refine, project each component by its 2018–2023 trend.

### Legacy files (xlsx-based, parametric splice methodology)

The files below are produced by the earlier pipeline that fits a Type II Pareto / exponential splice to the post-GIT bracket means in the appendix workbook (sheets I9a–I9i). They are kept for comparison and as fallbacks where the .dta-based approach is not yet implemented (wealth, world distribution, pre-GIT thresholds).

#### `data/income_pre_git_legacy.csv`

Posttax income thresholds at 6 key percentiles, **before** Global Income Tax, for each country and each year 2020–2100.

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

#### `data/income_legacy.csv`

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

#### `data/income_world_legacy.csv`

World income distribution under SC at 6 target years (2025, 2030, 2035, 2050, 2080, 2100).

| Column | Description |
|--------|-------------|
| `gpercentile` | Global income percentile rank, 1–100 |
| `income_2025` … `income_2100` | Income in EUR PPP 2025/year |

Dimensions: 100 rows × 7 columns. Used for the distribution chart on the webpage.

#### `data/wealth_legacy.csv`

SC scenario wealth, all 100 gpercentiles, target years 2025–2100.

| Column | Description |
|--------|-------------|
| `country` | Country/region code |
| `gpercentile` | Within-country wealth percentile rank, 1–100 |
| `wealth_2025` … `wealth_2100` | Wealth in EUR PPP 2025 |

**Methodology**: 5-group scaling (B10, p10-50, M40, T10-T1, T1) using K2 group average series, starting from K2 group averages at 2025.

Dimensions: 6,600 rows × 8 columns.

#### `data/wealth_world_legacy.csv`

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

Outputs the new `income.csv` plus the five `*_legacy.csv` files to `data/`. Runtime: ~2 minutes (legacy parametric fit) + a few seconds (.dta-based post-GIT computation).

## Local testing

Place the project folder under XAMPP's `htdocs/` and access via `http://localhost/global_justice/`.


## Income concepts and assumptions

### SNA

The system of national accounts distributes production between sectors (households, corporations, government) using different income accounts, each of them summing to GNI.
Primary income:
- households: compensation of employees + property income (incl. imputed rents & pension funds earning)
- government: taxes on production
- corporations: retained earnings
Secondary (= disposable) income: (the closest to cash income people think of)
- households: HH primary income - direct taxes + govt monetary transfers
- government: taxes on production + direct taxes - govt monetary transfers
- corporations: retained earnings
Adjusted disposable income:
- households: household disposable income + in-kind gov services (health, educ)
- government: collective expenditures (police, roads...)
- corporations: retained earnings

In other words, 
gross household primary income = GNI - taxes on production - retained earnings
gross household disposable income = GNI - all taxes + govt monetary transfers - retained earnings

Note that we also have Gross Value Added (GVA) = household primary income + retained earnings
GDP = GVA + taxes on production
GNI = GDP + net foreign earnings/transfers

Note that GDP is defined at market prices, i.e. inclusive of taxes on production (~VAT). It could be defined at factor prices, i.e. equal to GVA (in that case the VAT would be considered as paid by consumers "at 20% rate" instead of paid by firms so that it's "16.6% of GDP"). 
Market pricess take the point of view of producers' expenditures (wages+profits+VAT) or household income (primary + in-kind/collective from govt not paid by direct taxes, or secondary + in-kind/collective from govt), while basic takes the point of view of household expenditures (private + public prod).
Basic prices make more sense to understand where value production takes place, but market prices are more useful to understand who chooses expenditures, as the government (not consumers) decides what to do with VAT revenue.

### Naïve 

When one thinks of their income before taxes and transfers, it sums to 
gross household primary income - imputed rents
As for the income after taxes and transfers, it sums to 
gross household disposable income - imputed rents 
= GNI - govt in-kind services - collective expenditures - imputed rents - retained earnings
= GNI - all taxes + govt monetary transfers - imputed rents - retained earnings

### WID/DINA

The WID uses two main concepts: pretax and posttax income. Both sum to NNI = GNI - depreciation, where depreciation = CFC.
They reason net of depreciation and distribute everything to households, including retained earnings and taxes on production (pretax, paid in proportion to consumption) or government in-kind services and collective expenditures (posttax).
All of this makes sense economically but is far from what people naïvely understand as income. 
Their online comparator (https://github.com/world-inequality-database/wid-income-wealth-comparator/blob/main/import-data-simulator-updated-2026.do) uses pretax income. The WID recover users' pretax income by imputing taxes on production and asking people for their gross household primary income, their imputed rents, and their stock holdings (to impute retained earnings).

=> Don't they account for CFC?