# SESCO Campaign Cloud Batch 8

## Added

Campaign drafts, company/platform template reuse, structured message blocks, subject/preheader editing, fixed HTTPS buttons, allowlisted text personalization, desktop/mobile previews, sender selection, all/list/segment audiences, requested UTC send times, consent-aware audience counts, independent review, rejection notes, withdrawal, archive, optimistic revision checks and immutable history.

New route: `/dashboard/campaigns`. New migration: `008_campaign_workflows.sql`. No new environment variables. All previous source modules retained. Batch 9 adds actual scheduling and campaign delivery; the UI clearly identifies that boundary.

## Verification

TypeScript, lint, production build, campaign/provider unit tests and isolated SQL tenant/permission/workflow tests are run for this release. See QUALITY_REPORT_BATCH8.md for evidence and limits.

## Roadmap

Eight of twelve source development batches delivered. Four batches remain: queue/delivery, reporting, advanced administration/CMS and production hardening/acceptance. This count is a source milestone, not production certification.
