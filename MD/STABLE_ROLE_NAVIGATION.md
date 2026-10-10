# Stable admin and customer navigation

## Navigation model

Super Admin identity is verified from the database on workspace pages. Platform navigation stays present when opening company campaign, upload or reporting pages. Ordinary users see company navigation without platform management links. Backend permissions still govern every operation, even where a navigation destination is visible.

Company navigation now includes a direct Create campaign link and Pricing. Opening public Pricing or other public pages while signed in retains an additional workspace toolbar with campaign, upload, reporting, template, sender and billing destinations. Super Admins also retain control center, business management and provider links there.

The selected company is remembered in an HTTP-only preference cookie for thirty days when opening a company-scoped page. This cookie grants no access: candidate companies are read with the signed-in Supabase client under existing RLS. Invalid or inaccessible preferences fall back to an accessible company. With no company available, the workspace and admin links remain visible for setup.

Desktop sidebar stays visible and scrolls independently of the content. On small screens the navigation has a bounded scroll region and two-column link layout, so a long menu does not push all business content below it. Browser visual acceptance remains pending.

## Existing Resend environment

This package preserves all configured secrets and provider workflows. It does not recreate a domain, reset API keys or modify webhooks automatically. Existing environment settings must remain on Vercel when deploying.

Platform provider access must be enabled, and the chosen company must have a saved verified sending-domain record and sender identity. A Resend account domain already verified outside this application is not automatically a company sender record. Use Senders & domains and provider registration recovery to link the existing domain rather than replacing its DNS or deleting it. The domain verification and authorization checks remain enforced. No actual message is sent by this delivery.

## Admin testing path

Open /admin, select or create your own active company workspace, open Upload contacts, create a draft campaign, preview its design, and inspect Reports and Delivery queue. Manage business through Companies and Team & roles. Administration links remain available throughout. Reports show actual recorded events rather than sample delivery metrics.

Independent campaign approval, company postal address, consent and subscription allowance remain delivery prerequisites. Test only with operator-authorized recipients after configuration checks; draft creation does not require dispatching a message. Existing keys alone do not prove hosted sender, plan or worker configuration is complete.

## Install and evidence

Update with this complete package and redeploy. No new SQL migration is required. Preserve the database and environment. Includes all prior admin operations, public copy, sign out and session fixes.

The final local gate results accompany this package. Authenticated hosted workflows, actual Resend delivery and responsive browser visual checks remain pending. No claim that all live dependencies have been verified is made.

Final local results: ESLint passed, TypeScript passed, 76 automated tests passed, production build passed, 33 route checks passed including security headers and script nonces.
