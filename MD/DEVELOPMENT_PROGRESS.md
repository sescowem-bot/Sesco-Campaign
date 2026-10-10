# Current update: admin campaign testing · 0.14.0

Saved campaign previews to the verified owner email, revision-linked test history and owner readiness checks are implemented. See [testing setup](ADMIN_CAMPAIGN_TESTING.md). 87 automated tests passed. Deployment and live acceptance remain pending.

# Current update: owner workspace · 0.13.0

Dedicated owner workspace, owner approval, existing Resend connection and selected-run manual dispatch are implemented. See [owner setup](OWNER_WORKSPACE_UPGRADE.md). Existing customer access restrictions remain. Hosted deployment and live delivery acceptance are pending.

# Development progress

12 of 12 source delivery packages delivered: 100 percent of the source batch sequence. Live production acceptance is pending; this does not mean the app is approved for launch. This measures source delivery, not production readiness.

| Batch | Status | Scope |
| --- | --- | --- |
| 1 through 8 | Delivered | Foundation, accounts, company administration, subscriptions/payments, contacts, provider/sender setup, campaign composition and approvals |
| 9 | Delivered | Scheduled delivery queue, worker, provider budgets, callbacks and suppression |
| 10 | Delivered | Aggregate reporting, delivery/engagement analytics, run drill-down and CSV export |
| 11 | Delivered | Structured website CMS, publication, platform identity, company/team controls and audit activity |
| 12 | Source delivered; live acceptance pending | Security hardening, expanded tests, release validation, deployment and recovery procedures |

Batch 12 verification covers lint, strict TypeScript, isolated PostgreSQL migrations and tenant tests, transport/event tests, production build and HTTP smoke checks. Hosted Supabase, live DNS/provider delivery, payment acceptance, operational scheduling, backups and deployment require production acceptance work. No live sends or deployment are claimed.

The original ROADMAP.md phase grouping predates the current 12-delivery breakdown. This progress report tracks the active delivery sequence.
