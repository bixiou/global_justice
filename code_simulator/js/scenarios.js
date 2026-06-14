/**
 * conjoint.js
 *
 * Computes the seven displayed features of a conjoint scenario from the
 * eight underlying parameters. Loads three CSV files once and caches them.
 *
 * External CSV inputs (paths relative to the HTML page, served from code_simulator/data/):
 *   data/ineq_IT_2035.csv      – 127-row IT income distributions (2035)
 *   data/ineq_2100.csv         – 21-bracket IT+World income distributions (2100)
 *   data/conjoint_constants.csv – key-value constant table
 *
 * ─── Eight underlying parameters ────────────────────────────────────────────
 *   householdIncomeMonthly  – respondent household monthly cash income (EUR)
 *   isCouple                – boolean: income shared by two adults
 *   decarbonization         – "SD" | "ID" | "FD"
 *   hoursPerWeek            – 28 | 32 | 36 | 40 | 44   (real 2035 weekly hours worked)
 *   nationalRedistribution  – "current" | "SN"
 *   globalRedistribution    – "current" | "GIT"
 *   publicServices          – "stable" | "increased"
 *   beefAndFlights          – "none" | "beef" | "flights" | "both"
 *
 * ─── Seven displayed features (keys in the returned object) ─────────────────
 *   temperature             – { value }                   2100 temperature (°C)
 *   ownIncome               – { value (EUR/month, doubled to household total if couple),
 *                               respondentPercentile, currentIncomeMonthly, annualPerAdult }
 *   workingHours            – { value, targetHoursPerWeek }
 *   nationalIncomes         – { gpercentiles, values, respondentGpercentile,
 *                               respondentIncome, scenarioName }
 *   globalIncomes           – { brackets, itValues, worldValues, scenarioName }
 *   publicServicesFeature   – { taxRate, description }
 *   beefAndFlightsFeature   – { description, tempAdjustment }
 */

"use strict";

// ─── Module-level cached state ────────────────────────────────────────────────
let _dataReady  = false;
let _ineqIT2035 = null;   // array of row objects, one per gpercentile
let _ineq2100   = null;   // array of row objects, one per bracket
let _C          = null;   // constants dictionary: name → Number

// ─── CSV loader ───────────────────────────────────────────────────────────────

/** Fetch and parse a CSV file into an array of plain row objects. */
async function loadCsv(url) {
  const text = await (await fetch(url)).text();
  const lines = text.trim().split("\n").map(l => l.trim()).filter(Boolean);
  const headers = lines[0].split(",").map(h => h.trim());
  return lines.slice(1).map(line => {
    const cells = line.split(",");
    const row = {};
    headers.forEach((h, i) => { row[h] = (cells[i] || "").trim(); });
    return row;
  });
}

/** Parse every cell that looks like a number; leave the rest as strings. */
function numerify(rows) {
  return rows.map(row => {
    const out = {};
    for (const k in row) out[k] = row[k] === "" ? null : (isNaN(row[k]) ? row[k] : +row[k]);
    return out;
  });
}

/**
 * Load the three CSV files once. Must be awaited before calling
 * computeConjointFeatures(). Safe to call multiple times.
 *
 * @param {string} [basePath] – URL prefix; defaults to "data/"
 * @param {string} [it2035File] – 2035 distributions file; defaults to "ineq_IT_2035_full.csv".
 *        Pass "ineq2_IT_2035_full.csv" to use the 2%-growth B-scenario variant (variant_any2).
 */
async function ensureDataLoaded(basePath, it2035File) {
  if (_dataReady) return;
  basePath = basePath || "data/";
  it2035File = it2035File || "ineq_IT_2035_full.csv";
  const [rows2035, rows2100, constRows] = await Promise.all([
    loadCsv(basePath + it2035File),              // ineq_IT_2035 (+variants); ineq2_* for the 2% B-growth variant
    loadCsv(basePath + "ineq_2100_full.csv"),   // ineq_2100 + all scope/sub-target variants
    loadCsv(basePath + "conjoint_constants.csv"),
  ]);
  _ineqIT2035 = numerify(rows2035);
  _ineq2100   = numerify(rows2100);
  _C = {};
  constRows.forEach(r => { _C[r.name] = +r.value; });
  _dataReady = true;
}

