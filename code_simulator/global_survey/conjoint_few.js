/**
 * conjoint_few.js — IT survey "variant_few": split-screen conjoint comparison of two RANDOMLY
 * drawn NAMED scenarios. No user controls: the respondent only chooses between left and right.
 * English UI, country chosen with ?country=XX; reproduces inequality_figures.R layout.
 *
 * Draw: slot 1 is picked among the 12 scenarios with weight 2/13 for BC and 1/13 for the others;
 * slot 2 is then picked among the remaining 11 with the same relative weights (so the pair is distinct).
 *
 * The respondent's household income and living arrangement are read from ?income= and ?couple=
 * (see below), both passed by the survey tool.
 *
 * Scenario roster (label = our display name; code = method nomenclature {type}{scope}{sectoral_change}_{decarb}):
 *   BC=BC2_FD(36h)·2  BC90k=B90kC2_FD(40h)  BCmat=BC1_FD(36h, sectoral_change=1)  BC45k=B45kC2_FD(32h)
 *   BC120k=B120kC2_FD(44h)  BI120k=B120kI1_FD(44h, no redist)  BI=BI2_FD  BN=BN2_FD  BG=BG2_FD
 *   BCbeef=BC2_FDbeef  BCflight=BC2_FDflight  BC_SD=BC2_SD
 * NOTE: the 40h scenario is keyed BC90k after its 90k income target (the baseline BC is the 60k,
 * 36h scenario). "BC120k=BC1_FD" is read as B120kC2_FD. The beef/
 * flights focus follows the user's parentheticals: BCbeef = "less flights, stable beef" (beefAndFlights
 * = "flights"); BCflight = "less beef, stable flight" (beefAndFlights = "beef").
 */
"use strict";

// ─── Respondent income and household ────────────────────────────────────────────────────────────
// The survey tool passes the respondent's household cash income as ?income=..., in LOCAL CURRENCY
// UNITS and in the period the country usually quotes incomes in (fmt.period.XX in
// data/translations.csv: monthly almost everywhere, yearly in US/CA/GB/AU/JP/KR) — i.e. exactly
// the amount the respondent typed. It is converted to a monthly amount once the country is loaded.
const DEFAULT_INCOME_MONTHLY = 2500;   // fallback when ?income= is absent or unusable (local/month)
const urlParam = k => (typeof location !== "undefined" &&
  new URLSearchParams(location.search).get(k)) || null;
const INCOME_PARAM = urlParam("income");
let INCOME_MONTHLY = DEFAULT_INCOME_MONTHLY;   // resolved in init, once the period is known
// ?couple=1 means the income is shared by two adults, so the engine reads it per adult. Anything
// else — ?couple=0, an unexpected value, or no parameter at all — means an individual income.
const IS_COUPLE = /^(1|true|yes)$/i.test(urlParam("couple") || "");

/**
 * Parse an amount that may carry digit-group separators or a currency symbol: "3200", "3,200",
 * "3.200", "$3 200.50". Dots in groups of exactly three are read as separators, commas always are;
 * anything else keeps "." as the decimal point. A plain number is always safest.
 */
function parseAmount(s) {
  const clean = String(s).replace(/[^\d.,-]/g, "");
  const n = Number(/^-?\d{1,3}(\.\d{3})+$/.test(clean) ? clean.replace(/\./g, "")
                                                       : clean.replace(/,/g, ""));
  return isFinite(n) ? n : NaN;
}

/** ?income= in the country's own period -> household cash income in local currency per month. */
function resolveIncomeMonthly() {
  const n = INCOME_PARAM === null ? NaN : parseAmount(INCOME_PARAM);
  return (n > 0) ? n / ScenariosModule.periodFactor : DEFAULT_INCOME_MONTHLY;
}


// ─── Country selection ──────────────────────────────────────────────────────────────────────────
// The country is passed as a URL parameter, e.g. conjoint_any.html?country=FR . It must be one of
// the countries bundled in data/*.csv (see questionnaire_global.R).
const COUNTRY = urlParam("country") || "IT";
// Language column of data/translations.csv (Qualtrics code), e.g. conjoint_any.html?country=FR&lang=EN
// Empty => the engine falls back to the country's own language (constant `lang`).
const LANG = urlParam("lang");
// Every display string comes from data/translations.csv (never hard-coded here).
const T = k => ScenariosModule.t(k);

const SIDES = [{ id: "L", cls: "left", name: "" }, { id: "R", cls: "right", name: "" }];

// Helper to build an engine parameter set.
const P = (hoursPerWeek, nationalRedistribution, globalRedistribution, decarbonization, publicServices, beefAndFlights) =>
  ({ hoursPerWeek, nationalRedistribution, globalRedistribution, decarbonization, publicServices, beefAndFlights });

