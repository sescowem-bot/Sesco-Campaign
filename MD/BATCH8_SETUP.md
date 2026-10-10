# Batch 8: Campaign composition and approval

This is the complete source including Batches 1–7. Use Node 24 and `npm ci`. Existing Supabase configuration is retained; there are no new environment variables.

## Database

If migrations 001–007 are already installed, apply only `supabase/migrations/008_campaign_workflows.sql`. For a fresh database, apply 001–008 once in order. Do not drop previous tables. Migration 008 runs in a transaction and adds campaign drafts, immutable revision records, audience counts, edit/review permission functions and workflow RPCs.

## Create a campaign

1. Open `/dashboard/campaigns?org=YOUR_ORGANIZATION_UUID` as Company Admin, Manager, Designer or Platform Super Admin in an active workspace.
2. Save company branding and a postal address in Brand Studio. Set up a verified sender and enabled provider through Batch 7.
3. Create a campaign. Start with a saved company/platform template or create content blocks. The template design is copied into the campaign so subsequent template edits do not change its content.
4. Enter the campaign name, subject and optional preheader. Select a sender and either all eligible contacts, a contact list or a saved segment. Only contacts with email, granted consent and no unsubscribe qualify. Segment conditions use AND, and consent restrictions always apply.
5. Use first_name, last_name, email, company_name or attributes.field_name inside double braces. Missing first names display Customer; other missing values display empty text. Unknown or malformed variables are rejected. Personalization applies to text, not button URLs. Preview uses sample recipient data and escaped HTML.
6. Optionally choose a future requested send time in UTC. This records a request; it does not create a delivery job.
7. Save the draft. For a new campaign, open the saved campaign using the success link before submitting it for review.

## Approval

- Company Admin, Manager and Designer can create/edit/submit/withdraw/archive campaigns.
- Company Admin, Approver and Platform Super Admin can review campaigns.
- The reviewer must be different from both the last editor and submitter. An owner is not allowed to self-approve; use a separate authorized account.
- Submission and approval require a verified active sender, enabled provider, company postal address, eligible opted-in audience and a future requested time if supplied.
- Reject requires a reason. Return to draft allows editing a campaign under review. Editing an approved campaign clears its approval and review metadata.
- Every save and transition creates an immutable revision snapshot and audit entry. Stale revision submissions are rejected; reload before retrying. The UI shows the latest 30 revisions and latest 100 campaigns.

## Delivery boundaries

Batch 8 does not dispatch campaigns or send campaign-content tests. Batch 7 configuration tests remain available. Approved campaigns and requested times are prepared for Batch 9's durable queue, worker, suppression rechecks, quota reservations, live unsubscribe URLs and delivery events. Unsubscribe in the preview is an explicit placeholder; there is no production sending entry point using it.

Company branding is read at preview time. Campaign content and workflow revisions are stored, but a fully frozen delivery/brand/recipient snapshot will be established by the queue batch. Audience counts are live, not guaranteed final delivery counts. Before dispatch, Batch 9 must revalidate active organization, subscription entitlement, provider/domain ownership, sender identity, consent and suppression and freeze approved delivery content.

## Verify

Run `npm run lint`, `npm run typecheck`, `npm test`, `npm run build`, then `npm run test:smoke`. Integration tests execute SQL through isolated PGlite PostgreSQL with mock Supabase auth roles, not your live database. Live Supabase authentication, approval flows, browser layout and provider operations still require acceptance testing in your configured environment.

No GitHub push, merge, deployment, payment or email is performed by this source release. Take a backup before applying migrations. If 008 fails, its transaction rolls back. Prefer a reviewed forward migration to undoing earlier modules.
