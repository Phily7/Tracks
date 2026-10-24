// Rules and dropdown lists from Verlet_Procurement_Request_TemplateV1.xlsx.
// Keep in sync with the Request tab formulas (N2, C13, L19) and the Lists tab.

export const UNITS = ["pcs", "m", "kg", "set", "pair", "roll", "box", "litre", "sheet", "service"] as const;
export const URGENCIES = ["Normal", "Blocking within 2 weeks", "Blocking work right now"] as const;
export const AIR_FREIGHT = ["No", "Yes", "Not sure - please check"] as const;
export const STATUSES = ["draft", "submitted", "approved", "rejected", "ordered"] as const;

export type Unit = (typeof UNITS)[number];
export type Urgency = (typeof URGENCIES)[number];
export type AirFreight = (typeof AIR_FREIGHT)[number];
export type RequestStatus = (typeof STATUSES)[number];

export const MAX_LINES_PER_FILE = 40; // template rows 19..58
export const MIN_SPEC_CHARS = 25;
export const MIN_WHY_CHARS = 15;

export type Profile = {
  id: string;
  email: string;
  full_name: string | null;
  phone: string | null;
  role: "manager" | "engineer";
  is_owner?: boolean;
};

export type ProcRequest = {
  id: string;
  req_number: string | null;
  owner_id: string;
  title: string | null;
  project: string | null;
  date_submitted: string | null;
  needed_by: string | null;
  urgency: Urgency | null;
  justification: string | null;
  status: RequestStatus;
  manager_note: string | null;
  created_at: string;
  updated_at: string;
};

export type LineItem = {
  id: string;
  request_id: string;
  bom_upload_id: string | null;
  position: number;
  item_name: string | null;
  qty: number | null;
  unit: Unit | null;
  specification: string | null;
  datasheet_url: string | null;
  air_freight: AirFreight | null;
  est_unit_price_usd: number | null;
  suggested_vendor: string | null;
  notes: string | null;
  source_row: Record<string, string> | null;
  // which fields the system filled in itself (shown as "auto" in the UI)
  auto_fields: string[] | null;
};

const filled = (s: string | null | undefined) => (s ?? "").trim().length > 0;
const isNum = (n: unknown): n is number => typeof n === "number" && Number.isFinite(n);

/** Column L "Check" for one row. Empty array means "OK". */
export function lineIssues(item: LineItem, all: LineItem[]): string[] {
  const named = filled(item.item_name);
  const issues: string[] = [];
  if (named && !isNum(item.qty)) issues.push("Qty missing");
  if (named && isNum(item.qty) && item.qty <= 0) issues.push("Qty must be above zero");
  if (named && !filled(item.unit)) issues.push("Unit missing");
  if (named && (item.specification ?? "").trim().length < MIN_SPEC_CHARS) issues.push("Spec too thin");
  if (named && !filled(item.air_freight)) issues.push("Air-freight answer missing");
  if (named) {
    const key = item.item_name!.trim().toLowerCase();
    if (all.filter((o) => (o.item_name ?? "").trim().toLowerCase() === key).length > 1)
      issues.push("Duplicate item in this request");
  }
  if (!named && (isNum(item.qty) || filled(item.specification))) issues.push("Item name missing");
  return issues;
}

/** Helper cell N2: header fields that are missing. */
export function headerIssues(req: ProcRequest, owner: Pick<Profile, "full_name" | "email"> | null): string[] {
  const missing: string[] = [];
  if (!filled(owner?.full_name)) missing.push("your name");
  if (!filled(owner?.email)) missing.push("your email");
  if (!filled(req.project)) missing.push("project");
  if (!filled(req.needed_by)) missing.push("needed-by date");
  if ((req.justification ?? "").trim().length < MIN_WHY_CHARS) missing.push("why this is needed");
  return missing;
}

export type Readiness = {
  ready: boolean;
  label: string;
  headerMissing: string[];
  lineCount: number;
  linesNeedingAttention: number;
  // Prices don't block submitting; procurement fills them in before approving.
  unpriced: number;
  estTotal: number;
};

/** Status box C13..C16. */
export function readiness(
  req: ProcRequest,
  owner: Pick<Profile, "full_name" | "email"> | null,
  items: LineItem[],
): Readiness {
  const headerMissing = headerIssues(req, owner);
  const named = items.filter((i) => filled(i.item_name) || isNum(i.qty) || filled(i.specification));
  const lineCount = items.filter((i) => filled(i.item_name)).length;
  const linesNeedingAttention = named.filter((i) => lineIssues(i, items).length > 0).length;
  const unpriced = items.filter((i) => filled(i.item_name) && !isNum(i.est_unit_price_usd)).length;
  const estTotal = items.reduce((s, i) => s + lineTotal(i), 0);
  let label = "READY TO SEND";
  if (headerMissing.length) label = `NOT READY - missing: ${headerMissing.join(", ")}`;
  else if (lineCount === 0) label = "NOT READY - no line items entered";
  else if (linesNeedingAttention > 0)
    label = `NOT READY - ${linesNeedingAttention} line(s) need attention, see the Check column`;
  return { ready: label === "READY TO SEND", label, headerMissing, lineCount, linesNeedingAttention, unpriced, estTotal };
}

export function lineTotal(i: LineItem): number {
  return isNum(i.qty) && isNum(i.est_unit_price_usd) ? i.qty * i.est_unit_price_usd : 0;
}

export function exportFileName(name: string | null, project: string | null, date = new Date()): string {
  const clean = (s: string | null) => (s ?? "").trim().replace(/[^A-Za-z0-9]+/g, "") || "Unknown";
  return `PR_${clean(name)}_${clean(project)}_${date.toISOString().slice(0, 10)}.xlsx`;
}

export const usd = (n: number) =>
  n.toLocaleString("en-US", { style: "currency", currency: "USD", minimumFractionDigits: 2 });
