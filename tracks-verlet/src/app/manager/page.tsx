"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { AppShell } from "@/components/AppShell";
import { StatusChip } from "@/components/StatusChip";
import { useMe } from "@/lib/data";
import { supabase } from "@/lib/supabase/client";
import { STATUSES, usd, type ProcRequest, type Profile, type RequestStatus } from "@/lib/template";

type Summary = ProcRequest & {
  owner_name: string | null; owner_email: string; line_count: number; est_total_usd: number;
  has_air_restricted: boolean | null; issues: string[]; unpriced_count: number;
};

const URGENCY_RANK: Record<string, number> = { "Blocking work right now": 0, "Blocking within 2 weeks": 1, Normal: 2 };

export default function ManagerPage() {
  const { me, loading } = useMe();
  const [rows, setRows] = useState<Summary[]>([]);
  const [filter, setFilter] = useState<RequestStatus | "open">("open");
  const [showDrafts, setShowDrafts] = useState(false);

  const load = useCallback(async () => {
    const { data } = await supabase().from("request_summaries").select("*").order("updated_at", { ascending: false });
    setRows((data ?? []) as Summary[]);
  }, []);
  useEffect(() => { if (me?.role === "manager") load(); }, [me, load]);

  const visible = useMemo(() => rows
    .filter((r) => (showDrafts ? true : r.status !== "draft"))
    .filter((r) => (filter === "open" ? ["draft", "submitted", "approved"].includes(r.status) : r.status === filter))
    .sort((a, b) => (URGENCY_RANK[a.urgency ?? "Normal"] - URGENCY_RANK[b.urgency ?? "Normal"]) || (a.needed_by ?? "9").localeCompare(b.needed_by ?? "9")),
  [rows, filter, showDrafts]);

  if (loading) return <AppShell me={me}><p className="hint">Loading…</p></AppShell>;
  if (me?.role !== "manager") return <AppShell me={me}><p>This page is for managers. <Link href="/requests" className="text-accent-text">Go to my requests</Link></p></AppShell>;

  const submitted = rows.filter((r) => r.status === "submitted");
  const byProject = Object.entries(
    rows.filter((r) => r.status !== "draft" && r.status !== "rejected")
      .reduce<Record<string, number>>((m, r) => ({ ...m, [r.project ?? "—"]: (m[r.project ?? "—"] ?? 0) + Number(r.est_total_usd) }), {}),
  ).sort((a, b) => b[1] - a[1]);
  const maxProject = Math.max(1, ...byProject.map(([, v]) => v));

  return (
    <AppShell me={me}>
      <h1 className="mb-5 font-display text-3xl tracking-tight">Procurement overview</h1>

      <div className="mb-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Kpi label="Waiting for review" value={String(submitted.length)} />
        <Kpi label="Blocking work" value={String(rows.filter((r) => r.status === "submitted" && r.urgency?.startsWith("Blocking")).length)} tone="bad" />
        <Kpi label="Value waiting (est.)" value={usd(submitted.reduce((s, r) => s + Number(r.est_total_usd), 0))} />
        <Kpi label="With air-restricted items" value={String(rows.filter((r) => r.status === "submitted" && r.has_air_restricted).length)} tone="warn" />
      </div>

      <div className="grid gap-6 lg:grid-cols-[1fr_20rem]">
        <section>
          <div className="mb-2 flex flex-wrap items-center gap-2">
            {(["open", ...STATUSES.filter((s) => s !== "draft")] as const).map((s) => (
              <button key={s} onClick={() => setFilter(s)} className={`btn btn-sm capitalize ${filter === s ? "border-accent bg-accent-soft text-accent-text" : ""}`}>{s}</button>
            ))}
            <label className="ml-auto flex items-center gap-2 text-sm">
              <input type="checkbox" checked={showDrafts} onChange={(e) => setShowDrafts(e.target.checked)} /> Include drafts
            </label>
          </div>
          <div className="card overflow-x-auto">
            <table className="tbl">
              <thead><tr><th>Request</th><th>Requester</th><th>Project</th><th>Urgency</th><th>Needed by</th><th className="text-right">Est.</th><th>Status</th></tr></thead>
              <tbody>
                {visible.length === 0 && <tr><td colSpan={7} className="py-8 text-center text-muted">Nothing here.</td></tr>}
                {visible.map((r) => (
                  <tr key={r.id} className="hover:bg-bg">
                    <td>
                      <Link href={`/requests/${r.id}`} className="font-medium hover:underline">{r.title || "Untitled"}</Link>
                      <div className="text-xs text-muted">
                        {r.req_number && <span className="mr-2 font-mono">{r.req_number}</span>}
                        {r.line_count} lines{r.has_air_restricted && <span className="ml-2 text-bad">air-restricted</span>}
                        {r.unpriced_count > 0 && <span className="ml-2 text-warn">{r.unpriced_count} unpriced</span>}
                      </div>
                    </td>
                    <td>{r.owner_name || r.owner_email}</td>
                    <td>{r.project ?? "—"}</td>
                    <td className={r.urgency?.startsWith("Blocking") ? "font-medium text-bad" : ""}>{r.urgency ?? "—"}</td>
                    <td className="tabular-nums">{r.needed_by ?? "—"}</td>
                    <td className="text-right tabular-nums">{usd(Number(r.est_total_usd))}</td>
                    <td><StatusChip status={r.status} ready={r.issues.length === 0} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <aside className="space-y-6">
          <section className="card p-4">
            <h2 className="mb-3 font-semibold">Estimated spend by project</h2>
            {byProject.length === 0 ? <p className="hint">No submitted requests yet.</p> : (
              <ul className="space-y-2.5">
                {byProject.map(([p, v]) => (
                  <li key={p} className="text-sm">
                    <div className="flex justify-between"><span>{p}</span><span className="tabular-nums">{usd(v)}</span></div>
                    <div className="mt-1 h-1.5 rounded-full bg-bg"><div className="h-1.5 rounded-full bg-accent" style={{ width: `${(v / maxProject) * 100}%` }} /></div>
                  </li>
                ))}
              </ul>
            )}
          </section>
          <Team meId={me.id} meOwner={!!me.is_owner} />
          <Projects />
        </aside>
      </div>
    </AppShell>
  );
}

function Kpi({ label, value, tone }: { label: string; value: string; tone?: "bad" | "warn" }) {
  return (
    <div className="card px-4 py-3">
      <div className="text-xs text-muted">{label}</div>
      <div className={`mt-1 text-2xl font-semibold tabular-nums ${tone === "bad" ? "text-bad" : tone === "warn" ? "text-warn" : ""}`}>{value}</div>
    </div>
  );
}

function Team({ meId, meOwner }: { meId: string; meOwner: boolean }) {
  const [entries, setEntries] = useState<string[]>([]);
  const [people, setPeople] = useState<Profile[]>([]);
  const [v, setV] = useState("");
  const [error, setError] = useState("");
  const load = useCallback(async () => {
    const sb = supabase();
    const [{ data: a }, { data: p }] = await Promise.all([
      sb.from("allowlist").select("entry").order("created_at"),
      sb.from("profiles").select("*").order("created_at"),
    ]);
    setEntries((a ?? []).map((x: { entry: string }) => x.entry));
    setPeople((p ?? []) as Profile[]);
  }, []);
  useEffect(() => { load(); }, [load]);

  const add = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    const entry = v.trim().toLowerCase();
    if (!entry.includes("@")) { setError("Enter an email, or @domain.com for everyone at a domain"); return; }
    const { error } = await supabase().from("allowlist").insert({ entry });
    if (error) setError(error.message); else { setV(""); load(); }
  };
  const remove = async (entry: string) => { await supabase().from("allowlist").delete().eq("entry", entry); load(); };
  const setRole = async (p: Profile, role: Profile["role"]) => {
    setError("");
    const { error } = await supabase().rpc("set_role", { target: p.id, new_role: role });
    if (error) setError(error.message); else load();
  };

  return (
    <section className="card p-4">
      <h2 className="font-semibold">Engineers</h2>
      <p className="hint mb-3">Who can sign in with an email code. Add an address, or <code>@verlet.co</code> for everyone.</p>
      <form onSubmit={add} className="mb-3 flex gap-2">
        <input className="input" value={v} onChange={(e) => setV(e.target.value)} placeholder="name@verlet.co" aria-label="Email or domain to allow" />
        <button className="btn">Add</button>
      </form>
      {error && <p className="mb-2 text-sm text-bad">{error}</p>}
      <ul className="mb-3 flex flex-wrap gap-1.5">
        {entries.map((e) => (
          <li key={e} className="chip chip-muted">
            {e}
            <button onClick={() => remove(e)} aria-label={`Remove ${e}`} className="ml-0.5 hover:text-bad">×</button>
          </li>
        ))}
      </ul>
      <h3 className="mb-1 text-xs font-medium text-muted">Signed up</h3>
      <p className="hint mb-2">
        To add a manager, have them sign in once with their email, then promote them here.
        {!meOwner && " Only the owner can remove a manager."}
      </p>
      <ul className="space-y-1.5 text-sm">
        {people.map((p) => (
          <li key={p.id} className="flex items-center justify-between gap-2">
            <span className="min-w-0 truncate" title={p.email}>{p.full_name || p.email}</span>
            {p.id === meId ? (
              <span className="text-xs text-muted">{p.is_owner ? "owner" : p.role} (you)</span>
            ) : p.is_owner ? (
              <span className="text-xs text-accent-text">owner</span>
            ) : p.role === "manager" && !meOwner ? (
              <span className="text-xs text-accent-text">manager</span>
            ) : (
              <span className="flex shrink-0 items-center gap-2">
                <span className={`text-xs ${p.role === "manager" ? "text-accent-text" : "text-muted"}`}>{p.role}</span>
                <button className="btn btn-sm" onClick={() => setRole(p, p.role === "manager" ? "engineer" : "manager")}>
                  {p.role === "manager" ? "Make engineer" : "Make manager"}
                </button>
              </span>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}

function Projects() {
  const [rows, setRows] = useState<{ name: string; active: boolean }[]>([]);
  const [v, setV] = useState("");
  const load = useCallback(async () => {
    const { data } = await supabase().from("projects").select("name, active").order("created_at");
    setRows(data ?? []);
  }, []);
  useEffect(() => { load(); }, [load]);
  return (
    <section className="card p-4">
      <h2 className="font-semibold">Projects / cost centres</h2>
      <p className="hint mb-3">The Project dropdown on every request.</p>
      <form className="mb-3 flex gap-2" onSubmit={async (e) => { e.preventDefault(); if (v.trim()) { await supabase().from("projects").insert({ name: v.trim() }); setV(""); load(); } }}>
        <input className="input" value={v} onChange={(e) => setV(e.target.value)} placeholder="New project" aria-label="New project name" />
        <button className="btn">Add</button>
      </form>
      <ul className="flex flex-wrap gap-1.5">
        {rows.map((p) => (
          <li key={p.name}>
            <button className={`chip ${p.active ? "chip-muted" : "chip-muted opacity-50 line-through"}`} title={p.active ? "Click to hide" : "Click to restore"}
              onClick={async () => { await supabase().from("projects").update({ active: !p.active }).eq("name", p.name); load(); }}>
              {p.name}
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}
