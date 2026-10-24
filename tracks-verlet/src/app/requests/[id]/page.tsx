"use client";

import { use, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { AppShell } from "@/components/AppShell";
import { LineItemsTable } from "@/components/LineItemsTable";
import { QuestionFlow } from "@/components/QuestionFlow";
import { StatusBox } from "@/components/StatusBox";
import { StatusChip } from "@/components/StatusChip";
import { addBlankItem, deleteRequest, loadRequest, updateProfile, updateRequest, useMe, useProjects, type RequestBundle } from "@/lib/data";
import { downloadRequestXlsx } from "@/lib/download";
import { describeMapping } from "@/lib/bom";
import { BOM_ACCEPT } from "@/lib/bomFile";
import { importBomFile } from "@/lib/importBom";
import { supabase } from "@/lib/supabase/client";
import { MAX_LINES_PER_FILE, readiness, STATUSES, URGENCIES, type ProcRequest, type RequestStatus, type Urgency } from "@/lib/template";

export default function RequestPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const router = useRouter();
  const { me } = useMe();
  const { projects } = useProjects();
  const [bundle, setBundle] = useState<RequestBundle | null | undefined>(undefined);
  const [notice, setNotice] = useState<{ tone: "ok" | "bad"; text: string } | null>(null);
  const [busy, setBusy] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);

  const reload = useCallback(async () => setBundle(await loadRequest(id)), [id]);
  useEffect(() => { reload(); }, [reload]);

  const r = useMemo(() => (bundle ? readiness(bundle.request, bundle.owner, bundle.items) : null), [bundle]);

  if (bundle === undefined) return <AppShell me={me}><p className="hint">Loading…</p></AppShell>;
  if (bundle === null) return <AppShell me={me}><p>Request not found, or you don&apos;t have access. <Link className="text-accent-text" href="/requests">Back</Link></p></AppShell>;

  const { request, owner, items } = bundle;
  const isManager = me?.role === "manager";
  const isOwner = me?.id === request.owner_id;
  const editable = isManager || (isOwner && request.status === "draft");

  async function upload(file: File) {
    setNotice(null);
    setBusy(`Reading ${file.name}…`);
    try {
      const bom = await importBomFile(request.id, file, items);
      const skipped = bom.skipped.map((s) => `${s.count} ${s.reason.toLowerCase()}`).join(", ");
      const kind = bom.source === "fusion360" ? "Fusion 360" : bom.source === "kicad" ? "KiCad" : bom.sheet ? "spreadsheet" : "CSV";
      const read = describeMapping(bom.mapping);
      setNotice({ tone: "ok", text: `Imported ${bom.items.length} part${bom.items.length === 1 ? "" : "s"} from a ${kind} BOM${bom.sheet ? ` (sheet "${bom.sheet}")` : ""}, ${bom.rawRowCount} rows.${read ? ` Read columns: ${read}.` : ""}${skipped ? ` Left out: ${skipped}.` : ""}` });
      await reload();
    } catch (e) {
      setNotice({ tone: "bad", text: (e as Error).message });
    }
    setBusy("");
  }

  async function submit() {
    setBusy("Submitting…");
    try {
      await updateRequest(request.id, { status: "submitted" });
      setNotice({ tone: "ok", text: "Submitted. Procurement can see it now and will reply with a REQ number." });
      await reload();
    } catch (e) {
      setNotice({ tone: "bad", text: (e as Error).message });
    }
    setBusy("");
  }

  async function download() {
    if (!owner) return;
    setBusy("Preparing spreadsheet…");
    try { await downloadRequestXlsx(request, owner, items, projects); } catch (e) { setNotice({ tone: "bad", text: (e as Error).message }); }
    setBusy("");
  }

  async function removeDraft() {
    if (!window.confirm("Delete this draft request and all its line items?")) return;
    await deleteRequest(request.id);
    router.push("/requests");
  }

  return (
    <AppShell me={me}>
      <div className="mb-5 flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <Link href={isManager && !isOwner ? "/manager" : "/requests"} className="hint hover:text-ink">← Back</Link>
          <div className="mt-1 flex flex-wrap items-center gap-3">
            <TitleEditor request={request} editable={editable} onSaved={reload} />
            <StatusChip status={request.status} ready={r!.ready} />
            {request.req_number && <span className="font-mono text-sm text-muted">{request.req_number}</span>}
          </div>
          <p className="hint mt-1">
            {owner?.full_name || owner?.email} · created {new Date(request.created_at).toLocaleDateString()}
            {request.date_submitted && ` · submitted ${request.date_submitted}`}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {editable && <button className="btn" onClick={() => fileRef.current?.click()} disabled={!!busy}>Upload BOM</button>}
          <button className="btn" onClick={download} disabled={!!busy || !owner}>Download .xlsx</button>
          {isOwner && request.status === "draft" && (
            <button className="btn btn-primary" onClick={submit} disabled={!!busy || !r!.ready}
              title={r!.ready ? "" : "Finish the questions until the status reads READY TO SEND"}>
              Submit to procurement
            </button>
          )}
        </div>
        <input ref={fileRef} type="file" accept={BOM_ACCEPT} hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) upload(f); e.target.value = ""; }} />
      </div>

      <div className="space-y-5">
        <StatusBox r={r!} />
        {busy && <p className="hint" aria-live="polite">{busy}</p>}
        {notice && (
          <p className={`rounded-md px-3 py-2 text-sm ${notice.tone === "ok" ? "bg-ok-soft text-ok" : "bg-bad-soft text-bad"}`} role="status">{notice.text}</p>
        )}
        {r!.lineCount > MAX_LINES_PER_FILE && (
          <p className="rounded-md bg-warn-soft px-3 py-2 text-sm text-warn">
            The template holds {MAX_LINES_PER_FILE} lines, so the download will be split into {Math.ceil(r!.lineCount / MAX_LINES_PER_FILE)} files.
          </p>
        )}

        {request.status !== "draft" && isOwner && !isManager && (
          <p className="rounded-md bg-accent-soft px-3 py-2 text-sm">
            This request has been sent, so it&apos;s locked. To change it, use the Change Order form and quote your REQ number.
          </p>
        )}

        {request.manager_note && !isManager && (
          <p className="rounded-md border border-accent bg-accent-soft px-3 py-2 text-sm"><strong>Note from procurement:</strong> {request.manager_note}</p>
        )}

        {isManager && <ManagerPanel request={request} unpriced={r!.unpriced} onSaved={reload} />}

        {editable && items.length === 0 && (
          <button type="button" onClick={() => fileRef.current?.click()}
            className="card flex w-full flex-col items-center gap-1 border-2 border-dashed px-6 py-8 text-center hover:border-accent"
            onDragOver={(e) => e.preventDefault()} onDrop={(e) => { e.preventDefault(); const f = e.dataTransfer.files[0]; if (f) upload(f); }}>
            <span className="font-medium">Drop a BOM (Excel or CSV) here, or click to choose</span>
            <span className="hint">KiCad or Fusion 360 export. You can also add rows by hand below.</span>
          </button>
        )}

        {editable && <QuestionFlow request={request} owner={owner} items={items} projects={projects} onSaved={reload} />}

        <section>
          <div className="mb-2 flex items-end justify-between">
            <h2 className="font-semibold">Line items</h2>
            {editable && (
              <button className="btn btn-sm" onClick={async () => { await addBlankItem(request.id, items.reduce((m, i) => Math.max(m, i.position), 0) + 1); await reload(); }}>
                + Add row
              </button>
            )}
          </div>
          <LineItemsTable items={items} editable={editable} onSaved={reload} />
        </section>

        <RequestDetails request={request} owner={owner} projects={projects} editable={editable} canEditName={isOwner} onSaved={reload} />

        {isOwner && request.status === "draft" && (
          <div className="pt-4 text-right">
            <button className="btn btn-ghost btn-sm text-bad" onClick={removeDraft}>Delete draft</button>
          </div>
        )}
      </div>
    </AppShell>
  );
}

