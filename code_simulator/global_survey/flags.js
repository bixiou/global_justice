/**
 * flags.js
 *
 * Drawn country flags for the conjoint pages. The emoji flags do not render on Windows and on
 * several mobile browsers, so every flag is emitted as inline SVG instead — the same reason
 * IT_survey drew its tricolour in CSS. (The globe emoji does render, so the world panel keeps it.)
 *
 * Every flag shares a 60x40 (3:2) viewBox so the icons line up whatever the country's official
 * ratio. They are schematic on purpose: at the ~18px they are displayed only the broad structure
 * reads, so emblems are reduced to a recognisable mark rather than reproduced.
 *
 * Public API:
 *   FlagsModule.flagSvg(iso) – ISO2 country code -> an <svg class="flag"> string.
 *
 * Styling lives in compare.css (.flag). Wrapped in an IIFE because the drawing
 * helpers have deliberately generic names (rect, path, star ...) and every script on the page
 * shares one global scope, so only FlagsModule may escape.
 */

"use strict";

(function () {

// ─── Shape helpers ────────────────────────────────────────────────────────────
const rect = (x, y, w, h, f) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${f}"/>`;
const circ = (cx, cy, r, f) => `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${f}"/>`;
const poly = (pts, f) => `<polygon points="${pts}" fill="${f}"/>`;
const path = (d, stroke, w, fill) =>
  `<path d="${d}" stroke="${stroke || "none"}" stroke-width="${w || 0}" fill="${fill || "none"}"/>`;

/** n-pointed star (default: the usual 5-pointed one), `rot` in degrees, 0 = point up. */
function star(cx, cy, r, f, rot, n, ratio) {
  n = n || 5; ratio = ratio || 0.382;
  const pts = [];
  for (let i = 0; i < 2 * n; i++) {
    const a = Math.PI * i / n - Math.PI / 2 + (rot || 0) * Math.PI / 180;
    const rr = i % 2 ? r * ratio : r;
    pts.push((cx + rr * Math.cos(a)).toFixed(2) + "," + (cy + rr * Math.sin(a)).toFixed(2));
  }
  return poly(pts.join(" "), f);
}

const vert = (a, b, c) => rect(0, 0, 20, 40, a) + rect(20, 0, 20, 40, b) + rect(40, 0, 20, 40, c);
const horiz = (a, b, c) => rect(0, 0, 60, 13.34, a) + rect(0, 13.33, 60, 13.34, b) +
                           rect(0, 26.66, 60, 13.34, c);
/** Crescent: a white disc with a smaller disc of the background colour cut out of it. */
const crescent = (cx, cy, r, bg) => circ(cx, cy, r, "#fff") + circ(cx + r * 0.4, cy, r * 0.8, bg);

/** The Union Jack over the full 60x40 box (reused at half scale in the Australian canton). */
const unionJack = () =>
  rect(0, 0, 60, 40, "#012169") +
  path("M0,0 L60,40 M60,0 L0,40", "#ffffff", 9) +
  path("M0,0 L60,40 M60,0 L0,40", "#C8102E", 3.6) +
  path("M30,0 V40 M0,20 H60", "#ffffff", 13) +
  path("M30,0 V40 M0,20 H60", "#C8102E", 7.5);

// ─── The flags ────────────────────────────────────────────────────────────────
// One entry per country bundled in data/*.csv, keyed by ISO2.
const FLAGS = {
  // Vertical tricolours
  IT: () => vert("#009246", "#ffffff", "#CE2B37"),
  FR: () => vert("#002395", "#ffffff", "#ED2939"),
  PE: () => vert("#D91023", "#ffffff", "#D91023"),
  NG: () => vert("#008751", "#ffffff", "#008751"),
  MX: () => vert("#006847", "#ffffff", "#CE1126") +
            circ(30, 20, 3.2, "#7B3F00") + circ(30, 22.5, 2.4, "#0A6B3D"),

  // Horizontal bands
  DE: () => horiz("#000000", "#DD0000", "#FFCE00"),
  RU: () => horiz("#ffffff", "#0039A6", "#D52B1E"),
  IN: () => horiz("#FF9933", "#ffffff", "#138808") +
            circ(30, 20, 5, "#000080") + circ(30, 20, 3.6, "#ffffff") +
            star(30, 20, 4.6, "#000080", 0, 12, 0.9) + circ(30, 20, 1.2, "#000080"),
  EG: () => horiz("#CE1126", "#ffffff", "#000000") +
            poly("30,15 34,19 30,25 26,19", "#C09300") + rect(28.5, 24, 3, 2, "#C09300"),
  ET: () => horiz("#078930", "#FCDD09", "#DA121A") +
            circ(30, 20, 9, "#0F47AF") + star(30, 20, 6.5, "#FCDD09"),
  KE: () => rect(0, 0, 60, 11, "#000000") + rect(0, 11, 60, 2, "#ffffff") +
            rect(0, 13, 60, 14, "#BB0000") + rect(0, 27, 60, 2, "#ffffff") +
            rect(0, 29, 60, 11, "#006600") +
            path("M23,9 L37,31 M37,9 L23,31", "#ffffff", 1.6) +
            `<ellipse cx="30" cy="20" rx="4.2" ry="7.5" fill="#BB0000" stroke="#fff" stroke-width="1.1"/>`,
  ID: () => rect(0, 0, 60, 20, "#CE1126") + rect(0, 20, 60, 20, "#ffffff"),

  // A disc or a star on a plain ground
  JP: () => rect(0, 0, 60, 40, "#ffffff") + circ(30, 20, 12, "#BC002D"),
  BD: () => rect(0, 0, 60, 40, "#006A4D") + circ(27, 20, 11, "#F42A41"),
  VN: () => rect(0, 0, 60, 40, "#DA251D") + star(30, 20, 11, "#FFFF00"),
  CN: () => rect(0, 0, 60, 40, "#EE1C25") + star(12, 11, 7, "#FFDE00") +
            star(23, 4, 2.6, "#FFDE00") + star(28, 9, 2.6, "#FFDE00") +
            star(28, 16, 2.6, "#FFDE00") + star(23, 21, 2.6, "#FFDE00"),
  TR: () => rect(0, 0, 60, 40, "#E30A17") + crescent(23, 20, 9, "#E30A17") +
            star(36, 20, 4.4, "#ffffff", 15),
  PK: () => rect(0, 0, 60, 40, "#01411C") + rect(0, 0, 15, 40, "#ffffff") +
            crescent(35, 21, 8.5, "#01411C") + star(45, 12, 3.8, "#ffffff", 15),

  // Canton flags
  US: () => Array.from({ length: 13 }, (_, i) =>
              rect(0, i * 40 / 13, 60, 40 / 13, i % 2 ? "#ffffff" : "#B22234")).join("") +
            rect(0, 0, 24, 40 * 7 / 13, "#3C3B6E") +
            Array.from({ length: 20 }, (_, i) =>
              circ(2.8 + (i % 5) * 4.6, 3.2 + Math.floor(i / 5) * 5, 1.1, "#ffffff")).join(""),
  GB: () => unionJack(),
  AU: () => rect(0, 0, 60, 40, "#00247D") +
            `<g transform="scale(0.5)">${unionJack()}</g>` +
            star(15, 30, 4.6, "#ffffff", 0, 7, 0.5) +
            star(46, 9, 3, "#ffffff") + star(53, 20, 3, "#ffffff") + star(46, 31, 3, "#ffffff") +
            star(38.5, 22, 2.4, "#ffffff") + star(50, 14, 1.7, "#ffffff"),
  TW: () => rect(0, 0, 60, 40, "#FE0000") + rect(0, 0, 30, 20, "#000095") +
            star(15, 10, 8, "#ffffff", 0, 12, 0.55) + circ(15, 10, 4, "#ffffff"),

  // One-off designs
  CA: () => rect(0, 0, 15, 40, "#FF0000") + rect(45, 0, 15, 40, "#FF0000") +
            poly("30,10 31.8,14.2 35.4,13.4 34.3,17 38,16.4 36.3,19.2 39.4,20.6 36.6,22.2 " +
                 "37.7,24.4 34,23.9 34.6,27 31.4,25.4 31.8,30 30,28.4 28.2,30 28.6,25.4 " +
                 "25.4,27 26,23.9 22.3,24.4 23.4,22.2 20.6,20.6 23.7,19.2 22,16.4 25.7,17 " +
                 "24.6,13.4 28.2,14.2", "#FF0000"),
  KR: () => rect(0, 0, 60, 40, "#ffffff") +
            path("M22,20 a8,8 0 0 1 16,0 a4,4 0 0 1 -8,0 a4,4 0 0 0 -8,0", null, 0, "#CD2E3A") +
            path("M22,20 a4,4 0 0 1 8,0 a4,4 0 0 0 8,0 a8,8 0 0 1 -16,0", null, 0, "#0047A0") +
            [[8, 8], [8, 32], [52, 8], [52, 32]].map(([x, y]) =>
              [-2.6, 0, 2.6].map(d => rect(x - 4, y + d - 0.55, 8, 1.1, "#000000")).join("")).join(""),
  BR: () => rect(0, 0, 60, 40, "#009B3A") + poly("30,4 56,20 30,36 4,20", "#FEDF00") +
            circ(30, 20, 8.4, "#002776") +
            path("M22.4,23.4 Q30,17.4 37.8,22.2", "#ffffff", 2.4) +
            circ(26, 17, 0.8, "#ffffff") + circ(31, 15.5, 0.8, "#ffffff") +
            circ(34.5, 18, 0.8, "#ffffff"),
  ZA: () => rect(0, 0, 60, 20, "#E03C31") + rect(0, 20, 60, 20, "#002395") +
            path("M0,2 L26,20 L60,20 M0,38 L26,20", "#ffffff", 13) +
            path("M0,2 L26,20 L60,20 M0,38 L26,20", "#007A4D", 7.5) +
            poly("0,0 23,20 0,40", "#FFB612") + poly("0,4.5 17,20 0,35.5", "#000000"),
  ES: () => rect(0, 0, 60, 10, "#AA151B") + rect(0, 10, 60, 20, "#F1BF00") +
            rect(0, 30, 60, 10, "#AA151B") +
            path("M14,15 h7 v6 a3.5,3.5 0 0 1 -7,0 z", "#AA151B", 1.2, "#F1BF00"),
  SA: () => rect(0, 0, 60, 40, "#006C35") +
            rect(12, 13, 36, 1.8, "#ffffff") + rect(16, 17.5, 28, 1.8, "#ffffff") +
            rect(14, 25, 30, 1.6, "#ffffff") + poly("44,25.8 49,25.8 44,29", "#ffffff"),
  CD: () => rect(0, 0, 60, 40, "#007FFF") +
            path("M-6,42 L56,-6", "#F7D618", 14) + path("M-6,42 L56,-6", "#CE1021", 8) +
            star(11, 9, 5.4, "#F7D618")
};

/**
 * Inline SVG for a country's flag, ready to be dropped into a label.
 * @param {string} iso – ISO2 country code
 * @returns {string} – an <svg class="flag"> string, or "" when the code is unknown
 */
function flagSvg(iso) {
  const draw = FLAGS[iso];
  return draw ? `<svg class="flag" viewBox="0 0 60 40" xmlns="http://www.w3.org/2000/svg" ` +
                `aria-hidden="true">${draw()}</svg>` : "";
}

const FlagsModule = { flagSvg, FLAGS };
if (typeof module !== "undefined" && module.exports) module.exports = FlagsModule;
else window.FlagsModule = FlagsModule;

})();
