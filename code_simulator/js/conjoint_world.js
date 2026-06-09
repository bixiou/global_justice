/**
 * conjoint_world.js — all-country conjoint module.
 *
 * CSV inputs (relative to data/):
 *   ineq_2035_full.csv           long-format: country × gpercentile × scenario cols
 *   ineq_2100_countries.csv      long-format: country × bracket × {SC,SG,SN,SI}
 *   ineq_2100_full.csv           21-bracket World_* columns
 *   conjoint_constants.csv       temperature / global constants (IT-based)
 *   conjoint_world_constants.csv per-country extra_tax_rate, ratio
 *   cash_income.csv              country × gpercentile × income_2025…income_2100 (SC trajectory)
 *
 * All income values returned are ANNUAL EUR PPP unless noted.
 * The HTML is responsible for × pppRate / 12 → monthly local currency.
 */
"use strict";

const INCOME_YEARS = Array.from({ length: 76 }, (_, i) => 2025 + i);

let _dataReady          = false;
let _ineq2035all        = null;
let _ineq2100c          = null;
let _ineq2100w          = null;
let _C                  = null;
let _WC                 = null;
let _availableCountries = null;
let _cashIncome         = null;   // country → pctKey → year → annual EUR PPP

let _country   = null;
let _rows2035  = null;
let _rows2100c = null;

// ─── CSV helpers ──────────────────────────────────────────────────────────────
async function loadCsv(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error("HTTP " + res.status + " loading " + url);
  const text = await res.text();
  const lines = text.trim().split("\n").map(l => l.trim()).filter(Boolean);
  const headers = lines[0].split(",").map(h => h.trim());
  return lines.slice(1).map(line => {
    const cells = line.split(",");
    const row = {};
    headers.forEach((h, i) => { row[h] = (cells[i] || "").trim(); });
    return row;
  });
}

function numerify(rows) {
  return rows.map(row => {
    const out = {};
    for (const k in row) out[k] = row[k] === "" ? null : (isNaN(row[k]) ? row[k] : +row[k]);
    return out;
  });
}

// ─── Load ─────────────────────────────────────────────────────────────────────
async function ensureDataLoaded(basePath) {
  if (_dataReady) return;
  basePath = basePath || "data/";
  const [rows2035, rows2100c, rows2100w, constRows, wcRows, cashRows] = await Promise.all([
    loadCsv(basePath + "ineq_2035_full.csv"),
    loadCsv(basePath + "ineq_2100_countries.csv"),
    loadCsv(basePath + "ineq_2100_full.csv"),
    loadCsv(basePath + "conjoint_constants.csv"),
    loadCsv(basePath + "conjoint_world_constants.csv"),
    loadCsv(basePath + "cash_income.csv"),
  ]);
  _ineq2035all = numerify(rows2035);
  _ineq2100c   = numerify(rows2100c);
  _ineq2100w   = numerify(rows2100w);
  _C = {};
  constRows.forEach(r => { _C[r.name] = +r.value; });
  _WC = {};
  wcRows.forEach(r => { _WC[r.country] = { extra_tax_rate: +r.extra_tax_rate, ratio: +r.ratio }; });
  _cashIncome = {};
  for (const row of cashRows) {
    const ctry = row.country, pct = row.gpercentile;
    if (!_cashIncome[ctry]) _cashIncome[ctry] = {};
    const byYear = {};
    INCOME_YEARS.forEach(y => { byYear[y] = +(row["income_" + y] || 0); });
    _cashIncome[ctry][pct] = byYear;
  }
  _availableCountries = new Set(_ineq2035all.map(r => r.country));
  _dataReady = true;
}

// ─── Country selection ─────────────────────────────────���──────────────────────
function setCountry(code) {
  if (!_dataReady) throw new Error("Data not loaded.");
  if (_country === code && _rows2035) return;
  _country   = code;
  _rows2035  = _ineq2035all.filter(r => r.country === code);
  _rows2100c = _ineq2100c.filter(r => r.country === code);
  if (!_rows2035.length) throw new Error("No 2035 data for country: " + code);
}

