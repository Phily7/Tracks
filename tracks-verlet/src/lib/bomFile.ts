// Any uploaded BOM file -> a grid of cell texts. CSV/TSV directly; Excel workbooks sheet by sheet,
// keeping the sheet that looks most like a parts list.
import { csvRows, findTable } from "./bom";

export const BOM_ACCEPT = ".csv,.tsv,.txt,.xlsx,.xlsm";

export async function readBomGrid(file: File): Promise<{ rows: string[][]; sheet: string | null }> {
  const name = file.name.toLowerCase();
  if (/\.(csv|tsv|txt)$/.test(name)) return { rows: csvRows(await file.text()), sheet: null };
  if (/\.xls$/.test(name))
    throw new Error("That's the old .xls format. Open it in Excel and use Save As → .xlsx (or .csv), then upload again.");
  if (!/\.(xlsx|xlsm)$/.test(name))
    throw new Error("Upload a BOM as .xlsx or .csv (KiCad, Fusion 360, or any spreadsheet with part names and quantities).");

  const ExcelJS = (await import("exceljs")).default; // large; load only when needed
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(await file.arrayBuffer());

  let best: { rows: string[][]; sheet: string; score: number } | null = null;
  wb.eachSheet((ws) => {
    if (ws.state !== "visible") return;
    const rows: string[][] = [];
    ws.eachRow({ includeEmpty: false }, (row) => {
      const cells: string[] = [];
      for (let c = 1; c <= ws.columnCount; c++) cells.push(cellText(row.getCell(c)));
      if (cells.some((v) => v.trim())) rows.push(cells);
    });
    if (!rows.length) return;
    // Prefer a sheet with a recognisable header row, then the one with more rows.
    const score = findTable(rows).score * 10000 + rows.length;
    if (!best || score > best.score) best = { rows, sheet: ws.name, score };
  });
  if (!best) throw new Error("That workbook has no data in it.");
  const { rows, sheet } = best;
  return { rows, sheet };
}

function cellText(cell: import("exceljs").Cell): string {
  try {
    const v = cell.value;
    if (v && typeof v === "object" && "hyperlink" in v) return String(v.hyperlink); // keep the URL, not the label
    return (cell.text ?? "").replace(/\s+/g, " ").trim();
  } catch {
    return "";
  }
}
