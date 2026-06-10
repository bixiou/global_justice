/**
 * conjoint_any2.js — IT survey "variant_any2": IDENTICAL to variant_any (conjoint_any.js) EXCEPT
 * it loads ineq2_IT_2035.csv (B scenarios at the country-specific F0a productivity growth) instead of
 * ineq_IT_2035.csv (flat 1.5% growth). Self-contained so it can be the only script on its page.
 *
 * Split-screen conjoint comparison of two RANDOMLY drawn scenarios (free parameters). No user
 * controls: the respondent only chooses between the left and right scenario. Italian UI.
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
 * Companion files: conjoint_few.js (named-scenario pairs) and conjoint_any2.js (F0a-growth dataset).
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
           title: `<span class="flag-it"></span> Redditi in Italia` },
  World: { bottom: "10% più povero del mondo", median: "Reddito tipico", top: "10% più ricco del mondo",
           title: "🌍 Redditi nel mondo" }
};
// Unit-rounded, "." as thousands separator, Italian "amount €" order (e.g. 23847 → "23.847 €").
const fmtEur = n => Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".") + " €";
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
                        ? Math.round(topMonthly / 10000) * 10 + "k"
                        : (v >= 1000 ? Math.round(v/1000) + "k" : Math.round(v)),
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
       <span><span style="color:${GRP_COL[g]};font-weight:700">${fmtEur(meanOf(g))}</span>/mese</span></div>`
  ).join("");
}

// Beef & flights phrase text.
const BF_TXT = {
  none:    "Nessuna variazione",
  beef:    "Meno prodotti bovini (2 porzioni di carne al mese)",
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
                      income: `Reddito mensile netto del suo nucleo familiare (attuale: ${DEFAULT_INCOME_MONTHLY.toLocaleString("it-IT")} €/mese)`,
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
      html += `<div class="rlabel ${isAttr ? "rlabel-attr" : "rlabel-dist"}">${title}</div>` +
        (isAttr ? valCell(r, "L") + valCell(r, "R") : distCell(r, "L") + distCell(r, "R"));
    });
  });
  return html;
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
    const p = PARAMS[id];
    return { workedHours: p.workedHours, hoursPerWeek: p.hoursPerWeek,
             decarbonization: p.decarbonization, redistribution: p.redist,
             nationalRedistribution: p.nationalRedistribution, globalRedistribution: p.globalRedistribution,
             publicServices: p.publicServices, beefAndFlights: p.beefAndFlights };
  };
  return {
    variant: "any2",
    rowOrder: { blocks: ORDER.blocks.slice(), r2035: ORDER.r2035.slice(), r2100: ORDER.r2100.slice() },
    sides: { L: sideData("L"), R: sideData("R") }
  };
}

// ─── init ──────────────────────────────────────────────────────────────────────
async function initVariantAny(it2035File) {
  const comparison = document.getElementById("comparison");
  // Draw two distinct scenarios.
  PARAMS.L = drawParams();
  PARAMS.R = drawParams();
  while (sig(PARAMS.L) === sig(PARAMS.R)) PARAMS.R = drawParams();

  // Draw the shared block/row order (same in both panels).
  ORDER.blocks = shuffle(["2035", "2100"]);
  ORDER.r2035  = shuffle(["hours", "income", "bf", "ps"]);
  ORDER.r2100  = shuffle(["temp", "IT", "World"]);

  comparison.innerHTML = buildGrid();
  window.conjointExport = buildExport();

  try {
    await ScenariosModule.ensureDataLoaded("data/", it2035File);
    document.getElementById("statusMsg").textContent = "";
    SIDES.forEach(s => updateSide(s.id));
  } catch (err) {
    document.getElementById("statusMsg").textContent =
      "Caricamento dei dati non riuscito: " + err.message + " — apri questa pagina tramite un web server.";
  }
}

// variant_any2: use the 2%-growth B-scenario dataset.
initVariantAny("ineq2_IT_2035.csv");