// ─── Helpers ─────────────────────────────────────────��────────────────────────
function gpWidth(g) {
  if (g < 99)    return 0.01;
  if (g < 99.9)  return 0.001;
  if (g < 99.99) return 0.0001;
  return 0.00001;
}

function gpercentiles() { return _rows2035.map(r => r.gpercentile); }

function interpolate(arr, gp, targetGp) {
  if (targetGp <= gp[0])              return arr[0];
  if (targetGp >= gp[gp.length - 1]) return arr[arr.length - 1];
  for (let i = 0; i < gp.length - 1; i++) {
    if (gp[i] <= targetGp && targetGp < gp[i + 1]) {
      const t = (targetGp - gp[i]) / (gp[i + 1] - gp[i]);
      return arr[i] + t * (arr[i + 1] - arr[i]);
    }
  }
  return arr[arr.length - 1];
}

function findPercentileIn2025(annualEUR) {
  const gp  = gpercentiles();
  const inc = _rows2035.map(r => r.income25);
  if (annualEUR <= inc[0])              return gp[0];
  if (annualEUR >= inc[inc.length - 1]) return gp[gp.length - 1];
  for (let i = 0; i < inc.length - 1; i++) {
    if (inc[i] <= annualEUR && annualEUR < inc[i + 1]) {
      const t = (annualEUR - inc[i]) / (inc[i + 1] - inc[i]);
      return gp[i] + t * (gp[i + 1] - gp[i]);
    }
  }
  return gp[gp.length - 1];
}

// ─── 2035 distribution ─────────────────────────────────────────────────────────
// Columns pre-computed with sectoral_change=2 / PS-increased as canonical assumption
const SECTORAL_CHANGE2_COLS_W = new Set([
  "SC","SG","SN","SC45k","SG45k","SN45k","SC15k","SG15k","SN15k",
  "B90kC","B90kG","B90kN","B90kI",
  "B45kC","B45kG","B45kN","B45kI","B30kC","B30kG","B30kN","B30kI","B15kC","B15kG","B15kN","B15kI",
  "Bbeef","Bflights","B90kC_SD","B120kC","B120kG","B120kN","B120kI",
  "B","BG","BN","BI"
]);

function getColName(h, gR, nR) {
  const hasGIT = gR === "GIT", hasNat = nR === "SN";
  const scope = hasGIT ? (hasNat ? "C" : "G") : (hasNat ? "N" : "I");
  // 35h baseline is B (B/BG/BN/BI = S{scope}·b_scale), NOT SC — see scenarios.js.
  // All non-45h map to the B-class so the hours→income ladder is monotonic.
  if (h === 45) return "B120k" + scope;
  if (h === 35) return scope === "C" ? "B" : "B" + scope;
  if (h === 40) return "B90k" + scope;
  if (h === 30) return "B45k" + scope;
  if (h === 29) return "B30k" + scope;
  return scope === "C" ? "B" : "B" + scope;
}

function get2035Distribution(h, gR, nR, decarb, ps) {
  const C = _C;
  const wc = _WC[_country] || { extra_tax_rate: C["extra_tax_rate_IT"] || 0 };
  const psExp     = 1 - wc.extra_tax_rate;
  const decarbU   = C["decarb_" + decarb];
  const decarbExp = C["decarb_FD"];
  const psUser    = ps === "increased" ? psExp : 1;
  const col       = getColName(h, gR, nR);
  const epf       = SECTORAL_CHANGE2_COLS_W.has(col) ? psExp : 1;
  const dr        = decarbU / decarbExp;
  const pr        = psUser / epf;
  return _rows2035.map(row => {
    const v = row[col];
    return (v == null || isNaN(v)) ? 0 : v * dr * pr;
  });
}

// ─── 2100 distribution ���───────────────────────────────────────────────────────
function get2100Scope(gR, nR) {
  const hasGIT = gR === "GIT", hasNat = nR === "SN";
  if (hasGIT && hasNat)   return "SC";
  if (hasGIT && !hasNat)  return "SG";
  if (!hasGIT && hasNat)  return "SN";
  return "SI";
}

