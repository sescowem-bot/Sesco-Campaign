# SESCO Campaign Cloud Batch 7

## Delivered

- Platform Super Admin provider management: enable/disable Resend and Brevo, connection checks, unresolved registration recovery.
- Company Admin domain registration, provider DNS instructions and workspace-specific ownership TXT verification.
- From name, exact-domain sender addresses and Reply-To configuration.
- Explicit Brevo sender registration.
- Fixed configuration tests addressed only to the signed-in user's verified account email.
- Atomic test quota reservations, accepted/unknown history, no automatic sending retries.
- Domain revocation and sender deactivation, tenant-scoped foreign keys and RLS.
- Incremental migration 007 with RPC authorization and service-only verification updates.
- Lockfile, ESLint configuration, CI, provider tests, isolated PostgreSQL integration tests and production route smoke checks.

## Foundation repairs

The existing lint command had no ESLint configuration. Three JSX text errors prevented a clean lint/build once lint was configured. These are repaired. The public pricing RLS policy invoked an admin-only function from the anonymous role; migration 007 separates public and authenticated policies, with an anonymous pricing regression test. Pricing copy now reflects the existing billing implementation accurately. A PostCSS dependency override fixes the dependency audit findings without changing the Next.js major version. The sidebar logo and main-grid shrink behavior are corrected.

## Install

See BATCH7_SETUP.md. Apply migration 007 only if 001–006 already exist. Use Node 24 and npm ci. Provider credentials are server-only environment variables. Providers start disabled.

## Roadmap

Seven of twelve source development batches delivered. This does not mean seven twelfths of production acceptance testing is complete. Next: Batch 8, campaign composition, personalization, previews and approval workflows. Bulk delivery, scheduling, durable queues and event processing remain Batch 9.

## Boundaries

No GitHub change, push, merge or deployment was performed. No live provider domain registration, DNS update, payment or email was performed. Existing website, auth, company, plan, payment, branding, template and audience source modules are retained. Their live end-to-end acceptance remains outstanding. This release does not claim complete production certification.
