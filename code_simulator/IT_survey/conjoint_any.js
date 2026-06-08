/**
 * conjoint_any.js — split-screen scenario comparison with FREE PARAMETERS.
 *
 * Each side (left/right) carries the full underlying-parameter form (as in scenarios.js).
 * The bottom updates dynamically with the seven displayed features. The 2035 distribution
 * is NOT shown; instead each side has two 2100 inequality charts (Italy, World) that
 * reproduce the layout of inequality_figures.R (monthly income, coloured brackets + caption).
 *
 * Companion file conjoint_few.js is identical except the top input (scenario dropdown).
 */
"use strict";

const SIDES = [{ id: "L", cls: "left", name: "Left" }, { id: "R", cls: "right", name: "Right" }];

// Redistribution selector → underlying national/global parameters
const REDIST_MAP = {
  both:     { nationalRedistribution: "SN",      globalRedistribution: "GIT" },
  global:   { nationalRedistribution: "current", globalRedistribution: "GIT" },
  national: { nationalRedistribution: "SN",      globalRedistribution: "current" },
  none:     { nationalRedistribution: "current", globalRedistribution: "current" }
};

// ─── inequality-figure styling (mirrors inequality_figures.R) ────────────────────
const GRP_COL = { bottom: "#2166AC", median: "#4DAC26", top: "#D6604D", other: "#D9D9D9" };
const GRP_OF = { p0p5: "bottom", p5p10: "bottom", p45p50: "median", p50p55: "median",
                 p90p95: "top", p95p99: "top", p99p100: "top" };
