"use client";

import { useEffect, useMemo, useState } from "react";
import { buildCards, CARD_TITLES, type Card, type HeaderField } from "@/lib/questions";
import { updateItems, updateProfile, updateRequest } from "@/lib/data";
import {
  AIR_FREIGHT, MIN_SPEC_CHARS, MIN_WHY_CHARS, UNITS, URGENCIES,
  type AirFreight, type LineItem, type ProcRequest, type Profile, type Unit, type Urgency,
} from "@/lib/template";

type Props = {
  request: ProcRequest;
  owner: Profile | null;
  items: LineItem[];
  projects: string[];
  onSaved: () => Promise<void>;
};

const skipKey = (id: string) => `tv-skipped-${id}`;

export function QuestionFlow({ request, owner, items, projects, onSaved }: Props) {
  const cards = useMemo(() => buildCards(request, owner, items), [request, owner, items]);
  const [skipped, setSkipped] = useState<string[]>([]);
  useEffect(() => {
    try { setSkipped(JSON.parse(localStorage.getItem(skipKey(request.id)) ?? "[]")); } catch { /* storage unavailable */ }
  }, [request.id]);
  const skip = (key: string) => {
    const next = [...new Set([...skipped, key])];
    setSkipped(next);
    try { localStorage.setItem(skipKey(request.id), JSON.stringify(next)); } catch { /* storage unavailable */ }
  };
  const unskipAll = () => {
    setSkipped([]);
    try { localStorage.removeItem(skipKey(request.id)); } catch { /* storage unavailable */ }
  };

  const open = cards.filter((c) => !skipped.includes(c.key));
  const required = cards.filter((c) => c.kind !== "extras");
  const card = open[0];

  if (!card) {
    return required.length === 0 ? null : (
      <div className="card flex items-center justify-between gap-4 px-5 py-4">
        <p className="text-sm">You skipped {required.length} question{required.length > 1 ? "s" : ""}. The table below shows what&apos;s still missing.</p>
        <button className="btn btn-sm" onClick={unskipAll}>Show questions again</button>
      </div>
    );
  }

  return (
    <section className="card overflow-hidden" aria-labelledby="q-title">
      <div className="flex flex-wrap items-center gap-2 border-b border-line bg-bg/60 px-5 py-2.5 text-xs">
        <span className="font-medium text-muted">To finish:</span>
        {cards.map((c) => (
          <span key={c.key} className={`chip ${c.key === card.key ? "chip-auto" : skipped.includes(c.key) ? "chip-muted line-through" : "chip-muted"}`}>
            {CARD_TITLES[c.kind].title}
            {"items" in c && <span className="tabular-nums">· {c.items.length}</span>}
          </span>
        ))}
      </div>
      <div className="px-5 py-5">
        <h2 id="q-title" className="text-lg font-semibold">{CARD_TITLES[card.kind].title}</h2>
        <p className="hint mt-1 max-w-3xl">{CARD_TITLES[card.kind].blurb}</p>
        <div className="mt-5">
          <CardBody key={card.key + ("items" in card ? card.items.length : "")} card={card} request={request} owner={owner}
            items={items} projects={projects} onSaved={onSaved} onSkip={() => skip(card.key)} />
        </div>
      </div>
    </section>
  );
}

type BodyProps = Omit<Props, "items"> & { card: Card; items: LineItem[]; onSkip: () => void };

function CardBody(props: BodyProps) {
  switch (props.card.kind) {
    case "header": return <HeaderCard {...props} card={props.card} />;
    case "air": return <AirCard {...props} card={props.card} />;
    case "unit": return <UnitCard {...props} card={props.card} />;
    case "qty": return <NumberCard {...props} rows={props.card.items} field="qty" placeholder="Qty" />;
    case "spec": return <SpecCard {...props} card={props.card} />;
    case "price": return <NumberCard {...props} rows={props.card.items} field="est_unit_price_usd" placeholder="0.00" prefix="$" />;
    case "extras": return <ExtrasCard {...props} rows={props.card.items} />;
  }
}

function useSaver(onSaved: () => Promise<void>) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const run = async (fn: () => Promise<void>) => {
    setBusy(true);
    setError("");
    try { await fn(); await onSaved(); } catch (e) { setError((e as Error).message); }
    setBusy(false);
  };
  return { busy, error, run };
}

