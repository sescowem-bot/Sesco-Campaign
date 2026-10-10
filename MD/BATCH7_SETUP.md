# Batch 7: Email providers, domains and sender identities

This complete source package retains Batches 1–6. Campaign composition and approval are Batch 8; bulk queues and delivery events are Batch 9. This batch sends only a fixed configuration test to the signed-in administrator's verified email address when they explicitly press the test button.

## Installation

1. Use Node.js 24. Run `npm ci` from the project root. The committed lockfile makes installation reproducible.
2. Configure `.env.local` from `.env.example`. Existing Supabase URL, anon key and server-only service role key are required. Add `RESEND_API_KEY` and/or `BREVO_API_KEY` to your server environment. Never expose them through `NEXT_PUBLIC_` variables.
3. For a database with migrations 001–006 already applied, apply **only** `supabase/migrations/007_email_providers.sql`. For a fresh database, apply 001–007 once in order. Do not drop existing tables. Migration 007 runs in a transaction and deliberately invalidates older cached verified domain states until ownership is rechecked.
4. Sign in as the verified Platform Super Admin. Open `/admin/providers`, check the provider connection, then enable the provider. Providers start disabled.
5. Sign in as Company Admin for an active company. Open `/dashboard/senders?org=YOUR_ORGANIZATION_UUID`. Register a domain you control. Provider plan restrictions and domain allowances still apply.
6. Add the displayed provider DNS records plus the unique `_sesco-campaign` ownership TXT record through your DNS host. DNS hosts may automatically append your domain; check whether they expect relative or full host names. Do not create a second SPF/DMARC record where one already exists. Ask your DNS administrator to merge policies and preserve existing email routing.
7. Click Check verification. Verification requires both provider authentication and the exact workspace ownership TXT token. Provider verification can be asynchronous; recheck after propagation. A refresh failure invalidates cached verification, and no test is sent.
8. Save a sender using exactly the verified domain, a From name and Reply-To address. Brevo may also require sender registration/approval: use the explicit Brevo registration control once and review its dashboard if needed.
9. Send a configuration test to your verified account address. Provider acceptance is recorded separately from inbox delivery. Limit: one test per minute and ten attempts per rolling 24 hours per organization. Reservations and unknown outcomes count toward the limit. Sending is never automatically retried.

## Registration reconciliation

Domain reservation happens before provider registration to prevent cross-company claims. There is no distributed transaction between the database and provider. A timeout or failed status write can leave a reserved domain with an unconfirmed provider registration. Do not repeatedly register it or adopt another company's provider domain.

The Super Admin must inspect the provider dashboard. Once they establish the correct domain belongs to the intended workspace, link the actual provider domain ID using the reconciliation form on `/admin/providers`. The server checks the provider domain name and saves it as pending; the Company Admin must then complete the ownership TXT check. Domains are globally reserved and revocation keeps the reservation to prevent takeover. Reassignment is an explicit future administrative workflow, not automatic.

## Verification and release limits

Run `npm run lint`, `npm run typecheck`, `npm test`, `npm run build`. The database tests execute migrations 001–007 in an isolated PGlite PostgreSQL instance with mock Supabase auth users/roles. The only SQL omitted there is `create extension pgcrypto`; PostgreSQL's built-in `gen_random_uuid()` is used. This does not substitute for live Supabase auth/session, DNS and provider testing.

No real provider domains were registered and no email was sent during development. Confirm account approval, appropriate provider terms for customer campaigns, DNS, API keys and test acceptance in your configured environment before operation. The Batch 7 test endpoint is not a general-purpose campaign sending endpoint. Marketing templates, consent, unsubscribe processing and durable campaign queues remain gated on later batches.

## Operations and recovery

Disable a provider centrally to stop new sender registrations/tests using it. Revoke a domain to deactivate its sender identities. Provider records remain for review; they are not deleted remotely. Preserve keys securely, rotate them in your hosting settings, and recheck connection. `email_test_attempts` records reservations/accepted/unknown outcomes, not delivery tracking. A crash after provider acceptance may leave a reserved attempt; inspect the provider dashboard before retrying.

Forward repair is preferred. If installation fails, the transaction rolls back the new migration. Do not re-run an already applied migration or undo previous payment/contact migrations. Take a database backup before deployment. No deployment is performed by this source package.
