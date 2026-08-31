// Country/region definitions: code, display name, currency code, PPP factor
// pppRate = local currency units per 1 EUR PPP 2025, i.e. the amount of local money that buys what
// 1 PPP euro buys. EUR PPP income = local income / pppRate; local display = EUR PPP x pppRate.
//
// Built as C0p_2025 x nominal EUR exchange rate, where:
//   - C0p is Chancel et al. (2026) Appendix_Macro sheet C0p, "Real Exchange Rate (Euro PPP XR /
//     Euro MER)". Its last observed year is 2025, the same price basis as every income series here.
//   - the nominal rate is open.er-api.com of 2026-08-31, used for every currency. It agrees with the
//     ECB euro reference rates of the same day within 0.76% on all 29 currencies both publish.
//
// Euro-area countries are NOT 1.00: the PPP euro is the euro-area average, so cheaper members sit
// below 1 (Italy 0.90, Spain 0.87) and dearer ones above (Germany 1.05).
// World has no C0p (a world aggregate has no exchange rate) and stays at 1, i.e. PPP euros.
// Official rates that households do not face are marked below: IRR, SDG, MMK, ARS.
//
// Superseded: this file previously held MARKET exchange rates of early 2024 labelled as PPP factors.

const COUNTRIES = [
  // Europe
  { code: "DE", name: "Germany",          currency: "EUR", pppRate: 1.054 },
  { code: "DK", name: "Denmark",          currency: "DKK", pppRate: 8.601 },
  { code: "ES", name: "Spain",            currency: "EUR", pppRate: 0.8681 },
  { code: "FR", name: "France",           currency: "EUR", pppRate: 1.011 },
  { code: "GB", name: "United Kingdom",   currency: "GBP", pppRate: 1.025 },
  { code: "IT", name: "Italy",            currency: "EUR", pppRate: 0.9009 },
  { code: "NL", name: "Netherlands",      currency: "EUR", pppRate: 1.144 },
  { code: "NO", name: "Norway",           currency: "NOK", pppRate: 12.60 },
  { code: "SE", name: "Sweden",           currency: "SEK", pppRate: 12.27 },
 // { code: "Europe", name: "Other Europe", currency: "EUR", pppRate: 1.00 },
  { code: "OC", name: "Rest of Western Europe", currency: "EUR", pppRate: 1.105 },
  { code: "QM", name: "Eastern Europe",       currency: "EUR", pppRate: 0.6619 },
  // North America & Oceania
  { code: "US", name: "United States",    currency: "USD", pppRate: 1.589 },
  { code: "CA", name: "Canada",           currency: "CAD", pppRate: 1.854 },
  { code: "AU", name: "Australia",        currency: "AUD", pppRate: 2.087 },
  { code: "NZ", name: "New Zealand",      currency: "NZD", pppRate: 2.415 },
 //{ code: "North America Oceania", name: "Other N. America/Oceania", currency: "USD", pppRate: 1.10 },
  { code: "OH", name: "Rest of Oceania", currency: "USD", pppRate: 1.142 },
  // Latin America
  { code: "AR", name: "Argentina",        currency: "ARS", pppRate: 1109 },   // official rate; parallel (blue) rate differs materially
  { code: "BR", name: "Brazil",           currency: "BRL", pppRate: 3.645 },
  { code: "CL", name: "Chile",            currency: "CLP", pppRate: 710.0 },
  { code: "CO", name: "Colombia",         currency: "COP", pppRate: 1836 },
  { code: "MX", name: "Mexico",           currency: "MXN", pppRate: 15.29 },
 // { code: "Latin America", name: "Other Latin America", currency: "USD", pppRate: 1.10 },
  { code: "OD", name: "Rest of Latin America", currency: "USD", pppRate: 0.8338 },
  // Middle East & North Africa
  { code: "AE", name: "UAE",              currency: "AED", pppRate: 3.718 },
  { code: "DZ", name: "Algeria",          currency: "DZD", pppRate: 67.57 },
  { code: "EG", name: "Egypt",            currency: "EGP", pppRate: 10.46 },
  { code: "IR", name: "Iran",             currency: "IRR", pppRate: 751640 },   // official rate; parallel market is many times higher
  { code: "MA", name: "Morocco",          currency: "MAD", pppRate: 5.571 },
  { code: "SA", name: "Saudi Arabia",     currency: "SAR", pppRate: 3.051 },
  { code: "TR", name: "Turkey",           currency: "TRY", pppRate: 29.61 },
  //{ code: "Middle East North Africa", name: "Other Middle East/N. Africa", currency: "USD", pppRate: 1.10 },
  { code: "OE", name: "Rest of Middle East & North Africa", currency: "USD", pppRate: 0.9945 },
  // Sub-Saharan Africa
  { code: "CD", name: "DR Congo",         currency: "CDF", pppRate: 1488 },
  { code: "CI", name: "Côte d'Ivoire",    currency: "XOF", pppRate: 317.8 },
  { code: "ET", name: "Ethiopia",         currency: "ETB", pppRate: 121.2 },
  { code: "KE", name: "Kenya",            currency: "KES", pppRate: 69.76 },
  { code: "ML", name: "Mali",             currency: "XOF", pppRate: 294.2 },
  { code: "NE", name: "Niger",            currency: "XOF", pppRate: 322.9 },
  { code: "NG", name: "Nigeria",          currency: "NGN", pppRate: 281.5 },
  { code: "RW", name: "Rwanda",           currency: "RWF", pppRate: 614.9 },
  { code: "SD", name: "Sudan",            currency: "SDG", pppRate: 228.9 },   // multiple exchange rates in wartime conditions
  { code: "ZA", name: "South Africa",     currency: "ZAR", pppRate: 10.52 },
  //{ code: "Sub-Saharan Africa", name: "Other Sub-Saharan Africa", currency: "USD", pppRate: 1.10 },
  { code: "OJ", name: "Rest of Sub-Saharan Africa", currency: "USD", pppRate: 0.5389 },
  // Russia & Central Asia
  { code: "RU", name: "Russia",           currency: "RUB", pppRate: 44.70 },
  //{ code: "Russia Central Asia", name: "Other Russia/Central Asia", currency: "USD", pppRate: 1.10 },
  { code: "OA", name: "Rest of Central Asia", currency: "USD", pppRate: 0.4802 },
  // East Asia
  { code: "CN", name: "China",            currency: "CNY", pppRate: 5.213 },
  { code: "JP", name: "Japan",            currency: "JPY", pppRate: 147.7 },
  { code: "KR", name: "South Korea",      currency: "KRW", pppRate: 1244 },
  { code: "TW", name: "Taiwan",           currency: "TWD", pppRate: 20.86 },
  //{ code: "East Asia", name: "Other East Asia", currency: "USD", pppRate: 1.10 },
  { code: "OB", name: "Rest of East Asia", currency: "USD", pppRate: 0.9766 },
  // South & South-East Asia
  { code: "BD", name: "Bangladesh",       currency: "BDT", pppRate: 49.90 },
  { code: "IN", name: "India",            currency: "INR", pppRate: 38.02 },
  { code: "ID", name: "Indonesia",        currency: "IDR", pppRate: 8170 },
  { code: "MM", name: "Myanmar",          currency: "MMK", pppRate: 585.7 },   // official rate diverges widely from the market rate
  { code: "PK", name: "Pakistan",         currency: "PKR", pppRate: 107.0 },
  { code: "PH", name: "Philippines",      currency: "PHP", pppRate: 32.71 },
  { code: "TH", name: "Thailand",         currency: "THB", pppRate: 15.04 },
  { code: "VN", name: "Vietnam",          currency: "VND", pppRate: 11180 },
  //{ code: "South & South-East Asia", name: "Other S. & SE Asia", currency: "USD", pppRate: 1.10 },
  { code: "OI", name: "Rest of South & South-East Asia", currency: "USD", pppRate: 0.6044 },
  // World
  { code: "World", name: "World", currency: "EUR", pppRate: 1.00 },
];

// Build lookup by code
const COUNTRY_MAP = {};
COUNTRIES.forEach(c => { COUNTRY_MAP[c.code] = c; });
