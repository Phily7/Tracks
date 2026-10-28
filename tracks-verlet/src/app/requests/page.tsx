"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { AppShell } from "@/components/AppShell";
import { StatusChip } from "@/components/StatusChip";
import { createRequest, useMe } from "@/lib/data";
import { BOM_ACCEPT } from "@/lib/bomFile";
import { importBomFile, titleFromFilename } from "@/lib/importBom";
import { supabase } from "@/lib/supabase/client";
import { usd, type ProcRequest } from "@/lib/template";

type Summary = ProcRequest & { line_count: number; est_total_usd: number; issues: string[]; pending_changes: number };

export default function MyRequests() {
  const { me } = useMe();
  const router = useRouter();
  const [rows, setRows] = useState<Summary[] | null>(null);
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [dragging, setDragging] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    if (!me) return;
    const { data } = await supabase().from("request_summaries").select("*").eq("owner_id", me.id).order("updated_at", { ascending: false });
    setRows((data ?? []) as Summary[]);
  }, [me]);
  useEffect(() => { load(); }, [load]);

  async function startFromFile(file: File) {
    setError("");
    setBusy(`Reading ${file.name}…`);
    let id: string | null = null;
    try {
      id = await createRequest(titleFromFilename(file.name));
      await importBomFile(id, file, []);
      router.push(`/requests/${id}`);
    } catch (e) {
      setError((e as Error).message);
      setBusy("");
      if (id) router.push(`/requests/${id}`);
    }
  }

  async function startBlank() {
    setBusy("Creating…");
    try {
      router.push(`/requests/${await createRequest(null)}`);
    } catch (e) {
      setError((e as Error).message);
      setBusy("");
    }
  }

  return (
    <AppShell me={me}>
      <div
        onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => { e.preventDefault(); setDragging(false); const f = e.dataTransfer.files[0]; if (f) startFromFile(f); }}
      >
        <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 className="font-display text-3xl tracking-tight">My requests</h1>
            <p className="hint mt-1">One request per purchase. Drop a BOM to start one.</p>
          </div>
          <button className="btn" onClick={startBlank} disabled={!!busy}>New empty request</button>
        </div>

        <button
          type="button"
          onClick={() => fileRef.current?.click()}
          disabled={!!busy}
          className={`card mb-8 flex w-full flex-col items-center justify-center gap-2 border-2 border-dashed px-6 py-10 text-center transition ${dragging ? "border-accent bg-accent-soft" : "hover:border-accent"}`}
        >
          <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="var(--accent)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M12 16V4M7 9l5-5 5 5M4 16v3a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-3" />
          </svg>
          <span className="font-medium">{busy || "Drop a BOM (Excel or CSV) here, or click to choose"}</span>
          <span className="hint">KiCad, Fusion 360, or any .xlsx / .csv parts list. Column names don&apos;t matter; missing details get asked for next.</span>
        </button>
        <input ref={fileRef} type="file" accept={BOM_ACCEPT} hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) startFromFile(f); e.target.value = ""; }} />
        {error && <p className="mb-6 rounded-md bg-bad-soft px-3 py-2 text-sm text-bad" role="alert">{error}</p>}

        {rows === null ? (
          <p className="hint">Loading…</p>
        ) : rows.length === 0 ? (
          <p className="hint">No requests yet.</p>
        ) : (
          <div className="card overflow-x-auto">
            <table className="tbl">
              <thead>
                <tr><th>Request</th><th>Project</th><th>Lines</th><th>Est. total</th><th>Needed by</th><th>Status</th></tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id} className="hover:bg-bg">
                    <td>
                      <Link href={`/requests/${r.id}`} className="font-medium hover:underline">{r.title || "Untitled request"}</Link>
                      {r.req_number && <span className="ml-2 font-mono text-xs text-muted">{r.req_number}</span>}
                    </td>
                    <td>{r.project ?? "—"}</td>
                    <td>{r.line_count}</td>
                    <td>{usd(Number(r.est_total_usd))}</td>
                    <td>{r.needed_by ?? "—"}</td>
                    <td><StatusChip status={r.status} ready={r.issues.length === 0} pending={r.pending_changes} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </AppShell>
  );
}
