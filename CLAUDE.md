# CLAUDE.md — Stock Tracking System (Excel)

> This file is auto-loaded by Claude Code at session start. It is the canonical project context. A longer narrative version lives in `Progress.md`.

## What this project is

Stock and sales tracking for a business with **two locations**: `Samantha` and `Magnifique`. The deliverable is an Excel workbook that tracks product-level stock and sales over time and supports comparison **by product, by date, and by location**.

**Note:** The actual `.xlsx` workbook is **not yet in this folder** — only context for now. Ask the user for the file before editing it. Do not fabricate its contents.

## Current state (working design)

A **three-sheet workbook**:

1. **Daily Entry** — reusable template (NOT copied each day).
   - Blue-highlighted cells = the only fields the user types into.
   - Formulas auto-calculate amounts and closing stock.
   - Warnings flag negative closing stock.
2. **Master Data** — permanent **long-format** database, one row per observation (product × date × location). Populated by pasting *values* from Daily Entry each day. Single source of truth.
3. **Dashboard** — pivot chart setup for comparing products, dates, locations.

## Daily workflow (do not break this)

1. Update the date on Daily Entry.
2. Fill **only the blue cells**.
3. Verify no warnings.
4. Paste **as values** into Master Data.
5. Refresh pivot tables/charts.

No new sheet per day — reuse the template.

## Hard constraints (regressions to avoid)

- **Long format only.** One row per observation. Never revert to wide format (products as columns) or one-sheet-per-day — that was the original broken design.
- **Totals are formula-driven**, never typed by hand.
- **Paste as values** into Master Data so formulas don't corrupt the permanent record.
- **Never copy sheets day-to-day** — caused date carry-over errors.

## Open tasks

- [ ] Verify Master Data → Dashboard pivot wiring end-to-end with real days of data.
- [ ] Convert Master Data to an **Excel Table** so the pivot range auto-extends on new rows.
- [ ] Confirm pivots refresh cleanly after a values-paste.
- [ ] Finalize Dashboard metrics (sales by product over time, location-vs-location, stock-on-hand trend).
- [ ] Add input validation: dropdowns for product + location to prevent typos that fragment pivots; data-type checks.
- [ ] Document the Master Data column schema (field names, types, expected values).
- [ ] Lock in a date-handling convention so each paste lands as a clean, comparable date.
- [ ] Decide on archiving/backup for Master Data as it grows.

## How the user works (Mucyo)

He usually arrives having already diagnosed the problem *and* the right solution direction (he identified wide-vs-long himself). He prefers that you **validate and refine his ideas** rather than rebuild from scratch, and he engages substantively with technical detail. Build on his thinking; confirm direction before large restructures.
