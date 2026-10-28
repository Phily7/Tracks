# Progress — Tracks Verlet

_Last updated: 2026-10-28_

## Where things stand

**Live and ready for a first round of testing.** https://tracks-verlet.vercel.app
Migrations 0001–0006 applied to Supabase `qnvjidujwwpoqdpqwlsb`. Builds clean. Committed on branch `tracks-verlet`
of the parent `Tracks` repo (not merged to `main`, not pushed).

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

## State at end of session 2 (2026-10-24)

**Accounts**
- `philemonmail77@gmail.com`: manager + **owner** (password login). Only the owner can demote managers; nobody can change the owner.
- `verletrobotics@gmail.com`: manager, password set by the user via SQL. Shared with testers for the manager side.
- `philemonmail77+eng@gmail.com`: engineer test account.
- Allowlist: the two philemon addresses, `verletrobotics@gmail.com`, `@verlet.co`, `@gmail.com` (open Gmail sign-ups for testing).

**Email**: custom SMTP through the user's own Gmail (`philemonmail77@gmail.com`, app password, smtp.gmail.com:465, sender
name "Tracks Verlet"), rate limit 500/h. Supabase's default "Your sign-in link" template is in use (no typed code yet).
Verified: email delivered, link redirects to `/auth/callback` with the session.

**Built this session**
- Prices optional for engineers; approve/ordered blocked until every line is priced (0003). Unpriced counts shown.
- Sign-in links use the implicit flow → `/auth/callback`, so they work in any browser/device (PKCE links didn't).
- BOM import: .xlsx/.xlsm and CSV/TSV in any layout (`bomFile.ts`, `bom.ts`): sheet picking, header row under titles,
  synonyms + loose header matches + content inference, headerless files, section/total/repeated-header rows,
  row-number columns, decimal commas, total-price columns, unit/notes columns, LCSC price breaks.
  Upload message shows "Read columns: …". Tested on 9 fixtures (not through the live UI).
- Team panel: Make manager / Make engineer (`set_role`, 0004), owner protection (0005).
- Verlet theme (DM Sans / DM Serif Display, pink #d64d7a, Verlet mark) + system dark mode.
- Security advisor fixes (0002).

## Change tracking (live since 2026-10-28)

Engineers and managers edit requests at every stage. After approval, edits are pending changes (New / Changed / Removed,
old values crossed out) until a manager approves them (`approve_request`) or someone discards them (`discard_changes`).
The confirmed BOM is shown separately and is what the .xlsx exports. Migration 0006 applied after the user re-authed the MCP.
Checked in a rolled-back SQL scenario as the real users (direct approve blocked; approve → pending 0; engineer edits →
pending 4; hard-delete of a confirmed line deletes nothing; snapshot not writable; engineer can't approve; discard restores;
approving changes merges and drops removed lines). In Chrome: a submitted request now opens editable for its engineer.
**Not clicked through in the UI yet:** the approved-request view (highlights, banner, Approve/Discard), which needs an
approved request and the manager session.

## Next steps

1. Collect tester feedback (message sent by the user). Watch Supabase auth logs for failed sign-ins.
2. User to check by hand: an exported .xlsx opened in Excel (status box should read READY TO SEND); an Excel BOM upload on the live site
3. Optional: paste the template with `{{ .ConfirmationURL }}` + `{{ .Token }}` into "Confirm sign up" and "Magic link or OTP"
   so emails also carry a typed code
4. Later: switch SMTP to a Verlet address (Resend + `verlet.co` DNS via Verlet IT); Supabase settings only, no code
5. When testing ends: remove `@gmail.com` from the allowlist; consider limiting delete-request / allowlist / projects edits to the owner
6. Merge or push the `tracks-verlet` branch when the user wants

## Open issues / decisions

- **Supabase free tier is at 2 active projects.** Provisioning through the Vercel Marketplace failed for that reason. The Supabase integration *is* installed on Vercel (free plan), but no resource was created. Using the user's own project `qnvjidujwwpoqdpqwlsb` instead.
- **Email** goes through the developer's personal Gmail for now; move to a Verlet sender before real use.
- **Screenshot of the Verlet exchange never came through** (it rendered as a blank file icon). Requirements in it, if any, are not captured yet.
- Old `.xls`, Google Sheets and Numbers files aren't read directly (users export to .xlsx/.csv).
- The xlsx status box was not recalculated locally (no LibreOffice). The app's readiness logic mirrors the formulas; confirm by opening an exported file in Excel.
- Ideas not built: Change Order form, email notifications to the manager on submit, price lookup from LCSC/DigiKey, BOM diffs between revisions.