// ─── Small utilities ──────────────────────────────────────────────────────────

function gpercentiles() { return _ineqIT2035.map(r => r.gpercentile); }

function gpWidth(g) {
  if (g < 99)    return 0.01;
  if (g < 99.9)  return 0.001;
  if (g < 99.99) return 0.0001;
  return 0.00001;
}

/** Weighted mean of an array over the 127 IT gpercentile grid. */
function weightedMean127(arr) {
  const gp = gpercentiles();
  let num = 0, den = 0;
  arr.forEach((v, i) => { const w = gpWidth(gp[i]); num += v * w; den += w; });
  return num / den;
}

// ─── Respondent percentile and own-income lookup ──────────────────────────────

/**
 * Find the respondent's gpercentile in the IT25 distribution via linear interpolation.
 * Returns a value in [0, 99.999].
 */
function findPercentileInIT25(annualIncome) {
  const gp  = gpercentiles();
  const it25 = _ineqIT2035.map(r => r.IT25);
  if (annualIncome <= it25[0])              return gp[0];
  if (annualIncome >= it25[it25.length - 1]) return gp[gp.length - 1];
  for (let i = 0; i < it25.length - 1; i++) {
    if (it25[i] <= annualIncome && annualIncome < it25[i + 1]) {
      const t = (annualIncome - it25[i]) / (it25[i + 1] - it25[i]);
      return gp[i] + t * (gp[i + 1] - gp[i]);
    }
  }
  return gp[gp.length - 1];
}

/** Interpolate income at a given gpercentile from a 127-element distribution array. */
function interpolateAtPercentile(dist, targetGp) {
  const gp = gpercentiles();
  if (targetGp <= gp[0])            return dist[0];
  if (targetGp >= gp[gp.length - 1]) return dist[dist.length - 1];
  for (let i = 0; i < gp.length - 1; i++) {
    if (gp[i] <= targetGp && targetGp < gp[i + 1]) {
      const t = (targetGp - gp[i]) / (gp[i + 1] - gp[i]);
      return dist[i] + t * (dist[i + 1] - dist[i]);
    }
  }
  return dist[dist.length - 1];
}

// ─── 2035 IT income distribution ─────────────────────────────────────────────

/**
 * Return the 2035 IT income distribution (127 values, EUR/adult/year) for the
 * given scenario. The exported columns in ineq_IT_2035.csv correspond to specific
 * selected scenarios (mostly sectoral_change=2, FD), so we re-scale for the user's chosen
 * decarbonization and public-services level.
 *
 * Hours handling: each hours class × scope reads its precomputed B-family column directly — the
 * SAME method as conjoint_world.js getColName, so any2/few/world stay consistent. 35h → B (C) /
 * BG/BN/BI; 30/40/45h → B{45k,90k,120k}{C,G,N,I} (45h uses B120k, the displayed 44h, not the
 * P-family). The non-convergence (G/N/I) columns are built in questionnaire.R §14 as
 * SG/SN/SI × coefC at the dataset's own growth (so reading them here keeps any2/few on the F0a
 * dataset, instead of re-deriving with the 1.5%-based avg_IT2035 constants).
 *
 * @returns {number[]} 127-element array
 */
