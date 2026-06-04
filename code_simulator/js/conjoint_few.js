/**
 * conjoint_few.js — split-screen scenario comparison with a SCENARIO PICKER.
 *
 * Identical to conjoint_any.js except the top input: each side picks a named scenario
 * (those exported in ineq_IT_2035) rather than free parameters, and a single shared
 * household income locates the respondent inside every scenario. The bottom shows the
 * seven displayed features; the 2035 distribution is not shown, and each side has two
 * 2100 inequality charts (Italy, World) reproducing inequality_figures.R.
 */
"use strict";

const SIDES = [{ id: "L", cls: "left", name: "Left" }, { id: "R", cls: "right", name: "Right" }];

// Named scenarios (ineq_IT_2035 columns that also have 2100 distributions) → parameters.
const SCENARIO_PARAMS = {
  SC:    { label: "SC — Sustainable Convergence (60k)", hoursPerWeek: 35, nationalRedistribution: "SN",      globalRedistribution: "GIT",     publicServices: "increased", beefAndFlights: "both" },
  SCmat: { label: "SCmat — SC, no sectoral change",     hoursPerWeek: 35, nationalRedistribution: "SN",      globalRedistribution: "GIT",     publicServices: "stable",    beefAndFlights: "none" },
  MC:    { label: "MC — Moderate Convergence (40h)",    hoursPerWeek: 40, nationalRedistribution: "SN",      globalRedistribution: "GIT",     publicServices: "increased", beefAndFlights: "both" },
  SC45k: { label: "SC-45k (30h)",                       hoursPerWeek: 30, nationalRedistribution: "SN",      globalRedistribution: "GIT",     publicServices: "increased", beefAndFlights: "both" },
  SC15k: { label: "SC-15k (25h)",                       hoursPerWeek: 25, nationalRedistribution: "SN",      globalRedistribution: "GIT",     publicServices: "increased", beefAndFlights: "both" },
  PC:    { label: "PC — Productivist Convergence (120k)",hoursPerWeek: 45, nationalRedistribution: "SN",      globalRedistribution: "GIT",     publicServices: "stable",    beefAndFlights: "none" },
  PI:    { label: "PI — Persistent Inequality",         hoursPerWeek: 45, nationalRedistribution: "current", globalRedistribution: "current", publicServices: "stable",    beefAndFlights: "none" },
  SI:    { label: "SI — no redistribution",             hoursPerWeek: 35, nationalRedistribution: "current", globalRedistribution: "current", publicServices: "increased", beefAndFlights: "both" },
  SN:    { label: "SN — national redistribution only",  hoursPerWeek: 35, nationalRedistribution: "SN",      globalRedistribution: "current", publicServices: "increased", beefAndFlights: "both" },
  SG:    { label: "SG — global redistribution only",    hoursPerWeek: 35, nationalRedistribution: "current", globalRedistribution: "GIT",     publicServices: "increased", beefAndFlights: "both" }
};

// ─── inequality-figure styling (mirrors inequality_figures.R) ────────────────────
const GRP_COL = { bottom: "#2166AC", median: "#4DAC26", top: "#D6604D", other: "#D9D9D9" };
const GRP_OF = { p0p5: "bottom", p5p10: "bottom", p45p50: "median", p50p55: "median",
                 p90p95: "top", p95p99: "top", p99p100: "top" };
function groupOf(b) { return GRP_OF[b] || "other"; }
// Inline Italian flag drawn as SVG (the 🇮🇹 regional-indicator emoji renders as "IT" on Windows).
const FLAG_IT = '<svg viewBox="0 0 3 2" width="18" height="12" style="vertical-align:-2px;margin-right:5px;border:0.5px solid #bbb"><rect width="1" height="2" fill="#009246"/><rect x="1" width="1" height="2" fill="#fff"/><rect x="2" width="1" height="2" fill="#ce2b37"/></svg>';
const LABELS = {
  IT:    { title: FLAG_IT + "Monthly incomes of Italians in 2100",
           bottom: "10% poorest Italians", median: "Typical income", top: "10% richest Italians" },
  World: { title: "🌍 Monthly incomes worldwide in 2100",
           bottom: "10% poorest humans", median: "Typical income", top: "10% richest humans" }
};
// Unit-rounded, space as thousands separator (e.g. 23847 → "€23 847").
const fmtEur = n => "€" + Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ");
const charts = {};

