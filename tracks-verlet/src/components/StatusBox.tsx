import { usd, type Readiness } from "@/lib/template";

export function StatusBox({ r }: { r: Readiness }) {
  return (
    <div className={`card flex flex-wrap items-center gap-x-8 gap-y-3 px-5 py-4 ${r.ready ? "border-ok bg-ok-soft" : "border-warn bg-warn-soft"}`}>
      <div className="min-w-0 flex-1">
        <div className="text-xs font-semibold tracking-wide text-muted">STATUS</div>
        <div className={`mt-0.5 font-semibold ${r.ready ? "text-ok" : "text-warn"}`} aria-live="polite">{r.label}</div>
      </div>
      <Stat label="Line items" value={String(r.lineCount)} />
      <Stat label="Need attention" value={String(r.linesNeedingAttention)} />
      {r.unpriced > 0 && <Stat label="Unpriced" value={String(r.unpriced)} />}
      <Stat label="Estimated total" value={usd(r.estTotal)} />
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-xs text-muted">{label}</div>
      <div className="font-semibold tabular-nums">{value}</div>
    </div>
  );
}
