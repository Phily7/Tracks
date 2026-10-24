"use client";
import { parseBomCsv, type ParsedBom } from "./bom";
import { addItems, recordUpload } from "./data";
import type { LineItem } from "./template";

export async function importBomFile(requestId: string, file: File, existing: LineItem[]): Promise<ParsedBom> {
  if (!/\.(csv|tsv|txt)$/i.test(file.name)) throw new Error("Upload a .csv export from KiCad, Fusion 360 or a spreadsheet.");
  const bom = parseBomCsv(await file.text(), file.name);
  if (!bom.items.length) throw new Error("No parts found. Check the file has a header row with names or values and quantities.");

  // Parts already on the request (same name) get their quantity topped up instead of duplicated.
  const byName = new Map(existing.map((i) => [(i.item_name ?? "").trim().toLowerCase(), i]));
  const fresh = bom.items.filter((d) => !byName.has(d.item_name.toLowerCase()));
  const uploadId = await recordUpload(requestId, file.name, bom);
  const startAt = existing.reduce((m, i) => Math.max(m, i.position), 0) + 1;
  await addItems(requestId, startAt, fresh, uploadId);

  const { supabase } = await import("./supabase/client");
  await Promise.all(
    bom.items
      .filter((d) => byName.has(d.item_name.toLowerCase()))
      .map((d) => {
        const cur = byName.get(d.item_name.toLowerCase())!;
        return supabase().from("line_items").update({ qty: (cur.qty ?? 0) + d.qty }).eq("id", cur.id);
      }),
  );
  return bom;
}

export const titleFromFilename = (name: string) =>
  name.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").replace(/\bbom\b/i, "").replace(/\s+/g, " ").trim() || "New request";
