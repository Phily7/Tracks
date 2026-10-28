"use client";

import { use, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { AppShell } from "@/components/AppShell";
import { LineItemsTable } from "@/components/LineItemsTable";
import { QuestionFlow } from "@/components/QuestionFlow";
import { StatusBox } from "@/components/StatusBox";
import { StatusChip } from "@/components/StatusChip";
import { addBlankItem, approveRequest, deleteRequest, discardChanges, loadRequest, updateProfile, updateRequest, useMe, useProjects, type RequestBundle } from "@/lib/data";
import { downloadRequestXlsx } from "@/lib/download";
import { describeMapping } from "@/lib/bom";
import { BOM_ACCEPT } from "@/lib/bomFile";
import { importBomFile } from "@/lib/importBom";
import { supabase } from "@/lib/supabase/client";
import {
  confirmedItems, confirmedRequest, headerChanges, MAX_LINES_PER_FILE, pendingChanges, readiness, STATUSES, URGENCIES,
  type HeaderField, type ProcRequest, type RequestStatus, type Urgency,
} from "@/lib/template";

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
  // Engineers keep editing their own requests after submitting; once approved, edits become pending changes.
  const editable = isManager || isOwner;
  const tracking = !!request.approved_at;
  const pending = pendingChanges(request, items);
  const approvedOn = request.approved_at ? new Date(request.approved_at).toLocaleDateString() : "";

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
      setNotice({ tone: "ok", text: "Submitted. Procurement can see it now and will reply with a REQ number. You can still edit it until it's approved." });
      await reload();
    } catch (e) {
      setNotice({ tone: "bad", text: (e as Error).message });
    }
    setBusy("");
  }

  async function download() {
    if (!owner) return;
    setBusy("Preparing spreadsheet…");
    // Once approved, procurement buys from the confirmed BOM, not from edits still waiting for approval.
    const [req, rows] = tracking ? [confirmedRequest(request), confirmedItems(items)] : [request, items];
    try { await downloadRequestXlsx(req, owner, rows, projects); } catch (e) { setNotice({ tone: "bad", text: (e as Error).message }); }
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
            <TitleEditor key={request.updated_at} request={request} editable={editable} onSaved={reload} />
            <StatusChip status={request.status} ready={r!.ready} pending={pending} />
            {request.req_number && <span className="font-mono text-sm text-muted">{request.req_number}</span>}
          </div>
          <p className="hint mt-1">
            {owner?.full_name || owner?.email} · created {new Date(request.created_at).toLocaleDateString()}
            {request.date_submitted && ` · submitted ${request.date_submitted}`}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {editable && <button className="btn" onClick={() => fileRef.current?.click()} disabled={!!busy}>Upload BOM</button>}
          <button className="btn" onClick={download} disabled={!!busy || !owner}
            title={tracking ? "The confirmed BOM, without changes still waiting for approval" : ""}>
            {tracking ? "Download confirmed .xlsx" : "Download .xlsx"}
          </button>
          {isOwner && (request.status === "draft" || request.status === "rejected") && (
            <button className="btn btn-primary" onClick={submit} disabled={!!busy || !r!.ready}
              title={r!.ready ? "" : "Finish the questions until the status reads READY TO SEND"}>
              {request.status === "rejected" ? "Resubmit" : "Submit to procurement"}
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

        {tracking && pending > 0 && (
          <ChangesBanner request={request} pending={pending} approvedOn={approvedOn} isManager={isManager} onSaved={reload} />
        )}
        {tracking && pending === 0 && editable && (
          <p className="rounded-md bg-accent-soft px-3 py-2 text-sm">
            Approved on {approvedOn}. You can still edit it: changes are highlighted and join the confirmed BOM once a manager approves them.
          </p>
        )}
        {request.status === "submitted" && !tracking && isOwner && !isManager && (
          <p className="rounded-md bg-accent-soft px-3 py-2 text-sm">
            Sent to procurement. You can still edit it until it&apos;s approved, for example if they ask you to clarify something.
          </p>
        )}

        {request.manager_note && !isManager && (
          <p className="rounded-md border border-accent bg-accent-soft px-3 py-2 text-sm"><strong>Note from procurement:</strong> {request.manager_note}</p>
        )}

        {isManager && <ManagerPanel request={request} unpriced={r!.unpriced} ready={r!.ready} onSaved={reload} />}

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
            <h2 className="font-semibold">
              {!tracking ? "Line items" : pending ? "Line items, with pending changes" : "Confirmed BOM"}
            </h2>
            {editable && (
              <button className="btn btn-sm" onClick={async () => { await addBlankItem(request.id, items.reduce((m, i) => Math.max(m, i.position), 0) + 1); await reload(); }}>
                + Add row
              </button>
            )}
          </div>
          <LineItemsTable items={items} editable={editable} tracking={tracking} onSaved={reload} />
        </section>

        {tracking && pending > 0 && (
          <details className="card p-4">
            <summary className="cursor-pointer font-semibold">Confirmed BOM <span className="hint font-normal">as approved on {approvedOn}</span></summary>
            <div className="mt-3"><LineItemsTable items={confirmedItems(items)} editable={false} onSaved={reload} /></div>
          </details>
        )}

        <RequestDetails key={request.updated_at} request={request} owner={owner} projects={projects} editable={editable} canEditName={isOwner} onSaved={reload}
          changed={headerChanges(request)} />

        {isOwner && request.status === "draft" && (
          <div className="pt-4 text-right">
            <button className="btn btn-ghost btn-sm text-bad" onClick={removeDraft}>Delete draft</button>
          </div>
        )}
      </div>
    </AppShell>
  );
}

function ChangesBanner({ request, pending, approvedOn, isManager, onSaved }: {
  request: ProcRequest; pending: number; approvedOn: string; isManager: boolean; onSaved: () => Promise<void>;
}) {
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState("");
  const run = async (fn: () => Promise<void>) => {
    setError("");
    try { await fn(); setConfirming(false); await onSaved(); } catch (e) { setError((e as Error).message); }
  };
  return (
    <section className="rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm" aria-live="polite">
      <p>
        <strong>{pending} pending change{pending === 1 ? "" : "s"}</strong> since this was approved on {approvedOn}.
        {" "}Highlighted below: <span className="chip chip-ok">New</span> <span className="chip chip-warn">Changed</span> <span className="chip chip-bad">Removed</span>.
        {" "}{isManager ? "Approving adds them to the confirmed BOM." : "A manager needs to approve them before they join the confirmed BOM."}
      </p>
      <div className="mt-2 flex flex-wrap items-center gap-2">
        {isManager && <button className="btn btn-primary btn-sm" onClick={() => run(() => approveRequest(request.id))}>Approve changes</button>}
        {!confirming ? (
          <button className="btn btn-sm" onClick={() => setConfirming(true)}>Discard changes</button>
        ) : (
          <>
            <span>Go back to the confirmed BOM?</span>
            <button className="btn btn-sm text-bad" onClick={() => run(() => discardChanges(request.id))}>Yes, discard</button>
            <button className="btn btn-ghost btn-sm" onClick={() => setConfirming(false)}>Keep them</button>
          </>
        )}
      </div>
      {error && <p className="mt-2 text-bad" role="alert">{error}</p>}
    </section>
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

function RequestDetails({ request, owner, projects, editable, canEditName, onSaved, changed }: {
  request: ProcRequest; owner: RequestBundle["owner"]; projects: string[]; editable: boolean; canEditName: boolean; onSaved: () => Promise<void>;
  changed: HeaderField[];
}) {
  const save = async (patch: Partial<ProcRequest>) => { await updateRequest(request.id, patch); await onSaved(); };
  // The confirmed value, for header fields edited since approval.
  const was = (f: HeaderField) => (changed.includes(f) ? request.approved_snapshot?.[f] ?? "—" : undefined);
  return (
    <section className="card p-5">
      <h2 className="mb-4 font-semibold">Request details</h2>
      {changed.includes("title") && (
        <p className="mb-3 text-sm">Title changed since approval. Was: <del className="text-muted">{request.approved_snapshot?.title || "—"}</del></p>
      )}
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
        <Field label="Project / cost centre" was={was("project")}>
          <select className="input" value={request.project ?? ""} disabled={!editable} onChange={(e) => save({ project: e.target.value || null })}>
            <option value="">Choose…</option>
            {projects.map((p) => <option key={p}>{p}</option>)}
          </select>
        </Field>
        <Field label="Needed by" was={was("needed_by")}>
          <input type="date" className="input" value={request.needed_by ?? ""} disabled={!editable} onChange={(e) => save({ needed_by: e.target.value || null })} />
        </Field>
        <Field label="Urgency" was={was("urgency")}>
          <select className="input" value={request.urgency ?? ""} disabled={!editable} onChange={(e) => save({ urgency: (e.target.value || null) as Urgency | null })}>
            <option value="">Choose…</option>
            {URGENCIES.map((u) => <option key={u}>{u}</option>)}
          </select>
        </Field>
        <div className="sm:col-span-2 lg:col-span-4">
          <Field label="Why this is needed" was={was("justification")}>
            <textarea className="input" rows={2} defaultValue={request.justification ?? ""} disabled={!editable}
              onBlur={(e) => { if (e.target.value.trim() !== (request.justification ?? "")) save({ justification: e.target.value.trim() || null }); }} />
          </Field>
        </div>
      </div>
    </section>
  );
}

function Field({ label, children, was }: { label: string; children: React.ReactNode; was?: string | null }) {
  return (
    <label className={`block ${was !== undefined ? "rounded-md bg-warn-soft p-1.5 -m-1.5" : ""}`}>
      <span className="label">{label}{was !== undefined && <span className="chip chip-warn ml-2">Changed</span>}</span>
      {children}
      {was !== undefined && <span className="mt-1 block text-xs text-muted">Was: <del>{was || "—"}</del></span>}
    </label>
  );
}

function ManagerPanel({ request, unpriced, ready, onSaved }: { request: ProcRequest; unpriced: number; ready: boolean; onSaved: () => Promise<void> }) {
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
            onChange={(e) => {
              const status = e.target.value as RequestStatus;
              // Approving goes through approve_request so the BOM gets confirmed.
              act(() => (status === "approved" ? approveRequest(request.id) : updateRequest(request.id, { status })));
            }}>
            {STATUSES.map((s) => <option key={s} value={s} className="capitalize">{s}</option>)}
          </select>
        </label>
        {request.status === "submitted" && (
          <button className="btn btn-primary" disabled={!ready || unpriced > 0} onClick={() => act(() => approveRequest(request.id))}
            title={!ready ? "Some lines still need attention" : unpriced > 0 ? "Price every line first" : "Confirm this BOM"}>
            Approve
          </button>
        )}
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