// Fixed 2100 hours→income coefs vs the scope base (SC/SG/SN/SI), matching the GDP
// targets used in questionnaire.R §13: 29h→30k=0.5, 30h→45k=0.75, 35h→60k=1.0,
// 40h→90k=1.5, 45h→120k=2.0. Scope-independent (the scope is the base column).
function get2100HoursCoef(h, gR, nR) {
  return { 29: 0.5, 30: 0.75, 35: 1.0, 40: 1.5, 45: 2.0 }[h] || 1;
}

function get2100Income(respondentGp, scope, hoursCoef) {
  if (!_rows2100c || !_rows2100c.length) return 0;
  for (const row of _rows2100c) {
    const m = row.bracket.match(/p(\d+(?:\.\d+)?)p(\d+(?:\.\d+)?)/);
    if (!m) continue;
    const lo = +m[1], hi = +m[2];
    if (respondentGp >= lo && (hi >= 100 ? true : respondentGp < hi))
      return (row[scope] || 0) * hoursCoef;
  }
  return (_rows2100c[_rows2100c.length - 1][scope] || 0) * hoursCoef;
}

function get2100Distributions(h, gR, nR) {
  const scope     = get2100Scope(gR, nR);
  const hoursCoef = get2100HoursCoef(h, gR, nR);
  const brackets    = _rows2100c.map(r => r.bracket);
  const countryVals = _rows2100c.map(r => (r[scope] || 0) * hoursCoef);
  const worldVals   = _ineq2100w.map(r => (r["World_" + scope] || 0) * hoursCoef);
  return { brackets, countryVals, worldVals, scope, hoursCoef };
}

// ─── Evolution trajectory ──────────────────────────────────────────────────────
// cash_income.csv only stores the SC path. We take the SC trajectory for the
// respondent's percentile and warp it (log-linearly within each segment) so it
// hits the SELECTED scenario's 2035 and 2100 income anchors, keeping the SC
// year-to-year shape between anchors. At 2025 the warp factor is 1 (baseline).
function getEvolTrajectory(countryCode, inc25AtGp) {
  if (!_cashIncome || !_cashIncome[countryCode]) return null;
  const byPct = _cashIncome[countryCode];
  let bestPct = null, bestDiff = Infinity;
  for (const pct of Object.keys(byPct)) {
    const diff = Math.abs((byPct[pct][2025] || 0) - inc25AtGp);
    if (diff < bestDiff) { bestDiff = diff; bestPct = pct; }
  }
  if (!bestPct) return null;
  const byYear = byPct[bestPct];
  return { years: INCOME_YEARS, annualEUR: INCOME_YEARS.map(y => byYear[y] || 0) };
}

function warpTrajectory(scTraj, own2035, own2100) {
  const { years, annualEUR } = scTraj;
  const t2035 = annualEUR[years.indexOf(2035)] || 0;
  const t2100 = annualEUR[years.indexOf(2100)] || 0;
  const lr2035 = (t2035 > 0 && own2035 > 0) ? Math.log(own2035 / t2035) : 0;
  const lr2100 = (t2100 > 0 && own2100 > 0) ? Math.log(own2100 / t2100) : 0;
  const warped = years.map((y, i) => {
    let lr;
    if (y <= 2025)      lr = 0;
    else if (y <= 2035) lr = lr2035 * (y - 2025) / 10;
    else                lr = lr2035 + (lr2100 - lr2035) * (y - 2035) / 65;
    return Math.round((annualEUR[i] || 0) * Math.exp(lr));
  });
  return { years, annualEUR: warped };
}

// ─── Country mean income 2025 (population-weighted, annual EUR PPP) ───────────
function getCountryMeanIncome(countryCode) {
  if (!_dataReady || !_ineq2035all) return null;
  const rows = _ineq2035all.filter(r => r.country === countryCode);
  if (!rows.length) return null;
  const widths = rows.map(r => r.gpercentile < 99 ? 1 : r.gpercentile < 99.9 ? 0.1 : r.gpercentile < 99.99 ? 0.01 : 0.001);
  const totalW = widths.reduce((a, b) => a + b, 0);
  return rows.reduce((s, r, i) => s + (r.income25 || 0) * widths[i], 0) / totalW;
}

