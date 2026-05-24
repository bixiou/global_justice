'use strict';

// ── constants ─────────────────────────────────────────────────────────────────

const DATA_PATH = '../data/';
const INCOME_YEARS = Array.from({ length: 81 }, (_, i) => 2020 + i);
const DIST_YEARS   = [2025, 2030, 2035, 2050, 2100];

const DIST_COLORS = {
  2025: '#e74c3c',
  2030: '#e67e22',
  2035: '#f39c12',
  2050: '#2ecc71',
  2100: '#27ae60',
};

// ── state ─────────────────────────────────────────────────────────────────────

let incomeCache  = null;  // country code → { gpercentile → { year → income } }
let worldCache   = null;  // gpercentile → { year → income }
let chartEvol    = null;
let chartDist    = null;

// ── CSV parser ────────────────────────────────────────────────────────────────

function parseCSV(text) {
  const lines  = text.trim().split('\n');
  const header = parseCSVLine(lines[0]);
  return lines.slice(1).map(line => {
    const vals = parseCSVLine(line);
    const obj  = {};
    header.forEach((h, i) => { obj[h] = vals[i]; });
    return obj;
  });
}

function parseCSVLine(line) {
  const result = [];
  let cur = '', inQ = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') { inQ = !inQ; continue; }
    if (ch === ',' && !inQ) { result.push(cur.trim()); cur = ''; continue; }
    cur += ch;
  }
  result.push(cur.trim());
  return result;
}

// ── data loading ──────────────────────────────────────────────────────────────

async function loadIncomeData() {
  if (incomeCache) return;
  showStatus('Loading income data (this may take a few seconds)…');
  const res  = await fetch(DATA_PATH + 'income.csv');
  const text = await res.text();
  const rows = parseCSV(text);

  incomeCache = {};
  for (const row of rows) {
    const ctry = row.country;
    const pct  = parseInt(row.gpercentile, 10);
    if (!incomeCache[ctry]) incomeCache[ctry] = {};
    const byYear = {};
    INCOME_YEARS.forEach(y => {
      byYear[y] = parseFloat(row[`income_${y}`]);
    });
    incomeCache[ctry][pct] = byYear;
  }
  showStatus('');
}

async function loadWorldData() {
  if (worldCache) return;
  const res  = await fetch(DATA_PATH + 'income_world.csv');
  const text = await res.text();
  const rows = parseCSV(text);

  worldCache = {};
  for (const row of rows) {
    const pct = parseInt(row.gpercentile, 10);
    const byYear = {};
    DIST_YEARS.forEach(y => {
      byYear[y] = parseFloat(row[`income_${y}`]);
    });
    worldCache[pct] = byYear;
  }
}

// ── percentile lookup ─────────────────────────────────────────────────────────

function findPercentile(countryCode, incomeEurPPP) {
  const byPct = incomeCache[countryCode];
  if (!byPct) return null;

  // Find the percentile whose income_2025 is closest to the user's income
  let best = 1, bestDiff = Infinity;
  for (let p = 1; p <= 100; p++) {
    if (!byPct[p]) continue;
    const diff = Math.abs(byPct[p][2025] - incomeEurPPP);
    if (diff < bestDiff) { bestDiff = diff; best = p; }
  }
  return best;
}

// ── chart helpers ─────────────────────────────────────────────────────────────

function destroyChart(ref) {
  if (ref) { try { ref.destroy(); } catch (_) {} }
}

function formatIncome(eurPPP, pppRate) {
  const local = eurPPP * pppRate;
  if (local >= 1e6)  return (local / 1e6).toFixed(1) + 'M';
  if (local >= 1e3)  return (local / 1e3).toFixed(0) + 'k';
  return local.toFixed(0);
}

// ── evolution chart ───────────────────────────────────────────────────────────

