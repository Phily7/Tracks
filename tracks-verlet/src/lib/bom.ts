// BOM CSV -> draft line items.
// Handles KiCad (Symbol Fields Table export and the legacy python BOM scripts),
// Fusion 360 (design BOM and electronics BOM) and anything with recognisable headers.
import Papa from "papaparse";
import type { AirFreight, Unit } from "./template";

export type BomSource = "kicad" | "fusion360" | "generic";

type Field =
  | "name" | "qty" | "reference" | "value" | "footprint" | "mpn" | "manufacturer"
  | "description" | "material" | "datasheet" | "vendor" | "vendor_pn" | "price" | "dnp" | "device";

// Normalised header -> field. Order inside each list is priority.
const SYNONYMS: Record<Field, string[]> = {
  name: ["part name", "component name", "item name", "name", "part", "component"],
  qty: ["qty", "quantity", "qnty", "qty per board", "count", "amount", "total qty"],
  reference: ["reference", "references", "ref", "refs", "designator", "designators", "ref des", "parts"],
  value: ["value", "val"],
  footprint: ["footprint", "package", "case", "case package"],
  mpn: ["mpn", "manufacturer part number", "mfr part number", "mfr part", "mfr no", "mfr pn",
        "manufacturer part", "part number", "pn", "manufacturer pn"],
  manufacturer: ["manufacturer", "mfr", "mfg", "maker", "brand", "manufacturer name"],
  description: ["description", "desc", "comment", "comments"],
  material: ["material", "material name"],
  datasheet: ["datasheet", "datasheet url", "link", "url", "product link", "supplier link"],
  vendor: ["vendor", "supplier", "distributor", "supplier name"],
  vendor_pn: ["lcsc", "lcsc part", "lcsc part number", "digikey", "digi key part number", "digikey pn",
              "mouser", "mouser part number", "supplier part number", "supplier pn", "vendor part number"],
  price: ["price", "unit price", "unit cost", "cost", "price usd", "unit price usd"],
  dnp: ["dnp", "do not populate", "exclude from bom", "exclude from board", "fitted"],
  device: ["device", "cmp name", "symbol", "lib id", "libid"],
};

const norm = (h: string) => h.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

function mapHeaders(headers: string[]): Partial<Record<Field, string>> {
  const out: Partial<Record<Field, string>> = {};
  const normed = headers.map((h) => ({ raw: h, n: norm(h) }));
  for (const field of Object.keys(SYNONYMS) as Field[]) {
    for (const syn of SYNONYMS[field]) {
      const hit = normed.find((h) => h.n === syn && !Object.values(out).includes(h.raw));
      if (hit) { out[field] = hit.raw; break; }
    }
  }
  return out;
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
  const n = Number(String(s).replace(/[^0-9.\-]/g, ""));
  return Number.isFinite(n) && String(s).match(/\d/) ? n : null;
};
const isUrl = (s: string | undefined) => !!s && /^https?:\/\//i.test(s.trim());
const clean = (s: string | undefined) => (s ?? "").replace(/\s+/g, " ").trim();
const meaningful = (s: string | undefined) => {
  const c = clean(s);
  return c && !["~", "-", "n/a", "na", "none", "dnp"].includes(c.toLowerCase()) ? c : "";
};

export function parseBomCsv(text: string, filename = ""): ParsedBom {
  // Some exporters write a preamble ("Source:", "Date:", "Tool:") before the real header row.
  const rows = Papa.parse<string[]>(text.replace(/^﻿/, ""), { skipEmptyLines: true }).data;
  let headerIdx = 0, best = -1;
  for (let i = 0; i < Math.min(rows.length, 25); i++) {
    const score = Object.keys(mapHeaders(rows[i].map(String))).length;
    if (score > best) { best = score; headerIdx = i; }
  }
  const headers = (rows[headerIdx] ?? []).map((h) => String(h).trim());
  const mapping = mapHeaders(headers);
  const records = rows.slice(headerIdx + 1).map((r) =>
    Object.fromEntries(headers.map((h, i) => [h, String(r[i] ?? "").trim()])),
  );
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
    if (/^(total|grand total|sum)\b/i.test(Object.values(r)[0] ?? "")) continue;

    // Name: explicit name column, else "<type> <value>", else description / mpn.
    let name = meaningful(get(r, "name"));
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
    const price = num(get(r, "price")) ?? breakPrice(r, qty);

    const text = [name, desc, value, footprint, material, type].join(" ");
    const airHint = AIR_RESTRICTED.test(text) || type === "Battery";
    const unitGuess = guessUnit(text);

    const key = (mpn || [name, value, footprint].join("|")).toLowerCase();
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
    if (unitGuess.confident) auto.push("unit");
    if (airHint) auto.push("air_freight");

    groups.set(key, {
      item_name: name,
      qty,
      unit: unitGuess.confident ? unitGuess.unit : null,
      specification,
      datasheet_url: datasheet,
      air_freight: airHint ? "Yes" : null,
      est_unit_price_usd: price,
      suggested_vendor: vendor,
      notes: null,
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
