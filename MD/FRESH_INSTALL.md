# Fresh installation

This package includes the complete source through Batch 12, version 0.12.0. GitHub upload, hosted database setup and live acceptance are pending.

## Database

1. Create a new Supabase project for this application.
2. Open SQL Editor. Copy the entire contents of `supabase/SESCO_Complete_Fresh_Install.sql` and run it once as the project administrator.
3. This file includes all twelve migrations in order, within one transaction. Do not additionally run individual migrations. It is a fresh installation script, not a repeatable upgrade script. If execution fails, retain the error and resolve it before retrying.
4. After success, later releases use only their new incremental migrations. Keep a record that migrations 001 through 012 are installed.

## Local application

1. Install Node.js 24 and extract this source package.
2. Open a terminal in the folder containing `package.json`.
3. Copy `.env.example` to `.env.local`. Enter your Supabase URL, public key and server-only service role key. Follow the example for other configuration. Keep `EMAIL_DELIVERY_ENABLED=false`.
4. Run `npm ci`, then `npm run dev`.
5. In Supabase Auth, configure the local Site URL and allow `http://localhost:3000/auth/callback` as a redirect. Configure SMTP and email confirmation.
6. Register through `/register` and verify your email.
7. In Supabase SQL Editor, run this separate owner bootstrap after replacing the email with your verified account:

```sql
insert into public.platform_staff(user_id, role)
select id, 'super_admin'
from auth.users
where lower(email) = lower('YOUR_VERIFIED_OWNER_EMAIL')
  and email_confirmed_at is not null
on conflict (user_id) do update set role = 'super_admin';
```

8. Sign in and open `/admin`. No default owner account or password is created by the installation SQL.

## GitHub and deployment

The ZIP is the entire editable project. Upload its extracted project contents to your intended repository when ready. Keep `README.md` at the root; other authored Markdown is in `MD`. Never commit `.env.local`, secrets, database backups, `node_modules` or `.next`.

GitHub upload is not required for running the application locally. For hosted setup, follow `MD/DEPLOYMENT_RUNBOOK.md`. Use test payment credentials and keep campaign sending disabled until staging acceptance.

## Verification

The combined SQL installation and tenant, delivery, CMS and payment security checks passed 23 isolated PostgreSQL tests. The test environment substitutes Supabase Auth and omits the pgcrypto extension because its UUID function is built in. Hosted Supabase execution and live browser acceptance remain pending.
