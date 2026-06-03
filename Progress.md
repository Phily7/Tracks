# Progress Report — Stock Tracking System (Excel)

> For Claude Code: `CLAUDE.md` (auto-loaded at session start) has the condensed, agent-ready version of this. This file is the fuller narrative.

**Owner:** Mucyo
**Context:** Stock and sales tracking for a business with two locations — **Samantha** and **Magnifique**. Goal is a reliable, chartable data system in Excel that tracks product-level stock and sales over time, allowing comparisons by product, date, and location.

---

## The core problem (solved)

The original system stored data in a **"wide" format** — one sheet per day, with products as columns. This broke charting and pivot tables, because Excel needs **"long"/"tall" format** (one row per observation) to aggregate and compare properly.

A second issue: each new day was created by **copying the previous day's sheet**, which carried over stale dates and introduced errors.

Both issues are now addressed by the new three-sheet design below.

---

## What has been built

The system is now a **three-sheet workbook**:

### 1. Daily Entry (template)
- A reusable template — **not** copied each day.
- **Blue-highlighted cells** mark the only fields the user should type into.
- Auto-calculating formulas handle **amounts** and **closing stock**.
- Built-in **warnings flag negative closing stock** values, catching data-entry mistakes before they propagate.

### 2. Master Data
- The **permanent long-format database** — one row per observation (product × date × location).
- Populated each day by **pasting values** (not formulas) from the Daily Entry sheet.
- This is the single source of truth that feeds reporting.

### 3. Dashboard
- **Pivot chart setup** for comparing products, dates, and locations.

---

## Intended daily workflow

1. Update the **date** on the Daily Entry sheet.
2. Fill in **only the blue cells**.
3. Verify **no warnings** appear (e.g. negative closing stock).
4. **Paste as values** into the Master Data sheet.
5. **Refresh** the pivot tables / charts.

> No new sheet is created each day. The template is reused.

---

## Key principles to preserve

- **Long format, not wide.** One row per observation. Do not revert to products-as-columns or one-sheet-per-day.
- **Formula-driven totals.** Total sales / amounts columns should be calculated, never typed manually.
- **Paste as values** into Master Data so formulas don't break the permanent record.
- **Don't copy sheets day-to-day** — that's what caused the date carry-over errors.

---

## What's still missing / to do

- **Verify the Master Data → Dashboard pivot wiring end-to-end** with a few real days of data, to confirm products/dates/locations all slice correctly.
- **Confirm the pivot tables refresh cleanly** after a values-paste (data range expands to include new rows — consider converting Master Data to an Excel Table so the range auto-extends).
- **Define the exact metrics** the Dashboard should surface (e.g. sales by product over time, location-vs-location comparison, stock-on-hand trend). Currently the chart setup exists but the target views aren't finalized.
- **Add input validation** beyond the negative-closing-stock warning (e.g. data-type checks, dropdowns for product and location to prevent typos that fragment pivots).
- **Document the column schema** of Master Data (field names, types, expected values) so entries stay consistent.
- **Decide on a date-handling convention** so each day's paste lands as a clean, comparable date value.
- **Consider an archiving / backup approach** for Master Data as it grows.

---

## Notes for the next developer

Mucyo thinks through data problems carefully and usually arrives with the problem *and* the correct solution direction already identified — he diagnosed the wide-vs-long issue himself. He works best with **validation and refinement of his ideas** rather than top-down rebuilds, and engages substantively with technical detail. Build on his thinking.