function renderEvolution(countryCode, percentile, currency, pppRate) {
  const byYear = incomeCache[countryCode][percentile];
  const labels = INCOME_YEARS;
  const data   = INCOME_YEARS.map(y => +(byYear[y] * pppRate).toFixed(0));

  destroyChart(chartEvol);
  const ctx = document.getElementById('chart-evolution').getContext('2d');
  chartEvol = new Chart(ctx, {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: `Income (${currency}/year)`,
        data,
        borderColor: '#2980b9',
        backgroundColor: 'rgba(41,128,185,0.08)',
        pointRadius: 0,
        borderWidth: 2,
        tension: 0.3,
      }],
    },
    options: {
      responsive: true,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { display: false },
        title: {
          display: true,
          text: `Your income trajectory under the Sustainable Convergence scenario`,
          font: { size: 14 },
        },
        tooltip: {
          callbacks: {
            label: ctx => ` ${ctx.parsed.y.toLocaleString()} ${currency}/year`,
          },
        },
      },
      scales: {
        x: {
          title: { display: true, text: 'Year' },
          ticks: { maxTicksLimit: 10 },
        },
        y: {
          title: { display: true, text: `Annual income (${currency})` },
          ticks: {
            callback: v => v >= 1e6 ? (v/1e6).toFixed(1)+'M'
                         : v >= 1e3 ? (v/1e3).toFixed(0)+'k'
                         : v,
          },
        },
      },
    },
  });
}

// Find the user's global percentile at a given year based on their EUR PPP income
function findWorldPercentile(incomeEurPPP, year) {
  let best = 1, bestDiff = Infinity;
  for (let p = 1; p <= 100; p++) {
    if (!worldCache[p]) continue;
    const diff = Math.abs(worldCache[p][year] - incomeEurPPP);
    if (diff < bestDiff) { bestDiff = diff; best = p; }
  }
  return best;
}

// ── distribution chart ────────────────────────────────────────────────────────

function renderDistribution(userIncomesByYearEur, currency, pppRate) {
  const percentiles = Array.from({ length: 100 }, (_, i) => i + 1);

  const datasets = DIST_YEARS.map(yr => ({
    label: String(yr),
    data: percentiles.map(p => +(worldCache[p][yr] * pppRate).toFixed(0)),
    borderColor: DIST_COLORS[yr],
    backgroundColor: DIST_COLORS[yr],
    pointRadius: 0,
    borderWidth: yr === 2025 ? 2.5 : 2,
    tension: 0.3,
    fill: false,
  }));

  // User dot on each year's curve: placed at global percentile
  const dotDatasets = DIST_YEARS.map(yr => {
    const userEur  = userIncomesByYearEur[yr];
    const globalPct = findWorldPercentile(userEur, yr);
    return {
      label: `You (${yr})`,
      data: percentiles.map(p => p === globalPct ? +(userEur * pppRate).toFixed(0) : null),
      borderColor: DIST_COLORS[yr],
      backgroundColor: DIST_COLORS[yr],
      pointRadius: percentiles.map(p => p === globalPct ? 8 : 0),
      pointStyle: 'circle',
      showLine: false,
      order: 0,
    };
  });

  destroyChart(chartDist);
  const ctx = document.getElementById('chart-distribution').getContext('2d');
  chartDist = new Chart(ctx, {
    type: 'line',
    data: {
      labels: percentiles,
      datasets: [...datasets, ...dotDatasets],
    },
    options: {
      responsive: true,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: {
          display: true,
          labels: {
            filter: item => !item.text.startsWith('You'),
            usePointStyle: true,
          },
        },
        title: {
          display: true,
          text: 'World income distribution — Sustainable Convergence scenario',
          font: { size: 14 },
        },
        tooltip: {
          callbacks: {
            label: ctx => {
              if (ctx.parsed.y === null) return null;
              return ` ${ctx.dataset.label}: ${ctx.parsed.y.toLocaleString()} ${currency}/year`;
            },
            filter: item => item.parsed.y !== null,
          },
        },
      },
      scales: {
        x: {
          title: { display: true, text: 'Humans, from poorest to richest (global percentile)' },
          ticks: { maxTicksLimit: 10 },
        },
        y: {
          title: { display: true, text: `Annual income (${currency})` },
          max: Math.ceil(worldCache[99][2025] * pppRate / 1000) * 1000,
          ticks: {
            callback: v => v >= 1e6 ? (v/1e6).toFixed(1)+'M'
                         : v >= 1e3 ? (v/1e3).toFixed(0)+'k'
                         : v,
          },
        },
      },
    },
  });
}

