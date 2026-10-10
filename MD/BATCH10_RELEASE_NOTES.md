# Batch 10 release notes

Company workspaces now offer campaign reporting with UTC date filters, run drill-down, audience/delivery charts, aggregate performance tables, pagination and CSV export. Metrics distinguish saved provider acknowledgements, recorded delivery callbacks, engagement and current queue exceptions. Repeated events count a recipient once per outcome. Local unsubscribe confirmation records run attribution without changing the existing suppression behavior.

Reports use a bounded, authorized PostgreSQL aggregate RPC. No raw recipients, tokens or provider keys are exposed. CSV cells prevent spreadsheet formula execution. The release adds migration 010 and no environment variables. All previous campaign, queue, billing, contact, provider and public routes are retained. No sends, payments, database changes on hosted services, GitHub updates or deployment were performed.

This completes source Batch 10. Batch 11 covers CMS and administration completeness; Batch 12 covers production security and acceptance. See DEVELOPMENT_PROGRESS.md and QUALITY_REPORT_BATCH10.md.
