# Session-aware website and admin navigation

## Fix

Public header and footer previously always rendered Sign in and Create account, regardless of an existing session. They now use a request-scoped, server-verified account lookup. Authenticated users see Dashboard and Sign out. The Admin dashboard button is shown only when the database is_platform_super_admin function returns true. This does not grant or infer admin privileges from an email address or client metadata.

Login routes confirmed Super Admins to /admin and other accounts to /dashboard. Public page requests with Supabase auth cookies now pass through session refresh middleware. Anonymous public pages avoid that middleware auth lookup. Existing server and database route permissions are retained. Missing environment configuration or failed identity verification uses guest navigation; an admin role lookup failure does not show the admin link.

## Deployment

Upload this complete source and redeploy. No new database migration is required. Keep NEXT_PUBLIC_APP_URL set to https://sesco-campaign.vercel.app. Test on the same domain where you signed in. A session on a preview hostname is not automatically a session on a different production hostname.

## Check your existing admin assignment

Run this read-only query in the same Supabase project configured on Vercel, replacing the email:

```sql
select u.id, u.email, u.email_confirmed_at, s.role
from auth.users u
left join public.platform_staff s on s.user_id = u.id
where lower(u.email) = lower('YOUR_EMAIL_HERE');
```

Expected: your verified user row and role super_admin. No row means the account is absent in this project; a null role means no platform role was assigned; platform_admin does not have Super Admin access. Do not rerun the full installation SQL to correct an account role. Use the reviewed first-owner bootstrap in MD/FRESH_INSTALL.md only for your verified owner account.

## Acceptance

After redeployment, sign in and return to the homepage. Confirm Dashboard and Sign out are shown and guest account buttons are replaced. Confirm Admin dashboard appears for the assigned owner and is absent for ordinary accounts. Refresh the homepage, open the mobile menu, sign out, and confirm the guest buttons return. Verify protected routes no longer admit the signed-out session.

Local lint, TypeScript, automated tests, production build and route smoke checks accompany this package. Authenticated live acceptance is still pending because no signed-in test account was supplied.