// ── UI helpers ────────────────────────────────────────────────────────────────

function showStatus(msg) {
  document.getElementById('status').textContent = msg;
}

function showError(msg) {
  const el = document.getElementById('error-msg');
  el.textContent = msg;
  el.style.display = msg ? 'block' : 'none';
}

function updateCurrencyLabel() {
  const code  = document.getElementById('country-select').value;
  const info  = COUNTRY_MAP[code];
  const label = info ? info.currency : 'EUR';
  document.getElementById('currency-label').textContent = label;
}

function populateCountries() {
  const sel = document.getElementById('country-select');

  // Individual countries: 2-char codes that don't start with 'O' and aren't 'QM'
  const isCountry = c => c.code.length === 2 && !c.code.startsWith('O') && c.code !== 'QM';
  const byName    = (a, b) => a.name.localeCompare(b.name);

  const countries = COUNTRIES.filter(isCountry).sort(byName);
  const regions   = COUNTRIES.filter(c => !isCountry(c)).sort(byName);

  for (const c of [...countries, ...regions]) {
    const opt = document.createElement('option');
    opt.value = c.code;
    opt.textContent = `${c.name} (${c.currency})`;
    sel.appendChild(opt);
  }

  sel.value = 'FR';
  updateCurrencyLabel();
}

// ── main handler ──────────────────────────────────────────────────────────────

async function onCalculate() {
  showError('');
  const countryCode = document.getElementById('country-select').value;
  const localIncome = parseFloat(document.getElementById('income-input').value);

  if (!countryCode) { showError('Please select a country.'); return; }
  if (isNaN(localIncome) || localIncome <= 0) { showError('Please enter a valid positive annual income.'); return; }

  const info       = COUNTRY_MAP[countryCode];
  const pppRate    = info.pppRate;
  const currency   = info.currency;
  const incomeEur  = localIncome / pppRate;

  try {
    await Promise.all([loadIncomeData(), loadWorldData()]);
  } catch (e) {
    showError('Failed to load data. Make sure the data files are in ../data/ relative to this page.');
    console.error(e);
    return;
  }

  const percentile = findPercentile(countryCode, incomeEur);
  if (!percentile) {
    showError(`No income data found for country "${countryCode}".`);
    return;
  }

  // User's income trajectory (in EUR PPP, all years)
  const byYear = incomeCache[countryCode][percentile];
  // For distribution chart: income at each dist-year in EUR PPP
  const userIncomesByYearEur = {};
  DIST_YEARS.forEach(y => { userIncomesByYearEur[y] = byYear[y]; });

  // Summary
  document.getElementById('result-summary').innerHTML =
    `You are at approximately the <strong>${percentile}th percentile</strong> of your country's ` +
    `income distribution in 2025 (${localIncome.toLocaleString()} ${currency}/year ≈ ` +
    `${Math.round(incomeEur).toLocaleString()} EUR PPP 2025/year).`;
  document.getElementById('result-section').style.display = 'block';

  renderEvolution(countryCode, percentile, currency, pppRate);
  renderDistribution(userIncomesByYearEur, currency, pppRate);
}

// ── init ──────────────────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', () => {
  populateCountries();
  document.getElementById('country-select').addEventListener('change', updateCurrencyLabel);
  document.getElementById('calculate-btn').addEventListener('click', onCalculate);
  document.getElementById('income-input').addEventListener('keydown', e => {
    if (e.key === 'Enter') onCalculate();
  });
});
