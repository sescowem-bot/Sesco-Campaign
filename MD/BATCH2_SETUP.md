# Batch 2: Authentication and secure owner branding

## Setup
1. Create a NEW Supabase project and configure its URL and anon/publishable key in `.env.local` (copy `.env.example`). Never expose the service role key in a browser.
2. In Supabase SQL Editor run `supabase/migrations/001_foundation.sql` then `002_access_policies.sql` in order.
3. Under Authentication > URL Configuration, set Site URL to your deployed URL and add `http://localhost:3000/auth/callback` plus your production `/auth/callback` URL to redirects.
4. Run `npm install`, `npm run typecheck`, `npm run build`, `npm run dev`.
5. Register at `/register`, verify the email, then use the Supabase SQL editor to bootstrap the **verified** owner account using the commented SQL at the bottom of migration 002, replacing `YOUR_VERIFIED_OWNER_EMAIL`.
6. Sign in at `/login`; `/admin` requires `platform_staff.role = super_admin`. `/dashboard` is authenticated and shows actual organization membership or awaiting access.
7. Super Admin may edit global display name, tagline and primary color. These are saved in Supabase. Wiring them into every public page is a subsequent CMS phase.

## Security and current limitations
- The public registration creates an auth identity only, NOT a company. Public company registration and payment processing are NOT implemented yet.
- Only owner branding has a mutation policy. Organization creation and other privileged mutations remain blocked.
- Do not assign platform roles using browser code or user metadata. Bootstrap the first verified owner using privileged SQL.
- Configure email verification, SMTP delivery and production redirect allowlist before launch.
- The initial workspace is not a full CRM; no real campaign sending yet.
- SQL migration 002 is intended for a fresh database with no existing policies of the same names.
