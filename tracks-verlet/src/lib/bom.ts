// BOM CSV -> draft line items.
// Handles KiCad (Symbol Fields Table export and the legacy python BOM scripts),
// Fusion 360 (design BOM and electronics BOM) and anything with recognisable headers.
import Papa from "papaparse";
import type { AirFreight, Unit } from "./template";

export type BomSource = "kicad" | "fusion360" | "generic";

type Field =
  | "name" | "qty" | "reference" | "value" | "footprint" | "mpn" | "manufacturer"
  | "description" | "material" | "datasheet" | "vendor" | "vendor_pn" | "price" | "total_price" | "dnp" | "device"
  | "uom" | "notes";

// Normalised header -> field. Order inside each list is priority.
const SYNONYMS: Record<Field, string[]> = {
  name: ["part name", "component name", "item name", "name", "part", "component", "item", "product", "product name",
         "article", "material description", "item to buy"],
  qty: ["qty", "quantity", "qnty", "qty per board", "count", "amount", "total qty", "quantity required", "qty required",
        "qty needed", "quantity needed", "order qty", "qty to order", "no of units", "number of units", "how many"],
  reference: ["reference", "references", "ref", "refs", "designator", "designators", "ref des", "parts"],
  value: ["value", "val"],
  footprint: ["footprint", "package", "case", "case package"],
  mpn: ["mpn", "manufacturer part number", "mfr part number", "mfr part", "mfr no", "mfr pn",
        "manufacturer part", "part number", "pn", "manufacturer pn"],
  manufacturer: ["manufacturer", "mfr", "mfg", "maker", "brand", "manufacturer name"],
  description: ["description", "desc", "comment", "comments", "item description", "part description", "specification",
                "specifications", "spec", "specs", "details", "detailed specification", "technical details"],
  material: ["material", "material name"],
  datasheet: ["datasheet", "datasheet url", "link", "url", "product link", "supplier link", "product url", "datasheet link",
              "purchase link", "buy link", "website", "web link"],
  vendor: ["vendor", "supplier", "distributor", "supplier name", "suggested vendor", "source", "store", "shop",
           "where to buy", "seller"],
  vendor_pn: ["lcsc", "lcsc part", "lcsc part number", "digikey", "digi key part number", "digikey pn",
              "mouser", "mouser part number", "supplier part number", "supplier pn", "vendor part number"],
  price: ["price", "unit price", "unit cost", "cost", "price usd", "unit price usd", "price each", "cost each",
          "est price", "estimated price", "est unit price", "estimated unit price", "price per unit", "cost per unit", "rate"],
  total_price: ["total price", "extended price", "ext price", "line total", "total cost", "total", "subtotal"],
  dnp: ["dnp", "do not populate", "exclude from bom", "exclude from board", "fitted"],
  device: ["device", "cmp name", "symbol", "lib id", "libid"],
  uom: ["unit", "uom", "unit of measure", "units of measure", "measure"],
  notes: ["notes", "note", "remarks", "remark"],
};

const norm = (h: string) => h.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

// Exact header names first; then headers that contain a known name as whole words, e.g. "Unit Price (USD)"
// or "Quantity required for 2 units". The exact pass runs for every field before any loose match.
function mapHeaders(headers: string[]): Partial<Record<Field, string>> {
  const out: Partial<Record<Field, string>> = {};
  const normed = headers.map((h) => ({ raw: h, n: norm(h) })).filter((h) => h.n);
  const used = (raw: string) => Object.values(out).includes(raw);
  const fields = Object.keys(SYNONYMS) as Field[];
  for (const field of fields) {
    for (const syn of SYNONYMS[field]) {
      const hit = normed.find((h) => h.n === syn && !used(h.raw));
      if (hit) { out[field] = hit.raw; break; }
    }
  }
  for (const field of fields) {
    if (out[field]) continue;
    for (const syn of SYNONYMS[field]) {
      if (syn.length < 3) continue; // "no", "pn" are too short to trust inside longer headers
      const hit = normed.find((h) => !used(h.raw) && h.n.length <= 40 && ` ${h.n} `.includes(` ${syn} `));
      if (hit) { out[field] = hit.raw; break; }
    }
  }
  return out;
}

