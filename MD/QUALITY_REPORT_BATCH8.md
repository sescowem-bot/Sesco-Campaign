# Batch 8 quality report

## Verification

- Strict TypeScript and ESLint checks passed with no errors or warnings.
- All 41 tests passed.
- Production build passed including the new campaign route.
- Clean npm ci --ignore-scripts passed from the committed lockfile.
- Route smoke checks passed: 15 public/health routes returned 200 and 3 protected routes redirected to login without setup.
- npm audit --omit=dev --audit-level=high reported zero production vulnerabilities.
- Tests cover safe personalization, escaped customer text, unsupported variables, fixed HTTPS destinations, subject line injection, email table/footer rendering, isolated migrations 001–008, tenant-scoped sender/audience selection, consent-aware counts, stale revisions, independent approval, approval invalidation on edit and read-only history.
- SQL runs in isolated PGlite PostgreSQL with mock Supabase auth roles. The pgcrypto extension creation is omitted there because built-in gen_random_uuid() is available. It is retained in the real Supabase migration.


## Security

RLS scopes campaign/history reads to company membership or Super Admin. Authenticated users have no direct campaign/history mutation policies. RPCs independently authorize active-workspace edit/review permissions. Sender foreign keys carry organization identity; lists/segments are checked in the same organization. Workflow revision numbers protect concurrent updates. Submitted content cannot be edited until withdrawn; editing approved content invalidates approval. Approvers cannot review their own last edit or submission. Text is escaped, button URLs are fixed HTTPS destinations, preview iframe is sandboxed, personalization does not reinterpret recipient values as templates, and malformed variables are rejected in both server validation and database saves.

## Outstanding acceptance

Live Supabase auth/session/RLS checks and authenticated browser visual QA remain untested here. No live emails or payments were sent. The current preview uses company branding and an explicit preview unsubscribe destination; production brand/recipient snapshots, live unsubscribe links, final suppression/entitlement checks and campaign delivery require Batch 9. Historical Batch 7 reports remain historical evidence rather than assertions of live provider validation.
