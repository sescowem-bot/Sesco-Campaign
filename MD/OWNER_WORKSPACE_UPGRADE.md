# Owner workspace upgrade · 0.13.0

## Install on your existing application

1. Back up the database. Your existing database already has migrations 001 through 012. Run only `supabase/migrations/013_owner_workspace.sql` in Supabase SQL Editor. This upgrade is transactional and can be rerun. It creates a separate active owner workspace without changing customer accounts or their suspensions.
2. Replace your application source with this complete package and deploy it to Vercel. Keep your existing environment values. No new API key is introduced by this upgrade.
3. Sign in with your existing verified Super Admin account and open `/admin/workspace`. The admin sidebar includes **My brand workspace**. The control center defaults to this workspace; you can still select and manage customer companies.
4. Click **Create campaign**. You can design and save drafts immediately, including before selecting a sender. Open the saved campaign after saving.
5. Under **Your existing email connection**, connect the sender you already use with Resend. Enter its From email, sender name, reply address, existing Resend domain ID and your business postal address. Copy the domain ID from the verified domain in Resend. The server checks it using your existing `RESEND_API_KEY`. This does not create a Resend domain or request another ownership TXT record. A restricted sending-only key cannot read domain status; this connection requires the existing server key to have domain read access.
6. Upload contacts with recorded consent. For your first test, create a contact list containing only your own address and select that list in the campaign. Select your connected sender and save the draft.
7. Click **Approve my campaign**. You do not need another company account or reviewer in your own workspace. Approval checks the sender, postal address and eligible recipients; it does not send email.
8. Open **Delivery queue** and queue that approved campaign. Sending requires `EMAIL_DELIVERY_ENABLED=true` and `NEXT_PUBLIC_APP_URL=https://sesco-campaign.vercel.app` in your deployed environment. Keep sending disabled until you are ready for your controlled test. The UI displays its current dispatch status.
9. Click **Send next queued email** on the queued run. Each click processes at most one due recipient in that selected owner run. This is a real send, not a preview. Provider limits, consent, suppression, fresh domain verification and queue leases still apply. For unattended campaigns, use the existing secure worker configuration in `MD/BATCH9_SETUP.md`.
10. Open **Reports & analytics**. Accepted means the provider accepted the email; webhook events update delivery outcomes. Confirm your existing Resend webhook targets this deployed application.

## What changed

- Dedicated owner workspace, independent of customer account status and subscription.
- Owner workspace navigation, campaign creation, contact uploads and reports.
- Owner approval restricted to a verified Super Admin operating in the dedicated workspace. Customer campaigns retain independent review.
- Drafts can be saved before a sender is selected. A verified sender is still required for approval and delivery.
- Existing Resend sender connection with server-side verification, no duplicate provider registration and no extra TXT ownership challenge for the owner.
- Controlled single-recipient dispatch from the selected owner run; automated worker remains available for bulk delivery.
- Explicit permission feedback when campaign editing is unavailable.
- Owner internal allowance of 10,000 emails per month, independent of customer billing. Provider account limits and the configurable platform provider budgets still apply.
- README remains at root. All other authored Markdown remains in `MD`.

A customer's domain record is not moved or reactivated. The owner's verified provider connection is recorded separately. Existing customer authentication and domain verification requirements remain unchanged.

## Verification

Run: `npm run lint`, `npm run typecheck`, `npm test`, `npm run build`, `npm run test:smoke`.

The isolated PostgreSQL tests cover installation, rerunning migration 013 without duplicate workspaces, unauthorized access, suspended client isolation, senderless drafts, approval validation, existing sender linking, customer self-approval rejection, owner self-approval with audit history, subscription-free owner queuing, and dispatch restricted to the selected owner run. Provider calls are not made by these database tests.

Hosted Supabase credentials, signed-in desktop/mobile browser behavior, real Resend acceptance and delivery/webhook behavior still require the controlled live test above. No deployment or live email was performed while preparing this package.

## SQL files

- Existing database at migration 012: run **013 only**.
- Completely new empty database: run `supabase/SESCO_Complete_Fresh_Install.sql`, containing 001–013, once. Do not run it on the existing database and do not run individual migrations afterward.

## Main changed files

`supabase/migrations/013_owner_workspace.sql`, fresh master SQL, `app/admin/workspace/`, `components/owner-sender-form.tsx`, admin overview, shared workspace navigation, account workspace selection, campaign studio/page/actions, sender page, email domain refresh, delivery page/actions/worker/form, database tests, smoke routes, package version and setup documentation.
