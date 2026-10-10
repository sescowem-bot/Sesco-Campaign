# Batch 9 release notes

Durable scheduled delivery queues now freeze approved campaign revisions and eligible audiences, enforce company and shared provider budgets, and expose pause/resume/cancel controls. The authenticated worker sends through fixed Resend or Brevo endpoints with one-click unsubscribe headers. Unknown send outcomes require review instead of automatic retries.

Authenticated provider callbacks store idempotent events, reconcile events that arrive before acknowledgement and enforce unsubscribe, bounce and complaint suppression. Provider controls expose daily budgets and request spacing. No real emails, account configuration, production migration or deployment were performed.

Install only migration 009 on an existing database with 001 through 008 installed. See BATCH9_SETUP.md for server variables, webhook setup and external worker scheduling. Historical batch documentation is retained unchanged.
