# Development roadmap

## Batch 1: Phases 01–04
New repository structure, branded responsive foundation, migration strategy and documentation.

## Batch 2: Phases 05–12
Complete design system, Supabase Auth, server-side guards, Super Admin bootstrap, company membership, tenant isolation and RLS policies. Protect /admin and /dashboard before any production exposure.

## Batch 3: Phases 13–24
Company administration, subscriptions, editable global/company branding, footers, provider adapters, domain verification and sender identities.

## Batch 4: Phases 25–36
Contact import, mapping, lists, segmentation, email design studio, campaign approvals, durable sending queues and event processing.

## Batch 5: Phases 37–48
Analytics, plan pricing and overrides, Paystack checkout, server-side verification, signed webhooks and idempotent subscription activation.

## Batch 6: Phases 49–58
Public SaaS onboarding, support, compliance, production testing, backups and deployment.

## Deferred: Phases 59–60
SMS and WhatsApp provider integrations. No simulated live sending.

## Security release gates
- Do not expose service role or provider credentials to client code.
- Do not activate real payment, sending, or admin operations before server authorization and audit logs.
- Do not process contact lists without consent and unsubscribe/suppression support.
- Never treat provider acceptance as confirmed delivery.
- Test multi-tenant isolation and webhook idempotency.