function Actions({ busy, error, onSkip, label = "Save and continue", disabled }: {
  busy: boolean; error: string; onSkip: () => void; label?: string; disabled?: boolean;
}) {
  return (
    <div className="mt-5 flex flex-wrap items-center gap-2">
      <button className="btn btn-primary" disabled={busy || disabled}>{busy ? "Saving…" : label}</button>
      <button type="button" className="btn btn-ghost" onClick={onSkip}>Skip for now</button>
      {error && <span className="text-sm text-bad" role="alert">{error}</span>}
    </div>
  );
}

function ItemLabel({ item }: { item: LineItem }) {
  return (
    <div className="min-w-0">
      <div className="truncate font-medium">{item.item_name}</div>
      <div className="truncate text-xs text-muted">
        {item.qty ?? "?"} {item.unit ?? ""}{item.specification ? ` · ${item.specification}` : ""}
      </div>
    </div>
  );
}

const HEADER_LABELS: Record<HeaderField, string> = {
  full_name: "Your name", title: "Request title", project: "Project / cost centre",
  needed_by: "Needed by", urgency: "Urgency", justification: "Why this is needed",
};

function HeaderCard({ card, request, owner, projects, onSaved, onSkip }: BodyProps & { card: Extract<Card, { kind: "header" }> }) {
  const [v, setV] = useState({
    full_name: owner?.full_name ?? "",
    title: request.title ?? "",
    project: request.project ?? "",
    needed_by: request.needed_by ?? "",
    urgency: request.urgency ?? "Normal",
    justification: request.justification ?? "",
  });
  const { busy, error, run } = useSaver(onSaved);
  const set = (k: keyof typeof v) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) =>
    setV({ ...v, [k]: e.target.value });

  const save = (e: React.FormEvent) => {
    e.preventDefault();
    run(async () => {
      if (card.fields.includes("full_name") && owner) await updateProfile(owner.id, { full_name: v.full_name.trim() || null });
      await updateRequest(request.id, {
        title: v.title.trim() || null,
        project: v.project || null,
        needed_by: v.needed_by || null,
        urgency: (v.urgency || null) as Urgency | null,
        justification: v.justification.trim() || null,
      });
    });
  };

  return (
    <form onSubmit={save} className="grid max-w-3xl gap-4 sm:grid-cols-2">
      {card.fields.map((f) => (
        <div key={f} className={f === "justification" ? "sm:col-span-2" : ""}>
          <label className="label" htmlFor={`h-${f}`}>{HEADER_LABELS[f]}</label>
          {f === "project" ? (
            <select id={`h-${f}`} className="input" value={v.project} onChange={set("project")}>
              <option value="">Choose…</option>
              {projects.map((p) => <option key={p}>{p}</option>)}
            </select>
          ) : f === "urgency" ? (
            <select id={`h-${f}`} className="input" value={v.urgency} onChange={set("urgency")}>
              {URGENCIES.map((u) => <option key={u}>{u}</option>)}
            </select>
          ) : f === "needed_by" ? (
            <input id={`h-${f}`} type="date" className="input" value={v.needed_by} onChange={set("needed_by")} />
          ) : f === "justification" ? (
            <>
              <textarea id={`h-${f}`} rows={3} className="input" value={v.justification} onChange={set("justification")}
                placeholder="Two or three sentences. What it's for and what happens if it's late." />
              <span className="hint">{v.justification.trim().length < MIN_WHY_CHARS ? `At least ${MIN_WHY_CHARS} characters` : "Good"}</span>
            </>
          ) : (
            <input id={`h-${f}`} className="input" value={v[f]} onChange={set(f)}
              placeholder={f === "title" ? "Short name for this request" : ""} />
          )}
        </div>
      ))}
      <div className="sm:col-span-2"><Actions busy={busy} error={error} onSkip={onSkip} /></div>
    </form>
  );
}

