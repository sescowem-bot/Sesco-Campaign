# Campaign access, uploads and sign out

## Changes

The dashboard now presents company workspace cards with prominent Create campaign and Upload contacts actions for permitted roles. Super Admins can see all company workspaces without needing separate membership just to discover them. Existing database authorization remains enforced. Inactive companies cannot create campaigns. Admin navigation now identifies Campaigns & contacts clearly; company navigation labels Upload contacts explicitly. The campaign studio Create campaign action has button styling.

Sign out previously compared the browser Origin only with the server request URL. Reverse proxy routing can make those origins differ. The guard now additionally accepts explicit HTTPS application and Vercel deployment origins from environment configuration. It does not trust forwarded host headers, wildcard domains, missing Origin or cross-site requests. Sign out redirects to the validated browser origin and reports auth failures instead of claiming success.

## Installation

Upload this complete source and redeploy. No new SQL is needed if migrations 001 through 012 are already installed. Preserve environment settings and do not rerun the fresh install script on an installed database.

Set NEXT_PUBLIC_APP_URL to https://sesco-campaign.vercel.app in Vercel. If APP_URL is also set, it must use the same origin. Vercel's deployment URL environment values provide explicit preview/production origin support. An additional custom domain requires the matching configured application URL. Keep delivery disabled until controlled acceptance.

## Access steps

1. Sign in with your verified Super Admin account.
2. Open Platform administration > Companies and create an active company if none exists.
3. Open Campaigns & contacts to see workspace cards.
4. Choose Upload contacts to import CSV/XLSX with mapping and preview.
5. Choose Create campaign to design a draft and select an audience and sender.
6. Verify sender domains and configure company branding and postal address before delivery. Campaigns need independent approval before queueing.

Ordinary accounts require company membership and an appropriate role. Designers can create campaigns but cannot import customer contacts. Company admins and managers can upload contacts. No automatic privilege or company assignment is introduced.

## Verification and limits

Automated security regression covers configured proxy origins, deployment previews, hostile origins, forged forwarded headers, malformed configuration and explicit cross-site requests. Local lint, types, tests, build and route smoke checks are recorded with this delivery. Live sign out, authenticated dashboard workflows and browser layout acceptance still need checking after redeployment. The proxy explanation is grounded in the old code comparison, not a captured live hosting trace.
