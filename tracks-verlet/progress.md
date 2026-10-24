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

State (2026-10-24, end of session 2): live at https://tracks-verlet.vercel.app, migrations 0001–0004 applied, Verlet theme
(light + system dark), committed on branch `tracks-verlet` of the parent `Tracks` repo.
- Prices optional for engineers; approve/ordered blocked until every line is priced (0003).
- BOM parser reads distributor price breaks (`Unit1`, `Unit10`…).
- `/auth/confirm` handles Supabase's default PKCE link (templates are locked without custom SMTP).
- Managers promote/demote from the Team panel (`set_role`, 0004). Promoted managers sign in with the email link; no password needed.
- E2E checked in Chrome as engineer; manager rules checked in SQL as the manager (rolled back).

1. **Custom SMTP.** Interim: Gmail SMTP from the developer's own `philemonmail77@gmail.com` (app password, smtp.gmail.com:465,
   sender name "Tracks Verlet"). Switch later to a Verlet address (Resend + `verlet.co` DNS, needs Verlet IT); that's a
   Supabase SMTP-settings change only, no code. Templates use `{{ .ConfirmationURL }}` + `{{ .Token }}`.
   Allowlist currently includes `@gmail.com` for testing; remove it in the Team panel to close sign-ups
2. User to check by hand: manager login, pricing, REQ number, approve, Team "Make manager" button, .xlsx opened in Excel
3. Push / merge the `tracks-verlet` branch when the user wants

## Open issues / decisions

- **Supabase free tier is at 2 active projects.** Provisioning through the Vercel Marketplace failed for that reason. The Supabase integration *is* installed on Vercel (free plan), but no resource was created. Using the user's own project `qnvjidujwwpoqdpqwlsb` instead.
- **Built-in Supabase email is rate-limited** (a few per hour). Fine for a demo; needs custom SMTP (Resend) before engineers really use it.
- **Screenshot of the Verlet exchange never came through** (it rendered as a blank file icon). Requirements in it, if any, are not captured yet.
- The xlsx status box was not recalculated locally (no LibreOffice). The app's readiness logic mirrors the formulas; confirm by opening an exported file in Excel.
- Ideas not built: Change Order form, email notifications to the manager on submit, price lookup from LCSC/DigiKey, BOM diffs between revisions.