function getIT2035Distribution(hoursPerWeek, globalRedistribution,
                                nationalRedistribution, decarbonization, publicServices,
                                col2035Override) {
  const C = _C;
  const decarbUser       = C["decarb_" + decarbonization];  // user decarb income factor
  const decarbExported   = C["decarb_FD"];                  // factor baked into exported cols
  const psExported       = 1 - C["extra_tax_rate_IT"];      // PS factor baked into sectoral_change=2 cols
  const psUser           = publicServices === "increased" ? psExported : 1;

  if (col2035Override) {
    // Direct column lookup from ineq_IT_2035_full (pre-computed at FD, sectoral_change=2 or sectoral_change=1)
    const sectoralChange2Cols = new Set(["SC","SC45k","SC15k","SI","SN","SG",
                                "B","BG","BN","BI",
                                "B45kC","B45kG","B45kN","B45kI",
                                "B90kC","B90kG","B90kN","B90kI",
                                "B120kC","B120kG","B120kN","B120kI",
                                "B30kC","B15kC","B90kC_SD"]);
    const exportedPsFactor = sectoralChange2Cols.has(col2035Override) ? psExported : 1;
    const decarbRatio = decarbUser / decarbExported;
    const psRatio     = psUser / exportedPsFactor;
    return _ineqIT2035.map(row => {
      const v = row[col2035Override];
      return (v == null || isNaN(v)) ? 0 : v * decarbRatio * psRatio;
    });
  }

  // Columns exported at sectoral_change=2 (carry PS tax):
  const sectoralChange2Cols  = new Set(["SC","SC45k","SC15k","SI","SN","SG",
                               "B","BG","BN","BI",
                               "B45kC","B45kG","B45kN","B45kI",
                               "B90kC","B90kG","B90kN","B90kI",
                               "B120kC","B120kG","B120kN","B120kI",
                               "B30kC","B15kC","B90kC_SD"]);
  // Columns exported at sectoral_change=1 (no PS tax): IT25, cash_GR35, IT35, SCmat, PC, PI

  const hasGIT = globalRedistribution === "GIT";
  const hasNat = nationalRedistribution === "SN";
  const scope  = hasGIT ? (hasNat ? "C" : "G") : (hasNat ? "N" : "I");

  // Read the precomputed B-family column for this hours class × scope — SAME method as
  // conjoint_world.js getColName, so any2/few/world stay consistent. The non-convergence (G/N/I)
  // columns B{45k,90k,120k}{G,N,I} are precomputed in the CSV, so they carry the loaded dataset's
  // own growth (no runtime coefC rescaling, which previously mixed the 1.5% constants into the F0a
  // ineq2 dataset). 44h uses B120k, 40h B90k, 32h B45k, 28h B30k, 36h the B baseline.
  let colName;
  if      (hoursPerWeek === 44) colName = "B120k" + scope;
  else if (hoursPerWeek === 40) colName = "B90k"  + scope;
  else if (hoursPerWeek === 32) colName = "B45k"  + scope;
  else if (hoursPerWeek === 28) colName = "B30k"  + scope;
  else                          colName = scope === "C" ? "B" : "B" + scope;   // 36h baseline

  const exportedPsFactor = sectoralChange2Cols.has(colName) ? psExported : 1;
  const decarbRatio = decarbUser / decarbExported;
  const psRatio     = psUser / exportedPsFactor;

  return _ineqIT2035.map(row => {
    const v = row[colName];
    return (v == null || isNaN(v)) ? 0 : v * decarbRatio * psRatio;
  });
}

// ─── 2100 IT + World income distributions ─────────────────────────────────────

/**
 * Return the 21-bracket IT and World 2100 income distributions for the scenario.
 *
 * For hours ≠ 35h: scale the 35h redistribution-scope column by
 * avg(hours_col) / avg(SC) — equivalent to the coefs 0.75, 0.25, 630/480, 2, etc.
 * used in questionnaire.R.  The coefs are derived from avg_World2100_* constants.
 *
 * @returns {{ brackets, itValues, worldValues, scenarioName }}
 */