// Scenario roster. Hours are expressed as a CLASS (B45k = ref-8, B = ref-4, B90k = ref,
// B120k = ref+4) and turned into the country's real weekly hours once the data are loaded, so the
// same roster works for a 35h country (France) and a 48h one (India).
const CLS_OF = { B45k: -8, B: -4, B90k: 0, B120k: 4 };
const SCENARIO_DEFS = {
  BC:       { weight: 2, cls: "B",     name: "B convergence",                          params: ["SN",      "GIT",     "FD", "increased", "both"] },
  BC90k:    { weight: 1, cls: "B90k",  name: "B90k convergence",                       params: ["SN",      "GIT",     "FD", "increased", "both"] },
  BCmat:    { weight: 1, cls: "B",     name: "B convergence, public services stable",  params: ["SN",      "GIT",     "FD", "stable",    "both"] },
  BC45k:    { weight: 1, cls: "B45k",  name: "B45k convergence",                       params: ["SN",      "GIT",     "FD", "increased", "both"] },
  BC120k:   { weight: 1, cls: "B120k", name: "B120k convergence",                      params: ["SN",      "GIT",     "FD", "increased", "both"] },
  BI120k:   { weight: 1, cls: "B120k", name: "B120k inequality",                       params: ["current", "current", "FD", "stable",    "none"] },
  BI:       { weight: 1, cls: "B",     name: "Inequality",                             params: ["current", "current", "FD", "increased", "both"] },
  BN:       { weight: 1, cls: "B",     name: "National redistribution only",           params: ["SN",      "current", "FD", "increased", "both"] },
  BG:       { weight: 1, cls: "B",     name: "Global redistribution only",             params: ["current", "GIT",     "FD", "increased", "both"] },
  BCbeef:   { weight: 1, cls: "B",     name: "B convergence, fewer flights",           params: ["SN",      "GIT",     "FD", "increased", "flights"] },
  BCflight: { weight: 1, cls: "B",     name: "B convergence, less beef",               params: ["SN",      "GIT",     "FD", "increased", "beef"] },
  BC_SD:    { weight: 1, cls: "B",     name: "B convergence, slow decarbonization",    params: ["SN",      "GIT",     "SD", "increased", "both"] }
};

// Filled by buildScenarios() once the country's ref_hours is known.
let SCENARIOS = {};

function buildScenarios(refHours) {
  SCENARIOS = {};
  for (const k in SCENARIO_DEFS) {
    const d = SCENARIO_DEFS[k];
    const h = refHours + CLS_OF[d.cls];
    SCENARIOS[k] = { weight: d.weight, label: d.name + " — " + h + "h",
                     params: P(h, d.params[0], d.params[1], d.params[2], d.params[3], d.params[4]) };
  }
}

// Weighted pick over a list of scenario keys.
function weightedPick(keys) {
  const total = keys.reduce((s, k) => s + SCENARIOS[k].weight, 0);
  let r = Math.random() * total;
  for (const k of keys) { r -= SCENARIOS[k].weight; if (r <= 0) return k; }
  return keys[keys.length - 1];
}

const CHOSEN = {};   // side id → scenario key
// Working hours by gender is not part of the named-scenario roster: it is drawn independently
// and equiprobably per side, and only displayed (no effect on the computed features).
const GENDER_CHOICES = ["unchanged", "equal"];
const GENDER = {};   // side id → "unchanged" | "equal"

// ─── inequality-figure styling (mirrors inequality_figures.R) ────────────────────
const GRP_COL = { bottom: "#2166AC", median: "#4DAC26", top: "#D6604D", other: "#D9D9D9" };
const GRP_OF = { p0p5: "bottom", p5p10: "bottom", p45p50: "median", p50p55: "median",
                 p90p95: "top", p95p99: "top", p99p100: "top" };
function groupOf(b) { return GRP_OF[b] || "other"; }
// Key "IT" is kept as the internal id of the NATIONAL panel (country-agnostic).
let LABELS = { IT: {}, World: {} };
// Money formatting is a COUNTRY convention (currency layout, thousands separator, and whether
// incomes are usually quoted per month or per year) and lives in the engine, so the three variants
// stay consistent. Amounts go in as local currency per MONTH and come out in the country's period.
const money    = n => ScenariosModule.fmtMoney(n);
const moneyPer = n => ScenariosModule.fmtMoneyPer(n);
// Compact axis labels, for scales ranging from 23,298 EUR to 391 million IDR: "23k", "82.9M".
const kLabel = v => {
  const a = Math.abs(v);
  if (a >= 1e9) return Math.round(v / 1e8) / 10 + "B";
  if (a >= 1e6) return Math.round(v / 1e5) / 10 + "M";
  if (a >= 1e3) return Math.round(v / 1e3) + "k";
  return String(Math.round(v));
};
/** Round to two significant figures (a clipped bar's true height is labelled that way). */
const roundSig2 = v => {
  if (!(v > 0)) return 0;
  const p = Math.pow(10, Math.floor(Math.log10(v)) - 1);
  return Math.round(v / p) * p;
};
const charts = {};

