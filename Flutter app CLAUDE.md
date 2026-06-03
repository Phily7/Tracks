# CLAUDE.md — FabFoods POS (Flutter)

> Auto-loaded by Claude Code at session start. Canonical project context. Fuller narrative in `Progress.md`.

## What this project is

**FabFoods** — a Flutter point-of-sale app for a food business, replacing an old Google Sheets workflow (Sales and Stock 7.0). Records sales through a supermarket-style interface, **offline-first with cloud sync**, plus export and analysis.

**Project folder:** `D:\Philemon_2026\AHEAD Space\Apps\Tracks\tracks`

## Tech stack (agreed — do not swap without asking)

- **Flutter Web** — primary deployment target; Windows/macOS/Linux desktop builds supported from the same codebase.
- **Drift** — local SQLite storage (via IndexedDB on web).
- **Supabase** — cloud Postgres backend.
- **Riverpod** — state management.
- **go_router** — navigation.
- **fl_chart** — dashboard charts.

## Theme (FabFoods logo palette)

- Primary near-black `#0F0D0B`
- Accent amber orange `#E8820C`
- Surfaces: `#1A1A1A` (dark panels) → `#F4F4F4` (page bg), white cards
- Payment method "Debt" = purple `#8B5CF6`
- (Replaced an earlier warm cream palette — don't reintroduce cream.)

## Current state

### Done & functional
- ✅ **Supabase schema**
- ✅ `shift_end_screen.dart` — closing balances, cash/MoMo reconciliation, discrepancy detection, success screen
- ✅ `sale_entry_screen.dart` — product-first + client-first modes, live stats bar, transaction log with delete, auto-seeds 20 products + clients
- ✅ `stock_count_screen.dart` — opening/refill/closing per product, per-row + bulk save, variance summary tab
- ✅ `export_screen.dart` — shift selector, CSV download via `dart:html`, toggle sections (summary/transactions/stock)
- ✅ `dashboard_screen.dart` — Day/Week/Month/Quarter/Year/All tabs, period nav, shift drill-down chips, KPI cards, revenue line chart, payment/client bar charts, top-products bars, staff bars, stock variance table (fl_chart)
- ✅ Searchable staff/client dropdowns — custom `_SearchableClientDropdown` (Flutter `Overlay` + `CompositedTransformTarget`); 52 named clients seeded from the original sheet
- ✅ Build order completed: schema → shift flows → transaction screens → reporting/export

### Remaining major piece
- ⬜ **Supabase cloud sync — NOT STARTED.** Offline-first local Drift/SQLite syncing to cloud Postgres. This is the next focus.

## Hard-won lessons (avoid re-hitting these)

- **Register every DAO in the `@DriftDatabase` annotation** — otherwise its getter methods are undefined on `AppDatabase`.
- **Stale build_runner cache → 0 outputs.** Fix: delete all `.g.dart` files (PowerShell) then rebuild clean.
- **go_router callbacks need both params named** (`BuildContext` and `GoRouterState`) — using `_` for both causes type errors.
- **Drift column names must match exactly** between table definitions and generated/query code (real names: `openStock`/`closingStock`/`refillQty` — not `openingQty`/`closingQty`).
- **No inline comments in `pubspec.yaml` dependency lines** — YAML parse error.
- **`dropdown_search` v5 API is unstable** — abandoned for a custom overlay widget. Don't reach back for it.

## How the user works (Philemon / Mucyo)

Strong independent debugging instinct — often diagnoses the problem and the right fix before confirmation (e.g. resolved a build_runner issue himself by renaming a DAO file). Prefers you **validate and refine his direction** over rebuilding from scratch, and engages deeply with technical detail. When a session gets long, he restores context by sharing prior code via Google Drive. Build on his thinking; confirm before large restructures.

## Reference data

Original business data lives in Google Drive sheet ID `1CGgzkoLmN4cMawxlN3oidS46PmY_q3RzHUanXpFOjO4`, worksheet "Shifts & Products & Staff" (full staff/client list).
