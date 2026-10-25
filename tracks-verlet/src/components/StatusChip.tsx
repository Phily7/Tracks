import type { RequestStatus } from "@/lib/template";

export function StatusChip({ status, ready, pending = 0 }: { status: RequestStatus; ready?: boolean; pending?: number }) {
  if (pending > 0)
    return <span className="chip chip-warn capitalize">{status} · {pending} change{pending === 1 ? "" : "s"} pending</span>;
  if (status === "draft")
    return ready ? <span className="chip chip-ok">Draft · ready</span> : <span className="chip chip-warn">Draft · not ready</span>;
  const cls = { submitted: "chip-accent", approved: "chip-ok", ordered: "chip-ok", rejected: "chip-bad" }[status];
  return <span className={`chip ${cls} capitalize`}>{status}</span>;
}
