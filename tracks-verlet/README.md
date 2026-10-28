# Tracks Verlet

Procurement requests for Verlet Robotics, built from the engineer's BOM.

Engineers sign in with an emailed code (no password), drop a KiCad or Fusion 360 BOM CSV, and answer
a few grouped questions. Each answer goes straight into the request. When the status box reads
**READY TO SEND** they submit it. Procurement (the manager) reviews it in the app, assigns a REQ number,
and can download the filled `Verlet_Procurement_Request_TemplateV1.xlsx` at any time.

Sister app to FabFoods Tracks (Flutter POS, `../tracks`). Different company, so separate codebase,
database and deployment.

> Current status and next steps: [`progress.md`](progress.md). History: [`session_log.md`](session_log.md).

## Stack

- **Next.js 15** (App Router, TypeScript, Tailwind v4) on **Vercel** (project `tracks-verlet`, hobby team `philemonmail77-5976`)
- **Supabase**: Postgres + Auth + RLS (project ref `qnvjidujwwpoqdpqwlsb`)
- `papaparse` for CSV, `exceljs` (lazy-loaded) to fill the real template

## Roles

| Role | Sign-in | Can |
|---|---|---|
| Engineer | Email OTP (6-digit code), only if the email or its `@domain` is on the allowlist | Create requests, upload BOMs, answer questions, submit when READY. Read-only after submitting |
| Manager | Email + password (created with `scripts/create-manager.mjs`) | See every request, set status, assign REQ numbers, leave notes, manage the allowlist and projects |

## How it maps to the spreadsheet

| Template | Tracks Verlet |
|---|---|
| Request tab C4–C11 (title, name, email, project, dates, urgency, why) | `requests` + `profiles` |
| Request rows 19–58 (item, qty, unit, spec, link, air freight, price, vendor, notes) | `line_items` |
| Check column (L), helper N2, status box C13–C16 | `src/lib/template.ts` (UI) and `line_issues()` / `request_issues()` (DB). The DB refuses to submit a request that isn't ready |
| Lists tab (projects, units, urgency, air freight) | `projects` table + Postgres enums |
| "Email it to procurement, wait for a REQ number" | Submit button → manager assigns `REQ-YYYY-NNNN` |
| "Don't edit and resend after sending" | Submitted requests are read-only for engineers (RLS + trigger) |
| 40-line limit | Download splits into `_part1`, `_part2`… files |

## Code map

```
src/lib/template.ts      template rules, dropdown lists, types (mirror of the xlsx formulas)
src/lib/bom.ts           CSV → draft line items (KiCad / Fusion 360 / generic), spec hints
src/lib/questions.ts     what's missing → question cards
src/lib/export.ts        fills public/template/Verlet_Procurement_Request_TemplateV1.xlsx
src/lib/data.ts          supabase-js data layer (RLS does the access control)
src/lib/importBom.ts     upload → parse → insert (tops up qty for parts already on the request)
src/components/QuestionFlow.tsx   the question cards
src/components/LineItemsTable.tsx editable table with Check column + "auto" markers
src/app/login            engineer code login / manager password login
src/app/requests         engineer home (drop a BOM to start) and the request workspace
src/app/manager          overview, allowlist, projects
supabase/migrations/0001_init.sql  schema, rules, RLS, triggers
scripts/create-manager.mjs         creates/resets the manager account
public/samples/          sample KiCad + Fusion 360 BOMs for demos
```

## BOM import

- Finds the header row even when there's a preamble, and maps columns by synonym (Reference/Designator, Value,
  Footprint/Package, Qty/Quantity, MPN/Part Number, Manufacturer, Description, Material, LCSC/DigiKey/Mouser, Datasheet, Price).
- KiCad: drops DNP parts, test points, fiducials, mounting holes and logos. Names parts from the reference prefix
  + value (`Resistor 10k`, `Connector B4B-XH-A`), and turns footprints into packages (`0603 (1608 metric) SMD`).
- Fusion 360: Part Name / Description / Material / Part Number.
- Groups identical parts and sums quantities. Two parts with the same name get their package appended, so the template's duplicate check doesn't trip.
- Pre-fills spec, link, vendor, unit (`pcs` when confident) and air freight (`Yes` for magnets, batteries, adhesives,
  threadlockers, liquids, aerosols…). Anything Tracks filled in itself shows an **auto** marker until a person edits it.

## Setup

1. Run `supabase/migrations/0001_init.sql` on the Supabase project (MCP `apply_migration` or the SQL editor).
2. Supabase Auth:
   - Email provider on, OTP length 6.
   - **Magic Link** email template must contain `{{ .Token }}` (the code). Optionally add a link to
     `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=email`.
   - Site URL + redirect URLs = the Vercel URL (and `http://localhost:3000`).
   - Built-in email is rate-limited to a few messages an hour. Set up custom SMTP (e.g. Resend) before real use.
3. Env vars (Vercel + `.env.local`): see `.env.example`.
4. Manager: `SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… node scripts/create-manager.mjs <email> '<password>' 'Name'`
5. Allowlist engineers from the Overview page (an address, or `@verlet.co` for everyone at the domain).

```bash
npm install
npm run dev      # http://localhost:3000. Without Supabase env vars every page redirects to /setup
npm run build
```