function TitleEditor({ request, editable, onSaved }: { request: ProcRequest; editable: boolean; onSaved: () => Promise<void> }) {
  const [v, setV] = useState(request.title ?? "");
  if (!editable) return <h1 className="font-display text-3xl tracking-tight">{request.title || "Untitled request"}</h1>;
  return (
    <input aria-label="Request title" value={v} placeholder="Untitled request"
      className="-ml-1.5 min-w-0 rounded-md border border-transparent bg-transparent px-1.5 font-display text-3xl tracking-tight hover:border-line focus:border-accent focus:outline-none"
      onChange={(e) => setV(e.target.value)}
      onBlur={async () => { if (v.trim() !== (request.title ?? "")) { await updateRequest(request.id, { title: v.trim() || null }); await onSaved(); } }}
      onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }} />
  );
}

function RequestDetails({ request, owner, projects, editable, canEditName, onSaved }: {
  request: ProcRequest; owner: RequestBundle["owner"]; projects: string[]; editable: boolean; canEditName: boolean; onSaved: () => Promise<void>;
}) {
  const save = async (patch: Partial<ProcRequest>) => { await updateRequest(request.id, patch); await onSaved(); };
  return (
    <section className="card p-5">
      <h2 className="mb-4 font-semibold">Request details</h2>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Field label="Your name">
          <input className="input" defaultValue={owner?.full_name ?? ""} disabled={!canEditName}
            onBlur={async (e) => { if (owner && e.target.value.trim() !== (owner.full_name ?? "")) { await updateProfile(owner.id, { full_name: e.target.value.trim() || null }); await onSaved(); } }} />
        </Field>
        <Field label="Your email"><input className="input" value={owner?.email ?? ""} disabled readOnly /></Field>
        <Field label="Phone (optional)">
          <input className="input" defaultValue={owner?.phone ?? ""} disabled={!canEditName}
            onBlur={async (e) => { if (owner && e.target.value.trim() !== (owner.phone ?? "")) { await updateProfile(owner.id, { phone: e.target.value.trim() || null }); await onSaved(); } }} />
        </Field>
        <Field label="Project / cost centre">
          <select className="input" value={request.project ?? ""} disabled={!editable} onChange={(e) => save({ project: e.target.value || null })}>
            <option value="">Choose…</option>
            {projects.map((p) => <option key={p}>{p}</option>)}
          </select>
        </Field>
        <Field label="Needed by">
          <input type="date" className="input" value={request.needed_by ?? ""} disabled={!editable} onChange={(e) => save({ needed_by: e.target.value || null })} />
        </Field>
        <Field label="Urgency">
          <select className="input" value={request.urgency ?? ""} disabled={!editable} onChange={(e) => save({ urgency: (e.target.value || null) as Urgency | null })}>
            <option value="">Choose…</option>
            {URGENCIES.map((u) => <option key={u}>{u}</option>)}
          </select>
        </Field>
        <div className="sm:col-span-2 lg:col-span-4">
          <Field label="Why this is needed">
            <textarea className="input" rows={2} defaultValue={request.justification ?? ""} disabled={!editable}
              onBlur={(e) => { if (e.target.value.trim() !== (request.justification ?? "")) save({ justification: e.target.value.trim() || null }); }} />
          </Field>
        </div>
      </div>
    </section>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <label className="block"><span className="label">{label}</span>{children}</label>;
}

function ManagerPanel({ request, unpriced, onSaved }: { request: ProcRequest; unpriced: number; onSaved: () => Promise<void> }) {
  const [error, setError] = useState("");
  const act = async (fn: () => Promise<unknown>) => {
    setError("");
    try { await fn(); await onSaved(); } catch (e) { setError((e as Error).message); }
  };
  return (
    <section className="card border-accent p-5">
      <h2 className="mb-3 font-semibold">Procurement</h2>
      <div className="flex flex-wrap items-end gap-4">
        <label className="block">
          <span className="label">Status</span>
          <select className="input w-40" value={request.status}
            onChange={(e) => act(() => updateRequest(request.id, { status: e.target.value as RequestStatus }))}>
            {STATUSES.map((s) => <option key={s} value={s} className="capitalize">{s}</option>)}
          </select>
        </label>
        <div>
          <span className="label">REQ number</span>
          {request.req_number ? (
            <span className="font-mono">{request.req_number}</span>
          ) : (
            <button className="btn" onClick={() => act(async () => {
              const { error } = await supabase().rpc("assign_req_number", { rid: request.id });
              if (error) throw error;
            })}>Assign next REQ number</button>
          )}
        </div>
        <label className="block min-w-64 flex-1">
          <span className="label">Note to requester</span>
          <input className="input" defaultValue={request.manager_note ?? ""}
            onBlur={(e) => { if (e.target.value !== (request.manager_note ?? "")) act(() => updateRequest(request.id, { manager_note: e.target.value || null })); }} />
        </label>
      </div>
      {unpriced > 0 && (
        <p className="mt-3 text-sm text-warn">{unpriced} line(s) have no price yet. Fill them in the Est. price column before approving.</p>
      )}
      {error && <p className="mt-3 text-sm text-bad" role="alert">{error}</p>}
    </section>
  );
}