// ─── Temperature (copied verbatim from scenarios.js) ──────────────────────────
function predictBaseTemp(gdpTotal, decarb, sc) {
  const C = _C;
  const isID = decarb === "ID" ? 1 : 0, isSD = decarb === "SD" ? 1 : 0;
  const isFD = decarb === "FD" ? 1 : 0;
  return C["noem_Intercept"]
    + C["noem_gdp"]          * gdpTotal
    + C["noem_decarbID"]     * isID
    + C["noem_decarbSD"]     * isSD
    + C["noem_gdp_decarbID"] * gdpTotal * isID
    + C["noem_gdp_decarbSD"] * gdpTotal * isSD
    + C["noem_decarbFD_sectoral_change"] * sc * isFD
    + C["noem_decarbID_sectoral_change"] * sc * isID
    + C["noem_decarbSD_sectoral_change"] * sc * isSD;
}

function computeTemperature(h, gR, ps, decarb, baf) {
  const C = _C;
  const hasGIT         = gR === "GIT";
  const sectoralChange = ps === "increased" ? 2 : 1;     // renamed from food
  const beefR     = baf === "beef"    || baf === "both";
  const flightR   = baf === "flights" || baf === "both";
  const isPItype  = h === 45 && !hasGIT;                  // distinct 2100 population/GDP basis (not sectoral change)
  const gdpPcKey  = hasGIT ? "gdp_pc_GIT_" + h + "h" : "gdp_pc_noGIT_" + h + "h";
  const gdpPc     = C[gdpPcKey];
  const popB      = isPItype ? C["pop_pi_2100_B"] : C["pop_sc_2100_B"];
  const sc        = sectoralChange === 2 ? 1 : 0;        // PS increased always applies the cooling term (incl. PI)
  let temp        = predictBaseTemp(gdpPc * popB, decarb, sc);
  const canonBeef = sectoralChange === 2, canonFlight = sectoralChange === 2;
  if (beefR    !== canonBeef)   temp += beefR    ? -C["temp_beef_reduction_C"]    : +C["temp_beef_reduction_C"];
  if (flightR  !== canonFlight) temp += flightR  ? -C["temp_flights_reduction_C"] : +C["temp_flights_reduction_C"];
  return Math.round(temp * 10) / 10;
}

function getWorkingHours2035(h) {
  // 2035 worked hours per 2100-target class, evenly spaced around the B90k (40h) baseline
  // in steps of 4 — matching scenarios.js (the IT survey) so both surveys label hours the same.
  return { 29: 28, 30: 32, 35: 36, 40: 40, 45: 44 }[h] || h;
}

function getPublicServicesFeature(ps) {
  const wc = _WC[_country] || { extra_tax_rate: 0 };
  const taxRate = wc.extra_tax_rate;
  if (ps === "increased")
    return { taxRate, description: "Public services +3pp of GNI — flat tax " +
             (taxRate * 100).toFixed(1) + "% of cash income." };
  return { taxRate: 0, description: "Public services stable (current share of GNI)." };
}

function getBeefAndFlightsFeature(baf) {
  const C = _C;
  const desc = { none: "No change.", beef: "Beef −60%.", flights: "Flights −50%.",
                 both: "Beef −60%, flights −50%." };
  let adj = 0;
  if (baf === "beef"    || baf === "both") adj -= C["temp_beef_reduction_C"];
  if (baf === "flights" || baf === "both") adj -= C["temp_flights_reduction_C"];
  return { description: desc[baf] || desc.none, tempAdjustment: Math.round(adj * 1000) / 1000 };
}

// ─── Main function ────────���───────────────────────────────────────────────────
/**
 * @param {string}  countryCode
 * @param {number}  pppRate          local currency per EUR PPP
 * @param {number}  householdIncomeMonthly   in local currency
 * @param {boolean} isCouple
 * @param {string}  decarbonization
 * @param {number}  hoursPerWeek
 * @param {string}  nationalRedistribution
 * @param {string}  globalRedistribution
 * @param {string}  publicServices
 * @param {string}  beefAndFlights
 * @returns {{ temperature, ownIncome, workingHours, national2035, global2100, evolution,
 *             publicServicesFeature, beefAndFlightsFeature }}
 *          All income values are ANNUAL EUR PPP unless the property name says Monthly or Local.
 */
