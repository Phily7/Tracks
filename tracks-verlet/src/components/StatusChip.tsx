import type { RequestStatus } from "@/lib/template";

export function StatusChip({ status, ready }: { status: RequestStatus; ready?: boolean }) {
  if (status === "draft")
    return ready ? <span className="chip chip-ok">Draft · ready</span> : <span className="chip chip-warn">Draft · not ready</span>;
  const cls = { submitted: "chip-accent", approved: "chip-ok", ordered: "chip-ok", rejected: "chip-bad" }[status];
  return <span className={`chip ${cls} capitalize`}>{status}</span>;
}