function get2100Distributions(hoursPerWeek, globalRedistribution, nationalRedistribution,
                              col2100Override) {
  if (col2100Override) {
    const brackets    = _ineq2100.map(r => r.bracket);
    const itValues    = _ineq2100.map(r => r["IT_"    + col2100Override] || 0);
    const worldValues = _ineq2100.map(r => r["World_" + col2100Override] || 0);
    return { brackets, itValues, worldValues, scenarioName: col2100Override };
  }
  const C = _C;
  const hasGIT = globalRedistribution === "GIT";
  const hasNat = nationalRedistribution === "SN";

  // Choose the redistribution-scope suffix (independent of hours)
  let scopeSuffix;
  if      (hasGIT && hasNat)   scopeSuffix = "SC";
  else if (hasGIT && !hasNat)  scopeSuffix = "SG";
  else if (!hasGIT && hasNat)  scopeSuffix = "SN";
  else                         scopeSuffix = "SI";

  // Fixed 2100 hours→income coefs vs the scope base (GDP targets ÷ 60k SC): 28h→30k=0.5,
  // 32h→45k=0.75, 36h→60k=1.0, 40h→90k=1.5, 44h→120k=2.0. Matches questionnaire.R §13.
  const hoursCoef = { 28: 0.5, 32: 0.75, 36: 1.0, 40: 1.5, 44: 2.0 }[hoursPerWeek] || 1;

  // For scope-specific hours scaling (e.g. SG at 30h ≈ SG_35h × SC45k_coef)
  const itColName    = "IT_"    + scopeSuffix;
  const worldColName = "World_" + scopeSuffix;

  const brackets    = _ineq2100.map(r => r.bracket);
  const itValues    = _ineq2100.map(r => (r[itColName]    || 0) * hoursCoef);
  const worldValues = _ineq2100.map(r => (r[worldColName] || 0) * hoursCoef);
  return { brackets, itValues, worldValues, scenarioName: scopeSuffix };
}

// ─── Temperature ──────────────────────────────────────────────────────────────

/**
 * Predict 2100 base temperature using the no-emissions GDP-based regression:
 *   T ~ Intercept + β_gdp·GDP + β_ID·isID + β_SD·isSD
 *       + β_gdp_ID·GDP·isID + β_gdp_SD·GDP·isSD
 *       + β_sc_FD·sc·isFD + β_sc_ID·sc·isID + β_sc_SD·sc·isSD
 *
 * Coefficients stored in constants as "noem_Intercept", "noem_gdp", etc.
 *
 * @param {number} gdpTotal       – total 2100 GDP (T€)
 * @param {string} decarbonization – "FD" | "ID" | "SD"
 * @param {0|1}    sectoralChange  – 1 if public services increased (sectoral_change=2), else 0
 */
function predictBaseTemp(gdpTotal, decarbonization, sectoralChange) {
  const C   = _C;
  const isID = decarbonization === "ID" ? 1 : 0;
  const isSD = decarbonization === "SD" ? 1 : 0;
  const isFD = decarbonization === "FD" ? 1 : 0;
  const sc   = sectoralChange;
  return C["noem_Intercept"]
    + C["noem_gdp"]         * gdpTotal
    + C["noem_decarbID"]    * isID
    + C["noem_decarbSD"]    * isSD
    + C["noem_gdp_decarbID"] * gdpTotal * isID
    + C["noem_gdp_decarbSD"] * gdpTotal * isSD
    + C["noem_decarbFD_sectoral_change"] * sc * isFD
    + C["noem_decarbID_sectoral_change"] * sc * isID
    + C["noem_decarbSD_sectoral_change"] * sc * isSD;
}

/**
 * Compute the 2100 temperature for the scenario.
 *
 * The method (method_questionnaire.md) picks a "fixed" modality (1 or 2)
 * as the base and then applies additive corrections:
 *   – SD/ID: fix = public services choice; adjust for beef/flights vs canonical
 *   – FD:    fix = beef-reduction choice;  adjust for PS and flights vs canonical
 *
 * Temperature corrections: −0.24°C per beef reduction, −0.155°C per flight reduction,
 * ±0.0004875·(67.25 + 2.06·GDPpc) for public services difference.
 */
