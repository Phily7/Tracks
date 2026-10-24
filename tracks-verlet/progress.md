# Progress — Tracks Verlet

_Last updated: 2026-10-24_

## Where things stand

**Code: feature complete, builds clean** (`npm run build`, `tsc`, `eslint`: no errors).
**Database: 0001 applied** (by the user, 2026-10-24). **Deployed:** https://tracks-verlet.vercel.app. Nothing committed to git yet.

## Done ✅

- [x] Read the template (`Verlet_Procurement_Request_TemplateV1.xlsx`): every Request-tab field, the N2 / C13 / L19 formulas, the Lists tab, the Read Me rules
- [x] Schema + rules + RLS: `supabase/migrations/0001_init.sql`
  - Tested in PGlite (local Postgres) with a stub `auth` schema, as manager / engineer / other engineer. All scenarios pass: allowlist, no self-promotion, engineers isolated from each other, submit blocked until READY, locked after submit, manager-only REQ numbers and approval
  - Bug found and fixed: the `can_sign_in` parameter was named `email`, which collided with the `profiles.email` column, so the check passed for every address. Renamed to `addr`
- [x] BOM parser (`src/lib/bom.ts`): checked on `public/samples/kicad_motor_driver_bom.csv` and `fusion360_gripper_bom.csv`
- [x] Question engine (`src/lib/questions.ts`) + UI cards (`QuestionFlow.tsx`)
- [x] Template export (`src/lib/export.ts`): checked with openpyxl. Header, items, formulas and all 4 dropdowns intact, example row cleared
- [x] Pages: login (engineer code / manager password), my requests (drop a BOM to start), request workspace, manager overview, `/setup` fallback
- [x] Manager script (`scripts/create-manager.mjs`), `.env.example`, README
- [x] Vercel project `tracks-verlet` created and linked (`.vercel/`, `.env.local` holds only `VERCEL_OIDC_TOKEN`)
- [x] Supabase MCP added to `.mcp.json` (project scope) for project `qnvjidujwwpoqdpqwlsb`

## Next steps (in order)

Done (2026-10-24, session 2): 0001 (user), 0002 hardening, 0003 prices-by-manager applied; allowlist set; philemonmail77@gmail.com
promoted to manager; env vars on Vercel; deployed https://tracks-verlet.vercel.app.
- Prices no longer block submit (SQL `line_issues` + `template.ts`). Approve/ordered is refused until every line has a price
  (`guard_request_status`). `unpriced_count` shown on the status box, manager panel and manager list.
- BOM parser reads distributor price breaks (`Unit1`, `Unit10`, `Price @ 100`…) and picks the break for the line qty.
  Backfilled the user's existing draft from `source_row` (1 line still unpriced).

1. ~~Auth config~~ done by the user: URL config set. Templates are locked without custom SMTP, so the app handles the default
   PKCE link (`/auth/confirm?code=`). Must be opened in the same browser.
2. E2E (Chrome, 2026-10-24): engineer link login ✅, KiCad sample upload ✅, cards ✅, READY with 10 unpriced ✅, submit + lock ✅.
   Manager approve guard checked in SQL as the manager (rolled back) ✅. **Still to check by hand:** manager password login,
   pricing in the table, REQ number, approve, .xlsx download opened in Excel.
3. Ask before committing

## Open issues / decisions

- **Supabase free tier is at 2 active projects.** Provisioning through the Vercel Marketplace failed for that reason. The Supabase integration *is* installed on Vercel (free plan), but no resource was created. Using the user's own project `qnvjidujwwpoqdpqwlsb` instead.
- **Built-in Supabase email is rate-limited** (a few per hour). Fine for a demo; needs custom SMTP (Resend) before engineers really use it.
- **Screenshot of the Verlet exchange never came through** (it rendered as a blank file icon). Requirements in it, if any, are not captured yet.
- The xlsx status box was not recalculated locally (no LibreOffice). The app's readiness logic mirrors the formulas; confirm by opening an exported file in Excel.
- Ideas not built: Change Order form, email notifications to the manager on submit, price lookup from LCSC/DigiKey, BOM diffs between revisions.