function groupOf(b) { return GRP_OF[b] || "other"; }
// Inline Italian flag drawn as SVG (the 🇮🇹 regional-indicator emoji renders as "IT" on Windows).
const FLAG_IT = '<svg viewBox="0 0 3 2" width="18" height="12" style="vertical-align:-2px;margin-right:5px;border:0.5px solid #bbb"><rect width="1" height="2" fill="#009246"/><rect x="1" width="1" height="2" fill="#fff"/><rect x="2" width="1" height="2" fill="#ce2b37"/></svg>';
const LABELS = {
  IT:    { bottom: "10% più povero in Italia", median: "Reddito tipico", top: "10% più ricco in Italia"},
  World: { bottom: "10% più povero della popolazione", median: "Reddito tipico", top: "10% più ricco della popolazione"}
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
  // Top bracket (p99p100) monthly value, and whether the chart is clipped (→ a hatch is drawn).
  const i99 = brackets.indexOf("p99p100");
  const topMonthly = i99 >= 0 ? Math.round(annualValues[i99] / 12) : 0;
  const hasHatch = topMonthly > YLIM_MONTHLY;
  // Clipped bars (value > ylim) keep a solid body up to HATCH_FROM and a thin hatched cap in the
  // top band (HATCH_FROM..ylim); other bars stay fully solid. Built as two stacked datasets.
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
                                label: c => " " + fmtEur(slotV[c.dataIndex]) + "/month" } } },
      scales: {
        x: { stacked: true, display: false, grid: { display: false } },
        y: { stacked: true, min: 0, max: YLIM_MONTHLY,
             ticks: { callback: v => (v >= YLIM_MONTHLY && hasHatch)
                        ? "€" + Math.round(topMonthly / 10000) * 10 + "k"   // true top of the clipped bar
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
         <span><span style="color:${GRP_COL[g]};font-weight:700">${fmtEur(meanOf(g))}</span>/month</span></div></div>`
  ).join("");
}

// Public-services / beef & flights phrase boxes.
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
    <div class="feat-row">
      <div class="chip temp"><span class="chip-label">Temperature 2100</span>
        <span class="chip-val" id="temp-${side}">—</span></div>
      <div class="chip income"><span class="chip-label">Your income in 2035</span>
        <span class="chip-val" id="inc-${side}">—</span><span class="chip-unit">€/month</span></div>
      <div class="chip"><span class="chip-label">Working hours 2035</span>
        <span class="chip-val" id="hrs-${side}">—</span><span class="chip-unit">h/week</span></div>
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

function updateSide(side) {
  const params = getParams(side);
  let f;
  try { f = ScenariosModule.computeConjointFeatures(params); }
  catch (e) { document.getElementById("statusMsg").textContent = "Error: " + e.message; return; }

  document.getElementById("temp-" + side).textContent = "+" + f.temperature.value.toFixed(1) + "°C";
  document.getElementById("inc-"  + side).textContent = "€" + f.ownIncome.value.toLocaleString("en-US");
  document.getElementById("hrs-"  + side).textContent = f.workingHours.value;
  setFeatureChips(side, params);

  const gi = f.globalIncomes;
  renderInequality("cIT-" + side, gi.brackets, gi.itValues);
  renderCaption("capIT-" + side, gi.brackets, gi.itValues, "IT");
  renderInequality("cW-" + side, gi.brackets, gi.worldValues);
  renderCaption("capW-" + side, gi.brackets, gi.worldValues, "World");
}

// ─── per-page input handling (the ONLY part that differs from conjoint_few.js) ────

function inputPanelHTML(side) {
  return `
    <div class="card">
      <div class="side-title">${SIDES.find(s => s.id === side).name} scenario</div>
      <div class="field"><label>Decarbonization pace</label>
        <select id="decarb-${side}"><option value="SD">Slow (SD)</option>
          <option value="ID">Intermediate (ID)</option><option value="FD" selected>Fast (FD)</option></select></div>
      <div class="field"><label>Working hours</label>
        <select id="hours-${side}"><option value="25">25 h/week</option><option value="30">30 h/week</option>
          <option value="35" selected>35 h/week</option><option value="40">40 h/week</option>
          <option value="45">45 h/week</option></select></div>
      <div class="field"><label>Redistribution</label>
        <select id="redist-${side}"><option value="both" selected>Both</option><option value="global">Global</option>
          <option value="national">National</option><option value="none">None</option></select></div>
      <div class="field"><label>Public services</label>
        <select id="ps-sel-${side}"><option value="stable">Stable</option>
          <option value="increased" selected>Increased</option></select></div>
      <div class="field"><label>Beef &amp; flights</label>
        <select id="bf-sel-${side}"><option value="none">No change</option><option value="beef">−60% beef</option>
          <option value="flights">−50% flights</option><option value="both" selected>Both</option></select></div>
    </div>`;
}

function getParams(side) {
  const redist = document.getElementById("redist-" + side).value;
  return {
    householdIncomeMonthly: parseFloat(document.getElementById("sharedIncome").value) || 2500,
    isCouple:        document.getElementById("sharedCouple").checked,
    decarbonization: document.getElementById("decarb-" + side).value,
    hoursPerWeek:    parseInt(document.getElementById("hours-" + side).value),
    ...REDIST_MAP[redist],
    publicServices:  document.getElementById("ps-sel-" + side).value,
    beefAndFlights:  document.getElementById("bf-sel-" + side).value
  };
}

// ─── init ──────────────────────────────────────────────────────────────────────
(async function init() {
  const controls = document.getElementById("controls");
  const comparison = document.getElementById("comparison");
  SIDES.forEach(s => {
    const ci = document.createElement("div"); ci.className = "side " + s.cls; ci.innerHTML = inputPanelHTML(s.id); controls.appendChild(ci);
    const cr = document.createElement("div"); cr.className = "side " + s.cls; cr.innerHTML = resultPanelHTML(s.id); comparison.appendChild(cr);
  });
  try {
    await ScenariosModule.ensureDataLoaded("data/");
    document.getElementById("statusMsg").textContent = "Adjust the parameters on either side to compare.";
    SIDES.forEach(s => updateSide(s.id));
  } catch (err) {
    document.getElementById("statusMsg").textContent =
      "Failed to load data: " + err.message + " — serve this page via a web server.";
    return;
  }
  controls.querySelectorAll("select, input").forEach(el =>
    el.addEventListener("change", () => {
      const side = el.id.split("-").pop();
      updateSide(side);
    }));
  // Shared income/couple (entered once at the top) affect both sides.
  ["sharedIncome", "sharedCouple"].forEach(id =>
    document.getElementById(id).addEventListener("change", () => SIDES.forEach(s => updateSide(s.id))));
})();
