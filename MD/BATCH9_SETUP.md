# Batch 9 setup

Apply migration 009 after migrations 001 through 008. Back up the database first. This release does not configure accounts or send messages during installation.

Configure the server-only variables in .env.example. Keep EMAIL_DELIVERY_ENABLED=false until staging checks pass. NEXT_PUBLIC_APP_URL must be the public HTTPS origin with no path. Use independent random secrets of at least 32 characters for worker and Brevo webhook authentication. Set the Resend signing secret from its webhook dashboard.

Configure Resend events to POST /api/email/webhooks/resend. Verification uses the original request bytes and Svix signature headers. Configure Brevo transactional events to POST /api/email/webhooks/brevo with Bearer authentication using BREVO_WEBHOOK_SECRET; use individual JSON events, not batched payloads. Subscribe to delivery, bounce, complaint, failed and engagement events supported by your provider. Provider acceptance is separate from confirmed delivery.

In Super Admin email providers, set access, the shared daily request budget and minimum seconds between requests. The default budget of 100 is a local safety setting, not a statement about a provider account allowance. Configuration test emails share this daily budget and spacing. A company needs an active subscription with a positive integer monthly_emails limit or override, a postal address and an active sender on a verified domain.

Approve a campaign through the existing independent review flow. Open Delivery queue, select the approved revision and confirm queueing. Audience and content are frozen at queue time; consent, unsubscribe, suppression, account status and provider settings are rechecked at dispatch. Requested UTC send time controls eligibility; actual time depends on worker frequency and quotas. A campaign can be queued once; create a new campaign for a resend. Cancel an active run before editing its content.

Run npm run worker:once in a trusted Node 24 environment with the origin and worker secret set. Each invocation processes at most one recipient. An external scheduler must repeat this authenticated POST often enough for the desired throughput. No scheduler is provisioned by this source release. Worker requests may overlap; leases and database locks coordinate claims. Monitor non-success responses and paused runs. Do not expose worker secrets in URLs or browser code.

Monthly budgets use UTC calendar months and count reserved dispatch attempts. Explicit 429 responses retry after at least one minute, at most three attempts; every attempt conservatively consumes budget. Provider timeouts, ambiguous acknowledgements and server errors become unknown and are not automatically resent. Review the provider dashboard before any manual follow-up. Expired pre-dispatch leases return to pending; expired dispatch leases become unknown. Pause or cancellation cannot recall an in-flight provider request. Company quota exhaustion pauses a run; review allowance and resume manually.

Unsubscribe links use opaque tokens. GET opens a confirmation page; POST records suppression. One-click unsubscribe headers use the same POST endpoint. Bounce and complaint events suppress future sends for that company. Raw recipient queues and tokens are service-only; company views show aggregate counts.

Validate in staging using controlled consenting recipients: domain/DNS ownership, provider acceptance and real delivery, webhook replay, one-click unsubscribe, pause/cancel races, scheduler throughput and recovery. Local tests do not substitute for hosted Supabase RLS or real-provider acceptance. Campaign sample test sending and hosted deployment remain outstanding.

Official references: https://resend.com/docs/webhooks/verify-webhooks-requests , https://resend.com/docs/api-reference/emails/send-email , https://developers.brevo.com/docs/secured-webhooks , https://developers.brevo.com/docs/transactional-webhooks .