function computeTemperature(hoursPerWeek, globalRedistribution,
                             publicServices, decarbonization, beefAndFlights,
                             gdpPc2100Override) {
  const C = _C;
  const hasGIT         = globalRedistribution === "GIT";
  const sectoralChange = publicServices === "increased" ? 2 : 1;   // renamed from food (1=stable, 2=increased PS)
  const beefReduced   = beefAndFlights === "beef"    || beefAndFlights === "both";
  const flightReduced = beefAndFlights === "flights" || beefAndFlights === "both";
  const isPItype      = hoursPerWeek === 44 && !hasGIT;  // distinct 2100 population/GDP basis (not sectoral change)

  const gdpPcKey = hasGIT
    ? "gdp_pc_GIT_"   + hoursPerWeek + "h"
    : "gdp_pc_noGIT_" + hoursPerWeek + "h";
  const gdpPc  = gdpPc2100Override != null ? gdpPc2100Override : C[gdpPcKey];
  const popB   = isPItype ? C["pop_pi_2100_B"] : C["pop_sc_2100_B"];
  const gdpTotal = gdpPc * popB;
  const sc = sectoralChange === 2 ? 1 : 0;   // PS increased always applies the cooling term (incl. PI)

  // Base temperature from the GDP regression (uses the user's sectoral_change/decarb directly)
  let temp = predictBaseTemp(gdpTotal, decarbonization, sc);

  // Adjust beef/flights vs the canonical co-variation (sectoral_change=2 → both reduced): the
  // cooling sectoral_change term is already in the base, so any diet divergence adds/removes its bit.
  const canonBeef = sectoralChange === 2, canonFlight = sectoralChange === 2;
  if (beefReduced   !== canonBeef)   temp += beefReduced   ? -C["temp_beef_reduction_C"]    : +C["temp_beef_reduction_C"];
  if (flightReduced !== canonFlight) temp += flightReduced ? -C["temp_flights_reduction_C"] : +C["temp_flights_reduction_C"];

  return Math.round(temp * 10) / 10;
}

// ─── Working hours in 2035 ────────────────────────────────────────────────────

/**
 * Weekly working hours actually worked in 2035. The hoursPerWeek param now carries the real
 * 2035 hours directly (28 | 32 | 36 | 40 | 44), evenly spaced around the B90k (40h) baseline in
 * steps of 4. These hours also encode the 2100 GDP-per-capita target (28h→30k … 44h→120k) and
 * drive the 2035 income scale (worked_hours / 40 relative to B90k).
 */
function getWorkingHours2035(hoursPerWeek) {
  return hoursPerWeek;
}

// ─── Public services feature description ──────────────────────────────────────

function getPublicServicesFeature(publicServices) {
  const taxRate = _C["extra_tax_rate_IT"];
  if (publicServices === "increased") {
    return {
      taxRate,
      description:
        "Spending on education, health and public services rises from 20% to 23% of GNI. " +
        "Financed by a flat-rate tax of " + (taxRate * 100).toFixed(1) +
        "% on all cash incomes."
    };
  }
  return { taxRate: 0, description: "Public services remain at their current level (20% of GNI)." };
}

// ─── Beef and flights feature description ─────────────────────────────────────

function getBeefAndFlightsFeature(beefAndFlights) {
  const C = _C;
  const descriptions = {
    none:    "No change in beef consumption or air travel.",
    beef:    "Beef consumption reduced by 60% (replaced by other proteins).",
    flights: "Air travel reduced by 50%.",
    both:    "Beef (−60%) and air travel (−50%) both reduced."
  };
  let tempAdj = 0;
  if (beefAndFlights === "beef"    || beefAndFlights === "both") tempAdj -= C["temp_beef_reduction_C"];
  if (beefAndFlights === "flights" || beefAndFlights === "both") tempAdj -= C["temp_flights_reduction_C"];
  return {
    description: descriptions[beefAndFlights] || descriptions.none,
    tempAdjustment: Math.round(tempAdj * 1000) / 1000
  };
}

// ─── Main public function ─────────────────────────────────────────────────────

/**
 * Compute all seven displayed features from the eight underlying parameters.
 * Throws if ensureDataLoaded() has not been awaited yet.
 *
 * @param {Object} params – the eight underlying parameters (see file header)
 * @returns {Object} – the seven displayed features (see file header)
 */
