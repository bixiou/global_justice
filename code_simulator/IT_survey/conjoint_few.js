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
 * Scenario roster (label = our display name; code = method nomenclature {type}{scope}{food}_{decarb}):
 *   BC=BC2_FD(35h)·2  BC60k=B90kC2_FD(40h)  BCmat=BC1_FD(35h, food1)  BC45k=B45kC2_FD(30h)
 *   BC120k=B120kC2_FD(45h)  BI120k=B120kI1_FD(45h, no redist)  BI=BI2_FD  BN=BN2_FD  BG=BG2_FD
 *   BCbeef=BC2_FDbeef  BCflight=BC2_FDflight  BC_SD=BC2_SD
 * NOTE (ambiguities flagged to the user): "BC60k" is read as the 40h B90k scenario (the literal
 * "60k" would equal the 35h B and duplicate BC). "BC120k=BC1_FD" is read as B120kC2_FD. The beef/
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
  BC:      { weight: 2, label: "Convergenza B — 36h",                  params: P(35, "SN",      "GIT",     "FD", "increased", "both") },
  BC60k:   { weight: 1, label: "Convergenza B90k — 40h",               params: P(40, "SN",      "GIT",     "FD", "increased", "both") },
  BCmat:   { weight: 1, label: "Convergenza B — 36h, servizi stabili", params: P(35, "SN",      "GIT",     "FD", "stable",    "none") },
  BC45k:   { weight: 1, label: "Convergenza B45k — 32h",               params: P(30, "SN",      "GIT",     "FD", "increased", "both") },
  BC120k:  { weight: 1, label: "Convergenza B120k — 44h",              params: P(45, "SN",      "GIT",     "FD", "increased", "both") },
  BI120k:  { weight: 1, label: "Disuguaglianza B120k — 44h",           params: P(45, "current", "current", "FD", "stable",    "none") },
  BI:      { weight: 1, label: "Disuguaglianza — 36h",                 params: P(35, "current", "current", "FD", "increased", "both") },
  BN:      { weight: 1, label: "Solo redistribuzione nazionale — 36h", params: P(35, "SN",      "current", "FD", "increased", "both") },
  BG:      { weight: 1, label: "Solo redistribuzione globale — 36h",   params: P(35, "current", "GIT",     "FD", "increased", "both") },
  BCbeef:  { weight: 1, label: "Convergenza B — meno voli",            params: P(35, "SN",      "GIT",     "FD", "increased", "flights") },
  BCflight:{ weight: 1, label: "Convergenza B — meno carne",           params: P(35, "SN",      "GIT",     "FD", "increased", "beef") },
  BC_SD:   { weight: 1, label: "Convergenza B — decarbonizz. lenta",   params: P(35, "SN",      "GIT",     "SD", "increased", "both") }
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
           title: "Disuguaglianza in Italia (2100)" },
  World: { bottom: "10% più povero della popolazione", median: "Reddito tipico", top: "10% più ricco della popolazione",
           title: "Disuguaglianza nel mondo (2100)" }
};
const fmtEur = n => "€" + Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ");
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
               ? "€" + Math.round(topMonthly / 10000) * 10 + "k"
               : "€" + (v >= 1000 ? Math.round(v/1000) + "k" : Math.round(v)),
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
    `<div class="cap-row"><div class="cap-sw" style="background:${GRP_COL[g]}"></div>
       <div class="cap-txt"><b style="color:${GRP_COL[g]}">${lab}</b>
         <span><span style="color:${GRP_COL[g]};font-weight:700">${fmtEur(meanOf(g))}</span>/mese</span></div></div>`
  ).join("");
}

const BF_TXT = {
  none:    "Nessuna variazione",
  beef:    "Meno carne bovina (2 porzioni al mese)<br>Prezzo dei voli triplica",
  flights: "Meno voli (2500 km all'anno)<br>Prezzo dei voli triplica",
  both:    "Meno carne bovina (2 porzioni al mese)<br>Meno voli (2500 km all'anno)<br>Prezzo dei voli triplica"
};
function setFeatureChips(side, params) {
  document.getElementById("ps-" + side).textContent =
    params.publicServices === "increased" ? "Più servizi pubblici, meno consumi materiali" : "Nessuna variazione";
  document.getElementById("bf-" + side).innerHTML = BF_TXT[params.beefAndFlights];
}

function resultPanelHTML(side) {
  return `
    <div class="side-title" id="title-${side}"></div>
    <div class="feat-row">
      <div class="chip temp"><span class="chip-label">Temperatura nel 2100</span>
        <span class="chip-val" id="temp-${side}">—</span></div>
      <div class="chip income"><span class="chip-label">Il tuo reddito nel 2035</span>
        <span class="chip-val" id="inc-${side}">—</span><span class="chip-unit">€/mese</span></div>
      <div class="chip"><span class="chip-label">Ore di lavoro nel 2035</span>
        <span class="chip-val" id="hrs-${side}">—</span><span class="chip-unit">ore/sett.</span></div>
      <div class="chip phrase"><span class="chip-val" id="ps-${side}">—</span></div>
      <div class="chip phrase"><span class="chip-val" id="bf-${side}">—</span></div>
    </div>
    <div class="card"><h4>${LABELS.IT.title}</h4>
      <div class="ineq"><div class="ineq-chart"><canvas id="cIT-${side}"></canvas></div>
      <div class="ineq-cap" id="capIT-${side}"></div></div></div>
    <div class="card"><h4>${LABELS.World.title}</h4>
      <div class="ineq"><div class="ineq-chart"><canvas id="cW-${side}"></canvas></div>
      <div class="ineq-cap" id="capW-${side}"></div></div></div>`;
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

  document.getElementById("title-" + side).textContent = SCENARIOS[CHOSEN[side]].label;
  document.getElementById("temp-" + side).textContent = "+" + f.temperature.value.toFixed(1) + "°C";
  document.getElementById("inc-"  + side).textContent = "€" + f.ownIncome.value.toLocaleString("it-IT");
  document.getElementById("hrs-"  + side).textContent = f.workingHours.value;
  setFeatureChips(side, params);

  const gi = f.globalIncomes;
  renderInequality("cIT-" + side, gi.brackets, gi.itValues);
  renderCaption("capIT-" + side, gi.brackets, gi.itValues, "IT");
  renderInequality("cW-" + side, gi.brackets, gi.worldValues);
  renderCaption("capW-" + side, gi.brackets, gi.worldValues, "World");
}

// ─── init ──────────────────────────────────────────────────────────────────────
(async function init() {
  const comparison = document.getElementById("comparison");
  // Slot 1: weighted over all 12; slot 2: weighted over the remaining 11 (distinct pair).
  const allKeys = Object.keys(SCENARIOS);
  CHOSEN.L = weightedPick(allKeys);
  CHOSEN.R = weightedPick(allKeys.filter(k => k !== CHOSEN.L));

  SIDES.forEach(s => {
    const cr = document.createElement("div"); cr.className = "side " + s.cls; cr.innerHTML = resultPanelHTML(s.id);
    comparison.appendChild(cr);
  });

  try {
    await ScenariosModule.ensureDataLoaded("../data/");
    document.getElementById("statusMsg").textContent = "Quale dei due scenari preferisci?";
    SIDES.forEach(s => updateSide(s.id));
  } catch (err) {
    document.getElementById("statusMsg").textContent =
      "Caricamento dei dati non riuscito: " + err.message + " — apri questa pagina tramite un web server.";
  }
})();
