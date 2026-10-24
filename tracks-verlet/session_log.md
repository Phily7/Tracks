# Session log — Tracks Verlet

## 2026-10-24 — Session 1: from spreadsheet to working app (pre-database)

**Ask:** build "Tracks Verlet" for Verlet Robotics, modelled on the FabFoods Tracks app. The backend collects
what `Verlet_Procurement_Request_TemplateV1.xlsx` needs. Managers log in with a password; engineers are passwordless.
Engineers upload BOM CSVs (KiCad, Fusion 360), get questions only for what their BOM lacks, and their answers fill the request.
Supabase for the database, Vercel for the demo.

**Findings**
- The FabFoods app (`../tracks`) is Flutter + Drift + Supabase, offline-first POS. Not reused: this one is a web workflow with a server
  and a Vercel target, so went with **Next.js + Supabase** in a new folder `tracks-verlet/`.
- Template rules extracted from the formulas: header needs name, email, project, needed-by, why (≥15 chars), example row deleted.
  Each line needs qty > 0, unit, spec ≥ 25 chars, air-freight answer, est. price, unique name. 40 rows max.
  Lists: 8 projects (incl. NIST in the filled copy), 10 units, 3 urgencies, 3 air-freight answers.
- Real filled requests (`Procurement/NIST Task1 request.xlsx`) and purchase lists (`Task 1/Task1_Purchase_List.xlsx`) confirmed how
  engineers actually fill it (Kigali sources in the vendor column, phone number in the G5 note).
- Access at the start: no Supabase MCP loaded, no Docker; Vercel CLI logged in via `npx vercel` (`philemonmail77-5976`).

**Built**
1. `supabase/migrations/0001_init.sql`: tables, enums, `line_issues` / `request_issues` (template rules in SQL),
   `request_summaries` view, allowlist + `can_sign_in`, `assign_req_number`, status-guard trigger, RLS.
2. `src/lib/bom.ts`: header detection, synonym mapping, KiCad naming (ref prefix + value, readable footprints, MPN for generic
   connector symbols), Fusion fields, grouping, unit and air-freight guesses, spec hints.
3. `src/lib/questions.ts` + `QuestionFlow.tsx`: grouped cards (details → air freight → units → qty → specs → prices → optional links).
   Answers save immediately; a confirmed answer drops its "auto" marker.
4. `src/lib/export.ts`: fills the real template; exceljs loaded on demand (request page went from 453 kB to 198 kB first load).
5. Pages: login, my requests, request workspace, manager overview; middleware auth; `/setup` fallback when env vars are missing.

**Verified**
- Parser on both sample BOMs (DNP / test points / mounting holes skipped, LCSC picked up as vendor, magnets/threadlocker/CR2032 flagged).
- Export reopened with openpyxl: formulas + validations intact.
- PGlite run of the migration with role-switching scenarios: all pass after fixing the `can_sign_in` parameter-shadowing bug.
- `npm run build` clean.

**Infra attempts**
- `vercel link` → project `tracks-verlet` created.
- `vercel integration add supabase`: user accepted the marketplace terms. `--plan free` was rejected (that's the installation plan ID, not a resource plan).
  Without a plan it failed: **Supabase free limit of 2 active projects** reached. Stopped and gave the user options (pause a project / upgrade / share a project).
- User supplied project `qnvjidujwwpoqdpqwlsb` and an MCP command (added to `.mcp.json`, **read_only=true**). The MCP tools only load after a restart, and read-only must be lifted to run the migration.

**State at end of session:** code complete, no database, not deployed, nothing committed. Next steps are in `progress.md`.
