# Public access and button audit

## Fixes

Desktop, tablet and phone headers now keep Sign in and Create account visible. The mobile menu and footer also include both destinations. Navigation collapses sooner to prevent crowding. Narrow screens wrap the account actions into their own row. Keyboard focus indicators and minimum header target heights are provided.

Removed the homepage development and early access notice. The campaign illustration remains explicitly labelled as illustrative. Its email design action now links to Features rather than resembling an inert button.

Pricing retains only active, published database plans. When none are returned, it presents Contact us for pricing and a Contact us link. Removed public billing setup instructions. Exact historical CMS default wording on pricing, FAQ and contact is upgraded at render time; custom published text remains unchanged. No database migration is required for these fixes.

Contact uses the configured site support email as a working mailto action. With no email configured it truthfully explains that online contact details are unavailable. Set Website CMS > site support email and publish it before using Contact as a sales channel. No fabricated email or nonfunctional submission form was added.

## Verification

ESLint passed, TypeScript passed, production build passed, 73 automated tests passed. Production smoke checks passed on 16 public/health routes, eight protected route redirects and nine API rejections, including security headers and script nonces. Inspected 37 literal local link references across app/components; page destinations and the contact CSV sample exist.

## Scope and remaining work

These are source changes, not a deployment. Upload the complete package to the intended repository and redeploy through your normal process. No GitHub write or deployment was performed. Do not rerun the fresh installation SQL if already installed.

Actual authenticated admin/company actions require hosted Supabase and appropriate accounts for end-to-end acceptance. Static route checks cannot prove every dynamic action works. New responsive styling has not been visually verified in desktop/mobile browsers. The public legal defaults retain their draft status rather than implying operator-approved legal terms; review and publish final policies in CMS. SMS and WhatsApp are still unavailable and are accurately described as future channels.

Files changed: components/public.tsx, app/page.tsx, app/pricing/page.tsx, app/contact/page.tsx, app/globals.css, lib/cms/content.ts, lib/cms/defaults.json, tests/cms.test.mjs and this report.
