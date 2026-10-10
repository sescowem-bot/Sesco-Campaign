# Admin campaign testing · 0.14.0

## Install

Deploy this complete source package. No new environment variables are required.

- If migration 013 is already installed, run only `supabase/migrations/014_owner_campaign_tests.sql`.
- If your database is still at 012, run 013, then 014, in order.
- Only for a new empty database, run `supabase/SESCO_Complete_Fresh_Install.sql` once. Never run the fresh install script on your existing database.

Migration 014 is transactional and repeatable. It adds campaign and revision references to test history, a not-sent outcome, and a protected owner test reservation function. Existing customer campaign approvals and delivery rules remain unchanged.

## Test your actual campaign

1. Sign in as Super Admin and open `/admin/workspace`.
2. Review **Campaign readiness**. Resolve missing sender details and postal address. Database read failures show Unavailable rather than Ready.
3. Create a campaign, select your existing connected sender and save it.
4. Open the saved campaign. Click **Send test to my email**. Any unsaved changes are excluded; the button identifies the saved revision.
5. Check your verified account inbox and spam folder. The subject begins with `[TEST]`. The body uses sample recipient data and marks itself as a preview. Unsubscribe is inactive in this preview.
6. Check **Recent campaign tests** for the tested revision, time and result.
7. When you are satisfied, use owner approval and Delivery queue for your consented audience.

You do not need a contact list, independent reviewer, or campaign approval to send this private preview. Tests go only to the verified email address of the signed-in owner; there is no arbitrary recipient field. A test does not approve or queue the campaign.

The test button sends one real email, including while `EMAIL_DELIVERY_ENABLED=false`. That setting controls audience dispatch; sender and campaign tests are explicit separate operations. Tests share the existing provider budgets and workspace test limit: one per minute and ten per rolling 24 hours. No test was sent while developing this release.

## Test results

| Result | Meaning |
| --- | --- |
| Reserved | Attempt created; a final outcome has not been saved. Check the provider before retrying if it remains here. |
| Accepted | Provider acknowledged submission. Inbox delivery is not guaranteed. |
| Unknown | Provider outcome is uncertain. Check the provider dashboard before retrying. |
| Not sent | Preparation or verification failed before the send request. |

Campaign preview history is separate from audience delivery reports. Preview messages do not create audience delivery runs. The existing worker and manual owner dispatch remain available.

## Readiness checklist

The owner dashboard checks workspace status, active sender/domain/provider configuration, business address, total eligible audience, presence of server credentials and audience dispatch configuration. Configuration presence and cached verification do not prove live service availability. Sender verification is refreshed when testing or dispatching. A selected audience can have fewer eligible contacts than the workspace total.

## Verification

87 automated tests passed, including the complete fresh SQL installation, migration upgrade and rerun, account-bound recipient selection, stale revision rejection, customer access denial, shared test quotas, unchanged campaign approval/queue state, marked preview content, no sending after preparation failure, and no automatic retry after uncertain provider outcomes.

Hosted signed-in browser checks and actual Resend receipt remain pending deployment and your controlled test. No GitHub push, deployment, live database modification or email send was performed.

Production build, ESLint, TypeScript, 16 public route checks, 9 protected redirects and 9 API rejection checks also passed. Security response headers and per-request script nonces passed.

## Changed files

`supabase/migrations/014_owner_campaign_tests.sql`, consolidated fresh SQL, `lib/campaigns/test-send.ts`, `lib/campaigns/readiness.ts`, campaign rendering and provider test subjects, campaign actions/page/studio, owner workspace readiness, database/provider/unit tests, package version and documentation.
