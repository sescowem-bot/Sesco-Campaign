# Batch 3: Company Management and Plans
1. Apply migrations `001_foundation.sql`, `002_access_policies.sql`, then `003_company_plans.sql` in that order.
2. Complete owner setup in `MD/BATCH2_SETUP.md` using a verified Supabase user.
3. Set `.env.local` based on `.env.example`. Never publish Supabase service-role credentials.
4. Start `npm install && npm run dev`.
5. Sign in as the verified Super Admin and visit `/admin/companies` and `/admin/plans`.
6. Create subscription plans with your own real prices and JSON quotas. Set Public to show them on `/pricing`.
7. Create companies. If adding a company administrator, their email must already be verified in Supabase Auth.
8. Assign a plan manually from the company management screen.

Security: mutations use SECURITY DEFINER Postgres RPCs that independently verify platform super-admin status and write audit logs. No client-side-only authorization. There is no live payment processing in this batch.
Known limitations: no plan editing UI, no self-service paid checkout, no invitation emails, no quotas enforced in the sending engine, no production migration validation.