// Y-limits are country-specific and come from the engine (local currency per month): the world
// panel keeps the fixed 30k EUR PPP scale so it stays comparable across countries, the national
// panel uses the p95-p99 bracket of the country's BI120k1_SD scenario in 2100 — both plus 12% of
// headroom. Bars above the limit are clipped and get a hatched cap in the top HATCH_FRAC band.
const HATCH_FRAC = 4 / 30;   // the band the previous fixed 26k..30k limits carved out
const capHatchPlugin = {
  id: "capHatch",
  afterDatasetsDraw(chart) {
    const meta = chart.getDatasetMeta(1);
    if (!meta || !chart.data.datasets[1]) return;
    const data = chart.data.datasets[1].data, ctx = chart.ctx;
    let capTop = null;   // pixel row of the cap top, set as soon as one bar turns out to be clipped
    ctx.save();
    ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 1.4; ctx.lineCap = "butt";
    meta.data.forEach((bar, i) => {
      if (!(data[i] > 0)) return;
      const wd = bar.width, l = Math.round(bar.x - wd / 2), r = Math.round(bar.x + wd / 2);
      const top = Math.round(bar.y), bot = Math.round(bar.base), bw = r - l;
      capTop = top;
      ctx.save();
      ctx.beginPath(); ctx.rect(l, top, bw, bot - top); ctx.clip();
      [4, 8].forEach(off => {
        ctx.beginPath();
        ctx.moveTo(l, top + off + bw / 2);
        ctx.lineTo(r, top + off - bw / 2);
        ctx.stroke();
      });
      ctx.restore();
    });
    // Break the y axis over the rows the bar's stripes span, so the truncation reads on the scale
    // and not only on the clipped bar. The axis line is thin and grey, so hairline cuts across it
    // would be invisible: erase the whole segment instead, leaving a plain white gap. White works
    // because the scales have a z of 0 and are therefore already drawn by now.
    if (capTop !== null) {
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(chart.chartArea.left - 1.5, capTop + 2, 3, 10);
    }
    ctx.restore();
  }
};

function renderInequality(canvasId, brackets, annualValues, ylim) {
  const slotV = [], slotC = [], slotB = [];
  brackets.forEach((b, i) => {
    const m = b.match(/p([\d.]+)p([\d.]+)/);
    const w = Math.max(1, Math.round((+m[2]) - (+m[1])));
    const v = Math.round(annualValues[i] / 12), col = GRP_COL[groupOf(b)];
    for (let s = 0; s < w; s++) { slotV.push(v); slotC.push(col); slotB.push(b); }
  });
  const i99 = brackets.indexOf("p99p100");
  const topMonthly = i99 >= 0 ? Math.round(annualValues[i99] / 12) : 0;
  const maxBar = slotV.reduce((m, v) => Math.max(m, v), 0);
  const hatchFrom = ylim * (1 - HATCH_FRAC);
  const hasHatch = topMonthly > ylim;
  const solidV = slotV.map(v => v > ylim ? hatchFrom : v);
  const capV   = slotV.map(v => v > ylim ? ylim - hatchFrom : 0);
  const PF = ScenariosModule.periodFactor;   // bars stay monthly; only the tick LABELS are scaled
  if (charts[canvasId]) charts[canvasId].destroy();
  charts[canvasId] = new Chart(document.getElementById(canvasId).getContext("2d"), {
    type: "bar",
    data: { labels: slotB, datasets: [
      { data: solidV, backgroundColor: slotC, borderWidth: 0, categoryPercentage: 1.0, barPercentage: 1.0, stack: "s" },
      { data: capV,   backgroundColor: slotC, borderWidth: 0, categoryPercentage: 1.0, barPercentage: 1.0, stack: "s" }
    ] },
    plugins: [capHatchPlugin],
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { display: false },
        tooltip: { filter: item => item.datasetIndex === 0,
                   callbacks: { title: items => slotB[items[0].dataIndex],
                                label: c => " " + moneyPer(slotV[c.dataIndex]) } } },
      scales: {
        x: { stacked: true, display: false, grid: { display: false } },
        y: { stacked: true, min: 0, max: ylim,
             // Pin the topmost tick exactly at the limit, so a clipped bar's true height can be
             // labelled there; drop any auto tick close enough to overlap that label. Skip the
             // pinned label altogether when no bar reaches past the highest auto tick: it would
             // then name a level nothing on the chart comes near.
             afterBuildTicks: axis => {
               axis.ticks = axis.ticks.filter(k => k.value < ylim * 0.93);
               const topAuto = axis.ticks.reduce((m, k) => Math.max(m, k.value), 0);
               if (maxBar > topAuto) axis.ticks.push({ value: ylim });
             },
             ticks: { autoSkip: false, maxTicksLimit: 6,
                      callback: v => (v >= ylim && hasHatch) ? kLabel(roundSig2(topMonthly * PF))
                                                             : kLabel(v * PF),
             font: { size: 8 } } }
      }
    }
  });
}

