# Admin campaign control center

## Result

The Super Admin homepage now leads with campaign operations instead of Website CMS. Select a company and open Create campaign, Upload contacts, Campaign studio, Delivery queue, Reports & analytics, Contacts, Templates, Senders, Team, Branding, Lists, Segments and Footers directly. All links carry the selected company ID.

The first active company is selected by default. An invalid or unavailable requested company is not silently replaced. With no companies, the existing guarded Create company form is shown directly on the homepage. Inactive companies show an activation message instead of the Create campaign action. Platform administration remains below the operational tools: company/subscription management, plans, providers, audit and CMS.

The existing session-aware website, admin login routing, workspace access, upload navigation and sign out fixes are included in this complete package. No features or existing migrations are removed. No new SQL is required when migrations 001 through 012 are installed.

## Installation

Extract the complete source and update the repository contents. Preserve secrets in environment configuration. Redeploy. Set NEXT_PUBLIC_APP_URL to https://sesco-campaign.vercel.app and ensure any APP_URL agrees. Do not rerun the fresh install SQL on an installed database.

Sign in as the assigned Super Admin and open /admin. Create an active company if necessary. Select it to upload contacts or create a campaign. A valid sender, company postal address, eligible consented audience, independent approval and configured delivery are required before sending. A saved draft does not send emails.

## Verification

Regression tests verify active default selection, explicit company switching, empty and invalid selection, tenant scope on every operation link and implemented route destinations. Local lint, strict types, tests, production build and route smoke checks are recorded with this delivery.

Hosted Supabase configuration, live authenticated browser workflows, responsive visual acceptance, payments and actual provider delivery still require verification on the deployed system. No live email or charge was performed. This package is not a guarantee that missing external configuration will work automatically.

Changed files: app/admin/page.tsx, lib/admin-operations.ts, app/globals.css, tests/admin-operations.test.mjs and this guide.

Final results: ESLint passed, TypeScript passed, 76 tests passed, production build passed, 33 route checks and security header checks passed.
