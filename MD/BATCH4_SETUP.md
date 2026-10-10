# Batch 4: Paystack payments and automatic subscription activation

1. Apply SQL migrations 001, 002, 003, then 004_payments.sql.
2. Add PAYSTACK_SECRET_KEY and SUPABASE_SERVICE_ROLE_KEY as server-only secrets. Never prefix them with NEXT_PUBLIC_.
3. Configure APP_URL to your exact public origin (HTTPS in production).
4. Configure Paystack webhook URL: https://YOUR_DOMAIN/api/billing/webhook.
5. Create and publish a paid plan using Super Admin. Use actual prices and valid limits.
6. Sign in as a company administrator or platform super admin and open /billing.
7. Test Paystack sandbox checkout, verify the callback, repeat the webhook and ensure no duplicate subscriptions.
8. Verify payments in the Supabase payment_transactions table. The webhook always checks the Paystack verify API before activation.

Security boundaries:
- Checkout amounts are read from the DB, never trusted from the browser.
- Only company admins or the platform super admin may start payments.
- Payment reference is generated server-side.
- Paystack webhook signatures use HMAC-SHA512 and constant-time comparison.
- A successful Paystack transaction is verified by the server against the stored reference, amount and currency.
- A service-role-only SQL function finalizes the payment and subscription atomically, with row locks and idempotency.
- No secret is embedded in client JavaScript.

Known limitations:
- No invoice PDF, refund automation, proration, scheduled renewal, payment dispute handling, plan editing UI or quota enforcement.
- Failed checkout may leave a transaction in initiated status; operational reconciliation and abandoned-payment cleanup should be added.
- Custom billing intervals have no automatic expiry; configure plan rules before production use.
- Test with Paystack sandbox before using live keys. Review migrations with a Supabase SQL environment before production.
