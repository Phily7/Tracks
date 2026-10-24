"use client";
import { exportFileName, type LineItem, type ProcRequest, type Profile } from "./template";

export async function downloadRequestXlsx(req: ProcRequest, owner: Profile, items: LineItem[], projects: string[]) {
  const { chunkItems, fillTemplate, TEMPLATE_PATH } = await import("./export"); // exceljs is large; load on demand
  const template = await (await fetch(TEMPLATE_PATH)).arrayBuffer();
  const chunks = chunkItems(items);
  const base = exportFileName(owner.full_name, req.project);
  for (let n = 0; n < chunks.length; n++) {
    const buf = await fillTemplate(template, req, owner, chunks[n], projects,
      chunks.length > 1 ? { index: n + 1, total: chunks.length } : undefined);
    const name = chunks.length > 1 ? base.replace(/\.xlsx$/, `_part${n + 1}.xlsx`) : base;
    const url = URL.createObjectURL(new Blob([buf], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }));
    const a = Object.assign(document.createElement("a"), { href: url, download: name });
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  }
}
