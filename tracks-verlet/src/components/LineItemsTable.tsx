"use client";

import { useState } from "react";
import { deleteItem, setRemoved, updateItems } from "@/lib/data";
import { AIR_FREIGHT, lineChange, lineIssues, lineTotal, UNITS, usd, type LineItem, type TrackedField } from "@/lib/template";

// tracking: the request has a confirmed BOM, so differences from it are shown as pending changes.
type Props = { items: LineItem[]; editable: boolean; tracking?: boolean; onSaved: () => Promise<void> };

const CHANGE_CHIP = {
  added: <span className="chip chip-ok">New</span>,
  changed: <span className="chip chip-warn">Changed</span>,
  removed: <span className="chip chip-bad">Removed</span>,
};

export function LineItemsTable({ items, editable, tracking = false, onSaved }: Props) {
  const [error, setError] = useState("");
  const [onlyIssues, setOnlyIssues] = useState(false);

  const save = async (item: LineItem, patch: Partial<LineItem>) => {
    const key = Object.keys(patch)[0] as keyof LineItem;
    if ((item[key] ?? null) === (patch[key] ?? null)) return;
    setError("");
    try { await updateItems(items, { [item.id]: patch }); await onSaved(); } catch (e) { setError((e as Error).message); }
  };
  const remove = async (item: LineItem, removed = true) => {
    setError("");
    try {
      // Confirmed lines stay visible, crossed out, until the change is approved.
      if (item.approved) await setRemoved(item.id, removed); else await deleteItem(item.id);
      await onSaved();
    } catch (e) { setError((e as Error).message); }
  };

  const rows = onlyIssues ? items.filter((i) => lineIssues(i, items).length > 0) : items;
  const issueCount = items.filter((i) => lineIssues(i, items).length > 0).length;

  return (
    <div>
      <div className="mb-2 flex items-center gap-3 text-sm">
        <label className="flex items-center gap-2">
          <input type="checkbox" checked={onlyIssues} onChange={(e) => setOnlyIssues(e.target.checked)} />
          Only rows needing attention ({issueCount})
        </label>
        <span className="hint ml-auto flex items-center gap-1"><span className="chip chip-auto">auto</span> filled by Tracks from your BOM, not yet confirmed</span>
      </div>
      {error && <p className="mb-2 rounded-md bg-bad-soft px-3 py-2 text-sm text-bad" role="alert">{error}</p>}
      <div className="card overflow-x-auto">
        <table className="tbl min-w-[1100px]">
          <thead>
            <tr>
              <th className="w-8">#</th>
              <th className="min-w-44">Item name</th>
              <th className="w-20">Qty</th>
              <th className="w-24">Unit</th>
              <th className="min-w-72">Detailed specification</th>
              <th className="min-w-40">Datasheet / link</th>
              <th className="w-32">Air freight</th>
              <th className="w-24">Unit USD</th>
              <th className="w-24 text-right">Line total</th>
              <th className="min-w-32">Vendor</th>
              <th className="min-w-32">Notes</th>
              <th className="min-w-36">Check</th>
              {editable && <th className="w-8" />}
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && (
              <tr><td colSpan={13} className="py-8 text-center text-muted">{onlyIssues ? "Every row is OK." : "No line items yet. Upload a BOM or add a row."}</td></tr>
            )}
            {rows.map((i) => {
              const issues = lineIssues(i, items);
              const auto = (f: string) => (i.auto_fields ?? []).includes(f);
              const change = lineChange(i, tracking);
              const gone = change.kind === "removed";
              const canEdit = editable && !gone;
              // Changed cells show the confirmed value underneath.
              const was = (f: TrackedField) => (change.kind === "changed" && change.fields.includes(f) ? { was: i.approved![f] ?? "—" } : {});
              const rowTone = change.kind === "added" ? "bg-ok-soft/60" : gone ? "bg-bad-soft/60 line-through text-muted" : "";
              return (
                <tr key={i.id} className={rowTone}>
                  <td className="pt-2.5 text-muted tabular-nums">
                    {items.indexOf(i) + 1}
                    {change.kind && <div className="mt-1 no-underline">{CHANGE_CHIP[change.kind]}</div>}
                  </td>
                  <Cell editable={canEdit} auto={auto("item_name")} value={i.item_name} {...was("item_name")} onSave={(s) => save(i, { item_name: s })} />
                  <Cell editable={canEdit} auto={auto("qty")} value={i.qty} numeric {...was("qty")} onSave={(s) => save(i, { qty: s === null ? null : Number(s) })} />
                  <SelectCell editable={canEdit} auto={auto("unit")} value={i.unit} options={UNITS} {...was("unit")} onSave={(s) => save(i, { unit: s as LineItem["unit"] })} />
                  <Cell editable={canEdit} auto={auto("specification")} value={i.specification} multiline {...was("specification")} onSave={(s) => save(i, { specification: s })} />
                  <Cell editable={canEdit} auto={auto("datasheet_url")} value={i.datasheet_url} link {...was("datasheet_url")} onSave={(s) => save(i, { datasheet_url: s })} />
                  <SelectCell editable={canEdit} auto={auto("air_freight")} value={i.air_freight} options={AIR_FREIGHT} {...was("air_freight")}
                    tone={i.air_freight === "Yes" ? "text-bad" : i.air_freight?.startsWith("Not") ? "text-warn" : ""}
                    onSave={(s) => save(i, { air_freight: s as LineItem["air_freight"] })} />
                  <Cell editable={canEdit} auto={auto("est_unit_price_usd")} value={i.est_unit_price_usd} numeric {...was("est_unit_price_usd")}
                    onSave={(s) => save(i, { est_unit_price_usd: s === null ? null : Number(s) })} />
                  <td className="pt-2.5 text-right tabular-nums">{lineTotal(i) ? usd(lineTotal(i)) : ""}</td>
                  <Cell editable={canEdit} auto={auto("suggested_vendor")} value={i.suggested_vendor} {...was("suggested_vendor")} onSave={(s) => save(i, { suggested_vendor: s })} />
                  <Cell editable={canEdit} value={i.notes} {...was("notes")} onSave={(s) => save(i, { notes: s })} />
                  <td className="pt-2 no-underline">
                    {gone ? <span className="hint">Goes when approved</span> : issues.length === 0 ? <span className="chip chip-ok">OK</span> : (
                      <div className="flex flex-wrap gap-1">{issues.map((x) => <span key={x} className="chip chip-warn">{x}</span>)}</div>
                    )}
                  </td>
                  {editable && (
                    <td className="pt-1.5">
                      {gone ? (
                        <button className="btn btn-ghost btn-sm text-accent-text" onClick={() => remove(i, false)} aria-label={`Undo removing ${i.item_name}`}>Undo</button>
                      ) : (
                        <button className="btn btn-ghost btn-sm px-1.5 text-muted hover:text-bad" onClick={() => remove(i)} aria-label={`Delete ${i.item_name}`}
                          title={i.approved ? "Remove from the confirmed BOM (needs approval)" : "Delete row"}>
                          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true"><path d="M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14" /></svg>
                        </button>
                      )}
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function AutoDot({ show }: { show?: boolean }) {
  return show ? <span className="absolute right-1 top-1 h-1.5 w-1.5 rounded-full bg-auto" title="Filled automatically from your BOM" /> : null;
}

// The confirmed value, crossed out, under a cell that changed since approval.
function Was({ value }: { value?: string | number | null }) {
  if (value === undefined) return null;
  return <div className="mt-0.5 text-xs text-muted"><span className="sr-only">was </span><del>{String(value ?? "") || "—"}</del></div>;
}

function Cell({ value, onSave, editable, auto, numeric, multiline, link, was }: {
  value: string | number | null; onSave: (v: string | null) => void; editable: boolean;
  auto?: boolean; numeric?: boolean; multiline?: boolean; link?: boolean; was?: string | number | null;
}) {
  const shown = value === null || value === undefined ? "" : String(value);
  const [draft, setDraft] = useState(shown);
  const [prev, setPrev] = useState(shown);
  if (prev !== shown) { setPrev(shown); setDraft(shown); }

  const changed = was !== undefined ? "bg-warn-soft" : "";
  if (!editable) {
    return (
      <td className={`${numeric ? "text-right tabular-nums" : ""} ${changed}`}>
        {link && shown ? <a href={shown} target="_blank" rel="noreferrer" className="break-all text-accent-text hover:underline">{shown}</a> : <span className="whitespace-pre-wrap">{shown}</span>}
        <Was value={was} />
      </td>
    );
  }
  const commit = () => {
    const t = draft.trim();
    onSave(t === "" ? null : numeric ? String(Number(t.replace(/[^0-9.\-]/g, ""))) : t);
  };
  const common = {
    className: `cell-input ${numeric ? "text-right tabular-nums" : ""}`,
    value: draft,
    onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setDraft(e.target.value),
    onBlur: commit,
  };
  return (
    <td className={`relative ${changed}`}>
      {multiline ? (
        <textarea {...common} rows={Math.min(4, Math.max(1, Math.ceil(draft.length / 48)))} className={`${common.className} resize-none`} />
      ) : (
        <input {...common} inputMode={numeric ? "decimal" : undefined}
          onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }} />
      )}
      <Was value={was} />
      <AutoDot show={auto} />
    </td>
  );
}

function SelectCell({ value, options, onSave, editable, auto, tone = "", was }: {
  value: string | null; options: readonly string[]; onSave: (v: string | null) => void; editable: boolean; auto?: boolean; tone?: string;
  was?: string | number | null;
}) {
  const changed = was !== undefined ? "bg-warn-soft" : "";
  if (!editable) return <td className={`${tone} ${changed}`}>{value ?? ""}<Was value={was} /></td>;
  return (
    <td className={`relative ${changed}`}>
      <select className={`cell-input ${tone}`} value={value ?? ""} onChange={(e) => onSave(e.target.value || null)}>
        <option value="">—</option>
        {options.map((o) => <option key={o} value={o}>{o === "Not sure - please check" ? "Not sure" : o}</option>)}
      </select>
      <Was value={was} />
      <AutoDot show={auto} />
    </td>
  );
}
