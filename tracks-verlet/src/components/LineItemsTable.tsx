"use client";

import { useState } from "react";
import { deleteItem, updateItems } from "@/lib/data";
import { AIR_FREIGHT, lineIssues, lineTotal, UNITS, usd, type LineItem } from "@/lib/template";

type Props = { items: LineItem[]; editable: boolean; onSaved: () => Promise<void> };

export function LineItemsTable({ items, editable, onSaved }: Props) {
  const [error, setError] = useState("");
  const [onlyIssues, setOnlyIssues] = useState(false);

  const save = async (item: LineItem, patch: Partial<LineItem>) => {
    const key = Object.keys(patch)[0] as keyof LineItem;
    if ((item[key] ?? null) === (patch[key] ?? null)) return;
    setError("");
    try { await updateItems(items, { [item.id]: patch }); await onSaved(); } catch (e) { setError((e as Error).message); }
  };
  const remove = async (item: LineItem) => {
    setError("");
    try { await deleteItem(item.id); await onSaved(); } catch (e) { setError((e as Error).message); }
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
              return (
                <tr key={i.id}>
                  <td className="pt-2.5 text-muted tabular-nums">{items.indexOf(i) + 1}</td>
                  <Cell editable={editable} auto={auto("item_name")} value={i.item_name} onSave={(s) => save(i, { item_name: s })} />
                  <Cell editable={editable} auto={auto("qty")} value={i.qty} numeric onSave={(s) => save(i, { qty: s === null ? null : Number(s) })} />
                  <SelectCell editable={editable} auto={auto("unit")} value={i.unit} options={UNITS} onSave={(s) => save(i, { unit: s as LineItem["unit"] })} />
                  <Cell editable={editable} auto={auto("specification")} value={i.specification} multiline onSave={(s) => save(i, { specification: s })} />
                  <Cell editable={editable} auto={auto("datasheet_url")} value={i.datasheet_url} link onSave={(s) => save(i, { datasheet_url: s })} />
                  <SelectCell editable={editable} auto={auto("air_freight")} value={i.air_freight} options={AIR_FREIGHT}
                    tone={i.air_freight === "Yes" ? "text-bad" : i.air_freight?.startsWith("Not") ? "text-warn" : ""}
                    onSave={(s) => save(i, { air_freight: s as LineItem["air_freight"] })} />
                  <Cell editable={editable} auto={auto("est_unit_price_usd")} value={i.est_unit_price_usd} numeric
                    onSave={(s) => save(i, { est_unit_price_usd: s === null ? null : Number(s) })} />
                  <td className="pt-2.5 text-right tabular-nums">{lineTotal(i) ? usd(lineTotal(i)) : ""}</td>
                  <Cell editable={editable} auto={auto("suggested_vendor")} value={i.suggested_vendor} onSave={(s) => save(i, { suggested_vendor: s })} />
                  <Cell editable={editable} value={i.notes} onSave={(s) => save(i, { notes: s })} />
                  <td className="pt-2">
                    {issues.length === 0 ? <span className="chip chip-ok">OK</span> : (
                      <div className="flex flex-wrap gap-1">{issues.map((x) => <span key={x} className="chip chip-warn">{x}</span>)}</div>
                    )}
                  </td>
                  {editable && (
                    <td className="pt-1.5">
                      <button className="btn btn-ghost btn-sm px-1.5 text-muted hover:text-bad" onClick={() => remove(i)} aria-label={`Delete ${i.item_name}`} title="Delete row">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true"><path d="M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14" /></svg>
                      </button>
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

function Cell({ value, onSave, editable, auto, numeric, multiline, link }: {
  value: string | number | null; onSave: (v: string | null) => void; editable: boolean;
  auto?: boolean; numeric?: boolean; multiline?: boolean; link?: boolean;
}) {
  const shown = value === null || value === undefined ? "" : String(value);
  const [draft, setDraft] = useState(shown);
  const [prev, setPrev] = useState(shown);
  if (prev !== shown) { setPrev(shown); setDraft(shown); }

  if (!editable) {
    return (
      <td className={numeric ? "text-right tabular-nums" : ""}>
        {link && shown ? <a href={shown} target="_blank" rel="noreferrer" className="break-all text-accent-text hover:underline">{shown}</a> : <span className="whitespace-pre-wrap">{shown}</span>}
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
    <td className="relative">
      {multiline ? (
        <textarea {...common} rows={Math.min(4, Math.max(1, Math.ceil(draft.length / 48)))} className={`${common.className} resize-none`} />
      ) : (
        <input {...common} inputMode={numeric ? "decimal" : undefined}
          onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }} />
      )}
      <AutoDot show={auto} />
    </td>
  );
}

function SelectCell({ value, options, onSave, editable, auto, tone = "" }: {
  value: string | null; options: readonly string[]; onSave: (v: string | null) => void; editable: boolean; auto?: boolean; tone?: string;
}) {
  if (!editable) return <td className={tone}>{value ?? ""}</td>;
  return (
    <td className="relative">
      <select className={`cell-input ${tone}`} value={value ?? ""} onChange={(e) => onSave(e.target.value || null)}>
        <option value="">—</option>
        {options.map((o) => <option key={o} value={o}>{o === "Not sure - please check" ? "Not sure" : o}</option>)}
      </select>
      <AutoDot show={auto} />
    </td>
  );
}
