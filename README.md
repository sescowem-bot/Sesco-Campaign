# SESCO Campaign Cloud

Current release: **Batch 12, version 0.12.0**. Complete editable Next.js and Supabase source through Batch 12 by Sesco Studio. Production acceptance remains outstanding.

## Setup

1. Use Node.js 24 and run `npm ci`.
2. Copy `.env.example` to `.env.local` and configure Supabase values.
3. On a new database, apply SQL migrations 001 through 012 in order. On a database already at Batch 11, apply only migration 012 after backup.
4. Follow [Batch 12 setup](MD/BATCH12_SETUP.md) and the provider/worker instructions in [Batch 9 setup](MD/BATCH9_SETUP.md).
5. Run `npm run dev`, or `npm run build` then `npm start`.

## Available modules

Protected account and company workspaces; contacts and CSV/XLSX imports; lists and segments; branding and structured email templates; domain verification and senders; campaign composition and independent approvals; durable scheduled delivery queues; provider events and suppression; aggregate reports and CSV exports; Paystack billing; company status, subscription and role administration; public website CMS with drafts, revisions, preview and publication; audit activity.

`/admin` requires Super Admin access. `/dashboard` requires sign-in and company membership for company tools. Bootstrap the first owner through reviewed Supabase SQL instructions in [engineering handoff](MD/AGENTS.md). Company role assignment requires an existing verified account and does not send invitations.

## Documentation

All authored Markdown is in **MD**, except this GitHub README. Start with [development progress](MD/DEVELOPMENT_PROGRESS.md), [release notes](MD/BATCH12_RELEASE_NOTES.md) and [quality report](MD/QUALITY_REPORT_BATCH12.md). Historical batch notes describe their original releases; current setup notes take precedence.

## Verification

Run `npm run lint`, `npm run typecheck`, `npm test`, `npm run build`, `npm run test:smoke` and `npm audit --omit=dev`. CI runs the same source gates with a clean dependency installation.

## Production status

12 of 12 source packages are delivered. This is a release candidate requiring the pending checks in [live acceptance](MD/LIVE_ACCEPTANCE.md). Live Supabase/provider/DNS/payment acceptance, browser checks, load tests, backups, operational scheduling and deployment remain release gates. No live sends, payments or deployment are claimed. SMS and WhatsApp are unavailable. Keep email delivery disabled until configured and accepted in staging. Public legal copy remains draft material requiring the operator's review.

Deployment and recovery procedures are in [deployment runbook](MD/DEPLOYMENT_RUNBOOK.md) and [backup recovery](MD/BACKUP_RECOVERY.md). `npm run check:release` validates configured environment names/roles without contacting services or printing secrets.
