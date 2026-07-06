/**
 * conjoint_few.js — IT survey "variant_few": split-screen conjoint comparison of two RANDOMLY
 * drawn NAMED scenarios. No user controls: the respondent only chooses between left and right.
 * Italian UI; reproduces inequality_figures.R layout.
 *
 * Draw: slot 1 is picked among the 12 scenarios with weight 2/13 for BC and 1/13 for the others;
 * slot 2 is then picked among the remaining 11 with the same relative weights (so the pair is distinct).
 *
 * Income/couple use DEFAULT values (placeholder) — TODO: feed these automatically from the
 * respondent's earlier answers (e.g. via URL query params or a global injected by the survey tool).
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

// ─── Respondent income placeholder (TODO: feed automatically from survey answers) ───────────────
const DEFAULT_INCOME_MONTHLY = 2500;   // household monthly cash income (EUR)
const DEFAULT_IS_COUPLE      = false;

const SIDES = [{ id: "L", cls: "left", name: "Sinistra" }, { id: "R", cls: "right", name: "Destra" }];

// Helper to build an engine parameter set.
const P = (hoursPerWeek, nationalRedistribution, globalRedistribution, decarbonization, publicServices, beefAndFlights) =>
  ({ hoursPerWeek, nationalRedistribution, globalRedistribution, decarbonization, publicServices, beefAndFlights });

const SCENARIOS = {
  BC:      { weight: 2, label: "Convergenza B — 36h",                  params: P(36, "SN",      "GIT",     "FD", "increased", "both") },
  BC90k:   { weight: 1, label: "Convergenza B90k — 40h",               params: P(40, "SN",      "GIT",     "FD", "increased", "both") },
  BCmat:   { weight: 1, label: "Convergenza B — 36h, servizi stabili", params: P(36, "SN",      "GIT",     "FD", "stable",    "both") },
  BC45k:   { weight: 1, label: "Convergenza B45k — 32h",               params: P(32, "SN",      "GIT",     "FD", "increased", "both") },
  BC120k:  { weight: 1, label: "Convergenza B120k — 44h",              params: P(44, "SN",      "GIT",     "FD", "increased", "both") },
  BI120k:  { weight: 1, label: "Disuguaglianza B120k — 44h",           params: P(44, "current", "current", "FD", "stable",    "none") },
  BI:      { weight: 1, label: "Disuguaglianza — 36h",                 params: P(36, "current", "current", "FD", "increased", "both") },
  BN:      { weight: 1, label: "Solo redistribuzione nazionale — 36h", params: P(36, "SN",      "current", "FD", "increased", "both") },
  BG:      { weight: 1, label: "Solo redistribuzione globale — 36h",   params: P(36, "current", "GIT",     "FD", "increased", "both") },
  BCbeef:  { weight: 1, label: "Convergenza B — meno voli",            params: P(36, "SN",      "GIT",     "FD", "increased", "flights") },
  BCflight:{ weight: 1, label: "Convergenza B — meno carne",           params: P(36, "SN",      "GIT",     "FD", "increased", "beef") },
  BC_SD:   { weight: 1, label: "Convergenza B — decarbonizz. lenta",   params: P(36, "SN",      "GIT",     "SD", "increased", "both") }
};

// Weighted pick over a list of scenario keys.
function weightedPick(keys) {
  const total = keys.reduce((s, k) => s + SCENARIOS[k].weight, 0);
  let r = Math.random() * total;
  for (const k of keys) { r -= SCENARIOS[k].weight; if (r <= 0) return k; }
  return keys[keys.length - 1];
}

const CHOSEN = {};   // side id → scenario key

// ─── inequality-figure styling (mirrors inequality_figures.R) ────────────────────
const GRP_COL = { bottom: "#2166AC", median: "#4DAC26", top: "#D6604D", other: "#D9D9D9" };
const GRP_OF = { p0p5: "bottom", p5p10: "bottom", p45p50: "median", p50p55: "median",
                 p90p95: "top", p95p99: "top", p99p100: "top" };
function groupOf(b) { return GRP_OF[b] || "other"; }
const LABELS = {
  IT:    { bottom: "10% più povero in Italia", median: "Reddito tipico", top: "10% più ricco in Italia",
           title: `<span class="flag-it"></span> Redditi in Italia` },
  World: { bottom: "10% più povero del mondo", median: "Reddito tipico", top: "10% più ricco del mondo",
           title: "🌍 Redditi nel mondo" }
};
const fmtEur = n => Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".") + " €";
const charts = {};

const YLIM_MONTHLY = 30000;
const HATCH_FROM_MONTHLY = 26000;
const capHatchPlugin = {
  id: "capHatch",
  afterDatasetsDraw(chart) {
    const meta = chart.getDatasetMeta(1);
    if (!meta || !chart.data.datasets[1]) return;
    const data = chart.data.datasets[1].data, ctx = chart.ctx;
    ctx.save();
    ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 1.4; ctx.lineCap = "butt";
    meta.data.forEach((bar, i) => {
      if (!(data[i] > 0)) return;
      const wd = bar.width, l = Math.round(bar.x - wd / 2), r = Math.round(bar.x + wd / 2);
      const top = Math.round(bar.y), bot = Math.round(bar.base), bw = r - l;
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
    ctx.restore();
  }
};

function renderInequality(canvasId, brackets, annualValues) {
  const slotV = [], slotC = [], slotB = [];
  brackets.forEach((b, i) => {
    const m = b.match(/p([\d.]+)p([\d.]+)/);
    const w = Math.max(1, Math.round((+m[2]) - (+m[1])));
    const v = Math.round(annualValues[i] / 12), col = GRP_COL[groupOf(b)];
    for (let s = 0; s < w; s++) { slotV.push(v); slotC.push(col); slotB.push(b); }
  });
  const i99 = brackets.indexOf("p99p100");
  const topMonthly = i99 >= 0 ? Math.round(annualValues[i99] / 12) : 0;
  const hasHatch = topMonthly > YLIM_MONTHLY;
  const solidV = slotV.map(v => v > YLIM_MONTHLY ? HATCH_FROM_MONTHLY : v);
  const capV   = slotV.map(v => v > YLIM_MONTHLY ? YLIM_MONTHLY - HATCH_FROM_MONTHLY : 0);
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
                                label: c => " " + fmtEur(slotV[c.dataIndex]) + "/mese" } } },
      scales: {
        x: { stacked: true, display: false, grid: { display: false } },
        y: { stacked: true, min: 0, max: YLIM_MONTHLY, ticks: { callback: v => (v >= YLIM_MONTHLY && hasHatch)
               ? Math.round(topMonthly / 10000) * 10 + "k"
               : (v >= 1000 ? Math.round(v/1000) + "k" : Math.round(v)),
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
       <span><span style="color:${GRP_COL[g]};font-weight:700">${fmtEur(meanOf(g))}</span>/mese</span></div>`
  ).join("");
}

const BF_TXT = {
  none:    "Nessuna variazione",
  beef:    "Meno prodotti bovini (2 porzioni di carne al mese)<br>Prezzi triplicati",
  flights: "Meno voli (2.500 km all'anno)<br>Prezzi triplicati",
  both:    "Meno prodotti bovini (2 porzioni di carne al mese)<br>Meno voli (2.500 km all'anno)<br>Prezzi triplicati"
};

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
const ATTR_LABELS = { hours: "Ore di lavoro (full-time)",
                      income: `<span class="lbl-full">Reddito mensile netto del suo nucleo familiare</span><span class="lbl-short">Il suo reddito</span> (attuale: ${DEFAULT_INCOME_MONTHLY.toLocaleString("it-IT")} €/mese)`,
                      bf: "Alimentazione e voli", ps: "Servizi pubblici",
                      temp: "Riscaldamento globale" };

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
    html += `<div class="block-head">Nel ${name}</div>`;
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
    householdIncomeMonthly: DEFAULT_INCOME_MONTHLY,   // TODO: feed automatically
    isCouple:               DEFAULT_IS_COUPLE,        // TODO: feed automatically
    ...p
  };
}

function updateSide(side) {
  const params = engineParams(side);
  let f;
  try { f = ScenariosModule.computeConjointFeatures(params); }
  catch (e) { document.getElementById("statusMsg").textContent = "Errore: " + e.message; return; }

  document.getElementById("temp-"   + side).textContent = "+" + f.temperature.value.toFixed(1) + "°C";
  document.getElementById("hours-"  + side).textContent = f.workingHours.value + " ore/sett.";
  document.getElementById("income-" + side).textContent = f.ownIncome.value.toLocaleString("it-IT") + " €/mese";
  document.getElementById("ps-"     + side).textContent =
    params.publicServices === "increased" ? "Più servizi pubblici" : "Nessuna variazione";
  document.getElementById("bf-"     + side).innerHTML = BF_TXT[params.beefAndFlights];

  const gi = f.globalIncomes;
  renderInequality("cIT-" + side, gi.brackets, gi.itValues);
  renderCaption("capIT-" + side, gi.brackets, gi.itValues, "IT");
  renderInequality("cW-" + side, gi.brackets, gi.worldValues);
  renderCaption("capW-" + side, gi.brackets, gi.worldValues, "World");
}

// ─── export: expose the drawn layout + both scenarios so the survey tool can record
// exactly what each respondent saw (window.conjointExport, refreshed on every build). ──
function buildExport() {
  const sideData = id => {
    const key = CHOSEN[id];
    return { scenario: key, label: SCENARIOS[key].label, params: { ...SCENARIOS[key].params } };
  };
  return {
    variant: "few",
    rowOrder: { blocks: ORDER.blocks.slice(), r2035: ORDER.r2035.slice(), r2100: ORDER.r2100.slice() },
    sides: { L: sideData("L"), R: sideData("R") }
  };
}

// ─── init ──────────────────────────────────────────────────────────────────────
(async function init() {
  const comparison = document.getElementById("comparison");
  // Slot 1: weighted over all 12; slot 2: weighted over the remaining 11 (distinct pair).
  const allKeys = Object.keys(SCENARIOS);
  CHOSEN.L = weightedPick(allKeys);
  CHOSEN.R = weightedPick(allKeys.filter(k => k !== CHOSEN.L));

  // Draw the shared block/row order (same in both panels).
  ORDER.blocks = shuffle(["2035", "2100"]);
  ORDER.r2035  = shuffle(["hours", "income", "bf", "ps"]);
  ORDER.r2100  = shuffle(["temp", "IT", "World"]);

  comparison.innerHTML = buildGrid();
  window.conjointExport = buildExport();

  try {
    await ScenariosModule.ensureDataLoaded("data/", "ineq_IT_2035.csv");   // flat 1.5% growth (B family)
    document.getElementById("statusMsg").textContent = "";
    SIDES.forEach(s => updateSide(s.id));
  } catch (err) {
    document.getElementById("statusMsg").textContent =
      "Caricamento dei dati non riuscito: " + err.message + " — apri questa pagina tramite un web server.";
  }
})();
