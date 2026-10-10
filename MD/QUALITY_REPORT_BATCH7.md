# Batch 7 verification report

## Passed locally

- Dependency installation, clean `npm ci --ignore-scripts` and committed package-lock.json.
- npm run lint: no errors or warnings after repairs.
- npm run typecheck: strict TypeScript passed.
- npm test: 31 passed, including eight PostgreSQL integration cases plus their parent migration test.
- npm audit --omit=dev --audit-level=high: zero production dependency vulnerabilities reported at check time.
- npm run build: production compilation, lint/type validation and route generation passed.
- npm run test:smoke: 15 public/health routes returned 200; both new protected routes redirected unauthenticated requests to login. The local test server binds to 127.0.0.1.
- Database tests executed migrations 001–007 in isolated PGlite PostgreSQL, using mock Supabase auth users/roles; pgcrypto extension creation omitted because core gen_random_uuid() is available. Tests verify anonymous pricing access, owner provider control, tenant isolation, service-only verification, exact sender domains, viewer denial, test limits, revoked-domain protection and suspension checks.
- Provider tests use injected mock fetch responses, not live provider accounts. They verify documented endpoints, response normalization, secret-safe errors, no retry and provider acknowledgement handling.

## Remaining live acceptance gates

- Execute migrations in your actual Supabase environment with backup and confirm its default grants, Auth/JWT/session handling and RLS.
- Verify real provider API permissions, account approvals and DNS records.
- Exercise company onboarding, payment test-mode checkout/webhooks and tenant permissions in the configured environment. Existing payment code was retained; this batch did not independently certify it.
- Manually review authenticated provider/sender screens on desktop and mobile with actual workspace data. Responsive CSS and accessible labels/feedback are implemented; authenticated browser visual QA is not claimed.
- Verify test message delivery and Reply-To in inboxes. Accepted status only acknowledges provider submission.
- Complete marketing consent, unsubscribe and durable queue integration in subsequent batches before real campaigns.

## Provider API references reviewed

- https://resend.com/docs/api-reference/domains/create-domain
- https://resend.com/docs/api-reference/domains/get-domain
- https://resend.com/docs/api-reference/emails/send-email
- https://developers.brevo.com/reference/create-domain
- https://developers.brevo.com/reference/get-domain-configuration
- https://developers.brevo.com/reference/authenticate-domain
- https://developers.brevo.com/reference/create-sender

## Security design

Public inputs cannot set verified state. Domain verification needs provider authentication and an organization-specific TXT token. Credentials are not rendered in the client. New write functions independently authorize the actor, and service-only status synchronization rejects revoked domains. Domain/sender actions use Next.js server actions and repeat server authorization. The database grants no direct authenticated mutation policies for new sender/provider/test tables. Per-company test reservations are serialized and count uncertain outcomes. Configuration tests contain fixed escaped content and only target the verified account mailbox. External operations cannot be rolled back atomically; explicit owner reconciliation and unknown outcomes address this limitation without claiming exactly-once remote delivery.
