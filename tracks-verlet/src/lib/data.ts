"use client";
// Thin data layer over supabase-js. RLS decides what each user can see and change.
import { useCallback, useEffect, useState } from "react";
import { supabase } from "./supabase/client";
import type { LineItem, ProcRequest, Profile } from "./template";
import type { DraftItem, ParsedBom } from "./bom";

export function useMe() {
  const [me, setMe] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);
  const reload = useCallback(async () => {
    const sb = supabase();
    const { data: { user } } = await sb.auth.getUser();
    if (!user) { setMe(null); setLoading(false); return; }
    const { data } = await sb.from("profiles").select("*").eq("id", user.id).single();
    setMe(data as Profile | null);
    setLoading(false);
  }, []);
  useEffect(() => { reload(); }, [reload]);
  return { me, loading, reload };
}

export function useProjects() {
  const [projects, setProjects] = useState<string[]>([]);
  const reload = useCallback(async () => {
    const { data } = await supabase().from("projects").select("name").eq("active", true).order("created_at");
    setProjects((data ?? []).map((p: { name: string }) => p.name));
  }, []);
  useEffect(() => { reload(); }, [reload]);
  return { projects, reload };
}

export type RequestBundle = { request: ProcRequest; owner: Profile | null; items: LineItem[] };

export async function loadRequest(id: string): Promise<RequestBundle | null> {
  const sb = supabase();
  const { data: request } = await sb.from("requests").select("*").eq("id", id).single();
  if (!request) return null;
  const [{ data: owner }, { data: items }] = await Promise.all([
    sb.from("profiles").select("*").eq("id", request.owner_id).single(),
    sb.from("line_items").select("*").eq("request_id", id).order("position").order("created_at"),
  ]);
  return { request, owner, items: (items ?? []).map(normaliseItem) };
}

// numeric columns come back as strings from PostgREST
function normaliseItem(i: LineItem): LineItem {
  const n = (v: unknown) => (v === null || v === undefined || v === "" ? null : Number(v));
  return { ...i, qty: n(i.qty), est_unit_price_usd: n(i.est_unit_price_usd), auto_fields: i.auto_fields ?? [] };
}

export async function updateRequest(id: string, patch: Partial<ProcRequest>) {
  const { error } = await supabase().from("requests").update(patch).eq("id", id);
  if (error) throw error;
}

export async function updateProfile(id: string, patch: Partial<Pick<Profile, "full_name" | "phone">>) {
  const { error } = await supabase().from("profiles").update(patch).eq("id", id);
  if (error) throw error;
}

/** Patch several line items. Touched fields stop being "auto" because a person confirmed them. */
export async function updateItems(items: LineItem[], patches: Record<string, Partial<LineItem>>) {
  const sb = supabase();
  await Promise.all(
    Object.entries(patches).map(async ([id, patch]) => {
      const current = items.find((i) => i.id === id);
      const auto = (current?.auto_fields ?? []).filter((f) => !(f in patch));
      const { error } = await sb.from("line_items").update({ ...patch, auto_fields: auto }).eq("id", id);
      if (error) throw error;
    }),
  );
}

export async function addItems(requestId: string, startPosition: number, drafts: DraftItem[], bomUploadId: string | null) {
  if (!drafts.length) return;
  const rows = drafts.map((d, n) => ({
    request_id: requestId,
    bom_upload_id: bomUploadId,
    position: startPosition + n,
    item_name: d.item_name,
    qty: d.qty,
    unit: d.unit,
    specification: d.specification || null,
    datasheet_url: d.datasheet_url,
    air_freight: d.air_freight,
    est_unit_price_usd: d.est_unit_price_usd,
    suggested_vendor: d.suggested_vendor,
    notes: d.notes,
    source_row: d.source_row,
    auto_fields: d.auto_fields,
  }));
  const { error } = await supabase().from("line_items").insert(rows);
  if (error) throw error;
}

export async function recordUpload(requestId: string, filename: string, bom: ParsedBom) {
  const { data, error } = await supabase()
    .from("bom_uploads")
    .insert({
      request_id: requestId,
      filename,
      source: bom.source,
      headers: bom.headers,
      raw_row_count: bom.rawRowCount,
      item_count: bom.items.length,
    })
    .select("id")
    .single();
  if (error) throw error;
  return data.id as string;
}

export async function addBlankItem(requestId: string, position: number) {
  const { error } = await supabase().from("line_items").insert({ request_id: requestId, position, item_name: "New item", qty: 1 });
  if (error) throw error;
}

export async function deleteItem(id: string) {
  const { error } = await supabase().from("line_items").delete().eq("id", id);
  if (error) throw error;
}

export async function createRequest(title: string | null) {
  const { data, error } = await supabase().from("requests").insert({ title }).select("id").single();
  if (error) throw error;
  return data.id as string;
}

export async function deleteRequest(id: string) {
  const { error } = await supabase().from("requests").delete().eq("id", id);
  if (error) throw error;
}

export async function signOut() {
  await supabase().auth.signOut();
  location.href = "/login";
}
