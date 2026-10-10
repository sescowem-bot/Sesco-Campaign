# SESCO Campaign Cloud

Current release: **Admin campaign testing, version 0.14.0**. Complete editable Next.js and Supabase source through migration 014 by Sesco Studio. Production acceptance remains outstanding.

## Setup

1. Use Node.js 24 and run `npm ci`.
2. Copy `.env.example` to `.env.local` and configure Supabase values.
3. On a new database, apply SQL migrations 001 through 014 in order, or use the fresh install SQL once. At migration 013, apply only 014. At migration 012, apply 013 then 014.
4. Follow [admin campaign testing setup](MD/ADMIN_CAMPAIGN_TESTING.md) and the provider/worker instructions in [Batch 9 setup](MD/BATCH9_SETUP.md).
5. Run `npm run dev`, or `npm run build` then `npm start`.

## Available modules

Protected account and company workspaces; contacts and CSV/XLSX imports; lists and segments; branding and structured email templates; domain verification and senders; campaign composition, owner approval in the dedicated brand workspace and independent customer approvals; durable scheduled delivery queues; provider events and suppression; aggregate reports and CSV exports; Paystack billing; company status, subscription and role administration; public website CMS with drafts, revisions, preview and publication; audit activity.

`/admin` requires Super Admin access. `/dashboard` requires sign-in and company membership for company tools. Bootstrap the first owner through reviewed Supabase SQL instructions in [engineering handoff](MD/AGENTS.md). Company role assignment requires an existing verified account and does not send invitations.

## Documentation

All authored Markdown is in **MD**, except this GitHub README. Start with [admin campaign testing](MD/ADMIN_CAMPAIGN_TESTING.md), [development progress](MD/DEVELOPMENT_PROGRESS.md), [release notes](MD/BATCH12_RELEASE_NOTES.md) and [quality report](MD/QUALITY_REPORT_BATCH12.md). Historical batch notes describe their original releases; current setup notes take precedence.

## Verification

Run `npm run lint`, `npm run typecheck`, `npm test`, `npm run build`, `npm run test:smoke` and `npm audit --omit=dev`. CI runs the same source gates with a clean dependency installation.

## Production status

12 of 12 source packages are delivered. This is a release candidate requiring the pending checks in [live acceptance](MD/LIVE_ACCEPTANCE.md). Live Supabase/provider/DNS/payment acceptance, browser checks, load tests, backups, operational scheduling and deployment remain release gates. No live sends, payments or deployment are claimed. SMS and WhatsApp are unavailable. Keep email delivery disabled until configured and accepted in staging. Public legal copy remains draft material requiring the operator's review.

Deployment and recovery procedures are in [deployment runbook](MD/DEPLOYMENT_RUNBOOK.md) and [backup recovery](MD/BACKUP_RECOVERY.md). `npm run check:release` validates configured environment names/roles without contacting services or printing secrets.

## Starting from a fresh project

See [Fresh installation](MD/FRESH_INSTALL.md). The complete database installation is `supabase/SESCO_Complete_Fresh_Install.sql`. Run it once instead of applying migrations 001 through 012 individually.
