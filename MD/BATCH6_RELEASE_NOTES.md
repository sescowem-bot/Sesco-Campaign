# Batch 6 Release Notes — Contacts & Audiences

## New features

- Company contact directory, manual record creation, editing, email search and pagination.
- Evidence-backed marketing consent status. CSV/Excel imports default to **unknown**, not opted in.
- Browser-parsed CSV and XLSX imports with manual field mapping, sample preview, optional Nigerian number normalization, up to 12 optional custom fields, progress indicators, duplicate and invalid row totals.
- Company-specific static contact lists with add/remove member workflows.
- Saved dynamic segments filtered by source, marketing consent and email presence.
- Import history, idempotent batches and auditable changes.
- Organization-specific navigation in desktop and mobile dashboards.
- Supabase RLS, composite tenant-safe list membership keys, restricted mutation RPCs.

## Files

- `supabase/migrations/006_contacts_audiences.sql`
- `app/dashboard/contacts`, `app/dashboard/imports`, `app/dashboard/lists`, `app/dashboard/segments`
- `app/api/contacts/import/route.ts`
- `app/dashboard/contacts/actions.ts`
- `components/contact-forms.tsx`, `components/contact-import-wizard.tsx`
- `lib/contacts/*`
- `public/samples/contacts-import.csv`
- `tests/*`
- `.github/workflows/ci.yml`

## Security and safety choices

- No use of Supabase service-role credentials in the new contact management routes.
- Contact PII available only to organization managers/admins and Platform Super Admin.
- RLS enabled and company ownership revalidated inside PostgreSQL functions.
- Contacts in different organizations may share an email or phone without collision.
- Import cannot override an existing contact or its unsubscribe/consent state.
- File limit 5 MB and 5,000 rows; server batch cap 100 contacts.
- Extra columns are opt-in, text-only, capped and not used for SQL expressions.

## Tests performed

- `npm test`: local CSV parsing, phone formatting and migration-structure checks passed.
- TypeScript AST syntax parsing: passed.

## Outstanding before real deployment

- Dependency install and full typecheck/build (registry networking unavailable in authoring environment).
- Apply migrations against a disposable Supabase project and perform real RLS tests with two distinct company accounts.
- Test XLSX upload using installed `read-excel-file` 9.x.
- Test actual session, forms, import batch retry and tenant isolation end to end.
- Generate and commit a `package-lock.json` after installation.
- Audit and test earlier payment flows separately before accepting live payments.
