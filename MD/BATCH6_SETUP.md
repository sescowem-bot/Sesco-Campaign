# SESCO Campaign Cloud — Batch 6: Contacts, Excel/CSV, Lists, Segments

## Installation

1. Begin from this **entire ZIP package** (it includes all previous batches). Back up your previous project.
2. Set up `.env.local` using the README. Never publish private keys.
3. Apply SQL migrations **001 → 006** in order on a fresh Supabase project. If you already applied 001–005, apply only `006_contacts_audiences.sql`.
4. Run `npm install` to obtain the current `read-excel-file` (9.x, using its named `readSheet` API) and other application dependencies. Generate and commit `package-lock.json` using your normal development environment (not generated in this offline environment).
5. Run `npm test`, `npm run typecheck`, and `npm run build`.
6. Sign in to a verified company administrator or manager account. Open `/dashboard`, select your company, then use Contacts, Import, Lists and Segments.

## Roles / permissions

Contact data can be seen or changed only by company admins and managers assigned to the same *active* organization, plus platform super admins. Other staff roles have no direct access to contact PII. Row Level Security is enforced by Supabase in addition to server authorization checks. No direct user-table mutations are permitted; write operations use guarded database functions.

## Import workflow

- Upload a **CSV or XLSX** with the first row containing column names (maximum 5 MB, 5,000 contact rows, 60 columns for CSV).
- Map first name, last name, email and phone. Map an email or phone column.
- If appropriate, select optional Nigerian phone conversion, or supply E.164 numbers directly.
- Optionally include up to 12 unmapped columns as text-only custom attributes (off by default for privacy).
- Review the first five records. Import in batches of 100. Each batch has an idempotency key so retried requests do not duplicate rows.
- Duplicate email/phone identities are skipped, never silently overwritten. Invalid records are counted as rejected.
- All imported contacts receive **unknown marketing consent** even if the file makes an unsupported opt-in claim. Send marketing only after consent has been documented.
- No uploaded source spreadsheet is stored on the server. The browser parses the file and sends mapped contact rows.

## Segment rules

Supported segment filters: consent status (unknown/granted/denied), contact source (manual/import) and email presence. Conditions combine with AND. Counts are recomputed from the latest data when the segment page is requested; there is no stale list to synchronize.

## Database validation checklist

- Verified company A cannot select company B's contacts, lists, segments or import history.
- A company viewer, designer or analyst cannot create or import contacts.
- Platform Super Admin can inspect company contact data only for legitimate administrative purposes.
- `contact_list_members` composite foreign keys prevent cross-organization list membership even if a privileged caller makes a mistake.
- Import the same 100-row batch twice with the **same key**; the second call returns original counts and does not reinsert contacts.
- Import duplicates with different cases in email; existing contacts and consent must remain untouched.
- Imported entries are not eligible for marketing sends until consent is confirmed in an authorized workflow.

## Limitations requiring additional work

- SQL migrations and RLS tests have **not** been run against a real Supabase instance in this environment.
- Full Next.js production build cannot be confirmed here because npm registry networking is unavailable. Only dependency-free unit tests and TypeScript syntax checks are performed.
- List membership editor currently selects the first 100 contacts, and list member count preview is capped; add server paginated member management before very large audience workloads.
- Advanced segment logic, tag filters, contact editing, exports, delete/erasure requests, consent proof document storage and unsubscribe integration belong to later batches.
- Plan quota enforcement, sending providers and campaign delivery are not yet implemented. Contact records do not authorize sending.

The `next`, `eslint-config-next`, `react`, and `react-dom` minimum versions were raised to incorporate publicly announced security fixes. Verify newer advisories before deployment.