function computeConjointFeatures({
  countryCode, pppRate, householdIncomeMonthly, isCouple,
  decarbonization, hoursPerWeek, nationalRedistribution, globalRedistribution,
  publicServices, beefAndFlights
}) {
  if (!_dataReady) throw new Error("Data not loaded — await ensureDataLoaded() first.");
  setCountry(countryCode);

  const ppp = pppRate || 1;
  const annualEUR = (householdIncomeMonthly / ppp) * 12 / (isCouple ? 2 : 1);
  const gp = findPercentileIn2025(annualEUR);
  const gpVec = gpercentiles();

  const dist2035 = get2035Distribution(hoursPerWeek, globalRedistribution,
                                        nationalRedistribution, decarbonization, publicServices);
  const ownAnnualEUR2035 = interpolate(dist2035, gpVec, gp);
  const inc25AtGp = interpolate(_rows2035.map(r => r.income25), gpVec, gp);

  const d2100 = get2100Distributions(hoursPerWeek, globalRedistribution, nationalRedistribution);
  const ownAnnualEUR2100 = get2100Income(gp, d2100.scope, d2100.hoursCoef);

  // Scenario-warped trajectory from the SC path (fallback: 4-point approx)
  const scTraj = getEvolTrajectory(countryCode, inc25AtGp);
  const evolution = scTraj
    ? warpTrajectory(scTraj, ownAnnualEUR2035, ownAnnualEUR2100)
    : (() => {
    const inc2050 = ownAnnualEUR2035 > 0 && ownAnnualEUR2100 > 0
      ? Math.exp(Math.log(ownAnnualEUR2035) + (15/65) * (Math.log(ownAnnualEUR2100) - Math.log(ownAnnualEUR2035)))
      : ownAnnualEUR2035 + (ownAnnualEUR2100 - ownAnnualEUR2035) * (15/65);
    return { years: [2025, 2035, 2050, 2100],
             annualEUR: [Math.round(inc25AtGp), Math.round(ownAnnualEUR2035),
                         Math.round(inc2050), Math.round(ownAnnualEUR2100)] };
  })();

  const scen2035Label = {
    "GIT-SN":"SC", "GIT-current":"SG", "current-SN":"SN", "current-current":"SI"
  }[globalRedistribution + "-" + nationalRedistribution] || "SC";
  const hoursLbl = { 29:"B30kC",30:"B45kC",35:scen2035Label,40:"B90kC",45:"B120kC" };
  const scenName = hoursLbl[hoursPerWeek] || scen2035Label;

  return {
    temperature: { value: computeTemperature(hoursPerWeek, globalRedistribution,
                                              publicServices, decarbonization, beefAndFlights) },
    ownIncome: {
      monthlyLocal:      Math.round(ownAnnualEUR2035 * ppp / 12 * (isCouple ? 2 : 1)),
      currency:          countryCode,
      respondentGp:      Math.round(gp * 10) / 10,
      currentMonthlyLocal: Math.round(householdIncomeMonthly),
      annualEUR2035:     Math.round(ownAnnualEUR2035)
    },
    workingHours: { value: getWorkingHours2035(hoursPerWeek) },
    national2035: {
      gpercentiles: gpVec,
      annualEUR:    dist2035,   // 127-element array, annual EUR PPP
      income25EUR:  _rows2035.map(r => r.income25),
      scenarioName: scenName
    },
    global2100: {
      brackets:        d2100.brackets,   // 21 bracket names
      countryAnnualEUR: d2100.countryVals,
      worldAnnualEUR:   d2100.worldVals,
      scopeSuffix:     d2100.scope
    },
    evolution,
    publicServicesFeature: getPublicServicesFeature(publicServices),
    beefAndFlightsFeature: getBeefAndFlightsFeature(beefAndFlights)
  };
}

// ─── Exports ────────────────────────────────────────────────────────────────
const WorldConjointModule = {
  ensureDataLoaded, setCountry, computeConjointFeatures,
  getCountryMeanIncome,
  get availableCountries() { return _availableCountries; },
  get _rows2035() { return _rows2035; }
};
if (typeof module !== "undefined" && module.exports) module.exports = WorldConjointModule;
else window.WorldConjointModule = WorldConjointModule;
