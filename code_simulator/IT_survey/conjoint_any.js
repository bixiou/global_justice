/**
 * conjoint_any.js — IT survey "variant_any": split-screen conjoint comparison of two
 * RANDOMLY drawn scenarios (free parameters). No user controls: the respondent only chooses
 * between the left and right scenario. Italian UI; reproduces inequality_figures.R layout.
 *
 * Parameter draws (uniform, independent across attributes; redraw if both sides are identical):
 *   – hours worked in 2035 ∈ {32, 36, 40, 44}  (→ 2100-target class 30/35/40/45)
 *   – decarbonization      ∈ {SD, ID, FD}
 *   – beef & flights       ∈ {both, beef, flights, none}
 *   – public services      ∈ {increased, stable}
 *   – redistribution       ∈ {none, national, global, both}
 *
 * Income/couple use DEFAULT values (placeholder) — TODO: feed these automatically from the
 * respondent's earlier answers (e.g. via URL query params or a global injected by the survey tool).
 *
 * Companion files: conjoint_few.js (named-scenario pairs) and conjoint_any2.js (2%-growth dataset).
 */
"use strict";

// ─── Respondent income placeholder (TODO: feed automatically from survey answers) ───────────────
const DEFAULT_INCOME_MONTHLY = 2500;   // household monthly cash income (EUR)
const DEFAULT_IS_COUPLE      = false;

const SIDES = [{ id: "L", cls: "left", name: "Sinistra" }, { id: "R", cls: "right", name: "Destra" }];

// Redistribution selector → underlying national/global parameters
const REDIST_MAP = {
  both:     { nationalRedistribution: "SN",      globalRedistribution: "GIT" },
  global:   { nationalRedistribution: "current", globalRedistribution: "GIT" },
  national: { nationalRedistribution: "SN",      globalRedistribution: "current" },
  none:     { nationalRedistribution: "current", globalRedistribution: "current" }
};

// ─── Random draw of the free parameters ─────────────────────────────────────────────────────────
const HOURS_CHOICES  = [32, 36, 40, 44];                       // hours worked in 2035
const HOURS_CLASS    = { 32: 30, 36: 35, 40: 40, 44: 45 };     // → 2100-target class param
const DECARB_CHOICES = ["SD", "ID", "FD"];
const BF_CHOICES     = ["both", "beef", "flights", "none"];
const PS_CHOICES     = ["increased", "stable"];
const REDIST_CHOICES = ["none", "national", "global", "both"];
const pick = arr => arr[Math.floor(Math.random() * arr.length)];

function drawParams() {
  const worked = pick(HOURS_CHOICES);
  const redist = pick(REDIST_CHOICES);
  return {
    workedHours:     worked,
    hoursPerWeek:    HOURS_CLASS[worked],   // class param fed to the engine
    decarbonization: pick(DECARB_CHOICES),
    redist,
    ...REDIST_MAP[redist],
    publicServices:  pick(PS_CHOICES),
    beefAndFlights:  pick(BF_CHOICES)
  };
}
// Signature over the 5 visible attributes (used to guarantee the two sides differ).
const sig = p => [p.workedHours, p.decarbonization, p.beefAndFlights, p.publicServices, p.redist].join("|");

const PARAMS = {};   // side id → drawn parameter object

// ─── inequality-figure styling (mirrors inequality_figures.R) ────────────────────
const GRP_COL = { bottom: "#2166AC", median: "#4DAC26", top: "#D6604D", other: "#D9D9D9" };
const GRP_OF = { p0p5: "bottom", p5p10: "bottom", p45p50: "median", p50p55: "median",
                 p90p95: "top", p95p99: "top", p99p100: "top" };
function groupOf(b) { return GRP_OF[b] || "other"; }
const LABELS = {
  IT:    { bottom: "10% più povero in Italia", median: "Reddito tipico", top: "10% più ricco in Italia",
           title: "Disuguaglianza in Italia (2100)" },
  World: { bottom: "10% più povero del mondo", median: "Reddito tipico", top: "10% più ricco del mondo",
           title: "Disuguaglianza nel mondo (2100)" }
};
// Unit-rounded, space as thousands separator (e.g. 23847 → "€23 847").
const fmtEur = n => "€" + Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ");
const charts = {};   // canvasId → Chart instance