// A header row is believable when it names the part somehow.
const NAMEISH: Field[] = ["name", "value", "description", "mpn", "device", "reference"];
// Two recognised columns also count: the item column can be found from its contents afterwards.
const headerScore = (m: Partial<Record<Field, string>>) => {
  const n = Object.keys(m).length;
  return NAMEISH.some((f) => m[f]) ? n + 1 : n >= 2 ? n : 0;
};

export function normalizeUnit(s: string): Unit | null {
  const t = norm(s);
  if (!t) return null;
  if (/^(pcs?|pieces?|ea|each|units?|nos?|no s|qty|x)$/.test(t)) return "pcs";
  if (/^(m|meters?|metres?|mtrs?)$/.test(t)) return "m";
  if (/^(kg|kgs|kilograms?|kilos?)$/.test(t)) return "kg";
  if (/^sets?$/.test(t)) return "set";
  if (/^(pairs?|pr)$/.test(t)) return "pair";
  if (/^rolls?$/.test(t)) return "roll";
  if (/^(box|boxes|bx)$/.test(t)) return "box";
  if (/^(l|ltr|ltrs|litres?|liters?)$/.test(t)) return "litre";
  if (/^sheets?$/.test(t)) return "sheet";
  if (/^services?$/.test(t)) return "service";
  return null;
}

// Reference designator prefix -> what the thing is.
const REF_TYPES: [RegExp, string][] = [
  [/^LED/i, "LED"], [/^BT/i, "Battery"], [/^SW/i, "Switch"], [/^TP/i, "Test point"],
  [/^FID/i, "Fiducial"], [/^MH|^H\d/i, "Mounting hole"], [/^JP/i, "Jumper"], [/^FB/i, "Ferrite bead"],
  [/^R/i, "Resistor"], [/^C/i, "Capacitor"], [/^L/i, "Inductor"], [/^D/i, "Diode"], [/^U|^IC/i, "IC"],
  [/^Q/i, "Transistor"], [/^[JP]/i, "Connector"], [/^[YX]/i, "Crystal"], [/^F/i, "Fuse"],
  [/^K/i, "Relay"], [/^M/i, "Motor"], [/^LS|^BZ/i, "Buzzer"], [/^G/i, "Logo"],
];
const NOT_PURCHASED = new Set(["Test point", "Fiducial", "Mounting hole", "Logo", "Jumper"]);

function refType(ref: string): string | null {
  const first = ref.split(/[\s,;]+/).find(Boolean) ?? "";
  for (const [re, t] of REF_TYPES) if (re.test(first)) return t;
  return null;
}

function prettyFootprint(fp: string): string {
  // "Resistor_SMD:R_0603_1608Metric" -> "0603 (1608 metric)"; "Connector_JST:JST_XH_B4B-XH-A_1x04_P2.50mm_Vertical" -> readable
  const body = fp.includes(":") ? fp.split(":").pop()! : fp;
  const imperial = body.match(/_(\d{4})_(\d{4})Metric/);
  if (imperial) return `${imperial[1]} (${imperial[2]} metric) SMD`;
  return body.replace(/_/g, " ").replace(/\s+/g, " ").trim();
}

const AIR_RESTRICTED =
  /\b(batter(y|ies)|li-?po|li-?ion|lithium|18650|21700|cell|magnets?|neodymium|ndfeb|adhesive|glue|epoxy|loctite|thread ?lock(er)?|aerosol|spray|liquid|oil|grease|lubricant|solvent|paint|isopropyl|ipa|alcohol|powder|flux|resin|gas|pressuri[sz]ed|co2|super ?glue|cyanoacrylate)\b/i;

export function guessUnit(text: string): { unit: Unit; confident: boolean } {
  const t = text.toLowerCase();
  if (/\b(wire|cable|tubing|tube|heat ?shrink|hose|cord|strip(?! ?board)|extrusion|rail|rod)\b/.test(t))
    return { unit: "m", confident: false };
  if (/\btape\b/.test(t)) return { unit: "roll", confident: false };
  if (/\b(sheet|plate|panel|acrylic|plywood|mdf)\b/.test(t)) return { unit: "sheet", confident: false };
  if (/\b(filament|resin)\b/.test(t)) return { unit: "kg", confident: false };
  if (/\b(paste|oil|grease|ipa|alcohol|solvent)\b/.test(t)) return { unit: "litre", confident: false };
  return { unit: "pcs", confident: true };
}

export const airFreightHint = (text: string) => AIR_RESTRICTED.test(text);

