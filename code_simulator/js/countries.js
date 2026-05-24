// Country/region definitions: code, display name, currency code, PPP factor
// PPP factor = local currency units per 1 EUR PPP 2025
// Derived from World Bank ICP 2025 data (approximate)
// EUR PPP income = local income / pppRate

const COUNTRIES = [
  // Europe
  { code: "DE", name: "Germany",          currency: "EUR", pppRate: 1.00 },
  { code: "DK", name: "Denmark",          currency: "DKK", pppRate: 7.46 },
  { code: "ES", name: "Spain",            currency: "EUR", pppRate: 1.00 },
  { code: "FR", name: "France",           currency: "EUR", pppRate: 1.00 },
  { code: "GB", name: "United Kingdom",   currency: "GBP", pppRate: 0.72 },
  { code: "IT", name: "Italy",            currency: "EUR", pppRate: 1.00 },
  { code: "NL", name: "Netherlands",      currency: "EUR", pppRate: 1.00 },
  { code: "NO", name: "Norway",           currency: "NOK", pppRate: 11.5 },
  { code: "SE", name: "Sweden",           currency: "SEK", pppRate: 10.5 },
 // { code: "Europe", name: "Other Europe", currency: "EUR", pppRate: 1.00 },
  { code: "OC", name: "Rest of Western Europe", currency: "EUR", pppRate: 1.00 },
  { code: "QM", name: "Eastern Europe",       currency: "EUR", pppRate: 0.65 },
  // North America & Oceania
  { code: "US", name: "United States",    currency: "USD", pppRate: 1.10 },
  { code: "CA", name: "Canada",           currency: "CAD", pppRate: 1.45 },
  { code: "AU", name: "Australia",        currency: "AUD", pppRate: 1.55 },
  { code: "NZ", name: "New Zealand",      currency: "NZD", pppRate: 1.75 },
 //{ code: "North America Oceania", name: "Other N. America/Oceania", currency: "USD", pppRate: 1.10 },
  { code: "OH", name: "Rest of Oceania", currency: "USD", pppRate: 1.10 },
  // Latin America
  { code: "AR", name: "Argentina",        currency: "ARS", pppRate: 1200 },
  { code: "BR", name: "Brazil",           currency: "BRL", pppRate: 5.5 },
  { code: "CL", name: "Chile",            currency: "CLP", pppRate: 1050 },
  { code: "CO", name: "Colombia",         currency: "COP", pppRate: 5000 },
  { code: "MX", name: "Mexico",           currency: "MXN", pppRate: 20 },
 // { code: "Latin America", name: "Other Latin America", currency: "USD", pppRate: 1.10 },
  { code: "OD", name: "Rest of Latin America", currency: "USD", pppRate: 1.10 },
  // Middle East & North Africa
  { code: "AE", name: "UAE",              currency: "AED", pppRate: 3.6 },
  { code: "DZ", name: "Algeria",          currency: "DZD", pppRate: 140 },
  { code: "EG", name: "Egypt",            currency: "EGP", pppRate: 50 },
  { code: "IR", name: "Iran",             currency: "IRR", pppRate: 55000 },
  { code: "MA", name: "Morocco",          currency: "MAD", pppRate: 11 },
  { code: "SA", name: "Saudi Arabia",     currency: "SAR", pppRate: 3.8 },
  { code: "TR", name: "Turkey",           currency: "TRY", pppRate: 38 },
  //{ code: "Middle East North Africa", name: "Other Middle East/N. Africa", currency: "USD", pppRate: 1.10 },
  { code: "OE", name: "Rest of Middle East & North Africa", currency: "USD", pppRate: 1.10 },
  // Sub-Saharan Africa
  { code: "CD", name: "DR Congo",         currency: "CDF", pppRate: 3000 },
  { code: "CI", name: "Côte d'Ivoire",    currency: "XOF", pppRate: 655 },
  { code: "ET", name: "Ethiopia",         currency: "ETB", pppRate: 130 },
  { code: "KE", name: "Kenya",            currency: "KES", pppRate: 150 },
  { code: "ML", name: "Mali",             currency: "XOF", pppRate: 655 },
  { code: "NE", name: "Niger",            currency: "XOF", pppRate: 655 },
  { code: "NG", name: "Nigeria",          currency: "NGN", pppRate: 1600 },
  { code: "RW", name: "Rwanda",           currency: "RWF", pppRate: 1400 },
  { code: "SD", name: "Sudan",            currency: "SDG", pppRate: 600 },
  { code: "ZA", name: "South Africa",     currency: "ZAR", pppRate: 20 },
  //{ code: "Sub-Saharan Africa", name: "Other Sub-Saharan Africa", currency: "USD", pppRate: 1.10 },
  { code: "OJ", name: "Rest of Sub-Saharan Africa", currency: "USD", pppRate: 1.10 },
  // Russia & Central Asia
  { code: "RU", name: "Russia",           currency: "RUB", pppRate: 95 },
  //{ code: "Russia Central Asia", name: "Other Russia/Central Asia", currency: "USD", pppRate: 1.10 },
  { code: "OA", name: "Rest of Central Asia", currency: "USD", pppRate: 1.10 },
  // East Asia
  { code: "CN", name: "China",            currency: "CNY", pppRate: 7.5 },
  { code: "JP", name: "Japan",            currency: "JPY", pppRate: 160 },
  { code: "KR", name: "South Korea",      currency: "KRW", pppRate: 1350 },
  { code: "TW", name: "Taiwan",           currency: "TWD", pppRate: 35 },
  //{ code: "East Asia", name: "Other East Asia", currency: "USD", pppRate: 1.10 },
  { code: "OB", name: "Rest of East Asia", currency: "USD", pppRate: 1.10 },
  // South & South-East Asia
  { code: "BD", name: "Bangladesh",       currency: "BDT", pppRate: 120 },
  { code: "IN", name: "India",            currency: "INR", pppRate: 90 },
  { code: "ID", name: "Indonesia",        currency: "IDR", pppRate: 17000 },
  { code: "MM", name: "Myanmar",          currency: "MMK", pppRate: 3000 },
  { code: "PK", name: "Pakistan",         currency: "PKR", pppRate: 310 },
  { code: "PH", name: "Philippines",      currency: "PHP", pppRate: 60 },
  { code: "TH", name: "Thailand",         currency: "THB", pppRate: 38 },
  { code: "VN", name: "Vietnam",          currency: "VND", pppRate: 27000 },
  //{ code: "South & South-East Asia", name: "Other S. & SE Asia", currency: "USD", pppRate: 1.10 },
  { code: "OI", name: "Rest of South & South-East Asia", currency: "USD", pppRate: 1.10 },
  // World
  { code: "World", name: "World", currency: "EUR", pppRate: 1.00 },
];

// Build lookup by code
const COUNTRY_MAP = {};
COUNTRIES.forEach(c => { COUNTRY_MAP[c.code] = c; });
