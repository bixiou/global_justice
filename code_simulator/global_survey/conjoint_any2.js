/**
 * conjoint_any2.js — global survey "variant_any2": split-screen conjoint comparison of two
 * RANDOMLY drawn scenarios (free parameters). No user controls: the respondent only chooses
 * between the left and right scenario. English UI, country chosen with ?country=XX; reproduces inequality_figures.R layout.
 *
 * Parameter draws (uniform, independent across attributes; redraw if both sides are identical):
 *   – hours worked in 2035 ∈ {32, 36, 40, 44}  (→ 2100-target class 30/35/40/45)
 *   – decarbonization      ∈ {SD, ID, FD}
 *   – beef & flights       ∈ {both, beef, flights, none}
 *   – public services      ∈ {increased, stable}
 *   – hours by gender      ∈ {unchanged, equal}   (displayed only)
 *   – redistribution       ∈ {none, national, global, both}
 *
 * The respondent's household income and living arrangement are read from ?income= and ?couple=
 * (see below), both passed by the survey tool.
 *
 * Companion files: conjoint_few.js (named-scenario pairs) and conjoint_any2.js (2%-growth dataset).
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

// Redistribution selector → underlying national/global parameters
const REDIST_MAP = {
  both:     { nationalRedistribution: "SN",      globalRedistribution: "GIT" },
  global:   { nationalRedistribution: "current", globalRedistribution: "GIT" },
  national: { nationalRedistribution: "SN",      globalRedistribution: "current" },
  none:     { nationalRedistribution: "current", globalRedistribution: "current" }
};

// ─── Random draw of the free parameters ─────────────────────────────────────────────────────────
let HOURS_CHOICES = [32, 36, 40, 44];   // overwritten after load with [ref-8, ref-4, ref, ref+4]
const DECARB_CHOICES = ["SD", "ID", "FD"];
const BF_CHOICES     = ["both", "beef", "flights", "none"];
const PS_CHOICES     = ["increased", "stable"];
const GENDER_CHOICES = ["unchanged", "equal"];
const REDIST_CHOICES = ["none", "national", "global", "both"];
const pick = arr => arr[Math.floor(Math.random() * arr.length)];

function drawParams() {
  const worked = pick(HOURS_CHOICES);
  const redist = pick(REDIST_CHOICES);
  return {
    workedHours:     worked,
    hoursPerWeek:    worked,                // real 2035 hours, fed directly to the engine
    decarbonization: pick(DECARB_CHOICES),
    redist,
    ...REDIST_MAP[redist],
    publicServices:  pick(PS_CHOICES),
    beefAndFlights:  pick(BF_CHOICES),
    genderHours:     pick(GENDER_CHOICES)   // displayed only: no effect on the computed features
  };
}
// Signature over the 6 visible attributes (used to guarantee the two sides differ).
const sig = p => [p.workedHours, p.decarbonization, p.beefAndFlights, p.publicServices, p.redist,
                  p.genderHours].join("|");

const PARAMS = {};   // side id → drawn parameter object

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
const charts = {};   // canvasId → Chart instance

// Y-limits are country-specific and come from the engine (local currency per month): the world
// panel keeps the fixed 30k EUR PPP scale so it stays comparable across countries, the national
// panel uses the p95-p99 bracket of the country's BI120k1_SD scenario in 2100 — both plus 12% of
// headroom. Bars above the limit are clipped and get a hatched cap in the top HATCH_FRAC band.
const HATCH_FRAC = 4 / 30;   // the band the previous fixed 26k..30k limits carved out
// Plugin: on each bar clipped by the y-limit (the cap = dataset index 1) draw two crisp white
// diagonal stripes — the 2nd and 3rd rows from the cap top — to flag the truncation.
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
      if (!(data[i] > 0)) return;                          // only clipped bars
      const wd = bar.width, l = Math.round(bar.x - wd / 2), r = Math.round(bar.x + wd / 2);
      const top = Math.round(bar.y), bot = Math.round(bar.base), bw = r - l;
      capTop = top;
      ctx.save();
      ctx.beginPath(); ctx.rect(l, top, bw, bot - top); ctx.clip();
      [4, 8].forEach(off => {                              // 2nd & 3rd stripe rows (px below cap top)
        ctx.beginPath();
        ctx.moveTo(l, top + off + bw / 2);                 // span exactly the bar width (no overshoot)
        ctx.lineTo(r, top + off - bw / 2);                 // 45° "/"
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

// ─── shared rendering ────────────────────────────────────────────────────────────

/** Monthly-income coloured-bracket histogram (annual values in, /12 inside).
 *  Each bracket is expanded into 1%-wide unit slots so bar widths match bracket sizes:
 *  19 brackets × 5%, then p95p99 = 4% and p99p100 = 1% (100 slots total). */
