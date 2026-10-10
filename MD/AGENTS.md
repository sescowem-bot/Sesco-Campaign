# SESCO Campaign Cloud | Codex Engineering Handoff

## Mission
Treat this as a real multi-tenant commercial SaaS product by Sesco Studio. Take ownership of the existing source from Batch 5; do not recreate it from scratch or delete any implemented routes or modules. Conduct an evidence-based audit, fix failing foundations, then implement subsequent batches with working features and verification.

## Baseline source
Import the file `sesco-campaign-cloud-batch5-brand-template-studio.zip` and inspect all files including SQL migrations 001 to 005 and `MD/` before changing code. The earlier development packages were not proven production-ready. **Do not assume the current project builds, that Supabase migrations work, or that payment handling is secure and correct until you test it.**

## Scope and capabilities
Public website: Home, Features, Solutions, Pricing, About, Resources, FAQ, Contact, Privacy, Terms, Cookies, Acceptable Use, Login and Registration. Production-quality responsive layout across desktop, tablet and mobile.

SaaS platform: Platform Super Admin, Platform Admin, Company Admin and granular staff roles; organization-scoped brand identities; companies, verified sender domains, contacts, audience segmentation, Excel/CSV imports, visual email template builder, email headers and legal footers, approvals, campaigns, queues, analytics, subscriptions, Paystack billing and audit logs. Central provider configuration for Brevo/Resend with safe server-only API keys. SMS and WhatsApp should remain explicitly unavailable until correctly implemented.

Super Admin must control global platform display name, logos, fonts, colors, CMS/pages, public plans/prices, feature entitlements, companies, memberships, manual upgrades and audits. Company Admin can manage only their company and its branding, staff, templates, footers, email domains and billing.

## Technology and architecture
Use Next.js App Router, React, TypeScript strict, Supabase Postgres and Auth, Postgres RLS, Tailwind CSS and accessible design components. Keep code modular: `app`, `components`, `lib`, `supabase/migrations`, `tests`, `docs`. DB migrations must be incremental, reproducible and reviewable. Use a durable queue/worker for campaign delivery; do not tie a high-volume sending engine to synchronous browser requests. Server Actions/API routes must re-authorize on the server and DB policies must enforce isolation.

## Task 1: Audit and harden existing Batch 5
1. Read the full repository and map all routes, migrations, components, dependencies and auth/data flows.
2. Run a clean dependency installation. Generate and commit `package-lock.json`; prefer `npm ci` thereafter.
3. Run `npm run typecheck`, `npm run lint`, `npm run build`, document all failures, and repair them without removing intended functionality.
4. Inspect SQL 001–005 against a disposable Supabase environment. Validate that all migrations execute sequentially, test row-level security with at least two organizations, and check SECURITY DEFINER functions for authorization, `search_path`, input validation and bypasses.
5. Audit Paystack checkout, verified webhook signatures, amount/currency/reference match, idempotency, replay behavior, unauthorized requests, errors and subscription race conditions. Use only test mode until an independent security review.
6. Identify static copy inconsistent with implemented behavior (e.g. Pricing page's outdated statement about payment availability), nonfunctional controls, incomplete pages, and placeholder flows. Fix or clearly mark them as not yet available. Never claim a feature is live just because files exist.
7. Audit user-supplied email template content against XSS, malicious links, template injection and privacy risks. Ensure approved senders and mandatory marketing unsubscribe flows before any actual sends.
8. Confirm no secrets are client-exposed; verify `.env.example`, build metadata, policies, API auth and error logging.
9. Add GitHub Actions CI for dependency install, typecheck, lint, tests and production build, with branch protection guidance.
10. Produce a short audit report with pass/fail evidence, outstanding risks and exact file references.

## Task 2: Establish professional release gates
- Source formatting, ESLint, strict types and deterministic installs.
- Unit tests for critical business logic; integration tests for Supabase auth/RLS, subscriptions, payment webhooks and template data isolation; browser tests for critical user flows at desktop and mobile widths.
- Responsive, keyboard-accessible, brand-consistent UI; loading, empty, error and success states. No cramped tables, overlapping menus, fake metrics, dead-end buttons or decorative forms that never submit.
- Data migrations tested on an isolated database, transaction-safe where possible; documented rollback or forward-fix strategy.
- Security protections including least privilege, strong tenant isolation, secure server-only keys, verified email domains, consent/unsubscribe, rate limiting, sanitized HTML/email content, logs with no sensitive data, and secure webhook processing.
- Review dependencies for supported versions and vulnerabilities. Explain upgrades and avoid arbitrary major-version churn.
- Stable API error contracts, idempotency keys for payment/sending, monitoring and backup/recovery plan.
- Tests and screenshots or explicit manual verification evidence. Label incomplete features accurately.

## Task 3: Continue remaining roadmap
Once Task 1 passes, implement Batch 6 (contacts, validated Excel/CSV imports, lists, deduplication, segmentation), then Batch 7 (providers and domain verification), Batch 8 (campaign creation, previews and approvals), Batch 9 (queue and delivery), Batch 10 (analytics), Batch 11 (global CMS/admin completeness), Batch 12 (production security, tests and deployment). Ship logical PRs, not opaque monolithic ZIPs.

## Deliverable contract for every task
- Complete and editable source changes, no code omitted or silently removed.
- Exact filenames changed, SQL migration(s), environment changes, reproducible setup instructions.
- Tests run with actual commands and results; distinguish passed from untested.
- Screenshots or preview for visual changes when available.
- A security note on affected auth, tenant, payment or email data paths.
- Git commits / pull requests, if a GitHub repository is connected and authorized.

## Initial instruction
**Start with Task 1 only. Do not deploy, do not charge real money, and do not send real campaigns. Audit the complete Batch 5 project, repair build, security and data-model problems, and show verified results before proceeding to more features.**