function AirCard({ card, items, onSaved, onSkip }: BodyProps & { card: Extract<Card, { kind: "air" }> }) {
  const [v, setV] = useState<Record<string, AirFreight>>(card.suggested);
  const { busy, error, run } = useSaver(onSaved);
  const flaggedElsewhere = items.filter((i) => i.air_freight === "Yes" && (i.auto_fields ?? []).includes("air_freight"));
  const save = (e: React.FormEvent) => {
    e.preventDefault();
    run(() => updateItems(items, Object.fromEntries(Object.entries(v).map(([id, a]) => [id, { air_freight: a }]))));
  };
  return (
    <form onSubmit={save}>
      {flaggedElsewhere.length > 0 && (
        <p className="mb-4 rounded-md bg-bad-soft px-3 py-2 text-sm text-bad">
          Already marked restricted from the BOM: {flaggedElsewhere.map((i) => i.item_name).join(", ")}. You can change these in the table.
        </p>
      )}
      <div className="mb-3 flex gap-2">
        <button type="button" className="btn btn-sm" onClick={() => setV(Object.fromEntries(card.items.map((i) => [i.id, "No"])))}>Set all to No</button>
        <span className="hint self-center">Items we think are restricted are pre-set to Yes.</span>
      </div>
      <ul className="divide-y divide-line rounded-lg border border-line">
        {card.items.map((i) => (
          <li key={i.id} className="flex flex-wrap items-center justify-between gap-3 px-3 py-2">
            <ItemLabel item={i} />
            <div className="flex shrink-0 gap-1" role="radiogroup" aria-label={`Air freight for ${i.item_name}`}>
              {AIR_FREIGHT.map((a) => (
                <button type="button" key={a} role="radio" aria-checked={v[i.id] === a} onClick={() => setV({ ...v, [i.id]: a })}
                  className={`btn btn-sm ${v[i.id] === a ? (a === "No" ? "border-ok bg-ok-soft text-ok" : a === "Yes" ? "border-bad bg-bad-soft text-bad" : "border-warn bg-warn-soft text-warn") : ""}`}>
                  {a === "Not sure - please check" ? "Not sure" : a}
                </button>
              ))}
              {card.suggested[i.id] === "Yes" && <span className="chip chip-auto self-center">flagged</span>}
            </div>
          </li>
        ))}
      </ul>
      <Actions busy={busy} error={error} onSkip={onSkip} />
    </form>
  );
}

function UnitCard({ card, items, onSaved, onSkip }: BodyProps & { card: Extract<Card, { kind: "unit" }> }) {
  const [v, setV] = useState<Record<string, string>>(card.suggested);
  const { busy, error, run } = useSaver(onSaved);
  return (
    <form onSubmit={(e) => { e.preventDefault(); run(() => updateItems(items, Object.fromEntries(Object.entries(v).map(([id, u]) => [id, { unit: u as Unit }])))); }}>
      <ul className="divide-y divide-line rounded-lg border border-line">
        {card.items.map((i) => (
          <li key={i.id} className="flex items-center justify-between gap-3 px-3 py-2">
            <ItemLabel item={i} />
            <select className="input w-28 shrink-0" value={v[i.id]} onChange={(e) => setV({ ...v, [i.id]: e.target.value })} aria-label={`Unit for ${i.item_name}`}>
              {UNITS.map((u) => <option key={u}>{u}</option>)}
            </select>
          </li>
        ))}
      </ul>
      <Actions busy={busy} error={error} onSkip={onSkip} />
    </form>
  );
}

function NumberCard({ rows, field, placeholder, prefix, onSaved, onSkip, items }: BodyProps & {
  rows: LineItem[]; field: "qty" | "est_unit_price_usd"; placeholder: string; prefix?: string;
}) {
  const [v, setV] = useState<Record<string, string>>({});
  const { busy, error, run } = useSaver(onSaved);
  const entered = Object.entries(v).filter(([, s]) => s.trim() !== "" && Number.isFinite(Number(s)));
  return (
    <form onSubmit={(e) => { e.preventDefault(); run(() => updateItems(items, Object.fromEntries(entered.map(([id, s]) => [id, { [field]: Number(s) }])))); }}>
      <ul className="divide-y divide-line rounded-lg border border-line">
        {rows.map((i, n) => (
          <li key={i.id} className="flex items-center justify-between gap-3 px-3 py-2">
            <ItemLabel item={i} />
            <div className="flex shrink-0 items-center gap-1">
              {prefix && <span className="text-muted">{prefix}</span>}
              <input className="input w-28 text-right tabular-nums" inputMode="decimal" placeholder={placeholder} autoFocus={n === 0}
                value={v[i.id] ?? ""} onChange={(e) => setV({ ...v, [i.id]: e.target.value.replace(/[^0-9.]/g, "") })}
                aria-label={`${field === "qty" ? "Quantity" : "Unit price"} for ${i.item_name}`} />
              {field === "est_unit_price_usd" && <span className="w-16 text-right text-xs text-muted">/{i.unit ?? "unit"}</span>}
            </div>
          </li>
        ))}
      </ul>
      <Actions busy={busy} error={error} onSkip={onSkip} disabled={entered.length === 0}
        label={entered.length ? `Save ${entered.length} and continue` : "Save and continue"} />
    </form>
  );
}