function renderCaption(capId, brackets, annualValues, region) {
  const meanOf = grp => {
    const xs = brackets.map((b, i) => groupOf(b) === grp ? annualValues[i] / 12 : null).filter(v => v != null);
    return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0;
  };
  const L = LABELS[region];
  const rows = [["bottom", L.bottom], ["median", L.median], ["top", L.top]];
  document.getElementById(capId).innerHTML = rows.map(([g, lab]) =>
    `<div class="cap-row"><b style="color:${GRP_COL[g]}">${lab}</b>
       <span><span style="color:${GRP_COL[g]};font-weight:700">${money(meanOf(g))}</span>${ScenariosModule.unitPerPeriod()}</span></div>`
  ).join("");
}

let BF_TXT = {}, GENDER_TXT = {};

// ─── table layout: a SINGLE 3-column grid — a shared left "title" column plus the L and R
// scenario columns — so each row's cells share a grid row and stay vertically locked, and
// each row title appears only once (on the left). The block order (2035 / 2100) AND the row
// order WITHIN each block are drawn once (ORDER) and apply to both columns. ───────────────
const shuffle = arr => {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
};
const ORDER = {};   // { blocks:[…], r2035:[…], r2100:[…] } — set in init, applies to both columns

// Row titles shown once in the shared left column (2035 attributes + temperature).
let ATTR_LABELS = {};

// Value cell for an attribute row: just the value (filled in by updateSide).
const valCell = (key, side) =>
  `<div class="gcell vcell ${side === "L" ? "col-l" : "col-r"}">
     <span class="attr-val" id="${key}-${side}">—</span></div>`;

// Distribution cell: the income card (chart + per-side legend); its title is the row's left label.
const distCell = (region, side) => {
  const sfx = region === "IT" ? "IT" : "W";
  return `<div class="gcell dcell ${side === "L" ? "col-l" : "col-r"}"><div class="card">
      <div class="ineq"><div class="ineq-chart"><canvas id="c${sfx}-${side}"></canvas></div>
      <div class="ineq-cap" id="cap${sfx}-${side}"></div></div></div></div>`;
};

// Build the grid: a full-width block header, then per row a left title cell + the L and R cells.
function buildGrid() {
  let html = "";
  ORDER.blocks.forEach(name => {
    html += `<div class="block-head">${T("ui.in_year").replace("{year}", name)}</div>`;
    (name === "2035" ? ORDER.r2035 : ORDER.r2100).forEach(r => {
      const isAttr = name === "2035" || r === "temp";
      const title = isAttr ? ATTR_LABELS[r] : LABELS[r].title;
      html += `<div class="rlabel ${isAttr ? "rlabel-attr" : "rlabel-dist"}"><span>${title}</span></div>` +
        (isAttr ? valCell(r, "L") + valCell(r, "R") : distCell(r, "L") + distCell(r, "R"));
    });
  });
  return html;
}

function engineParams(side) {
  const p = SCENARIOS[CHOSEN[side]].params;
  return {
    householdIncomeMonthly: INCOME_MONTHLY,           // from ?income=
    isCouple:               IS_COUPLE,               // from ?couple=
    ...p
  };
}