const YLIM_MONTHLY = 30000;        // monthly-income y-limit for the inequality bars
const HATCH_FROM_MONTHLY = 26000;  // clipped bars get a thin hatched cap in this top band (26k..30k)
// Thin white diagonal hatch over a bar's colour, used to cap bars clipped by the y-limit.
const _hatch = {};
function hatchFor(color) {
  if (_hatch[color]) return _hatch[color];
  const s = 4, cv = document.createElement("canvas"); cv.width = cv.height = s;
  const x = cv.getContext("2d");
  x.fillStyle = color; x.fillRect(0, 0, s, s);
  // Thin white stripes; small tile so the red gap equals one (thin) stripe width (lineWidth = s/(2√2)).
  x.strokeStyle = "rgba(255,255,255,0.95)"; x.lineWidth = s / (2 * Math.SQRT2);
  x.beginPath();
  x.moveTo(0, s);     x.lineTo(s, 0);      // x+y = s
  x.moveTo(-s, s);    x.lineTo(s, -s);     // x+y = 0  (top-left corner)
  x.moveTo(0, 2 * s); x.lineTo(2 * s, 0);  // x+y = 2s (bottom-right corner)
  x.stroke();
  return (_hatch[color] = x.createPattern(cv, "repeat"));
}

// ─── shared rendering (identical to conjoint_any.js) ─────────────────────────────
// Each bracket is expanded into 1%-wide unit slots so bar widths match bracket sizes:
// 19 brackets × 5%, then p95p99 = 4% and p99p100 = 1% (100 slots total).
function renderInequality(canvasId, brackets, annualValues) {
  const slotV = [], slotC = [], slotB = [];
  brackets.forEach((b, i) => {
    const m = b.match(/p([\d.]+)p([\d.]+)/);
    const w = Math.max(1, Math.round((+m[2]) - (+m[1])));   // bracket width in % points
    const v = Math.round(annualValues[i] / 12), col = GRP_COL[groupOf(b)];
    for (let s = 0; s < w; s++) { slotV.push(v); slotC.push(col); slotB.push(b); }
  });
  // Clipped bars (value > ylim) keep a solid body up to HATCH_FROM and a thin hatched cap in the
  // top band (HATCH_FROM..ylim); other bars stay fully solid. Built as two stacked datasets.
  const solidV = slotV.map(v => v > YLIM_MONTHLY ? HATCH_FROM_MONTHLY : v);
  const capV   = slotV.map(v => v > YLIM_MONTHLY ? YLIM_MONTHLY - HATCH_FROM_MONTHLY : 0);
  const capBG  = slotC.map(col => hatchFor(col));
  if (charts[canvasId]) charts[canvasId].destroy();
  charts[canvasId] = new Chart(document.getElementById(canvasId).getContext("2d"), {
    type: "bar",
    data: { labels: slotB, datasets: [
      { data: solidV, backgroundColor: slotC, borderWidth: 0, categoryPercentage: 1.0, barPercentage: 1.0, stack: "s" },
      { data: capV,   backgroundColor: capBG, borderWidth: 0, categoryPercentage: 1.0, barPercentage: 1.0, stack: "s" }
    ] },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { display: false },
        tooltip: { filter: item => item.datasetIndex === 0,
                   callbacks: { title: items => slotB[items[0].dataIndex],
                                label: c => " " + fmtEur(slotV[c.dataIndex]) + "/month" } } },
      scales: {
        x: { stacked: true, display: false, grid: { display: false } },
        y: { stacked: true, min: 0, max: YLIM_MONTHLY, ticks: { callback: v => "€" + (v >= 1000 ? Math.round(v/1000) + "k" : Math.round(v)),
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
         <span><span style="color:${GRP_COL[g]};font-weight:700">${fmtEur(meanOf(g))}</span>/month</span></div></div>`
  ).join("");
}

// Public-services / beef & flights phrase boxes.
const BF_TXT = { none: "Same behavior", beef: "Less beef", flights: "Less flights", both: "Less beef<br>Less flights" };
function setFeatureChips(side, params) {
  document.getElementById("ps-" + side).textContent =
    params.publicServices === "increased" ? "More public services" : "Stable public services";
  document.getElementById("bf-" + side).innerHTML = BF_TXT[params.beefAndFlights];
}

function resultPanelHTML(side) {
  return `
    <div class="side-title" id="title-${side}"></div>
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

  document.getElementById("title-" + side).textContent = sideTitle(side, f);
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

// ─── per-page input handling (the ONLY part that differs from conjoint_any.js) ────

function inputPanelHTML(side) {
  const opts = Object.keys(SCENARIO_PARAMS).map((k, i) =>
    `<option value="${k}"${i === 0 ? " selected" : ""}>${SCENARIO_PARAMS[k].label}</option>`).join("");
  return `
    <div class="card">
      <div class="side-title">${SIDES.find(s => s.id === side).name} scenario</div>
      <div class="field"><label>Scenario</label>
        <select id="scen-${side}">${opts}</select></div>
    </div>`;
}

function getParams(side) {
  const sc = document.getElementById("scen-" + side).value;
  const p  = SCENARIO_PARAMS[sc];
  return {
    householdIncomeMonthly: parseFloat(document.getElementById("sharedIncome").value) || 2500,
    isCouple:        document.getElementById("sharedCouple").checked,
    decarbonization: "FD",
    hoursPerWeek:    p.hoursPerWeek,
    nationalRedistribution: p.nationalRedistribution,
    globalRedistribution:   p.globalRedistribution,
    publicServices:  p.publicServices,
    beefAndFlights:  p.beefAndFlights
  };
}

function sideTitle(side) {
  return SCENARIO_PARAMS[document.getElementById("scen-" + side).value].label;
}

// ─── init ──────────────────────────────────────────────────────────────────────
(async function init() {
  const controls = document.getElementById("controls");
  const comparison = document.getElementById("comparison");
  SIDES.forEach((s, i) => {
    const ci = document.createElement("div"); ci.className = "side " + s.cls; ci.innerHTML = inputPanelHTML(s.id); controls.appendChild(ci);
    const cr = document.createElement("div"); cr.className = "side " + s.cls; cr.innerHTML = resultPanelHTML(s.id); comparison.appendChild(cr);
  });
  // Default the two sides to different scenarios for an informative first view.
  const keys = Object.keys(SCENARIO_PARAMS);
  if (keys.length > 1) document.getElementById("scen-R").value = keys[6]; // PI

  try {
    await ScenariosModule.ensureDataLoaded("data/");
    document.getElementById("statusMsg").textContent = "Pick a scenario on either side, or change the income, to compare.";
    SIDES.forEach(s => updateSide(s.id));
  } catch (err) {
    document.getElementById("statusMsg").textContent =
      "Failed to load data: " + err.message + " — serve this page via a web server.";
    return;
  }
  controls.querySelectorAll("select").forEach(el =>
    el.addEventListener("change", () => updateSide(el.id.split("-").pop())));
  // Shared income/couple affect both sides.
  ["sharedIncome", "sharedCouple"].forEach(id =>
    document.getElementById(id).addEventListener("change", () => SIDES.forEach(s => updateSide(s.id))));
})();