// KiCad library placeholders like "Conn_01x04" or "Screw_Terminal_01x02" say little on their own.
function prettyValue(value: string): { text: string; generic: boolean } {
  const conn = value.match(/^(conn|screw_terminal|pin_header|pin_socket)\w*?_(\d+)x(\d+)/i);
  if (conn) {
    const pins = Number(conn[2]) * Number(conn[3]);
    const kind = conn[1].toLowerCase() === "conn" ? "" : conn[1].replace(/_/g, " ").toLowerCase() + " ";
    return { text: `${kind}${pins}-pin`, generic: true };
  }
  return { text: value.replace(/_/g, " "), generic: /^(led|r|c|l|d|q|sw_push|crystal|fuse)$/i.test(value) };
}

export type DraftItem = {
  item_name: string;
  qty: number;
  unit: Unit | null;
  specification: string;
  datasheet_url: string | null;
  air_freight: AirFreight | null;
  est_unit_price_usd: number | null;
  suggested_vendor: string | null;
  notes: string | null;
  source_row: Record<string, string>;
  auto_fields: string[];
  air_freight_hint: boolean; // keyword match -> suggested "Yes"
};

export type ParsedBom = {
  source: BomSource;
  headers: string[];
  mapping: Partial<Record<Field, string>>;
  rawRowCount: number;
  items: DraftItem[];
  skipped: { reason: string; count: number }[];
};

const num = (s: string | undefined) => {
  if (!s) return null;
  let t = String(s).trim();
  if (/^[^.]*\d,\d{1,2}\D*$/.test(t)) t = t.replace(",", "."); // decimal comma: "6,50" (but "1,000" stays a thousand)
  const n = Number(t.replace(/[^0-9.\-]/g, ""));
  return Number.isFinite(n) && String(s).match(/\d/) ? n : null;
};
const isUrl = (s: string | undefined) => !!s && /^https?:\/\//i.test(s.trim());
const clean = (s: string | undefined) => (s ?? "").replace(/\s+/g, " ").trim();
const meaningful = (s: string | undefined) => {
  const c = clean(s);
  return c && !["~", "-", "n/a", "na", "none", "dnp"].includes(c.toLowerCase()) ? c : "";
};

export function parseBomCsv(text: string, filename = ""): ParsedBom {
  return parseBomRows(csvRows(text), filename);
}

export const csvRows = (text: string) =>
  Papa.parse<string[]>(text.replace(/^\uFEFF/, ""), { skipEmptyLines: true }).data.map((r) => r.map((c) => String(c ?? "")));

/** Where the parts table starts in a grid of cells, and how good it looks. Used to pick a sheet in a workbook. */
export function findTable(rows: string[][]): { headerIdx: number; headers: string[]; mapping: Partial<Record<Field, string>>; score: number } {
  // Titles, logos, project info and blank rows often sit above the real header row.
  let headerIdx = -1, best = 0;
  for (let i = 0; i < Math.min(rows.length, 40); i++) {
    const score = headerScore(mapHeaders(rows[i].map((c) => c.trim())));
    if (score > best) { best = score; headerIdx = i; }
  }
  if (headerIdx >= 0) {
    const headers = uniqueHeaders(rows[headerIdx]);
    const mapping = inferByContent(headers, rows.slice(headerIdx + 1), mapHeaders(headers));
    return { headerIdx, headers, mapping, score: best };
  }
  return guessHeaderless(rows);
}