function renderInequality(canvasId, brackets, annualValues, ylim) {
  const slotV = [], slotC = [], slotB = [];
  brackets.forEach((b, i) => {
    const m = b.match(/p([\d.]+)p([\d.]+)/);
    const w = Math.max(1, Math.round((+m[2]) - (+m[1])));   // bracket width in % points
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

/** Caption sidebar: mean monthly income of the bottom-10 / median / top-10 groups. */
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

// Beef & flights and gender phrase text.
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
  const p = PARAMS[side];
  return {
    householdIncomeMonthly: INCOME_MONTHLY,           // from ?income=
    isCouple:               IS_COUPLE,               // from ?couple=
    decarbonization:        p.decarbonization,
    hoursPerWeek:           p.hoursPerWeek,
    nationalRedistribution: p.nationalRedistribution,
    globalRedistribution:   p.globalRedistribution,
    publicServices:         p.publicServices,
    beefAndFlights:         p.beefAndFlights
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
  document.getElementById("gender-" + side).textContent = GENDER_TXT[PARAMS[side].genderHours];

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
    const p = PARAMS[id];
    return { workedHours: p.workedHours, hoursPerWeek: p.hoursPerWeek,
             decarbonization: p.decarbonization, redistribution: p.redist,
             nationalRedistribution: p.nationalRedistribution, globalRedistribution: p.globalRedistribution,
             publicServices: p.publicServices, beefAndFlights: p.beefAndFlights,
             genderHours: p.genderHours };
  };
  return {
    variant: "any2",
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
async function initVariantAny(file2035) {
  const comparison = document.getElementById("comparison");
  // Load first: the hours grid depends on the country's ref_hours.
  try {
    await ScenariosModule.ensureDataLoaded("data/", file2035, COUNTRY, LANG);
    INCOME_MONTHLY = resolveIncomeMonthly();
    applyTranslations();
    HOURS_CHOICES = ScenariosModule.hoursChoices();
  } catch (err) {
    document.getElementById("statusMsg").textContent =
      T("ui.load_error") + err.message + T("ui.load_error_hint");
    return;
  }
  // Draw two distinct scenarios.
  PARAMS.L = drawParams();
  PARAMS.R = drawParams();
  while (sig(PARAMS.L) === sig(PARAMS.R)) PARAMS.R = drawParams();

  // Draw the shared block/row order (same in both panels).
  ORDER.blocks = shuffle(["2035", "2100"]);
  ORDER.r2035  = shuffle(["hours", "income", "bf", "ps", "gender"]);
  ORDER.r2100  = shuffle(["temp", "IT", "World"]);

  comparison.innerHTML = buildGrid();
  window.conjointExport = buildExport();

  document.getElementById("statusMsg").textContent = "";
  SIDES.forEach(s => updateSide(s.id));
}

// Default dataset (1%-growth B scenarios). conjoint_any2.js overrides with the 2% file.
if (typeof window !== "undefined" && !window.__SKIP_AUTO_INIT)
  initVariantAny("ineq2_2035.csv");