function SpecCard({ card, items, onSaved, onSkip }: BodyProps & { card: Extract<Card, { kind: "spec" }> }) {
  const [v, setV] = useState<Record<string, string>>(Object.fromEntries(card.items.map((i) => [i.id, i.specification ?? ""])));
  const { busy, error, run } = useSaver(onSaved);
  const changed = card.items.filter((i) => (v[i.id] ?? "") !== (i.specification ?? ""));
  const append = (id: string, hint: string) => {
    const label = hint.replace(/\s*\(.*\)$/, "");
    const cur = (v[id] ?? "").trim();
    setV({ ...v, [id]: `${cur}${cur ? ", " : ""}${label}: ` });
    requestAnimationFrame(() => {
      const el = document.getElementById(`spec-${id}`) as HTMLTextAreaElement | null;
      el?.focus();
      el?.setSelectionRange(el.value.length, el.value.length);
    });
  };
  return (
    <form onSubmit={(e) => { e.preventDefault(); run(() => updateItems(items, Object.fromEntries(changed.map((i) => [i.id, { specification: v[i.id].trim() }])))); }}>
      <p className="hint mb-3">“M3 screws, 200pcs” is not a spec. “M3 x 10 mm, socket head cap, stainless A2, DIN 912” is.</p>
      <ul className="space-y-4">
        {card.items.map((i) => {
          const len = (v[i.id] ?? "").trim().length;
          return (
            <li key={i.id} className="rounded-lg border border-line p-3">
              <div className="flex items-baseline justify-between gap-3">
                <label htmlFor={`spec-${i.id}`} className="font-medium">{i.item_name}</label>
                <span className={`text-xs tabular-nums ${len >= MIN_SPEC_CHARS ? "text-ok" : "text-muted"}`}>{len}/{MIN_SPEC_CHARS}</span>
              </div>
              <textarea id={`spec-${i.id}`} rows={2} className="input mt-2" value={v[i.id]}
                onChange={(e) => setV({ ...v, [i.id]: e.target.value })} />
              <div className="mt-2 flex flex-wrap gap-1.5">
                {card.hints[i.id].map((h) => (
                  <button type="button" key={h} className="chip chip-muted hover:bg-accent-soft hover:text-accent-text" onClick={() => append(i.id, h)}>+ {h}</button>
                ))}
              </div>
            </li>
          );
        })}
      </ul>
      <Actions busy={busy} error={error} onSkip={onSkip} disabled={changed.length === 0} />
    </form>
  );
}

function ExtrasCard({ rows, items, onSaved, onSkip }: BodyProps & { rows: LineItem[] }) {
  const [v, setV] = useState<Record<string, { link: string; vendor: string }>>({});
  const { busy, error, run } = useSaver(onSaved);
  const entered = Object.entries(v).filter(([, x]) => x.link.trim() || x.vendor.trim());
  const set = (id: string, k: "link" | "vendor", s: string) => setV({ ...v, [id]: { ...(v[id] ?? { link: "", vendor: "" }), [k]: s } });
  return (
    <form onSubmit={(e) => {
      e.preventDefault();
      run(async () => {
        await updateItems(items, Object.fromEntries(entered.map(([id, x]) => [id, {
          ...(x.link.trim() ? { datasheet_url: x.link.trim() } : {}),
          ...(x.vendor.trim() ? { suggested_vendor: x.vendor.trim() } : {}),
        }])));
        if (entered.length === rows.length) return;
        onSkip();
      });
    }}>
      <ul className="divide-y divide-line rounded-lg border border-line">
        {rows.map((i) => (
          <li key={i.id} className="grid items-center gap-2 px-3 py-2 md:grid-cols-[1fr_16rem_12rem]">
            <ItemLabel item={i} />
            <input className="input" type="url" placeholder="https://datasheet or product page" value={v[i.id]?.link ?? ""}
              onChange={(e) => set(i.id, "link", e.target.value)} aria-label={`Link for ${i.item_name}`} />
            <input className="input" placeholder="Vendor" value={v[i.id]?.vendor ?? ""}
              onChange={(e) => set(i.id, "vendor", e.target.value)} aria-label={`Vendor for ${i.item_name}`} />
          </li>
        ))}
      </ul>
      <Actions busy={busy} error={error} onSkip={onSkip} label={entered.length ? `Save ${entered.length}` : "Save"} disabled={entered.length === 0} />
    </form>
  );
}