function updateSide(side) {
  const params = engineParams(side);
  let f;
  try { f = ScenariosModule.computeConjointFeatures(params); }
  catch (e) { document.getElementById("statusMsg").textContent = T("ui.error") + e.message; return; }

  document.getElementById("temp-"   + side).textContent = "+" + f.temperature.value.toFixed(1) + "°C";
  document.getElementById("hours-"  + side).textContent =
    f.workingHours.value + "\u00a0" + T("unit.hours_per_week");
  document.getElementById("income-" + side).textContent = moneyPer(f.ownIncome.value);
  document.getElementById("ps-"     + side).textContent =
    params.publicServices === "increased" ? T("ps.increased") : T("ps.stable");
  document.getElementById("bf-"     + side).innerHTML = BF_TXT[params.beefAndFlights];
  document.getElementById("gender-" + side).textContent = GENDER_TXT[GENDER[side]];

  const gi = f.globalIncomes;
  renderInequality("cIT-" + side, gi.brackets, gi.itValues, ScenariosModule.ylimNat);
  renderCaption("capIT-" + side, gi.brackets, gi.itValues, "IT");
  renderInequality("cW-" + side, gi.brackets, gi.worldValues, ScenariosModule.ylimWorld);
  renderCaption("capW-" + side, gi.brackets, gi.worldValues, "World");
}

// ─── export: expose the drawn layout + both scenarios so the survey tool can record
// exactly what each respondent saw (window.conjointExport, refreshed on every build). ──
function buildExport() {
  const sideData = id => {
    const key = CHOSEN[id];
    return { scenario: key, label: SCENARIOS[key].label, params: { ...SCENARIOS[key].params },
             genderHours: GENDER[id] };
  };
  return {
    variant: "few",
    rowOrder: { blocks: ORDER.blocks.slice(), r2035: ORDER.r2035.slice(), r2100: ORDER.r2100.slice() },
    sides: { L: sideData("L"), R: sideData("R") }
  };
}


// ─── Filled from data/translations.csv once it is loaded ────────────────────────────────────────
function applyTranslations() {
  SIDES[0].name = T("ui.left");
  SIDES[1].name = T("ui.right");
  // The national title carries a drawn flag (flags.js): emoji flags render as blanks or as a
  // plain dot on Windows and on several mobile browsers. The globe emoji does render, so it stays.
  LABELS = {
    IT:    { bottom: T("chart.nat_bottom"), median: T("chart.nat_median"),
             top: T("chart.nat_top"),
             title: FlagsModule.flagSvg(ScenariosModule.country) + T("chart.nat_title") },
    World: { bottom: T("chart.world_bottom"), median: T("chart.world_median"),
             top: T("chart.world_top"), title: "\ud83c\udf0d " + T("chart.world_title") }
  };
  BF_TXT = { none: T("bf.none"), beef: T("bf.beef"), flights: T("bf.flights"), both: T("bf.both") };
  GENDER_TXT = { unchanged: T("gender.unchanged"), equal: T("gender.equal") };
  ATTR_LABELS = {
    hours: T("attr.hours"),
    income: '<span class="lbl-full">' +
            T(ScenariosModule.periodFactor === 12 ? "attr.income_full_year" : "attr.income_full") +
            '</span>' +
            '<span class="lbl-short">' + T("attr.income_short") + '</span> (' +
            T("attr.income_current") + moneyPer(INCOME_MONTHLY) + ')',
    bf: T("attr.bf"), ps: T("attr.ps"), gender: T("attr.gender"), temp: T("attr.temp")
  };
}

// ─── init ──────────────────────────────────────────────────────────────────────
(async function init() {
  const comparison = document.getElementById("comparison");
  // Load first: the roster's hour levels depend on the country's ref_hours.
  try {
    await ScenariosModule.ensureDataLoaded("data/", "ineq_2035.csv", COUNTRY, LANG);   // growth1 (B family)
    INCOME_MONTHLY = resolveIncomeMonthly();
    applyTranslations();
    buildScenarios(ScenariosModule.refHours);
  } catch (err) {
    document.getElementById("statusMsg").textContent =
      T("ui.load_error") + err.message + T("ui.load_error_hint");
    return;
  }
  // Slot 1: weighted over all 12; slot 2: weighted over the remaining 11 (distinct pair).
  const allKeys = Object.keys(SCENARIOS);
  CHOSEN.L = weightedPick(allKeys);
  CHOSEN.R = weightedPick(allKeys.filter(k => k !== CHOSEN.L));
  SIDES.forEach(s => { GENDER[s.id] = GENDER_CHOICES[Math.floor(Math.random() * GENDER_CHOICES.length)]; });

  // Draw the shared block/row order (same in both panels).
  ORDER.blocks = shuffle(["2035", "2100"]);
  ORDER.r2035  = shuffle(["hours", "income", "bf", "ps", "gender"]);
  ORDER.r2100  = shuffle(["temp", "IT", "World"]);

  comparison.innerHTML = buildGrid();
  window.conjointExport = buildExport();

  document.getElementById("statusMsg").textContent = "";
  SIDES.forEach(s => updateSide(s.id));
})();