const YLIM_MONTHLY = 30000;        // monthly-income y-limit for the inequality bars
const HATCH_FROM_MONTHLY = 26000;  // clipped bars get a hatched cap in this top band (26k..30k)
// Plugin: on each bar clipped by the y-limit (the cap = dataset index 1) draw two crisp white
// diagonal stripes — the 2nd and 3rd rows from the cap top — to flag the truncation.
const capHatchPlugin = {
  id: "capHatch",
  afterDatasetsDraw(chart) {
    const meta = chart.getDatasetMeta(1);
    if (!meta || !chart.data.datasets[1]) return;
    const data = chart.data.datasets[1].data, ctx = chart.ctx;
    ctx.save();
    ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 1.4; ctx.lineCap = "butt";
    meta.data.forEach((bar, i) => {
      if (!(data[i] > 0)) return;                          // only clipped bars
      const wd = bar.width, l = Math.round(bar.x - wd / 2), r = Math.round(bar.x + wd / 2);
      const top = Math.round(bar.y), bot = Math.round(bar.base), bw = r - l;
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
    ctx.restore();
  }
};

// ─── shared rendering ────────────────────────────────────────────────────────────

/** Monthly-income coloured-bracket histogram (annual values in, /12 inside).
 *  Each bracket is expanded into 1%-wide unit slots so bar widths match bracket sizes:
 *  19 brackets × 5%, then p95p99 = 4% and p99p100 = 1% (100 slots total). */
function renderInequality(canvasId, brackets, annualValues) {
  const slotV = [], slotC = [], slotB = [];
  brackets.forEach((b, i) => {
    const m = b.match(/p([\d.]+)p([\d.]+)/);
    const w = Math.max(1, Math.round((+m[2]) - (+m[1])));   // bracket width in % points
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
        y: { stacked: true, min: 0, max: YLIM_MONTHLY,
             ticks: { callback: v => (v >= YLIM_MONTHLY && hasHatch)
                        ? "€" + Math.round(topMonthly / 10000) * 10 + "k"
                        : "€" + (v >= 1000 ? Math.round(v/1000) + "k" : Math.round(v)),
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
    `<div class="cap-row"><div class="cap-sw" style="background:${GRP_COL[g]}"></div>
       <div class="cap-txt"><b style="color:${GRP_COL[g]}">${lab}</b>
         <span><span style="color:${GRP_COL[g]};font-weight:700">${fmtEur(meanOf(g))}</span>/mese</span></div></div>`
  ).join("");
}

// Public-services / beef & flights phrase boxes.
const BF_TXT = {
  none:    "Nessuna variazione",
  beef:    "Meno prodotti bovini (2 porzioni di carne al mese)",
  flights: "Meno voli (2.500 km all'anno)<br>Prezzo dei voli triplica",
  both:    "Meno prodotti bovini (2 porzioni di carne al mese)<br>Meno voli (2.500 km all'anno)<br>Prezzo dei voli triplica"
};
function setFeatureChips(side, params) {
  document.getElementById("ps-" + side).textContent =
    params.publicServices === "increased" ? "Più servizi pubblici" : "Nessuna variazione";
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
  const p = PARAMS[side];
  return {
    householdIncomeMonthly: DEFAULT_INCOME_MONTHLY,   // TODO: feed automatically
    isCouple:               DEFAULT_IS_COUPLE,        // TODO: feed automatically
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
  catch (e) { document.getElementById("statusMsg").textContent = "Errore: " + e.message; return; }

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
async function initVariantAny(it2035File) {
  const comparison = document.getElementById("comparison");
  // Draw two distinct scenarios.
  PARAMS.L = drawParams();
  PARAMS.R = drawParams();
  while (sig(PARAMS.L) === sig(PARAMS.R)) PARAMS.R = drawParams();

  SIDES.forEach(s => {
    const cr = document.createElement("div"); cr.className = "side " + s.cls; cr.innerHTML = resultPanelHTML(s.id);
    comparison.appendChild(cr);
    document.getElementById("title-" + s.id).textContent = s.name;
  });

  try {
    await ScenariosModule.ensureDataLoaded("data/", it2035File);
    document.getElementById("statusMsg").textContent = "Quale dei due scenari preferisci?";
    SIDES.forEach(s => updateSide(s.id));
  } catch (err) {
    document.getElementById("statusMsg").textContent =
      "Caricamento dei dati non riuscito: " + err.message + " — apri questa pagina tramite un web server.";
  }
}

// Default dataset (1%-growth B scenarios). conjoint_any2.js overrides with the 2% file.
if (typeof window !== "undefined" && !window.__SKIP_AUTO_INIT)
  initVariantAny();
