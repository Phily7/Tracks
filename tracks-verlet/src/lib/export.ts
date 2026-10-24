// Fills the real Verlet template (public/template/...) so procurement gets the file they already know,
// formulas, dropdowns and status box intact. Runs in the browser and in Node (for tests).
import ExcelJS from "exceljs";
import { MAX_LINES_PER_FILE, type LineItem, type ProcRequest, type Profile } from "./template";

export const TEMPLATE_PATH = "/template/Verlet_Procurement_Request_TemplateV1.xlsx";
const FIRST_ROW = 19;

export async function fillTemplate(
  template: ArrayBuffer,
  req: ProcRequest,
  owner: Pick<Profile, "full_name" | "email" | "phone">,
  items: LineItem[],
  projects: string[],
  part?: { index: number; total: number },
): Promise<ArrayBuffer> {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(template);
  wb.calcProperties.fullCalcOnLoad = true; // status box + Check column recalculate on open

  const lists = wb.getWorksheet("Lists")!;
  const allProjects = [...new Set([...projects, req.project ?? ""].filter(Boolean))];
  for (let r = 2; r <= Math.max(11, allProjects.length + 1); r++) lists.getCell(`A${r}`).value = allProjects[r - 2] ?? null;

  const ws = wb.getWorksheet("Request")!;
  const title = part && part.total > 1 ? `${req.title ?? ""} (part ${part.index} of ${part.total})` : req.title;
  ws.getCell("C4").value = title ?? null;
  ws.getCell("C5").value = owner.full_name ?? null;
  ws.getCell("C6").value = owner.email ?? null;
  ws.getCell("C7").value = req.project ?? null;
  ws.getCell("C8").value = toDate(req.date_submitted) ?? toDate(new Date().toISOString().slice(0, 10));
  ws.getCell("C9").value = toDate(req.needed_by);
  ws.getCell("C10").value = req.urgency ?? null;
  ws.getCell("C11").value = req.justification ?? null;
  if (owner.phone) ws.getCell("G5").value = `Contact phone: ${owner.phone}`;
  if (req.req_number) ws.getCell("G4").value = req.req_number;

  // Project dropdown must cover every project we wrote.
  const projectRange = `Lists!$A$2:$A$${Math.max(10, allProjects.length + 1)}`;
  ws.getCell("C7").dataValidation = { type: "list", allowBlank: true, formulae: [projectRange] };

  for (let n = 0; n < MAX_LINES_PER_FILE; n++) {
    const row = ws.getRow(FIRST_ROW + n);
    const it = items[n];
    row.getCell("B").value = it?.item_name ?? null;
    row.getCell("C").value = it?.qty ?? null;
    row.getCell("D").value = it?.unit ?? null;
    row.getCell("E").value = it?.specification ?? null;
    row.getCell("F").value = it?.datasheet_url ? { text: it.datasheet_url, hyperlink: it.datasheet_url } : null;
    row.getCell("G").value = it?.air_freight ?? null;
    row.getCell("H").value = it?.est_unit_price_usd ?? null;
    row.getCell("J").value = it?.suggested_vendor ?? null;
    row.getCell("K").value = it?.notes ?? null; // also clears the example row's note
  }

  return (await wb.xlsx.writeBuffer()) as ArrayBuffer;
}

/** Template holds 40 lines; longer requests become several files. */
export function chunkItems(items: LineItem[]): LineItem[][] {
  const named = items.filter((i) => (i.item_name ?? "").trim());
  const chunks: LineItem[][] = [];
  for (let i = 0; i < named.length; i += MAX_LINES_PER_FILE) chunks.push(named.slice(i, i + MAX_LINES_PER_FILE));
  return chunks.length ? chunks : [[]];
}

function toDate(iso: string | null | undefined): Date | null {
  if (!iso) return null;
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}