// Columns whose names we don't recognise can still be placed by what's in them.
function inferByContent(headers: string[], body: string[][], mapping: Partial<Record<Field, string>>) {
  const out = { ...mapping };
  const used = new Set(Object.values(out));
  const share = (vals: string[], test: (v: string) => boolean) => (vals.length ? vals.filter(test).length / vals.length : 0);
  headers.forEach((h, c) => {
    if (used.has(h)) return;
    const vals = body.slice(0, 200).map((r) => (r[c] ?? "").trim()).filter(Boolean);
    if (vals.length < 2) return;
    let field: Field | null = null;
    if (!out.datasheet && share(vals, (v) => isUrl(v)) >= 0.6) field = "datasheet";
    else if (!out.uom && share(vals, (v) => normalizeUnit(v) != null) >= 0.7) field = "uom";
    else if (!out.price && share(vals, (v) => /^\s*(\$|usd|us\$)\s*\d|\d\s*(usd|\$)\s*$/i.test(v)) >= 0.6) field = "price";
    else if (!out.qty && share(vals, (v) => /^\d{1,5}(\.0+)?$/.test(v) && Number(v) > 0) >= 0.8 &&
             !/^(#|no|nr|s ?n|sl|item|line|row|idx|index|pos)$/.test(norm(h))) field = "qty";
    if (field) { out[field] = h; used.add(h); }
  });
  if (!NAMEISH.some((f) => out[f])) {
    // Nothing names the part: use the column with the most words in it.
    let bestCol = -1, bestLen = 0;
    headers.forEach((h, c) => {
      if (used.has(h)) return;
      const len = body.slice(0, 200).map((r) => (r[c] ?? "").trim())
        .filter((v) => v && !isUrl(v) && num(v) == null).reduce((t, v) => t + v.length, 0);
      if (len > bestLen) { bestLen = len; bestCol = c; }
    });
    if (bestCol >= 0) out.name = headers[bestCol];
  }
  return out;
}

// Blank or repeated header cells would collide as object keys.
function uniqueHeaders(row: string[]): string[] {
  const seen = new Map<string, number>();
  return row.map((h, i) => {
    const base = h.trim() || `Column ${i + 1}`;
    const n = (seen.get(base) ?? 0) + 1;
    seen.set(base, n);
    return n > 1 ? `${base} ${n}` : base;
  });
}

// No recognisable headers: the wordiest column is the item, a column of small whole numbers is the quantity.
function guessHeaderless(rows: string[][]) {
  const width = Math.max(0, ...rows.map((r) => r.length));
  const headers = Array.from({ length: width }, (_, i) => `Column ${i + 1}`);
  const cols = headers.map((_, c) => rows.map((r) => (r[c] ?? "").trim()).filter(Boolean));
  const textScore = cols.map((v) => v.filter((x) => !isUrl(x) && (num(x) == null || /[a-z]{3}/i.test(x))).reduce((s, x) => s + x.length, 0));
  const qtyScore = cols.map((v) => (v.length ? v.filter((x) => /^\d{1,5}(\.0+)?$/.test(x) && Number(x) > 0).length / v.length : 0));
  const nameCol = textScore.indexOf(Math.max(...textScore));
  const qtyCandidates = qtyScore.map((q, i) => ({ q, i })).filter((x) => x.i !== nameCol && x.q >= 0.6).sort((a, b) => b.q - a.q);
  const mapping: Partial<Record<Field, string>> = {};
  if (nameCol >= 0 && textScore[nameCol] > 0) mapping.name = headers[nameCol];
  if (qtyCandidates[0]) mapping.qty = headers[qtyCandidates[0].i];
  return { headerIdx: -1, headers, mapping, score: mapping.name ? 1 : 0 };
}

export function parseBomRows(rows: string[][], filename = ""): ParsedBom {
  const { headerIdx, headers, mapping } = findTable(rows);
  const headerKey = headers.map((h) => norm(h)).join("|");
  const records = rows
    .slice(headerIdx + 1)
    // multi-page exports repeat the header row
    .filter((r) => r.map((c) => norm(c)).join("|") !== headerKey)
    .map((r) => Object.fromEntries(headers.map((h, i) => [h, String(r[i] ?? "").trim()])));
  const get = (r: Record<string, string>, f: Field) => (mapping[f] ? r[mapping[f]!] ?? "" : "");
  // Distributor price breaks ("Unit1", "Unit10", "Price @ 100"): unit price at that order quantity.
  const priceBreaks = headers
    .map((h) => ({ h, at: Number(norm(h).match(/^(?:unit ?price|unit ?cost|price|unit)(?: ?qty)? ?(\d+)$/)?.[1]) }))
    .filter((b) => b.at > 0)
    .sort((a, b) => a.at - b.at);
  const breakPrice = (r: Record<string, string>, qty: number) => {
    let price: number | null = null;
    for (const b of priceBreaks) {
      const p = num(r[b.h]);
      if (p != null && (price == null || b.at <= qty)) price = p;
    }
    return price;
  };

  const source: BomSource =
    mapping.reference && (mapping.footprint || /kicad/i.test(filename)) ? "kicad"
    : mapping.material || /fusion|f360/i.test(filename) || (mapping.name && norm(mapping.name).includes("component")) ? "fusion360"
    : "generic";

  const skipped = new Map<string, number>();
  const skip = (reason: string) => skipped.set(reason, (skipped.get(reason) ?? 0) + 1);
  const groups = new Map<string, DraftItem>();

  for (const r of records) {
    if (Object.values(r).every((v) => !v)) continue;
    const ref = clean(get(r, "reference"));
    const value = meaningful(get(r, "value"));
    const footprint = meaningful(get(r, "footprint"));
    const mpn = meaningful(get(r, "mpn"));
    const mfr = meaningful(get(r, "manufacturer"));
    const desc = meaningful(get(r, "description"));
    const material = meaningful(get(r, "material"));
    const device = meaningful(get(r, "device"));
    const dnp = clean(get(r, "dnp")).toLowerCase();
    let type = ref ? refType(ref) : null;
    if (type === "Diode" && /^led/i.test(value)) type = "LED";

    if (["x", "yes", "true", "1", "dnp", "excluded"].includes(dnp) || (mapping.dnp && norm(mapping.dnp) === "fitted" && ["no", "false", "0"].includes(dnp))) { skip("Marked DNP / excluded"); continue; }
    if (/^dnp$/i.test(value)) { skip("Marked DNP / excluded"); continue; }
    if (type && NOT_PURCHASED.has(type)) { skip(`${type}s (not purchased)`); continue; }
    const filledCells = Object.values(r).filter(Boolean);
    if (filledCells.some((v) => /^(sub ?total|grand total|total|sum)\b:?/i.test(v)) && filledCells.length <= 4) continue;
    // Section headings ("Electronics", "Fasteners") sit alone on their row.
    if (filledCells.length === 1 && !num(get(r, "qty")) && !mapping.reference) { skip("Section headings"); continue; }

    // Name: explicit name column, else "<type> <value>", else description / mpn.
    let name = meaningful(get(r, "name"));
    if (/^\d+\.?$/.test(name)) name = ""; // an "Item" column of row numbers
    if (!name && (type || value)) {
      const pv = value ? prettyValue(value) : { text: "", generic: true };
      const label = pv.generic && mpn ? mpn : pv.text;
      name = [type, type && label.toLowerCase() === type.toLowerCase() ? "" : label].filter(Boolean).join(" ");
    }
    if (!name) name = desc || device || mpn;
    if (!name) { skip("Rows without a name or value"); continue; }

    let qty = num(get(r, "qty"));
    if (qty == null && ref) qty = ref.split(/[\s,;]+/).filter(Boolean).length;
    if (qty == null) qty = 1;

    const specParts = [
      type && value
        ? prettyValue(value).text.toLowerCase() === type.toLowerCase() ? type : `${type}, ${prettyValue(value).text}`
        : value && value !== name ? value : "",
      desc && desc !== name ? desc : "",
      footprint ? prettyFootprint(footprint) : "",
      material ? `Material: ${material}` : "",
      mpn ? `MPN ${mpn}` : "",
      mfr ? `Mfr ${mfr}` : "",
    ].filter(Boolean);
    const specification = specParts.join(", ");

    const datasheet = [get(r, "datasheet")].find(isUrl) ?? null;
    const vendorPn = meaningful(get(r, "vendor_pn"));
    const vendorCol = meaningful(get(r, "vendor"));
    const vendorPnHeader = mapping.vendor_pn ? norm(mapping.vendor_pn).split(" ")[0] : "";
    const vendor = vendorCol || (vendorPn ? `${vendorPnHeader.toUpperCase()} ${vendorPn}` : null);
    const total = num(get(r, "total_price"));
    const price = num(get(r, "price")) ?? breakPrice(r, qty) ?? (total != null && qty > 0 ? Math.round((total / qty) * 10000) / 10000 : null);
    const statedUnit = normalizeUnit(get(r, "uom"));
    const notes = meaningful(get(r, "notes")) || null;

    const text = [name, desc, value, footprint, material, type].join(" ");
    const airHint = AIR_RESTRICTED.test(text) || type === "Battery";
    const unitGuess = guessUnit(text);

    const key = (mpn || [name, value, footprint, desc].join("|")).toLowerCase();
    const existing = groups.get(key);
    if (existing) {
      existing.qty += qty;
      if (ref) existing.source_row.Reference = [existing.source_row.Reference, ref].filter(Boolean).join(", ");
      continue;
    }

    const auto: string[] = ["item_name", "qty"];
    if (specification) auto.push("specification");
    if (datasheet) auto.push("datasheet_url");
    if (vendor) auto.push("suggested_vendor");
    if (price != null) auto.push("est_unit_price_usd");
    if (statedUnit || unitGuess.confident) auto.push("unit");
    if (airHint) auto.push("air_freight");

    groups.set(key, {
      item_name: name,
      qty,
      unit: statedUnit ?? (unitGuess.confident ? unitGuess.unit : null),
      specification,
      datasheet_url: datasheet,
      air_freight: airHint ? "Yes" : null,
      est_unit_price_usd: price,
      suggested_vendor: vendor,
      notes,
      source_row: { ...r, ...(ref ? { Reference: ref } : {}) },
      auto_fields: auto,
      air_freight_hint: airHint,
    });
  }

  // Same display name but different parts (e.g. two "Capacitor 100n" footprints) would trip
  // the template's duplicate check, so disambiguate with the package.
  const items = [...groups.values()];
  const byName = new Map<string, DraftItem[]>();
  for (const it of items) byName.set(it.item_name.toLowerCase(), [...(byName.get(it.item_name.toLowerCase()) ?? []), it]);
  for (const dupes of byName.values()) {
    if (dupes.length < 2) continue;
    dupes.forEach((d, i) => {
      const fp = mapping.footprint ? meaningful(d.source_row[mapping.footprint]) : "";
      const mpn = mapping.mpn ? meaningful(d.source_row[mapping.mpn]) : "";
      d.item_name = `${d.item_name} (${fp ? prettyFootprint(fp) : mpn || `variant ${i + 1}`})`;
    });
  }

  return {
    source,
    headers,
    mapping,
    rawRowCount: records.length,
    items,
    skipped: [...skipped].map(([reason, count]) => ({ reason, count })),
  };
}

/** What a good spec for this kind of part usually needs, shown as hints next to the spec question. */
export function specHints(name: string, spec: string): string[] {
  const t = `${name} ${spec}`.toLowerCase();
  const has = (re: RegExp) => re.test(t);
  if (has(/resistor/)) return ["tolerance (e.g. 1%)", "power rating (e.g. 0.1 W)", "package"].filter((h) => !(h.startsWith("tolerance") && has(/%/)) && !(h.startsWith("power") && has(/\bw\b|watt/)));
  if (has(/capacitor/)) return ["voltage rating", "dielectric (X7R, C0G...)", "tolerance"].filter((h) => !(h.startsWith("voltage") && has(/\d+\s?v\b/)));
  if (has(/inductor|ferrite/)) return ["current rating", "DCR", "package"];
  if (has(/led/)) return ["colour", "package", "forward current"];
  if (has(/connector|header|jst|molex/)) return ["series", "pin count", "pitch (mm)", "gender / orientation", "mating part"];
  if (has(/screw|bolt|nut|washer|standoff|spacer|insert/)) return ["thread & pitch (M3 x 0.5)", "length", "head type", "material / grade", "standard (DIN/ISO)"];
  if (has(/motor|servo|stepper/)) return ["voltage", "torque", "shaft diameter", "connector"];
  if (has(/bearing/)) return ["bore x OD x width", "seal type", "standard number (e.g. 608ZZ)"];
  if (has(/wire|cable/)) return ["gauge (AWG / mm²)", "colour", "insulation", "strand type"];
  if (has(/ic|regulator|mcu|sensor|driver/)) return ["exact MPN", "package", "datasheet link"];
  return ["dimensions", "material", "rating", "datasheet or product link"];
}

const FIELD_LABELS: Partial<Record<Field, string>> = {
  name: "Item name", description: "Spec", value: "Value", mpn: "Part number", qty: "Qty", uom: "Unit",
  price: "Est. price", total_price: "Total (÷ qty for unit price)", datasheet: "Link", vendor: "Vendor",
  vendor_pn: "Vendor part #", manufacturer: "Manufacturer", footprint: "Package", material: "Material", notes: "Notes",
};

/** "Item name ← "Component", Qty ← "How many"…" so people can see how their columns were read. */
export function describeMapping(mapping: Partial<Record<Field, string>>): string {
  return (Object.keys(FIELD_LABELS) as Field[])
    .filter((f) => mapping[f])
    .map((f) => `${FIELD_LABELS[f]} ← "${mapping[f]}"`)
    .join(", ");
}
