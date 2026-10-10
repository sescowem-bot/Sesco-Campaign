# Batch 12 setup and release candidate

Version 0.12.0 completes the 12 source delivery packages. This is a release candidate requiring hosted acceptance, not an accepted live production deployment. No GitHub change, hosted database migration, payment, send, backup or deployment was performed.

## Install and migrate

Use Node 24. Run npm ci, npm run lint, npm run typecheck, npm test, npm run build and npm run test:smoke. Run npm audit --omit=dev. All Markdown is in MD except the root GitHub README.md.

Back up and review existing pending payments before applying migration 012 to a database already at migrations 001 through 011. New installations apply 001 through 012 sequentially. Never drop the existing database to install this package. Migration 012 snapshots checkout billing intervals, limits checkout starts to five per company per five minutes and strengthens service-only payment finalization. Older payment rows are backfilled from the plan's current interval; this does not reconstruct historical plan changes. Reconcile older pending checkouts with the operator before accepting them. New checkouts preserve the interval selected at checkout even if the plan changes later. Amount/currency/reference verification and transaction identity remain mandatory.

NEXT_PUBLIC_APP_URL is the canonical HTTPS origin for checkout callbacks and delivery. APP_URL is supported only for older installations; if both are set their origins must agree. The example uses localhost for development, but real checkout and delivery require HTTPS. PAYSTACK_WEBHOOK_SECRET is not used; Paystack HMAC verification uses PAYSTACK_SECRET_KEY. Optional DATABASE_URL and BACKUP_DIRECTORY are server/operator backup settings, never public variables.

## Request and browser protections

Browser mutation endpoints require an Origin matching the request origin and reject cross-site requests. This applies to sign-out, checkout, payment verification and contact imports. Browser fetch/form requests normally provide it. Scripted clients must set the matching Origin and still authenticate; Origin is not a substitute for authentication. Provider webhooks and one-click unsubscribe retain their independently authenticated/token-based external request flows.

Request readers enforce byte limits while streaming, including chunked and multi-byte requests, with a ten-second read deadline. Payment webhook limit is 150 KB, email webhook limit 64 KB, contact import limit 95 KB and billing browser payload limit 4 KB. Signed payment callbacks authenticate the exact bytes before JSON parsing. Paystack API requests time out after 15 seconds. DNS TXT checks use one five-second resolver attempt. Failures return generic errors rather than credentials or provider response bodies.

Production responses add MIME sniffing, framing, referrer, browser capability and HTTPS transport headers. Dynamic HTML uses a fresh script nonce per request through middleware; initial Next.js scripts receive that nonce. Production script policy excludes unsafe-eval. Inline styles remain allowed because theme/editor/chart styles use inline declarations. Images support HTTPS/data/blob sources for the current UI. Supabase HTTPS/WebSocket connections are scoped to its configured origin. Development permits eval and WebSocket schemes for tooling. Do not cache nonce-bearing HTML at an external CDN, add arbitrary scripts, or disable security headers to work around integration errors. Signed-in browser acceptance must verify hydration, editing, billing redirects and CSP violations before launch.

Login, registration, company administration/workspace routes and unsubscribe views are not intended for indexing. robots.txt discourages crawling sensitive paths; robots is not access control. Existing server/database authorization remains required.

## Configuration validation

Run npm run check:release in the trusted deployment environment before enabling sending. It is read-only, makes no network calls and prints check names, never values. It checks Node, HTTPS origins, public versus service key roles, payment/provider configuration and independent secrets. It expects EMAIL_DELIVERY_ENABLED=false while awaiting acceptance. Missing configuration returns nonzero. A passing result is configuration validation only, not proof of account permissions, provider delivery, database access or production acceptance.

Keep all configured secrets server-only. Rotate keys if exposed and use independently generated worker/Brevo secrets of at least 32 characters. Use the provider-issued Resend signing secret. Continue Batch 9 webhook and worker setup. No scheduler is provisioned automatically.

## Rollback

Keep the Batch 11 source archive and a database backup. Revert application code if needed before forward-fixing migration 012. The added interval snapshot is compatible with older readers, but restoring the old payment functions loses these safeguards. Preserve transaction/audit history. Reconcile unknown send outcomes and payment review states before retries.

See DEPLOYMENT_RUNBOOK.md, BACKUP_RECOVERY.md and LIVE_ACCEPTANCE.md for operational work still required.

Official references: https://nextjs.org/docs/app/guides/content-security-policy and https://paystack.com/docs/payments/webhooks/ .