function computeConjointFeatures({
  householdIncomeMonthly,
  isCouple,
  decarbonization,
  hoursPerWeek,
  nationalRedistribution,
  globalRedistribution,
  publicServices,
  beefAndFlights,
  col2035Override,    // optional: direct column name in ineq_IT_2035_full (e.g. "MC45k")
  col2100Override,    // optional: scope stem in ineq_2100_full (e.g. "MC45k" → IT_MC45k)
  gdpPc2100Override   // optional: GDP per capita (k€/adult) override for temperature
}) {
  if (!_dataReady) throw new Error("Data not loaded — call ensureDataLoaded() first.");

  // Percentile and 2035 interpolation use per-adult income (half the household total for couples)
  const annualIncomePerAdult = householdIncomeMonthly * 12 / (isCouple ? 2 : 1);
  const respondentGp = findPercentileInIT25(annualIncomePerAdult);

  const dist2035 = getIT2035Distribution(
    hoursPerWeek, globalRedistribution, nationalRedistribution,
    decarbonization, publicServices, col2035Override);
  const ownIncomeAnnualPerAdult = interpolateAtPercentile(dist2035, respondentGp);
  // Displayed 2035 income: monthly, doubled to the household total when a couple
  const coupleFactor = isCouple ? 2 : 1;
  const ownIncomeMonthly = Math.round(ownIncomeAnnualPerAdult / 12 * coupleFactor);

  const incomes2100 = get2100Distributions(
    hoursPerWeek, globalRedistribution, nationalRedistribution, col2100Override);

  const temp = computeTemperature(
    hoursPerWeek, globalRedistribution, publicServices, decarbonization, beefAndFlights,
    gdpPc2100Override);

  const hours2035 = getWorkingHours2035(hoursPerWeek);

  // Determine scenario name for national incomes chart label
  const scenarioLabel35h = {
    "GIT-SN":   "SC",  "GIT-current":   "SG",
    "current-SN":"SN", "current-current":"SI"
  }[(globalRedistribution + "-" + nationalRedistribution)] || "SC";
  // 45h uses the B120k B-family class (matching the displayed 44h), not the P-family.
  const hoursLabel = { 28:"B30kC",32:"B45kC",36:scenarioLabel35h,40:"B90kC",44:"B120kC" };
  const natScenarioName = hoursLabel[hoursPerWeek] || scenarioLabel35h;

  return {
    temperature: { value: temp },
    ownIncome: {
      value: ownIncomeMonthly,                              // EUR/month, household total if couple
      respondentPercentile: Math.round(respondentGp * 10) / 10,
      currentIncomeMonthly: Math.round(householdIncomeMonthly),
      annualPerAdult: Math.round(ownIncomeAnnualPerAdult)
    },
    workingHours: { value: hours2035, targetHoursPerWeek: hoursPerWeek },
    nationalIncomes: {
      gpercentiles: _ineqIT2035.map(r => r.gpercentile),
      values:        dist2035.map(v => Math.round(v)),
      respondentGpercentile: Math.round(respondentGp * 10) / 10,
      respondentIncome: Math.round(ownIncomeAnnualPerAdult),
      scenarioName: natScenarioName
    },
    globalIncomes: {
      brackets:   incomes2100.brackets,
      itValues:   incomes2100.itValues.map(v => Math.round(v)),
      worldValues:incomes2100.worldValues.map(v => Math.round(v)),
      scenarioName: incomes2100.scenarioName
    },
    publicServicesFeature: getPublicServicesFeature(publicServices),
    beefAndFlightsFeature: getBeefAndFlightsFeature(beefAndFlights)
  };
}

// ─── Exports ──────────────────────────────────────────────────────────────────
const ScenariosModule = {
  ensureDataLoaded,
  computeConjointFeatures,
  // Internal state exposed for chart rendering
  get _ineqIT2035() { return _ineqIT2035; },
  get _ineq2100()   { return _ineq2100; }
};

if (typeof module !== "undefined" && module.exports) {
  module.exports = ScenariosModule;
} else {
  window.ScenariosModule = ScenariosModule;
  window.ConjointModule  = ScenariosModule;   // backward-compat alias (conjoint.html)
}
