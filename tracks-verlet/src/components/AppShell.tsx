"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Logo } from "./Logo";
import { signOut } from "@/lib/data";
import type { Profile } from "@/lib/template";

export function AppShell({ me, children }: { me: Profile | null; children: React.ReactNode }) {
  const path = usePathname();
  const nav = me?.role === "manager"
    ? [{ href: "/manager", label: "Overview" }, { href: "/requests", label: "My requests" }]
    : [{ href: "/requests", label: "My requests" }];
  return (
    <div className="min-h-screen">
      <header className="border-b border-line bg-panel">
        <div className="mx-auto flex h-14 max-w-6xl items-center gap-6 px-4">
          <Link href="/" className="flex items-center gap-2 font-semibold">
            <Logo size={26} /> <span className="font-display text-xl font-normal tracking-tight">Tracks Verlet</span>
          </Link>
          <nav className="flex gap-1 text-sm">
            {nav.map((n) => (
              <Link key={n.href} href={n.href}
                className={`rounded-md px-3 py-1.5 ${path === n.href ? "bg-bg font-medium" : "text-muted hover:text-ink"}`}>
                {n.label}
              </Link>
            ))}
          </nav>
          <div className="ml-auto flex items-center gap-3 text-sm">
            {me && (
              <span className="hidden text-muted sm:inline">
                {me.full_name || me.email}
                {me.role === "manager" && <span className="chip chip-muted ml-2">Manager</span>}
              </span>
            )}
            <button className="btn btn-sm" onClick={signOut}>Sign out</button>
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-4 py-6">{children}</main>
    </div>
  );
}
