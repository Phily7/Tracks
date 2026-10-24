// Turns "what the template still needs" into a short series of question cards.
// Cards are derived from current data every time, so an answered question simply disappears.
import { airFreightHint, guessUnit, specHints } from "./bom";
import { MIN_SPEC_CHARS, MIN_WHY_CHARS, type LineItem, type ProcRequest, type Profile } from "./template";

export type HeaderField = "full_name" | "title" | "project" | "needed_by" | "urgency" | "justification";

export type Card =
  | { kind: "header"; key: "header"; fields: HeaderField[] }
  | { kind: "air"; key: "air"; items: LineItem[]; suggested: Record<string, "Yes" | "No"> }
  | { kind: "unit"; key: "unit"; items: LineItem[]; suggested: Record<string, string> }
  | { kind: "qty"; key: "qty"; items: LineItem[] }
  | { kind: "spec"; key: "spec"; items: LineItem[]; hints: Record<string, string[]> }
  | { kind: "price"; key: "price"; items: LineItem[] }
  | { kind: "extras"; key: "extras"; items: LineItem[] };

const blank = (s: string | null | undefined) => (s ?? "").trim().length === 0;
const itemText = (i: LineItem) => `${i.item_name ?? ""} ${i.specification ?? ""}`;

export function buildCards(req: ProcRequest, owner: Profile | null, items: LineItem[]): Card[] {
  const named = items.filter((i) => !blank(i.item_name));
  const cards: Card[] = [];

  const fields: HeaderField[] = [];
  if (blank(owner?.full_name)) fields.push("full_name");
  if (blank(req.title)) fields.push("title");
  if (blank(req.project)) fields.push("project");
  if (blank(req.needed_by)) fields.push("needed_by");
  if (blank(req.urgency)) fields.push("urgency");
  if ((req.justification ?? "").trim().length < MIN_WHY_CHARS) fields.push("justification");
  if (fields.length) cards.push({ kind: "header", key: "header", fields });

  const noAir = named.filter((i) => blank(i.air_freight));
  if (noAir.length)
    cards.push({
      kind: "air",
      key: "air",
      items: noAir,
      suggested: Object.fromEntries(noAir.map((i) => [i.id, airFreightHint(itemText(i)) ? "Yes" : "No"])),
    });

  const noUnit = named.filter((i) => blank(i.unit));
  if (noUnit.length)
    cards.push({
      kind: "unit",
      key: "unit",
      items: noUnit,
      suggested: Object.fromEntries(noUnit.map((i) => [i.id, guessUnit(itemText(i)).unit])),
    });

  const badQty = named.filter((i) => typeof i.qty !== "number" || i.qty <= 0);
  if (badQty.length) cards.push({ kind: "qty", key: "qty", items: badQty });

  const thin = named.filter((i) => (i.specification ?? "").trim().length < MIN_SPEC_CHARS);
  if (thin.length)
    cards.push({
      kind: "spec",
      key: "spec",
      items: thin,
      hints: Object.fromEntries(thin.map((i) => [i.id, specHints(i.item_name ?? "", i.specification ?? "")])),
    });

  const noPrice = named.filter((i) => typeof i.est_unit_price_usd !== "number");
  if (noPrice.length) cards.push({ kind: "price", key: "price", items: noPrice });

  // Optional: not required by the template, but the Read Me says a link settles more ambiguity than a paragraph.
  const noLink = named.filter((i) => blank(i.datasheet_url) && blank(i.suggested_vendor));
  if (noLink.length) cards.push({ kind: "extras", key: "extras", items: noLink });

  return cards;
}

export const CARD_TITLES: Record<Card["kind"], { title: string; blurb: string }> = {
  header: { title: "About this request", blurb: "The approver reads this and often nothing else." },
  air: {
    title: "Air freight check",
    blurb: "Magnets, batteries, adhesives, threadlockers, aerosols, liquids, powders and anything pressurised are restricted. One undeclared item can hold a whole shipment.",
  },
  unit: { title: "Units", blurb: "We guessed these. Confirm or change." },
  qty: { title: "Quantities", blurb: "These rows have no usable quantity." },
  spec: {
    title: "Specs need more detail",
    blurb: "Write it so someone who has never seen your assembly could order the right part without asking you anything.",
  },
  price: {
    title: "Estimated unit prices (optional)",
    blurb: "Fill in what you know. Leave the rest blank and procurement will price them before approving.",
  },
  extras: { title: "Links and vendors (optional)", blurb: "A datasheet or product link settles more ambiguity than a paragraph." },
};
