-- SESCO Campaign Cloud 0.12.0 | Complete fresh installation
-- New Supabase project only. Run once as project administrator in SQL Editor.
-- Includes migrations 001 through 012; do not also run them individually.
-- Migration transaction wrappers consolidated into one atomic transaction.

begin;

-- BEGIN 001_foundation.sql
-- SESCO Campaign Cloud | 001 Foundation
-- Execute in a NEW Supabase project. Run only after reviewing this migration.
create extension if not exists pgcrypto;
create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 160),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  status text not null default 'pending' check (status in ('pending','active','suspended')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('company_admin','manager','designer','approver','analyst','viewer')),
  created_at timestamptz not null default now(),
  primary key (organization_id,user_id)
);
create table if not exists public.platform_staff (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('super_admin','platform_admin')),
  created_at timestamptz not null default now()
);
create table if not exists public.platform_branding (
  id boolean primary key default true check (id),
  display_name text not null default 'SESCO Campaign Cloud',
  tagline text not null default 'Professional Business Communication',
  logo_path text, primary_color text not null default '#102b4e',
  updated_at timestamptz not null default now()
);
insert into public.platform_branding(id) values(true) on conflict (id) do nothing;
create table if not exists public.organization_branding (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  display_name text not null, logo_path text, primary_color text not null default '#102b4e',
  website_url text, contact_email text, postal_address text,
  updated_at timestamptz not null default now()
);
create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check(code ~ '^[a-z_]+$'),
  name text not null, price_ngn_kobo bigint not null default 0 check(price_ngn_kobo>=0),
  billing_interval text not null default 'month' check(billing_interval in ('month','year','custom')),
  limits jsonb not null default '{}'::jsonb,
  is_public boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.organization_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null default 'pending' check(status in ('pending','active','past_due','cancelled','expired')),
  starts_at timestamptz, expires_at timestamptz,
  quota_overrides jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create unique index if not exists one_active_subscription_per_org on public.organization_subscriptions(organization_id) where status='active';
create table if not exists public.email_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  name text not null, subject text not null default '',
  design jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check(status in ('draft','approved','archived')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create table if not exists public.email_footers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null, design jsonb not null default '{}'::jsonb,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index if not exists one_default_footer_per_org on public.email_footers(organization_id) where is_default;
create table if not exists public.sending_domains (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  domain text not null unique,
  provider text not null,
  provider_domain_id text,
  verification_status text not null default 'pending' check(verification_status in ('pending','verified','failed','revoked')),
  created_at timestamptz not null default now()
);
create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid references public.organizations(id),
  actor_id uuid references auth.users(id),
  action text not null, entity_type text not null, entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
-- Deny direct API access until reviewed, role-scoped policies are implemented.
-- Server-only service credentials bypass RLS: keep them secret and enforce server authorization.
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.platform_staff enable row level security;
alter table public.platform_branding enable row level security;
alter table public.organization_branding enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.organization_subscriptions enable row level security;
alter table public.email_templates enable row level security;
alter table public.email_footers enable row level security;
alter table public.sending_domains enable row level security;
alter table public.audit_logs enable row level security;
-- No user-facing policies intentionally: Phase 09–12 introduces tested access policies.
-- END 001_foundation.sql

-- BEGIN 002_access_policies.sql
-- Apply AFTER 001_foundation.sql in a new Supabase project.
-- SECURITY: Only the platform super admin can modify global branding.
create or replace function public.is_platform_super_admin() returns boolean language sql stable security definer set search_path = '' as $$select exists(select 1 from public.platform_staff where user_id=(select auth.uid()) and role='super_admin')$$;
revoke all on function public.is_platform_super_admin() from public;
grant execute on function public.is_platform_super_admin() to authenticated;
create or replace function public.is_organization_member(org uuid) returns boolean language sql stable security definer set search_path = '' as $$select exists(select 1 from public.organization_members where user_id=(select auth.uid()) and organization_id=org)$$;
revoke all on function public.is_organization_member(uuid) from public;
grant execute on function public.is_organization_member(uuid) to authenticated;
create policy "platform staff can view own role" on public.platform_staff for select to authenticated using (user_id=(select auth.uid()));
create policy "members can view own memberships" on public.organization_members for select to authenticated using (user_id=(select auth.uid()) or public.is_platform_super_admin());
create policy "members can view own organizations" on public.organizations for select to authenticated using (public.is_organization_member(id) or public.is_platform_super_admin());
create policy "super admin can view branding" on public.platform_branding for select to authenticated using (public.is_platform_super_admin());
create policy "super admin can update branding" on public.platform_branding for update to authenticated using (public.is_platform_super_admin()) with check (public.is_platform_super_admin());
create policy "members can view organization branding" on public.organization_branding for select to authenticated using (public.is_organization_member(organization_id) or public.is_platform_super_admin());
create policy "members can view subscriptions" on public.organization_subscriptions for select to authenticated using (public.is_organization_member(organization_id) or public.is_platform_super_admin());
create policy "members can view templates" on public.email_templates for select to authenticated using (organization_id is not null and public.is_organization_member(organization_id) or public.is_platform_super_admin());
create policy "members can view footers" on public.email_footers for select to authenticated using (public.is_organization_member(organization_id) or public.is_platform_super_admin());
create policy "members can view sender domains" on public.sending_domains for select to authenticated using (public.is_organization_member(organization_id) or public.is_platform_super_admin());
create policy "public plans visible" on public.subscription_plans for select to anon,authenticated using (is_public and is_active or public.is_platform_super_admin());
-- Do not expose mutation policies for organizations, subscriptions, domains or campaigns yet.
-- Bootstrap the FIRST super admin using Supabase SQL editor ONLY after account verification:
-- insert into public.platform_staff(user_id,role) select id,'super_admin' from auth.users where email='YOUR_VERIFIED_OWNER_EMAIL' on conflict(user_id) do update set role='super_admin';
-- END 002_access_policies.sql

-- BEGIN 003_company_plans.sql

-- Batch 3: server-enforced company and subscription administration
-- Apply after 001 and 002. No demo customers or invented subscription prices.
alter table public.subscription_plans add column if not exists description text not null default '';
alter table public.subscription_plans add column if not exists updated_at timestamptz not null default now();
create unique index if not exists one_pending_subscription_per_org on public.organization_subscriptions(organization_id) where status='pending';

create or replace function public.admin_create_organization(p_name text,p_slug text,p_admin_email text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_user uuid; v_email text;
begin
 if not public.is_platform_super_admin() then raise exception 'Not authorized'; end if;
 if length(trim(coalesce(p_name,''))) not between 2 and 160 then raise exception 'Invalid organization name'; end if;
 if p_slug is null or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then raise exception 'Invalid organization slug'; end if;
 insert into public.organizations(name,slug,status) values(trim(p_name),p_slug,'active') returning id into v_org;
 insert into public.organization_branding(organization_id,display_name) values(v_org,trim(p_name));
 v_email:=nullif(lower(trim(coalesce(p_admin_email,''))),'');
 if v_email is not null then
   select id into v_user from auth.users where lower(email)=v_email and email_confirmed_at is not null;
   if v_user is null then raise exception 'Company admin must already have a verified account'; end if;
   insert into public.organization_members(organization_id,user_id,role) values(v_org,v_user,'company_admin');
 end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details)
 values(v_org,auth.uid(),'organization.created','organization',v_org::text,jsonb_build_object('name',trim(p_name)));
 return v_org;
end;$$;
revoke all on function public.admin_create_organization(text,text,text) from public,anon;
grant execute on function public.admin_create_organization(text,text,text) to authenticated;

create or replace function public.admin_save_plan(p_id uuid,p_code text,p_name text,p_description text,p_price_ngn_kobo bigint,p_billing_interval text,p_limits jsonb,p_is_public boolean,p_is_active boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
 if not public.is_platform_super_admin() then raise exception 'Not authorized'; end if;
 if p_code is null or p_code !~ '^[a-z_]+$' or length(p_code)>40 then raise exception 'Invalid plan code'; end if;
 if length(trim(coalesce(p_name,''))) not between 2 and 100 then raise exception 'Invalid plan name'; end if;
 if p_price_ngn_kobo is null or p_price_ngn_kobo<0 then raise exception 'Invalid price'; end if;
 if p_billing_interval not in ('month','year','custom') then raise exception 'Invalid interval'; end if;
 if p_limits is null or jsonb_typeof(p_limits)<>'object' then raise exception 'Limits must be an object'; end if;
 if p_id is null then
   insert into public.subscription_plans(code,name,description,price_ngn_kobo,billing_interval,limits,is_public,is_active)
   values(p_code,trim(p_name),coalesce(p_description,''),p_price_ngn_kobo,p_billing_interval,p_limits,p_is_public,p_is_active) returning id into v_id;
 else
   update public.subscription_plans set code=p_code,name=trim(p_name),description=coalesce(p_description,''),price_ngn_kobo=p_price_ngn_kobo,billing_interval=p_billing_interval,limits=p_limits,is_public=p_is_public,is_active=p_is_active,updated_at=now()
   where id=p_id returning id into v_id;
   if v_id is null then raise exception 'Plan not found'; end if;
 end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
 values(auth.uid(),'plan.saved','subscription_plan',v_id::text,jsonb_build_object('code',p_code,'price_ngn_kobo',p_price_ngn_kobo));
 return v_id;
end;$$;
revoke all on function public.admin_save_plan(uuid,text,text,text,bigint,text,jsonb,boolean,boolean) from public,anon;
grant execute on function public.admin_save_plan(uuid,text,text,text,bigint,text,jsonb,boolean,boolean) to authenticated;

create or replace function public.admin_assign_subscription(p_organization_id uuid,p_plan_id uuid,p_expires_at timestamptz default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
 if not public.is_platform_super_admin() then raise exception 'Not authorized'; end if;
 if not exists(select 1 from public.organizations where id=p_organization_id and status='active') then raise exception 'Organization not active'; end if;
 if not exists(select 1 from public.subscription_plans where id=p_plan_id and is_active) then raise exception 'Plan not active'; end if;
 if p_expires_at is not null and p_expires_at<=now() then raise exception 'Expiry must be in future'; end if;
 -- Serialized on the organization row to avoid two simultaneous active plans.
 perform 1 from public.organizations where id=p_organization_id for update;
 update public.organization_subscriptions set status='cancelled'
 where organization_id=p_organization_id and status in ('active','pending');
 insert into public.organization_subscriptions(organization_id,plan_id,status,starts_at,expires_at)
 values(p_organization_id,p_plan_id,'active',now(),p_expires_at) returning id into v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details)
 values(p_organization_id,auth.uid(),'subscription.manually_assigned','organization_subscription',v_id::text,jsonb_build_object('plan_id',p_plan_id));
 return v_id;
end;$$;
revoke all on function public.admin_assign_subscription(uuid,uuid,timestamptz) from public,anon;
grant execute on function public.admin_assign_subscription(uuid,uuid,timestamptz) to authenticated;

-- Existing select policies in migration 002 already cover these tables.
create policy "super admin reads audit logs" on public.audit_logs for select to authenticated using (public.is_platform_super_admin());
-- END 003_company_plans.sql

-- BEGIN 004_payments.sql

-- Run AFTER 003_company_plans.sql.
create table if not exists public.payment_transactions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 plan_id uuid not null references public.subscription_plans(id),
 initiated_by uuid not null references auth.users(id),
 reference text not null unique check(length(reference) between 12 and 120),
 amount_kobo bigint not null check(amount_kobo >= 100),
 currency text not null default 'NGN' check(currency='NGN'),
 status text not null default 'initiated' check(status in ('initiated','pending','successful','failed','abandoned','review')),
 provider text not null default 'paystack' check(provider='paystack'),
 provider_transaction_id text,
 provider_paid_at timestamptz,
 provider_payload jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists payment_org_created_idx on public.payment_transactions(organization_id,created_at desc);
create unique index if not exists payment_provider_tx_unique on public.payment_transactions(provider_transaction_id) where provider_transaction_id is not null;
alter table public.payment_transactions enable row level security;
create policy "company admins see own payments" on public.payment_transactions for select to authenticated
 using (public.is_platform_super_admin() or exists(select 1 from public.organization_members m where m.organization_id=payment_transactions.organization_id and m.user_id=(select auth.uid()) and m.role='company_admin'));
-- Payment mutation is performed exclusively via server-only functions; client cannot write directly.
create or replace function public.payment_start(p_organization_id uuid,p_plan_id uuid,p_reference text)
returns table(amount_kobo bigint, plan_name text, customer_email text)
language plpgsql security definer set search_path='' as $$
declare v_price bigint; v_name text; v_email text;
begin
 if not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=auth.uid() and m.role='company_admin')
 and not public.is_platform_super_admin() then raise exception 'Not authorized'; end if;
 if not exists(select 1 from public.organizations where id=p_organization_id and status='active') then raise exception 'Company not active'; end if;
 select price_ngn_kobo,name into v_price,v_name from public.subscription_plans where id=p_plan_id and is_active and is_public;
 if v_price is null or v_price<100 then raise exception 'Plan not eligible for online checkout'; end if;
 select email into v_email from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if v_email is null then raise exception 'Verified account required'; end if;
 insert into public.payment_transactions(organization_id,plan_id,initiated_by,reference,amount_kobo)
 values(p_organization_id,p_plan_id,auth.uid(),p_reference,v_price);
 return query select v_price,v_name,v_email;
end;$$;
revoke all on function public.payment_start(uuid,uuid,text) from public,anon;
grant execute on function public.payment_start(uuid,uuid,text) to authenticated;

-- Called only by server using the Supabase service role after Paystack transaction verification.
create or replace function public.payment_finalize(p_reference text,p_transaction_id text,p_amount_kobo bigint,p_currency text,p_paid_at timestamptz)
returns text language plpgsql security definer set search_path='' as $$
declare v_tx public.payment_transactions%rowtype; v_current text;
begin
 if auth.role() <> 'service_role' then raise exception 'Service role required'; end if;
 select * into v_tx from public.payment_transactions where reference=p_reference for update;
 if not found then return 'unknown_reference'; end if;
 if v_tx.status='successful' then
   if v_tx.provider_transaction_id=p_transaction_id then return 'already_processed'; end if;
   return 'transaction_conflict';
 end if;
 if v_tx.status not in ('initiated','pending') then return 'invalid_status'; end if;
 if p_amount_kobo is distinct from v_tx.amount_kobo or p_currency is distinct from v_tx.currency or nullif(p_transaction_id,'') is null then
   update public.payment_transactions set status='review',updated_at=now() where id=v_tx.id;
   return 'payment_mismatch';
 end if;
 perform 1 from public.organizations where id=v_tx.organization_id for update;
 update public.organization_subscriptions set status='cancelled'
 where organization_id=v_tx.organization_id and status in ('active','pending');
 insert into public.organization_subscriptions(organization_id,plan_id,status,starts_at,expires_at)
 values(v_tx.organization_id,v_tx.plan_id,'active',now(),
 case when (select billing_interval from public.subscription_plans where id=v_tx.plan_id)='month' then now()+interval '1 month'
 when (select billing_interval from public.subscription_plans where id=v_tx.plan_id)='year' then now()+interval '1 year'
 else null end);
 update public.payment_transactions set status='successful',provider_transaction_id=p_transaction_id,provider_paid_at=p_paid_at,updated_at=now() where id=v_tx.id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details)
 values(v_tx.organization_id,v_tx.initiated_by,'subscription.payment_activated','payment_transaction',v_tx.id::text,jsonb_build_object('reference',p_reference,'plan_id',v_tx.plan_id));
 return 'activated';
end;$$;
revoke all on function public.payment_finalize(text,text,bigint,text,timestamptz) from public,anon,authenticated;
grant execute on function public.payment_finalize(text,text,bigint,text,timestamptz) to service_role;
-- END 004_payments.sql

-- BEGIN 005_brand_templates.sql
-- Batch 5. Apply after 004_payments.sql. This migration does not delete existing data.
alter table public.organization_branding add column if not exists secondary_color text not null default '#356df3';
alter table public.organization_branding add column if not exists tagline text not null default '';
alter table public.organization_branding add column if not exists social_links jsonb not null default '{}'::jsonb;
alter table public.email_templates add column if not exists updated_at timestamptz not null default now();
alter table public.email_templates add column if not exists updated_by uuid references auth.users(id);
alter table public.email_templates add column if not exists description text not null default '';
alter table public.email_templates add column if not exists category text not null default 'general';
alter table public.email_footers add column if not exists updated_at timestamptz not null default now();

-- All mutations use security-definer RPCs with an independent permission check.
create or replace function public.can_edit_company_design(p_org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select public.is_platform_super_admin() or exists (
 select 1 from public.organization_members m where m.organization_id=p_org
 and m.user_id=(select auth.uid()) and m.role in ('company_admin','manager','designer'));
$$;
revoke all on function public.can_edit_company_design(uuid) from public,anon;
grant execute on function public.can_edit_company_design(uuid) to authenticated;

create or replace function public.save_company_brand(p_org uuid,p_name text,p_tagline text,p_primary text,p_secondary text,p_website text,p_email text,p_address text,p_social jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.can_edit_company_design(p_org) then raise exception 'Not authorized'; end if;
 if length(trim(coalesce(p_name,''))) not between 2 and 160 then raise exception 'Invalid company name'; end if;
 if p_primary !~ '^#[0-9A-Fa-f]{6}$' or p_secondary !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Invalid colors'; end if;
 if length(coalesce(p_tagline,''))>240 or length(coalesce(p_address,''))>1000 then raise exception 'Text too long'; end if;
 if length(coalesce(p_website,''))>300 or (coalesce(p_website,'')<>'' and p_website !~* '^https://[^[:space:]]+$') then raise exception 'Website must be HTTPS'; end if;
 if length(coalesce(p_email,''))>254 then raise exception 'Invalid email'; end if;
 if jsonb_typeof(p_social) is distinct from 'object' or length(p_social::text)>4000 then raise exception 'Invalid social links'; end if;
 insert into public.organization_branding(organization_id,display_name,tagline,primary_color,secondary_color,website_url,contact_email,postal_address,social_links,updated_at)
 values(p_org,trim(p_name),coalesce(p_tagline,''),p_primary,p_secondary,nullif(p_website,''),nullif(p_email,''),nullif(p_address,''),p_social,now())
 on conflict(organization_id) do update set display_name=excluded.display_name,tagline=excluded.tagline,primary_color=excluded.primary_color,secondary_color=excluded.secondary_color,website_url=excluded.website_url,contact_email=excluded.contact_email,postal_address=excluded.postal_address,social_links=excluded.social_links,updated_at=now();
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'brand.updated','organization_branding',p_org::text);
end;$$;
revoke all on function public.save_company_brand(uuid,text,text,text,text,text,text,text,jsonb) from public,anon;
grant execute on function public.save_company_brand(uuid,text,text,text,text,text,text,text,jsonb) to authenticated;

create or replace function public.save_email_template(p_id uuid,p_org uuid,p_name text,p_subject text,p_description text,p_category text,p_design jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_owner uuid;
begin
 if p_org is null then
  if not public.is_platform_super_admin() then raise exception 'Not authorized'; end if;
 else
  if not public.can_edit_company_design(p_org) then raise exception 'Not authorized'; end if;
 end if;
 if length(trim(coalesce(p_name,''))) not between 2 and 120 or length(coalesce(p_subject,''))>200 then raise exception 'Invalid template name or subject'; end if;
 if length(coalesce(p_description,''))>500 or length(coalesce(p_category,''))>40 then raise exception 'Invalid template metadata'; end if;
 if jsonb_typeof(p_design) is distinct from 'object' or length(p_design::text)>60000 then raise exception 'Invalid design'; end if;
 if p_design->>'version' <> '1' or jsonb_typeof(p_design->'blocks') is distinct from 'array' or jsonb_array_length(p_design->'blocks')>30 then raise exception 'Unsupported design schema'; end if;
 if exists(select 1 from jsonb_array_elements(p_design->'blocks') b where b->>'type' not in ('heading','paragraph','button','divider') or length(b->>'text')>5000) then raise exception 'Unsupported block'; end if;
 if p_id is null then
  insert into public.email_templates(organization_id,name,subject,description,category,design,created_by,updated_by)
  values(p_org,trim(p_name),coalesce(p_subject,''),coalesce(p_description,''),coalesce(p_category,'general'),p_design,auth.uid(),auth.uid()) returning id into v_id;
 else
  select organization_id into v_owner from public.email_templates where id=p_id for update;
  if not found or v_owner is distinct from p_org then raise exception 'Template not found in this workspace'; end if;
  update public.email_templates set name=trim(p_name),subject=coalesce(p_subject,''),description=coalesce(p_description,''),category=coalesce(p_category,'general'),design=p_design,updated_at=now(),updated_by=auth.uid(),status='draft' where id=p_id returning id into v_id;
 end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'template.saved','email_template',v_id::text);
 return v_id;
end;$$;
revoke all on function public.save_email_template(uuid,uuid,text,text,text,text,jsonb) from public,anon;
grant execute on function public.save_email_template(uuid,uuid,text,text,text,text,jsonb) to authenticated;

create or replace function public.save_email_footer(p_id uuid,p_org uuid,p_name text,p_design jsonb,p_default boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not public.can_edit_company_design(p_org) then raise exception 'Not authorized'; end if;
 if length(trim(coalesce(p_name,''))) not between 2 and 120 then raise exception 'Invalid footer name'; end if;
 if jsonb_typeof(p_design) is distinct from 'object' or length(p_design::text)>6000 then raise exception 'Invalid footer'; end if;
 perform 1 from public.organizations where id=p_org for update;
 if p_default then update public.email_footers set is_default=false where organization_id=p_org and is_default; end if;
 if p_id is null then
  insert into public.email_footers(organization_id,name,design,is_default) values(p_org,trim(p_name),p_design,p_default) returning id into v_id;
 else
  update public.email_footers set name=trim(p_name),design=p_design,is_default=p_default,updated_at=now() where id=p_id and organization_id=p_org returning id into v_id;
  if v_id is null then raise exception 'Footer not found in this workspace'; end if;
 end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'footer.saved','email_footer',v_id::text);
 return v_id;
end;$$;
revoke all on function public.save_email_footer(uuid,uuid,text,jsonb,boolean) from public,anon;
grant execute on function public.save_email_footer(uuid,uuid,text,jsonb,boolean) to authenticated;

-- Platform templates are visible to authenticated company members, but not anonymously.
create policy "authenticated users view global templates" on public.email_templates for select to authenticated
using (organization_id is null and exists(select 1 from public.organization_members where user_id=(select auth.uid())));
-- END 005_brand_templates.sql

-- BEGIN 006_contacts_audiences.sql
-- SESCO Campaign Cloud | Batch 6 | Contacts & audiences
-- Apply after 005_brand_templates.sql. Non-destructive; no demo customer records.
-- The only allowed mutations are through guarded SECURITY DEFINER functions.

create or replace function public.can_manage_contacts(p_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
 select public.is_platform_super_admin() or exists (
  select 1 from public.organization_members m join public.organizations o on o.id=m.organization_id
  where m.organization_id=p_org and m.user_id=(select auth.uid())
    and m.role in ('company_admin','manager') and o.status='active'
 );
$$;
revoke all on function public.can_manage_contacts(uuid) from public,anon;
grant execute on function public.can_manage_contacts(uuid) to authenticated;

create table if not exists public.contacts (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 first_name text not null default '' check(length(first_name)<=100),
 last_name text not null default '' check(length(last_name)<=100),
 email text check(email is null or (length(email)<=254 and email=lower(btrim(email)) and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
 phone text check(phone is null or phone ~ '^\+[1-9][0-9]{7,14}$'),
 source text not null default 'manual' check(source in ('manual','import')),
 consent_status text not null default 'unknown' check(consent_status in ('unknown','granted','denied')),
 consent_evidence text,
 consent_recorded_at timestamptz,
 unsubscribed_at timestamptz,
 attributes jsonb not null default '{}'::jsonb check (jsonb_typeof(attributes)='object' and length(attributes::text)<=4000),
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint contact_needs_identity check(email is not null or phone is not null),
 constraint granted_consent_requires_evidence check (consent_status<>'granted' or (consent_evidence is not null and length(btrim(consent_evidence))>=6 and consent_recorded_at is not null)),
 unique (organization_id,id)
);
create unique index if not exists contacts_org_email_unique on public.contacts(organization_id,email) where email is not null;
create unique index if not exists contacts_org_phone_unique on public.contacts(organization_id,phone) where phone is not null;
create index if not exists contacts_org_created on public.contacts(organization_id,created_at desc);
create index if not exists contacts_org_consent on public.contacts(organization_id,consent_status);

create table if not exists public.contact_lists (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null check(length(btrim(name)) between 2 and 100),
 description text not null default '' check(length(description)<=500),
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 unique(organization_id,id),
 unique(organization_id,name)
);
create table if not exists public.contact_list_members (
 organization_id uuid not null,
 list_id uuid not null,
 contact_id uuid not null,
 added_at timestamptz not null default now(),
 primary key(list_id,contact_id),
 foreign key(organization_id,list_id) references public.contact_lists(organization_id,id) on delete cascade,
 foreign key(organization_id,contact_id) references public.contacts(organization_id,id) on delete cascade
);
create index if not exists list_members_org_contact on public.contact_list_members(organization_id,contact_id);

create table if not exists public.contact_segments (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null check(length(btrim(name)) between 2 and 100),
 description text not null default '' check(length(description)<=500),
 -- Conservative allowlisted filters; evaluated server-side as query conditions, never raw SQL.
 rules jsonb not null default '{}'::jsonb check(jsonb_typeof(rules)='object' and length(rules::text)<=1000),
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 unique(organization_id,name)
);
create table if not exists public.contact_import_batches (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 batch_key uuid not null,
 imported_by uuid not null references auth.users(id),
 inserted_count integer not null default 0,
 skipped_count integer not null default 0,
 rejected_count integer not null default 0,
 created_at timestamptz not null default now(),
 unique(organization_id,batch_key)
);

alter table public.contacts enable row level security;
alter table public.contact_lists enable row level security;
alter table public.contact_list_members enable row level security;
alter table public.contact_segments enable row level security;
alter table public.contact_import_batches enable row level security;

create policy "authorized company staff view contacts" on public.contacts for select to authenticated
 using(public.can_manage_contacts(organization_id));
create policy "authorized company staff view lists" on public.contact_lists for select to authenticated
 using(public.can_manage_contacts(organization_id));
create policy "authorized company staff view list members" on public.contact_list_members for select to authenticated
 using(public.can_manage_contacts(organization_id));
create policy "authorized company staff view segments" on public.contact_segments for select to authenticated
 using(public.can_manage_contacts(organization_id));
create policy "authorized company staff view imports" on public.contact_import_batches for select to authenticated
 using(public.can_manage_contacts(organization_id));
-- No INSERT/UPDATE/DELETE RLS policies. Privileged mutations only through vetted RPC.

create or replace function public.save_contact(
 p_org uuid,p_id uuid,p_first text,p_last text,p_email text,p_phone text,p_consent text,p_evidence text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_email text; v_phone text; v_evidence text;
begin
 if not public.can_manage_contacts(p_org) then raise exception 'Not authorized'; end if;
 v_email:=nullif(lower(btrim(coalesce(p_email,''))),'');
 v_phone:=nullif(btrim(coalesce(p_phone,'')),'');
 v_evidence:=nullif(btrim(coalesce(p_evidence,'')),'');
 if (v_email is null and v_phone is null) or length(coalesce(p_first,''))>100 or length(coalesce(p_last,''))>100
   or (v_email is not null and (length(v_email)>254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'))
   or (v_phone is not null and v_phone !~ '^\+[1-9][0-9]{7,14}$') then raise exception 'Invalid contact details'; end if;
 if p_consent not in ('unknown','granted','denied') then raise exception 'Invalid consent'; end if;
 if p_consent='granted' and (v_evidence is null or length(v_evidence)<6 or length(v_evidence)>500) then
    raise exception 'Document proof of consent (minimum six characters)'; end if;
 if p_id is null then
  insert into public.contacts(organization_id,first_name,last_name,email,phone,consent_status,consent_evidence,consent_recorded_at,created_by)
  values(p_org,btrim(coalesce(p_first,'')),btrim(coalesce(p_last,'')),v_email,v_phone,p_consent,
         case when p_consent='granted' then v_evidence else null end,
         case when p_consent='granted' then now() else null end,auth.uid()) returning id into v_id;
 else
  update public.contacts set first_name=btrim(coalesce(p_first,'')),last_name=btrim(coalesce(p_last,'')),
   email=v_email,phone=v_phone,
   -- Once opted out, do not re-subscribe through an ordinary contact edit.
   consent_status=case when consent_status='denied' and p_consent='granted' then 'denied' else p_consent end,
   consent_evidence=case when consent_status='denied' and p_consent='granted' then consent_evidence when p_consent='granted' then v_evidence else null end,
   consent_recorded_at=case when consent_status='denied' and p_consent='granted' then consent_recorded_at when p_consent='granted' then now() else null end,
   updated_at=now() where organization_id=p_org and id=p_id returning id into v_id;
  if v_id is null then raise exception 'Contact not found in this workspace'; end if;
 end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id)
 values(p_org,auth.uid(),'contact.saved','contact',v_id::text);
 return v_id;
end;$$;
revoke all on function public.save_contact(uuid,uuid,text,text,text,text,text,text) from public,anon;
grant execute on function public.save_contact(uuid,uuid,text,text,text,text,text,text) to authenticated;

create or replace function public.save_contact_list(p_org uuid,p_name text,p_description text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not public.can_manage_contacts(p_org) then raise exception 'Not authorized'; end if;
 if length(btrim(coalesce(p_name,''))) not between 2 and 100 or length(coalesce(p_description,''))>500 then raise exception 'Invalid list'; end if;
 insert into public.contact_lists(organization_id,name,description,created_by)
 values(p_org,btrim(p_name),coalesce(p_description,''),auth.uid()) returning id into v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id)
 values(p_org,auth.uid(),'contact_list.created','contact_list',v_id::text);
 return v_id;
end;$$;
revoke all on function public.save_contact_list(uuid,text,text) from public,anon;
grant execute on function public.save_contact_list(uuid,text,text) to authenticated;

create or replace function public.add_contact_to_list(p_org uuid,p_list uuid,p_contact uuid,p_add boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.can_manage_contacts(p_org) then raise exception 'Not authorized'; end if;
 if p_add then
  insert into public.contact_list_members(organization_id,list_id,contact_id) values(p_org,p_list,p_contact)
  on conflict(list_id,contact_id) do nothing;
 else
  delete from public.contact_list_members where organization_id=p_org and list_id=p_list and contact_id=p_contact;
 end if;
end;$$;
revoke all on function public.add_contact_to_list(uuid,uuid,uuid,boolean) from public,anon;
grant execute on function public.add_contact_to_list(uuid,uuid,uuid,boolean) to authenticated;

create or replace function public.save_contact_segment(p_org uuid,p_name text,p_description text,p_rules jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not public.can_manage_contacts(p_org) then raise exception 'Not authorized'; end if;
 if length(btrim(coalesce(p_name,''))) not between 2 and 100 or length(coalesce(p_description,''))>500 then raise exception 'Invalid segment'; end if;
 if p_rules is null or jsonb_typeof(p_rules)<>'object' or length(p_rules::text)>1000 or
    (p_rules - 'consent_status' - 'source' - 'has_email') <> '{}'::jsonb or
    (p_rules ? 'consent_status' and p_rules->>'consent_status' not in ('unknown','granted','denied')) or
    (p_rules ? 'source' and p_rules->>'source' not in ('manual','import')) or
    (p_rules ? 'has_email' and jsonb_typeof(p_rules->'has_email')<>'boolean') then raise exception 'Unsupported segment rules'; end if;
 if p_rules='{}'::jsonb then raise exception 'At least one condition is required'; end if;
 insert into public.contact_segments(organization_id,name,description,rules,created_by)
 values(p_org,btrim(p_name),coalesce(p_description,''),p_rules,auth.uid()) returning id into v_id;
 return v_id;
end;$$;
revoke all on function public.save_contact_segment(uuid,text,text,jsonb) from public,anon;
grant execute on function public.save_contact_segment(uuid,text,text,jsonb) to authenticated;

create or replace function public.import_contact_batch(p_org uuid,p_batch_key uuid,p_rows jsonb)
returns table(inserted integer,skipped integer,rejected integer)
language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_row jsonb; v_email text; v_phone text; v_first text; v_last text;
 v_inserted integer:=0; v_skipped integer:=0; v_rejected integer:=0; v_rows_count int; v_attributes jsonb;
begin
 if not public.can_manage_contacts(p_org) then raise exception 'Not authorized'; end if;
 if p_batch_key is null or p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'Invalid import request'; end if;
 v_rows_count:=jsonb_array_length(p_rows);
 if v_rows_count<1 or v_rows_count>100 or length(p_rows::text)>100000 then raise exception 'Batch exceeds import limits'; end if;
 insert into public.contact_import_batches(organization_id,batch_key,imported_by)
 values(p_org,p_batch_key,auth.uid()) on conflict(organization_id,batch_key) do nothing returning id into v_id;
 if v_id is null then
   return query select b.inserted_count,b.skipped_count,b.rejected_count from public.contact_import_batches b
   where b.organization_id=p_org and b.batch_key=p_batch_key;
   return;
 end if;
 for v_row in select value from jsonb_array_elements(p_rows) loop
  v_email:=nullif(lower(btrim(coalesce(v_row->>'email',''))),'');
  v_phone:=nullif(btrim(coalesce(v_row->>'phone','')),'');
  v_first:=btrim(coalesce(v_row->>'first_name',''));
  v_last:=btrim(coalesce(v_row->>'last_name',''));
  v_attributes:=coalesce(v_row->'attributes','{}'::jsonb);
  if jsonb_typeof(v_attributes)<>'object' or length(v_attributes::text)>4000 then
    v_rejected:=v_rejected+1; continue;
  end if;
  if (select count(*) from jsonb_object_keys(v_attributes))>12 or
     exists(select 1 from jsonb_each(v_attributes) a where
      a.key !~ '^[a-z][a-z0-9_]{0,39}$' or jsonb_typeof(a.value)<>'string' or length(a.value#>>'{}')>500) then
      v_rejected:=v_rejected+1; continue;
  end if;
  if jsonb_typeof(v_row)<>'object' or
     (v_email is null and v_phone is null) or
     (v_email is not null and (length(v_email)>254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')) or
     (v_phone is not null and v_phone !~ '^\+[1-9][0-9]{7,14}$') or
     length(v_first)>100 or length(v_last)>100 then
       v_rejected:=v_rejected+1; continue;
  end if;
  -- Conservative deduplication. Never overwrite existing consent, opt-outs or customer records.
  if exists(select 1 from public.contacts c where c.organization_id=p_org
    and ((v_email is not null and c.email=v_email) or (v_phone is not null and c.phone=v_phone))) then
       v_skipped:=v_skipped+1; continue;
  end if;
  begin
   insert into public.contacts(organization_id,first_name,last_name,email,phone,source,consent_status,attributes,created_by)
   values(p_org,v_first,v_last,v_email,v_phone,'import','unknown',v_attributes,auth.uid());
   v_inserted:=v_inserted+1;
  exception when unique_violation then
   -- Another concurrent import may already have inserted the same address.
   v_skipped:=v_skipped+1;
  end;
 end loop;
 update public.contact_import_batches b set inserted_count=v_inserted,skipped_count=v_skipped,rejected_count=v_rejected where b.id=v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details)
 values(p_org,auth.uid(),'contacts.import_batch','contact_import_batch',v_id::text,
 jsonb_build_object('inserted',v_inserted,'skipped',v_skipped,'rejected',v_rejected));
 return query select v_inserted,v_skipped,v_rejected;
end;$$;
revoke all on function public.import_contact_batch(uuid,uuid,jsonb) from public,anon;
grant execute on function public.import_contact_batch(uuid,uuid,jsonb) to authenticated;
-- END 006_contacts_audiences.sql

-- BEGIN 007_email_providers.sql
-- Batch 7: additive migration. Apply after 006. Provider keys remain server env only.
-- Public pricing must not invoke an admin-only function as the anon role.
drop policy "public plans visible" on public.subscription_plans;
create policy "public reads published plans" on public.subscription_plans for select to anon using(is_public and is_active);
create policy "authenticated reads plans" on public.subscription_plans for select to authenticated using((is_public and is_active) or public.is_platform_super_admin());
create table public.email_provider_settings (
 provider text primary key check(provider in ('resend','brevo')),
 enabled boolean not null default false,
 health_status text not null default 'unchecked' check(health_status in ('unchecked','healthy','error')),
 checked_at timestamptz,
 updated_at timestamptz not null default now()
);
insert into public.email_provider_settings(provider) values ('resend'),('brevo');
alter table public.email_provider_settings enable row level security;
create policy "owner reads provider settings" on public.email_provider_settings for select to authenticated using(public.is_platform_super_admin());

alter table public.sending_domains add column dns_records jsonb not null default '[]';
alter table public.sending_domains add column ownership_token uuid not null default gen_random_uuid();
alter table public.sending_domains add column last_checked_at timestamptz;
alter table public.sending_domains add column updated_at timestamptz not null default now();
alter table public.sending_domains add column created_by uuid references auth.users(id);
alter table public.sending_domains add constraint domain_tenant_key unique(organization_id,id);
-- Older domain rows are deliberately not trusted until a fresh ownership check.
update public.sending_domains set verification_status='pending' where verification_status='verified';
create table public.sender_identities (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 domain_id uuid not null,
 from_name text not null check(length(trim(from_name)) between 1 and 100 and from_name !~ '[<>\r\n]'),
 from_email text not null check(length(from_email)<=254),
 reply_to text not null check(length(reply_to)<=254),
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(organization_id,from_email),
 foreign key(organization_id,domain_id) references public.sending_domains(organization_id,id)
);
alter table public.sender_identities enable row level security;
create policy "members read senders" on public.sender_identities for select to authenticated using(public.is_organization_member(organization_id) or public.is_platform_super_admin());
create table public.email_test_attempts (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 sender_id uuid not null references public.sender_identities(id),
 actor_id uuid not null references auth.users(id),
 status text not null default 'reserved' check(status in ('reserved','accepted','unknown')),
 provider_message_id text,
 created_at timestamptz not null default now()
);
create index email_test_quota on public.email_test_attempts(organization_id,created_at);
alter table public.email_test_attempts enable row level security;
create policy "members read test history" on public.email_test_attempts for select to authenticated using(public.is_organization_member(organization_id) or public.is_platform_super_admin());

create or replace function public.can_manage_senders(p_org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organizations o where o.id=p_org and o.status='active') and
 (public.is_platform_super_admin() or exists(select 1 from public.organization_members m
 where m.organization_id=p_org and m.user_id=auth.uid() and m.role='company_admin'));
$$;
revoke all on function public.can_manage_senders(uuid) from public,anon;
grant execute on function public.can_manage_senders(uuid) to authenticated;

create function public.email_domain_reserve(p_org uuid,p_domain text,p_provider text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not public.can_manage_senders(p_org) then raise exception 'Not authorized'; end if;
 if p_provider not in ('resend','brevo') or not exists(select 1 from public.email_provider_settings where provider=p_provider and enabled) then raise exception 'Provider unavailable'; end if;
 if p_domain is null or length(p_domain)>253 or p_domain<>lower(trim(p_domain)) or p_domain !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$' then raise exception 'Invalid domain'; end if;
 perform 1 from public.organizations where id=p_org for update;
 if (select count(*) from public.sending_domains where organization_id=p_org)>=20 then raise exception 'Domain allowance reached. Contact support'; end if;
 if exists(select 1 from public.sending_domains where organization_id=p_org and created_at>now()-interval '1 minute') then raise exception 'Wait one minute before adding another domain'; end if;
 insert into public.sending_domains(organization_id,domain,provider,created_by) values(p_org,p_domain,p_provider,auth.uid()) returning id into v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'domain.reserved','sending_domain',v_id::text);
 return v_id;
exception when unique_violation then raise exception 'Domain unavailable. Contact the platform administrator';
end;$$;
revoke all on function public.email_domain_reserve(uuid,text,text) from public,anon;
grant execute on function public.email_domain_reserve(uuid,text,text) to authenticated;

create function public.email_domain_claim_check(p_org uuid,p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_last timestamptz;
begin
 if not public.can_manage_senders(p_org) then raise exception 'Not authorized'; end if;
 select last_checked_at into v_last from public.sending_domains where id=p_id and organization_id=p_org and verification_status<>'revoked' for update;
 if not found then raise exception 'Domain unavailable'; end if;
 if v_last>now()-interval '30 seconds' then raise exception 'Wait 30 seconds before checking again'; end if;
 update public.sending_domains set last_checked_at=now() where id=p_id;
end;$$;
revoke all on function public.email_domain_claim_check(uuid,uuid) from public,anon;
grant execute on function public.email_domain_claim_check(uuid,uuid) to authenticated;

-- Only trusted server calls may supply provider-confirmed verification results.
create function public.email_domain_sync(p_id uuid,p_provider_id text,p_records jsonb,p_verified boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if p_provider_id is null or length(p_provider_id) not between 1 and 200 or jsonb_typeof(p_records) is distinct from 'array' or length(p_records::text)>40000 then raise exception 'Invalid provider response'; end if;
 update public.sending_domains set provider_domain_id=p_provider_id,dns_records=p_records,
 verification_status=case when p_verified then 'verified' else 'pending' end,updated_at=now()
 where id=p_id and verification_status<>'revoked';
 if not found then raise exception 'Domain unavailable'; end if;
end;$$;
revoke all on function public.email_domain_sync(uuid,text,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.email_domain_sync(uuid,text,jsonb,boolean) to service_role;

create function public.email_domain_revoke(p_org uuid,p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.can_manage_senders(p_org) then raise exception 'Not authorized'; end if;
 update public.sending_domains set verification_status='revoked',updated_at=now() where id=p_id and organization_id=p_org;
 if not found then raise exception 'Domain unavailable'; end if;
 update public.sender_identities set is_active=false where domain_id=p_id and organization_id=p_org;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'domain.revoked','sending_domain',p_id::text);
end;$$;
revoke all on function public.email_domain_revoke(uuid,uuid) from public,anon;
grant execute on function public.email_domain_revoke(uuid,uuid) to authenticated;

create function public.email_sender_save(p_org uuid,p_domain uuid,p_name text,p_email text,p_reply text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_domain text; v_id uuid;
begin
 if not public.can_manage_senders(p_org) then raise exception 'Not authorized'; end if;
 select domain into v_domain from public.sending_domains where id=p_domain and organization_id=p_org and verification_status='verified' for update;
 if not found then raise exception 'Verify the domain first'; end if;
 if p_name is null or length(trim(p_name)) not between 1 and 100 or p_name ~ '[<>\r\n]' then raise exception 'Invalid sender name'; end if;
 if p_email is null or p_reply is null or length(p_email)>254 or length(p_reply)>254 or p_email !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9.-]+$' or p_reply !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9.-]+$' or split_part(p_email,'@',2)<>v_domain then raise exception 'Invalid sender email'; end if;
 insert into public.sender_identities(organization_id,domain_id,from_name,from_email,reply_to) values(p_org,p_domain,trim(p_name),p_email,p_reply)
 on conflict(organization_id,from_email) do update set from_name=excluded.from_name,reply_to=excluded.reply_to,is_active=true returning id into v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'sender.saved','sender_identity',v_id::text);
 return v_id;
end;$$;
revoke all on function public.email_sender_save(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.email_sender_save(uuid,uuid,text,text,text) to authenticated;

create function public.email_test_reserve(p_org uuid,p_sender uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not public.can_manage_senders(p_org) then raise exception 'Not authorized'; end if;
 perform 1 from public.organizations where id=p_org for update;
 if not exists(select 1 from public.sender_identities s join public.sending_domains d on d.id=s.domain_id and d.organization_id=s.organization_id
 join public.email_provider_settings p on p.provider=d.provider
 where s.id=p_sender and s.organization_id=p_org and s.is_active and d.verification_status='verified' and p.enabled) then raise exception 'Verified sender unavailable'; end if;
 if exists(select 1 from public.email_test_attempts where organization_id=p_org and created_at>now()-interval '1 minute') or
 (select count(*) from public.email_test_attempts where organization_id=p_org and created_at>now()-interval '24 hours')>=10 then raise exception 'Test limit reached: one per minute and ten per rolling day per company'; end if;
 insert into public.email_test_attempts(organization_id,sender_id,actor_id) values(p_org,p_sender,auth.uid()) returning id into v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'email_test.reserved','email_test',v_id::text);
 return v_id;
end;$$;
revoke all on function public.email_test_reserve(uuid,uuid) from public,anon;
grant execute on function public.email_test_reserve(uuid,uuid) to authenticated;

create function public.admin_email_provider_save(p_provider text,p_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_platform_super_admin() then raise exception 'Not authorized'; end if;
 update public.email_provider_settings set enabled=p_enabled,updated_at=now() where provider=p_provider;
 if not found then raise exception 'Unknown provider'; end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'provider.updated','email_provider',p_provider,jsonb_build_object('enabled',p_enabled));
end;$$;
revoke all on function public.admin_email_provider_save(text,boolean) from public,anon;
grant execute on function public.admin_email_provider_save(text,boolean) to authenticated;
-- END 007_email_providers.sql

-- BEGIN 008_campaign_workflows.sql
-- Batch 8. Apply once after 007. Draft/approval workflow; no campaign dispatch.
create function public.can_edit_campaigns(p_org uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organizations where id=p_org and status='active') and
 (public.is_platform_super_admin() or exists(select 1 from public.organization_members where organization_id=p_org and user_id=auth.uid() and role in ('company_admin','manager','designer')));
$$;
create function public.can_approve_campaigns(p_org uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organizations where id=p_org and status='active') and
 (public.is_platform_super_admin() or exists(select 1 from public.organization_members where organization_id=p_org and user_id=auth.uid() and role in ('company_admin','approver')));
$$;
revoke all on function public.can_edit_campaigns(uuid),public.can_approve_campaigns(uuid) from public,anon;
grant execute on function public.can_edit_campaigns(uuid),public.can_approve_campaigns(uuid) to authenticated;
alter table public.sender_identities add constraint sender_tenant_key unique(organization_id,id);
create table public.campaign_drafts (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 name text not null check(length(trim(name)) between 2 and 120),
 subject text not null check(length(trim(subject)) between 1 and 200 and subject !~ '[\r\n]'),
 preheader text not null default '' check(length(preheader)<=250),
 design jsonb not null,
 sender_id uuid not null,
 audience_type text not null check(audience_type in ('all','list','segment')),
 audience_id uuid,
 requested_send_at timestamptz,
 status text not null default 'draft' check(status in ('draft','pending_approval','approved','rejected','archived')),
 revision integer not null default 1,
 edited_by uuid not null references auth.users(id),
 submitted_by uuid references auth.users(id),
 reviewed_by uuid references auth.users(id),
 review_note text not null default '',
 eligible_at_review integer,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(organization_id,id),
 check((audience_type='all' and audience_id is null) or (audience_type<>'all' and audience_id is not null)),
 foreign key(organization_id,sender_id) references public.sender_identities(organization_id,id)
);
create table public.campaign_revisions (
 id bigint generated always as identity primary key,
 organization_id uuid not null,
 campaign_id uuid not null,
 revision integer not null,
 snapshot jsonb not null,
 actor_id uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 unique(campaign_id,revision),
 foreign key(organization_id,campaign_id) references public.campaign_drafts(organization_id,id)
);
alter table public.campaign_drafts enable row level security;
alter table public.campaign_revisions enable row level security;
create policy "members read campaigns" on public.campaign_drafts for select to authenticated using(public.is_organization_member(organization_id) or public.is_platform_super_admin());
create policy "members read campaign revisions" on public.campaign_revisions for select to authenticated using(public.is_organization_member(organization_id) or public.is_platform_super_admin());

-- Caller is authorized separately. Consent and unsubscribes always override segment filters.
create function public.campaign_audience_count(p_org uuid,p_type text,p_audience uuid) returns integer
language plpgsql stable security definer set search_path='' as $$
declare v_rules jsonb; v_count integer;
begin
 if not (public.is_organization_member(p_org) or public.is_platform_super_admin()) then raise exception 'Not authorized'; end if;
 if p_type='list' and not exists(select 1 from public.contact_lists where id=p_audience and organization_id=p_org) then raise exception 'List unavailable'; end if;
 if p_type='segment' then
  select rules into v_rules from public.contact_segments where id=p_audience and organization_id=p_org;
  if not found then raise exception 'Segment unavailable'; end if;
 elsif p_type not in ('all','list') then raise exception 'Invalid audience'; end if;
 select count(*) into v_count from public.contacts c where c.organization_id=p_org and c.email is not null
 and c.consent_status='granted' and c.unsubscribed_at is null
 and (p_type<>'list' or exists(select 1 from public.contact_list_members lm where lm.organization_id=p_org and lm.list_id=p_audience and lm.contact_id=c.id))
 and (p_type<>'segment' or (
 (not(v_rules?'source') or c.source=v_rules->>'source') and
 (not(v_rules?'consent_status') or c.consent_status=v_rules->>'consent_status') and
 (not(v_rules?'has_email') or (c.email is not null)=(v_rules->>'has_email')::boolean)));
 return v_count;
end;$$;
revoke all on function public.campaign_audience_count(uuid,text,uuid) from public,anon;
grant execute on function public.campaign_audience_count(uuid,text,uuid) to authenticated;

create function public.campaign_save(p_org uuid,p_id uuid,p_expected integer,p_name text,p_subject text,p_preheader text,p_design jsonb,p_sender uuid,p_type text,p_audience uuid,p_requested timestamptz) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_row public.campaign_drafts; v_text text;
begin
 if not public.can_edit_campaigns(p_org) then raise exception 'Not authorized'; end if;
 if p_name is null or p_subject is null or length(trim(p_name)) not between 2 and 120 or length(trim(p_subject)) not between 1 and 200 or p_subject ~ '[\r\n]' or length(coalesce(p_preheader,''))>250 then raise exception 'Invalid campaign details'; end if;
 if jsonb_typeof(p_design) is distinct from 'object' or p_design->>'version' is distinct from '1' or jsonb_typeof(p_design->'blocks') is distinct from 'array' or length(p_design::text)>60000 then raise exception 'Invalid design'; end if;
 if jsonb_array_length(p_design->'blocks') not between 1 and 30 then raise exception 'Invalid block count'; end if;
 if exists(select 1 from jsonb_array_elements(p_design->'blocks') b where b->>'type' is null or b->>'type' not in ('heading','paragraph','button','divider') or b->>'text' is null or length(b->>'text')>5000 or (b->>'type'='button' and (b->>'url' is null or b->>'url' !~ '^https://[^[:space:]]+$'))) then raise exception 'Invalid design block'; end if;
 for v_text in select p_subject union all select coalesce(p_preheader,'') union all select b->>'text' from jsonb_array_elements(p_design->'blocks') b loop
  if regexp_replace(v_text,'\{\{[[:space:]]*(first_name|last_name|email|company_name|attributes\.[a-z][a-z0-9_]{0,39})[[:space:]]*\}\}','','g') ~ '\{\{|\}\}' or v_text ~ 'attributes\.(constructor|prototype)' then raise exception 'Unsupported personalization'; end if;
 end loop;
 if not exists(select 1 from public.sender_identities where id=p_sender and organization_id=p_org and is_active) then raise exception 'Sender unavailable'; end if;
 if p_type is null or p_type not in ('all','list','segment') or (p_type='all' and p_audience is not null) or (p_type<>'all' and p_audience is null) then raise exception 'Invalid audience'; end if;
 perform public.campaign_audience_count(p_org,p_type,p_audience);
 if p_requested is not null and p_requested<=now() then raise exception 'Requested send time must be in the future'; end if;
 if p_id is null then
  insert into public.campaign_drafts(organization_id,name,subject,preheader,design,sender_id,audience_type,audience_id,requested_send_at,edited_by)
  values(p_org,trim(p_name),trim(p_subject),coalesce(p_preheader,''),p_design,p_sender,p_type,p_audience,p_requested,auth.uid()) returning * into v_row;
 else
  select * into v_row from public.campaign_drafts where id=p_id and organization_id=p_org for update;
  if not found then raise exception 'Campaign unavailable'; end if;
  if v_row.revision is distinct from p_expected then raise exception 'Campaign changed. Reload before saving'; end if;
  if v_row.status in ('pending_approval','archived') then raise exception 'Return the campaign to draft before editing'; end if;
  update public.campaign_drafts set name=trim(p_name),subject=trim(p_subject),preheader=coalesce(p_preheader,''),design=p_design,sender_id=p_sender,audience_type=p_type,audience_id=p_audience,requested_send_at=p_requested,
  status='draft',revision=revision+1,edited_by=auth.uid(),submitted_by=null,reviewed_by=null,review_note='',eligible_at_review=null,updated_at=now() where id=p_id returning * into v_row;
 end if;
 v_id=v_row.id;
 insert into public.campaign_revisions(organization_id,campaign_id,revision,snapshot,actor_id) values(p_org,v_id,v_row.revision,to_jsonb(v_row),auth.uid());
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'campaign.saved','campaign',v_id::text);
 return v_id;
end;$$;
revoke all on function public.campaign_save(uuid,uuid,integer,text,text,text,jsonb,uuid,text,uuid,timestamptz) from public,anon;
grant execute on function public.campaign_save(uuid,uuid,integer,text,text,text,jsonb,uuid,text,uuid,timestamptz) to authenticated;

create function public.campaign_transition(p_org uuid,p_id uuid,p_expected integer,p_action text,p_note text) returns void
language plpgsql security definer set search_path='' as $$
declare v_row public.campaign_drafts; v_status text; v_eligible integer;
begin
 if not (public.can_edit_campaigns(p_org) or public.can_approve_campaigns(p_org)) then raise exception 'Not authorized'; end if;
 select * into v_row from public.campaign_drafts where id=p_id and organization_id=p_org for update;
 if not found then raise exception 'Campaign unavailable'; end if;
 if v_row.revision is distinct from p_expected then raise exception 'Campaign changed. Reload before continuing'; end if;
 if length(coalesce(p_note,''))>1000 then raise exception 'Review note too long'; end if;
 if p_action in ('approve','reject') then
  if not public.can_approve_campaigns(p_org) then raise exception 'Not authorized'; end if;
  if v_row.status<>'pending_approval' then raise exception 'Campaign is not awaiting review'; end if;
  if auth.uid()=v_row.edited_by or auth.uid()=v_row.submitted_by then raise exception 'A different authorized person must review this campaign'; end if;
  if p_action='reject' and length(trim(coalesce(p_note,'')))<3 then raise exception 'Provide a rejection reason'; end if;
  v_status=case when p_action='approve' then 'approved' else 'rejected' end;
 else
  if not public.can_edit_campaigns(p_org) then raise exception 'Not authorized'; end if;
  if p_action='submit' and v_row.status in ('draft','rejected') then v_status='pending_approval';
  elsif p_action='withdraw' and v_row.status in ('pending_approval','approved','rejected') then v_status='draft';
  elsif p_action='archive' and v_row.status<>'archived' then v_status='archived';
  else raise exception 'Invalid campaign transition'; end if;
 end if;
 if p_action in ('submit','approve') then
  if not exists(select 1 from public.sender_identities s join public.sending_domains d on d.id=s.domain_id and d.organization_id=s.organization_id join public.email_provider_settings p on p.provider=d.provider where s.id=v_row.sender_id and s.organization_id=p_org and s.is_active and d.verification_status='verified' and p.enabled) then raise exception 'Verified sender and enabled provider required'; end if;
  if not exists(select 1 from public.organization_branding where organization_id=p_org and length(trim(coalesce(postal_address,'')))>=6) then raise exception 'Save a company postal address in Brand Studio first'; end if;
  v_eligible=public.campaign_audience_count(p_org,v_row.audience_type,v_row.audience_id);
  if v_eligible=0 then raise exception 'No eligible opted-in contacts'; end if;
  if v_row.requested_send_at is not null and v_row.requested_send_at<=now() then raise exception 'Requested send time has passed. Revise the draft'; end if;
 end if;
 update public.campaign_drafts set status=v_status,revision=revision+1,
 submitted_by=case when p_action='submit' then auth.uid() when p_action='withdraw' then null else submitted_by end,
 reviewed_by=case when p_action in ('approve','reject') then auth.uid() when p_action='withdraw' then null else reviewed_by end,
 review_note=case when p_action in ('approve','reject') then coalesce(p_note,'') when p_action='withdraw' then '' else review_note end,
 eligible_at_review=case when p_action in ('submit','approve') then v_eligible when p_action='withdraw' then null else eligible_at_review end,updated_at=now()
 where id=p_id returning * into v_row;
 insert into public.campaign_revisions(organization_id,campaign_id,revision,snapshot,actor_id) values(p_org,p_id,v_row.revision,to_jsonb(v_row),auth.uid());
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details) values(p_org,auth.uid(),'campaign.'||p_action,'campaign',p_id::text,jsonb_build_object('revision',v_row.revision));
end;$$;
revoke all on function public.campaign_transition(uuid,uuid,integer,text,text) from public,anon;
grant execute on function public.campaign_transition(uuid,uuid,integer,text,text) to authenticated;
-- END 008_campaign_workflows.sql

-- BEGIN 009_delivery_engine.sql
-- Batch 9: durable queue, consent/suppression, quotas and authenticated event ingestion.
alter table public.email_provider_settings add column daily_limit integer not null default 100 check(daily_limit between 1 and 1000000);
alter table public.email_provider_settings add column minimum_interval_seconds integer not null default 2 check(minimum_interval_seconds between 1 and 3600);
alter table public.email_provider_settings add column last_dispatch_at timestamptz;
create table public.email_suppressions (
 organization_id uuid not null references public.organizations(id),
 email text not null,reason text not null check(reason in ('unsubscribe','bounce','complaint','blocked')),
 created_at timestamptz not null default now(),primary key(organization_id,email)
);
create table public.campaign_runs (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,
 campaign_id uuid not null unique,revision integer not null,
 status text not null default 'queued' check(status in ('queued','running','paused','cancelled','completed')),
 scheduled_at timestamptz not null,provider text not null check(provider in ('resend','brevo')),
 snapshot jsonb not null,created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),last_error text,
 unique(organization_id,id),foreign key(organization_id,campaign_id) references public.campaign_drafts(organization_id,id)
);
create table public.email_deliveries (
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,run_id uuid not null,
 contact_id uuid not null,recipient_email text not null,recipient jsonb not null,
 unsubscribe_token uuid not null default gen_random_uuid() unique,
 status text not null default 'pending' check(status in ('pending','leased','dispatching','accepted','delivered','failed','unknown','skipped','bounced','complained','unsubscribed')),
 lease_token uuid,lease_until timestamptz,available_at timestamptz not null default now(),
 attempts integer not null default 0,quota_at timestamptz,
 provider_message_id text,reason text,updated_at timestamptz not null default now(),
 unique(run_id,contact_id),foreign key(organization_id,run_id) references public.campaign_runs(organization_id,id),
 foreign key(organization_id,contact_id) references public.contacts(organization_id,id)
);
create table public.delivery_quota_reservations (
 delivery_id uuid not null references public.email_deliveries(id),attempt integer not null,
 organization_id uuid not null references public.organizations(id),provider text not null,
 reserved_at timestamptz not null default now(),primary key(delivery_id,attempt)
);
alter table public.delivery_quota_reservations enable row level security;
revoke all on public.delivery_quota_reservations from anon,authenticated;
create index quota_company_time on public.delivery_quota_reservations(organization_id,reserved_at);
create index quota_provider_time on public.delivery_quota_reservations(provider,reserved_at);
create unique index email_provider_message_unique on public.email_deliveries(provider_message_id) where provider_message_id is not null;
create index delivery_pending on public.email_deliveries(available_at) where status='pending';
create index delivery_quotas on public.email_deliveries(organization_id,quota_at);
create table public.email_delivery_events (
 id bigint generated always as identity primary key,provider text not null,event_key text not null,
 provider_message_id text not null,event_type text not null,occurred_at timestamptz not null,
 delivery_id uuid references public.email_deliveries(id),created_at timestamptz not null default now(),
 unique(provider,event_key)
);
alter table public.email_suppressions enable row level security;
alter table public.campaign_runs enable row level security;
alter table public.email_deliveries enable row level security;
alter table public.email_delivery_events enable row level security;
create policy "members read suppressions" on public.email_suppressions for select to authenticated using(public.is_organization_member(organization_id) or public.is_platform_super_admin());
create policy "members read campaign runs" on public.campaign_runs for select to authenticated using(public.is_organization_member(organization_id) or public.is_platform_super_admin());
-- Tokens and recipient snapshots must not be exposed by raw authenticated table reads.
revoke all on public.email_deliveries,public.email_delivery_events from anon,authenticated;

create function public.can_dispatch_campaigns(p_org uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organizations where id=p_org and status='active') and
 (public.is_platform_super_admin() or exists(select 1 from public.organization_members where organization_id=p_org and user_id=auth.uid() and role in ('company_admin','manager')));
$$;
revoke all on function public.can_dispatch_campaigns(uuid) from public,anon;
grant execute on function public.can_dispatch_campaigns(uuid) to authenticated;

create function public.delivery_monthly_limit(p_org uuid) returns integer language plpgsql stable security definer set search_path='' as $$
declare v_value jsonb;
begin
 select coalesce(s.quota_overrides->'monthly_emails',p.limits->'monthly_emails') into v_value
 from public.organization_subscriptions s join public.subscription_plans p on p.id=s.plan_id
 where s.organization_id=p_org and s.status='active' and p.is_active and (s.starts_at is null or s.starts_at<=now()) and (s.expires_at is null or s.expires_at>now());
 if v_value is null or jsonb_typeof(v_value)<>'number' or v_value::text !~ '^[0-9]+$' then return 0; end if;
 return least((v_value::text)::numeric,10000000)::integer;
end;$$;
revoke all on function public.delivery_monthly_limit(uuid) from public,anon,authenticated;
grant execute on function public.delivery_monthly_limit(uuid) to service_role;

create function public.campaign_enqueue(p_org uuid,p_campaign uuid,p_revision integer) returns uuid
language plpgsql security definer set search_path='' as $$
declare c public.campaign_drafts; v_sender public.sender_identities; v_brand public.organization_branding;
 v_provider text;v_run uuid;v_count integer;v_rules jsonb;
begin
 if not public.can_dispatch_campaigns(p_org) then raise exception 'Not authorized'; end if;
 perform 1 from public.organizations where id=p_org for update;
 select * into c from public.campaign_drafts where id=p_campaign and organization_id=p_org for update;
 if not found or c.status<>'approved' or c.revision is distinct from p_revision then raise exception 'Unchanged approved campaign required'; end if;
 if exists(select 1 from public.campaign_runs where campaign_id=p_campaign) then raise exception 'Campaign already queued. Create a new campaign for another send'; end if;
 select s.* into v_sender from public.sender_identities s join public.sending_domains d on d.id=s.domain_id and d.organization_id=p_org join public.email_provider_settings p on p.provider=d.provider
 where s.id=c.sender_id and s.organization_id=p_org and s.is_active and d.verification_status='verified' and p.enabled;
 if not found then raise exception 'Verified active sender required'; end if;
 select provider into v_provider from public.sending_domains where id=v_sender.domain_id;
 select * into v_brand from public.organization_branding where organization_id=p_org;
 if not found or length(trim(coalesce(v_brand.postal_address,'')))<6 then raise exception 'Company postal address required'; end if;
 if public.delivery_monthly_limit(p_org)=0 then raise exception 'Active subscription with monthly_emails allowance required'; end if;
 if c.requested_send_at is not null and c.requested_send_at<=now() then raise exception 'Requested send time has passed. Revise and reapprove'; end if;
 if c.audience_type='list' and not exists(select 1 from public.contact_lists where organization_id=p_org and id=c.audience_id) then raise exception 'Audience list unavailable'; end if;
 if c.audience_type='segment' then select rules into v_rules from public.contact_segments where id=c.audience_id and organization_id=p_org; if not found then raise exception 'Audience segment unavailable'; end if;end if;
 insert into public.campaign_runs(organization_id,campaign_id,revision,scheduled_at,provider,snapshot,created_by)
 values(p_org,p_campaign,c.revision,coalesce(c.requested_send_at,now()),v_provider,
 jsonb_build_object('campaign',to_jsonb(c),'sender',to_jsonb(v_sender),'brand',to_jsonb(v_brand)),auth.uid()) returning id into v_run;
 insert into public.email_deliveries(organization_id,run_id,contact_id,recipient_email,recipient)
 select p_org,v_run,t.id,t.email,jsonb_build_object('first_name',t.first_name,'last_name',t.last_name,'email',t.email,'attributes',t.attributes)
 from public.contacts t where t.organization_id=p_org and t.email is not null and t.consent_status='granted' and t.unsubscribed_at is null
 and not exists(select 1 from public.email_suppressions x where x.organization_id=p_org and x.email=t.email)
 and (c.audience_type<>'list' or exists(select 1 from public.contact_list_members l where l.organization_id=p_org and l.list_id=c.audience_id and l.contact_id=t.id))
 and (c.audience_type<>'segment' or ((not(v_rules?'source') or t.source=v_rules->>'source') and (not(v_rules?'consent_status') or t.consent_status=v_rules->>'consent_status') and (not(v_rules?'has_email') or (t.email is not null)=(v_rules->>'has_email')::boolean)));
 get diagnostics v_count=row_count;
 if v_count not between 1 and 10000 then raise exception 'Audience must contain 1 to 10000 eligible contacts'; end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details) values(p_org,auth.uid(),'campaign.queued','campaign_run',v_run::text,jsonb_build_object('recipients',v_count,'revision',c.revision));
 return v_run;
end;$$;
revoke all on function public.campaign_enqueue(uuid,uuid,integer) from public,anon;
grant execute on function public.campaign_enqueue(uuid,uuid,integer) to authenticated;

create function public.campaign_run_control(p_org uuid,p_run uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$
declare v_status text;
begin
 if not public.can_dispatch_campaigns(p_org) then raise exception 'Not authorized'; end if;
 perform 1 from public.organizations where id=p_org for update;
 select status into v_status from public.campaign_runs where id=p_run and organization_id=p_org for update;
 if not found then raise exception 'Run unavailable'; end if;
 if p_action='pause' and v_status in ('queued','running') then update public.campaign_runs set status='paused' where id=p_run;
 elsif p_action='resume' and v_status='paused' then update public.campaign_runs set status='queued',last_error=null where id=p_run;
 elsif p_action='cancel' and v_status in ('queued','running','paused') then
  update public.campaign_runs set status='cancelled' where id=p_run;
  update public.email_deliveries set status='skipped',reason='run_cancelled',lease_token=null where run_id=p_run and status in ('pending','leased');
 else raise exception 'Invalid run transition';end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'run.'||p_action,'campaign_run',p_run::text);
end;$$;
revoke all on function public.campaign_run_control(uuid,uuid,text) from public,anon;
grant execute on function public.campaign_run_control(uuid,uuid,text) to authenticated;

create function public.campaign_content_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.campaign_runs where campaign_id=old.id and status in ('queued','running','paused')) then raise exception 'Cancel the active delivery run before changing this campaign';end if;
 return new;
end;$$;
revoke all on function public.campaign_content_guard() from public,anon,authenticated;
create trigger protect_queued_campaign before update on public.campaign_drafts for each row execute function public.campaign_content_guard();

create function public.delivery_recover() returns void language plpgsql security definer set search_path='' as $$
begin
 update public.email_deliveries set status='pending',lease_token=null,lease_until=null where status='leased' and lease_until<now();
 update public.email_deliveries set status='unknown',reason='dispatch_lease_expired',updated_at=now() where status='dispatching' and lease_until<now();
end;$$;
revoke all on function public.delivery_recover() from public,anon,authenticated;
grant execute on function public.delivery_recover() to service_role;
create function public.delivery_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.email_deliveries; r public.campaign_runs;
begin
 -- Only pre-dispatch leases are reclaimable. Uncertain external sends never auto-retry.
 update public.campaign_runs r0 set status='completed' where r0.status in ('queued','running') and not exists(select 1 from public.email_deliveries d0 where d0.run_id=r0.id and d0.status in ('pending','leased','dispatching'));
 select * into r from public.campaign_runs r0 where r0.status in ('queued','running') and r0.scheduled_at<=now() and exists(select 1 from public.email_deliveries q where q.run_id=r0.id and q.status='pending' and q.available_at<=now()) order by r0.scheduled_at,r0.id limit 1 for update skip locked;
 if not found then return null;end if;
 select q.* into d from public.email_deliveries q where q.run_id=r.id and q.status='pending' and q.available_at<=now() order by q.id limit 1 for update skip locked;
 if not found then return null;end if;
 update public.email_deliveries set status='leased',lease_token=gen_random_uuid(),lease_until=now()+interval '2 minutes' where id=d.id returning * into d;

 return jsonb_build_object('delivery',to_jsonb(d),'run',to_jsonb(r));
end;$$;
revoke all on function public.delivery_claim() from public,anon,authenticated;
grant execute on function public.delivery_claim() to service_role;

create function public.delivery_begin(p_id uuid,p_lease uuid) returns text language plpgsql security definer set search_path='' as $$
declare d public.email_deliveries; r public.campaign_runs;p public.email_provider_settings;v_limit integer;v_count integer;
begin
 -- Global provider lock then organization lock serialize quota checks across workers.
 select r0.* into r from public.campaign_runs r0 join public.email_deliveries d0 on d0.run_id=r0.id where d0.id=p_id;
 if not found then return 'unavailable';end if;
 select * into p from public.email_provider_settings where provider=r.provider for update;
 perform 1 from public.organizations where id=r.organization_id for update;
 select * into r from public.campaign_runs where id=r.id for update;
 select * into d from public.email_deliveries where id=p_id and status='leased' and lease_token=p_lease and lease_until>now() for update;
 if not found then return 'lease_lost';end if;

 if r.status not in ('queued','running') then update public.email_deliveries set status='pending',lease_token=null where id=d.id;return 'run_inactive';end if;
 if not exists(select 1 from public.contacts c where c.id=d.contact_id and c.organization_id=d.organization_id and c.email=d.recipient_email and c.consent_status='granted' and c.unsubscribed_at is null)
 or exists(select 1 from public.email_suppressions where organization_id=d.organization_id and email=d.recipient_email) then
 update public.email_deliveries set status='skipped',reason='consent_or_suppression',lease_token=null where id=d.id;return 'suppressed';end if;
 if not p.enabled or not exists(select 1 from public.organizations where id=d.organization_id and status='active') or not exists(select 1 from public.sender_identities s join public.sending_domains sd on sd.id=s.domain_id where s.id=(r.snapshot->'sender'->>'id')::uuid and s.organization_id=d.organization_id and s.is_active and sd.verification_status='verified') then
 update public.campaign_runs set status='paused',last_error='Sender, provider or organization unavailable' where id=r.id;
 update public.email_deliveries set status='pending',lease_token=null where id=d.id;return 'not_ready';end if;
 v_limit=public.delivery_monthly_limit(d.organization_id);
 select count(*) into v_count from public.delivery_quota_reservations where organization_id=d.organization_id and reserved_at>=date_trunc('month',now() at time zone 'UTC') at time zone 'UTC';
 if v_count>=v_limit then
 update public.campaign_runs set status='paused',last_error='Monthly email allowance reached or subscription unavailable' where id=r.id;
 update public.email_deliveries set status='pending',lease_token=null where id=d.id;return 'company_limit';end if;
 select count(*) into v_count from public.delivery_quota_reservations where provider=r.provider and reserved_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
 select v_count+count(*) into v_count from public.email_test_attempts t join public.sender_identities si on si.id=t.sender_id join public.sending_domains sd on sd.id=si.domain_id where sd.provider=r.provider and t.created_at>=(date_trunc('day',now() at time zone 'UTC') at time zone 'UTC');
 if v_count>=p.daily_limit or p.last_dispatch_at>now()-make_interval(secs=>p.minimum_interval_seconds) then
 update public.email_deliveries set status='pending',lease_token=null,available_at=case when v_count>=p.daily_limit then (date_trunc('day',now() at time zone 'UTC')+interval '1 day') at time zone 'UTC' else now()+make_interval(secs=>p.minimum_interval_seconds) end where id=d.id;return 'provider_limit';end if;
 update public.campaign_runs set status='running' where id=r.id and status='queued';
 insert into public.delivery_quota_reservations(delivery_id,attempt,organization_id,provider) values(d.id,d.attempts+1,d.organization_id,r.provider);
 update public.email_provider_settings set last_dispatch_at=now() where provider=r.provider;
 update public.email_deliveries set status='dispatching',attempts=attempts+1,quota_at=coalesce(quota_at,now()),lease_until=now()+interval '2 minutes',updated_at=now() where id=d.id;
 return 'dispatch';
end;$$;
revoke all on function public.delivery_begin(uuid,uuid) from public,anon,authenticated;
grant execute on function public.delivery_begin(uuid,uuid) to service_role;

create function public.delivery_finish(p_id uuid,p_lease uuid,p_status text,p_message text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare d public.email_deliveries;ev public.email_delivery_events;v_provider text;
begin
 if p_status not in ('accepted','failed','unknown','retry') then raise exception 'Invalid delivery result';end if;
 select * into d from public.email_deliveries where id=p_id and lease_token=p_lease and status in ('dispatching','unknown') for update;
 if not found then raise exception 'Dispatch lease unavailable';end if;
 if p_status='accepted' and nullif(p_message,'') is null then raise exception 'Provider acknowledgement required';end if;
 update public.email_deliveries set status=case when p_status='retry' and attempts<3 then 'pending' when p_status='retry' then 'failed' else p_status end,
 provider_message_id=nullif(trim(both '<>' from p_message),''),reason=left(p_reason,200),available_at=now()+interval '1 minute',lease_token=null,lease_until=null,updated_at=now() where id=p_id;
 if p_status='accepted' then
  select provider into v_provider from public.campaign_runs where id=d.run_id;
  for ev in select * from public.email_delivery_events where provider=v_provider and provider_message_id=trim(both '<>' from p_message) and delivery_id is null loop
   perform public.delivery_event(ev.provider,ev.event_key,ev.provider_message_id,ev.event_type,ev.occurred_at);
  end loop;
 end if;
end;$$;
revoke all on function public.delivery_finish(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.delivery_finish(uuid,uuid,text,text,text) to service_role;

create function public.delivery_hold(p_id uuid,p_lease uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare v_run uuid;
begin
 select run_id into v_run from public.email_deliveries where id=p_id;
 perform 1 from public.campaign_runs where id=v_run for update;
 v_run:=null;
 update public.email_deliveries set status='pending',lease_token=null where id=p_id and status='leased' and lease_token=p_lease returning run_id into v_run;
 if v_run is not null then update public.campaign_runs set status='paused',last_error=left(p_reason,200) where id=v_run and status in ('queued','running');end if;
end;$$;
revoke all on function public.delivery_hold(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.delivery_hold(uuid,uuid,text) to service_role;

create function public.delivery_unsubscribe(p_token uuid) returns void language plpgsql security definer set search_path='' as $$
declare d public.email_deliveries;
begin
 select * into d from public.email_deliveries where unsubscribe_token=p_token;
 if not found then return;end if;
 insert into public.email_suppressions(organization_id,email,reason) values(d.organization_id,d.recipient_email,'unsubscribe') on conflict(organization_id,email) do nothing;
 update public.contacts set unsubscribed_at=coalesce(unsubscribed_at,now()),consent_status='denied',updated_at=now() where organization_id=d.organization_id and email=d.recipient_email;
end;$$;
revoke all on function public.delivery_unsubscribe(uuid) from public,anon,authenticated;
grant execute on function public.delivery_unsubscribe(uuid) to service_role;

create function public.delivery_event(p_provider text,p_key text,p_message text,p_type text,p_time timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare d public.email_deliveries;v_event bigint;
begin
 if p_provider not in ('resend','brevo') or p_type not in ('delivered','bounce','complaint','unsubscribe','blocked','opened','clicked','delayed','accepted','failed') or length(p_key)>200 or length(p_message)>300 then raise exception 'Invalid event';end if;
 select q.* into d from public.email_deliveries q join public.campaign_runs r on r.id=q.run_id where r.provider=p_provider and q.provider_message_id=trim(both '<>' from p_message) for update of q;
 insert into public.email_delivery_events(provider,event_key,provider_message_id,event_type,occurred_at,delivery_id) values(p_provider,p_key,trim(both '<>' from p_message),p_type,p_time,d.id) on conflict(provider,event_key) do nothing returning id into v_event;
 if v_event is null and d.id is not null then
  update public.email_delivery_events set delivery_id=d.id where provider=p_provider and event_key=p_key and delivery_id is null and provider_message_id=trim(both '<>' from p_message) returning id into v_event;
 end if;
 if v_event is null or d.id is null then return;end if;
 if p_type in ('bounce','complaint','unsubscribe','blocked') then
  insert into public.email_suppressions(organization_id,email,reason) values(d.organization_id,d.recipient_email,case when p_type='unsubscribe' then 'unsubscribe' when p_type='complaint' then 'complaint' when p_type='blocked' then 'blocked' else 'bounce' end) on conflict(organization_id,email) do nothing;
  update public.contacts set consent_status='denied',unsubscribed_at=coalesce(unsubscribed_at,now()),updated_at=now() where organization_id=d.organization_id and email=d.recipient_email;
  update public.email_deliveries set status=case when p_type='bounce' then 'bounced' when p_type='complaint' then 'complained' when p_type='unsubscribe' then 'unsubscribed' else 'failed' end,updated_at=now() where id=d.id;
 elsif p_type='delivered' and d.status not in ('bounced','complained','unsubscribed','failed') then update public.email_deliveries set status='delivered',updated_at=now() where id=d.id;
 elsif p_type='failed' and d.status='accepted' then update public.email_deliveries set status='failed',updated_at=now() where id=d.id;
 end if;
end;$$;
revoke all on function public.delivery_event(text,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.delivery_event(text,text,text,text,timestamptz) to service_role;

create function public.delivery_summary(p_org uuid,p_run uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
 if not(public.is_organization_member(p_org) or public.is_platform_super_admin()) then raise exception 'Not authorized';end if;
 select jsonb_object_agg(status,cnt) into v_result from (select status,count(*) cnt from public.email_deliveries where organization_id=p_org and run_id=p_run group by status) x;
 return coalesce(v_result,'{}');
end;$$;
revoke all on function public.delivery_summary(uuid,uuid) from public,anon;
grant execute on function public.delivery_summary(uuid,uuid) to authenticated;

create function public.admin_provider_limits(p_provider text,p_daily integer,p_interval integer) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_platform_super_admin() then raise exception 'Not authorized';end if;
 if p_daily not between 1 and 1000000 or p_interval not between 1 and 3600 then raise exception 'Invalid provider limits';end if;
 update public.email_provider_settings set daily_limit=p_daily,minimum_interval_seconds=p_interval where provider=p_provider;
 if not found then raise exception 'Provider unavailable';end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id) values(auth.uid(),'provider.limits_updated','email_provider',p_provider);
end;$$;
revoke all on function public.admin_provider_limits(text,integer,integer) from public,anon;
grant execute on function public.admin_provider_limits(text,integer,integer) to authenticated;
-- Configuration tests share the provider daily budget and spacing with campaigns.
create or replace function public.email_test_reserve(p_org uuid,p_sender uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_provider text;p public.email_provider_settings;v_count integer;
begin
 if not public.can_manage_senders(p_org) then raise exception 'Not authorized';end if;
 select sd.provider into v_provider from public.sender_identities si join public.sending_domains sd on sd.id=si.domain_id where si.id=p_sender and si.organization_id=p_org and si.is_active and sd.verification_status='verified';
 if not found then raise exception 'Verified sender unavailable';end if;
 select * into p from public.email_provider_settings where provider=v_provider for update;
 perform 1 from public.organizations where id=p_org for update;
 if not p.enabled then raise exception 'Provider unavailable';end if;
 select count(*) into v_count from public.delivery_quota_reservations where provider=v_provider and reserved_at>=(date_trunc('day',now() at time zone 'UTC') at time zone 'UTC');
 select v_count+count(*) into v_count from public.email_test_attempts t join public.sender_identities si on si.id=t.sender_id join public.sending_domains sd on sd.id=si.domain_id where sd.provider=v_provider and t.created_at>=(date_trunc('day',now() at time zone 'UTC') at time zone 'UTC');
 if v_count>=p.daily_limit or p.last_dispatch_at>now()-make_interval(secs=>p.minimum_interval_seconds) then raise exception 'Provider allowance or spacing limit reached';end if;
 if exists(select 1 from public.email_test_attempts where organization_id=p_org and created_at>now()-interval '1 minute') or (select count(*) from public.email_test_attempts where organization_id=p_org and created_at>now()-interval '24 hours')>=10 then raise exception 'Test limit reached';end if;
 insert into public.email_test_attempts(organization_id,sender_id,actor_id) values(p_org,p_sender,auth.uid()) returning id into v_id;
 update public.email_provider_settings set last_dispatch_at=now() where provider=v_provider;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(p_org,auth.uid(),'email_test.reserved','email_test',v_id::text);
 return v_id;
end;$$;
revoke all on function public.email_test_reserve(uuid,uuid) from public,anon;
grant execute on function public.email_test_reserve(uuid,uuid) to authenticated;
-- END 009_delivery_engine.sql

-- BEGIN 010_campaign_analytics.sql

-- Keep reporting aggregate-only. Raw recipients, tokens and events remain service-only.
alter table public.email_deliveries add column unsubscribe_recorded_at timestamptz;
create index analytics_runs_cohort on public.campaign_runs(organization_id,created_at desc,id);
create index analytics_delivery_events on public.email_delivery_events(delivery_id,event_type) where delivery_id is not null;

create or replace function public.delivery_unsubscribe(p_token uuid) returns void language plpgsql security definer set search_path='' as $$
declare d public.email_deliveries;
begin
 select * into d from public.email_deliveries where unsubscribe_token=p_token;
 if not found then return;end if;
 insert into public.email_suppressions(organization_id,email,reason) values(d.organization_id,d.recipient_email,'unsubscribe') on conflict(organization_id,email) do nothing;
 update public.contacts set unsubscribed_at=coalesce(unsubscribed_at,now()),consent_status='denied',updated_at=now() where organization_id=d.organization_id and email=d.recipient_email;
 update public.email_deliveries set unsubscribe_recorded_at=coalesce(unsubscribe_recorded_at,now()) where id=d.id;
end;$$;
revoke all on function public.delivery_unsubscribe(uuid) from public,anon,authenticated;
grant execute on function public.delivery_unsubscribe(uuid) to service_role;

create function public.campaign_analytics(p_org uuid,p_from timestamptz,p_until timestamptz,p_run uuid default null,p_limit integer default 50,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
 if not(public.is_organization_member(p_org) or public.is_platform_super_admin()) then raise exception 'Not authorized';end if;
 if p_org is null or p_from is null or p_until is null or p_until<=p_from or p_until-p_from>interval '366 days'
 or p_limit is null or p_limit not between 1 and 1000 or p_offset is null or p_offset not between 0 and 100000 then raise exception 'Invalid report range';end if;
 if p_run is not null and not exists(select 1 from public.campaign_runs where id=p_run and organization_id=p_org) then raise exception 'Run unavailable';end if;
 with cohort as materialized (
  select r.id,r.snapshot->'campaign'->>'name' as name,r.provider,r.status,r.created_at,r.scheduled_at
  from public.campaign_runs r where r.organization_id=p_org and r.created_at>=p_from and r.created_at<p_until and (p_run is null or r.id=p_run)
 ), flags as (
  select d.run_id,d.status,d.provider_message_id is not null as submitted,d.attempts,
   coalesce(e.delivered,false) as delivered,coalesce(e.opened,false) as opened,coalesce(e.clicked,false) as clicked,
   coalesce(e.bounced,false) as bounced,coalesce(e.complained,false) as complained,
   (d.unsubscribe_recorded_at is not null or coalesce(e.unsubscribed,false)) as unsubscribed
  from public.email_deliveries d join cohort c on c.id=d.run_id
  left join lateral (select bool_or(event_type='delivered') as delivered,bool_or(event_type='opened') as opened,bool_or(event_type='clicked') as clicked,
   bool_or(event_type='bounce') as bounced,bool_or(event_type='complaint') as complained,bool_or(event_type='unsubscribe') as unsubscribed
   from public.email_delivery_events where delivery_id=d.id) e on true
  where d.organization_id=p_org
 ), metrics as materialized (
  select c.id,c.name,c.provider,c.status,c.created_at,c.scheduled_at,
   count(f.run_id) as recipients,count(*) filter(where f.submitted) as submitted,
   count(*) filter(where f.delivered) as delivered,count(*) filter(where f.opened) as opened,count(*) filter(where f.clicked) as clicked,
   count(*) filter(where f.bounced) as bounced,count(*) filter(where f.complained) as complained,count(*) filter(where f.unsubscribed) as unsubscribed,
   count(*) filter(where f.status='failed') as failed,count(*) filter(where f.status='unknown') as unknown,
   count(*) filter(where f.status='skipped') as skipped,count(*) filter(where f.status in ('pending','leased','dispatching')) as waiting,
   coalesce(sum(f.attempts),0) as attempts
  from cohort c left join flags f on f.run_id=c.id group by c.id,c.name,c.provider,c.status,c.created_at,c.scheduled_at
 ), daily as (
  select (created_at at time zone 'UTC')::date as day,count(*) as runs,sum(recipients) as recipients,sum(submitted) as submitted,sum(delivered) as delivered
  from metrics group by (created_at at time zone 'UTC')::date
 )
 select jsonb_build_object('generated_at',now(),'total_runs',(select count(*) from metrics),
  'totals',(select jsonb_build_object('recipients',coalesce(sum(recipients),0),'submitted',coalesce(sum(submitted),0),'delivered',coalesce(sum(delivered),0),
   'opened',coalesce(sum(opened),0),'clicked',coalesce(sum(clicked),0),'bounced',coalesce(sum(bounced),0),'complained',coalesce(sum(complained),0),
   'unsubscribed',coalesce(sum(unsubscribed),0),'failed',coalesce(sum(failed),0),'unknown',coalesce(sum(unknown),0),'skipped',coalesce(sum(skipped),0),
   'waiting',coalesce(sum(waiting),0),'attempts',coalesce(sum(attempts),0)) from metrics),
  'runs',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc) from (select * from metrics order by created_at desc,id desc limit p_limit offset p_offset) x),'[]'::jsonb),
  'daily',coalesce((select jsonb_agg(to_jsonb(daily) order by day) from daily),'[]'::jsonb)) into v_result;
 return v_result;
end;$$;
revoke all on function public.campaign_analytics(uuid,timestamptz,timestamptz,uuid,integer,integer) from public,anon;
grant execute on function public.campaign_analytics(uuid,timestamptz,timestamptz,uuid,integer,integer) to authenticated;
-- END 010_campaign_analytics.sql

-- BEGIN 011_cms_administration.sql
create table public.site_pages(
 slug text primary key check(slug in ('site','home','features','solutions','pricing','about','resources','faq','contact','privacy','terms','cookies','acceptable-use','login','register')),
 draft jsonb not null default '{}'::jsonb check(jsonb_typeof(draft)='object'),
 published jsonb check(published is null or jsonb_typeof(published)='object'),
 revision integer not null default 0,published_revision integer,
 updated_by uuid references auth.users(id),updated_at timestamptz not null default now(),published_at timestamptz
);
create table public.site_page_revisions(
 id bigint generated always as identity primary key,slug text not null references public.site_pages(slug),revision integer not null,
 content jsonb not null,operation text not null check(operation in ('save','publish','unpublish')),actor_id uuid references auth.users(id),created_at timestamptz not null default now()
);
alter table public.site_pages enable row level security;
alter table public.site_page_revisions enable row level security;
create policy "owner reads CMS drafts" on public.site_pages for select to authenticated using(public.is_platform_super_admin());
create policy "owner reads CMS history" on public.site_page_revisions for select to authenticated using(public.is_platform_super_admin());
grant select on public.site_pages,public.site_page_revisions to authenticated;
revoke all on public.site_pages,public.site_page_revisions from anon;
insert into public.site_pages(slug) select unnest(array['site','home','features','solutions','pricing','about','resources','faq','contact','privacy','terms','cookies','acceptable-use','login','register']);
-- Preserve the existing platform identity as a published starting point.
update public.site_pages set draft=jsonb_build_object('display_name',b.display_name,'tagline',b.tagline,'primary_color',b.primary_color),
 published=jsonb_build_object('display_name',b.display_name,'tagline',b.tagline,'primary_color',b.primary_color),published_revision=0,published_at=now()
 from public.platform_branding b where slug='site' and b.id=true;

create function public.cms_public(p_slug text) returns jsonb language sql stable security definer set search_path='' as $$select published from public.site_pages where slug=p_slug$$;
revoke all on function public.cms_public(text) from public;
grant execute on function public.cms_public(text) to anon,authenticated;

create function public.cms_edit(p_slug text,p_revision integer,p_operation text,p_content jsonb default null) returns integer language plpgsql security definer set search_path='' as $$
declare v public.site_pages;v_next integer;
begin
 if not public.is_platform_super_admin() then raise exception 'Not authorized';end if;
 select * into v from public.site_pages where slug=p_slug for update;
 if not found then raise exception 'Page unavailable';end if;
 if p_revision is null or p_revision<>v.revision then raise exception 'Page changed. Reload before saving.';end if;
 if p_operation not in ('save','publish','unpublish') or p_operation is null then raise exception 'Invalid operation';end if;
 if p_operation='save' and (p_content is null or jsonb_typeof(p_content)<>'object' or octet_length(p_content::text)>60000) then raise exception 'Invalid content';end if;
 if p_operation='publish' and v.draft='{}'::jsonb then raise exception 'Save content before publishing';end if;
 v_next:=v.revision+1;
 update public.site_pages set draft=case when p_operation='save' then p_content else draft end,
 published=case when p_operation='publish' then draft when p_operation='unpublish' then null else published end,
 published_revision=case when p_operation='publish' then v_next when p_operation='unpublish' then null else published_revision end,
 published_at=case when p_operation='publish' then now() when p_operation='unpublish' then null else published_at end,
 revision=v_next,updated_at=now(),updated_by=auth.uid() where slug=p_slug;
 insert into public.site_page_revisions(slug,revision,content,operation,actor_id) values(p_slug,v_next,case when p_operation='save' then p_content else v.draft end,p_operation,auth.uid());
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'cms.'||p_operation,'site_page',p_slug,jsonb_build_object('revision',v_next));
 return v_next;
end;$$;
revoke all on function public.cms_edit(text,integer,text,jsonb) from public,anon;
grant execute on function public.cms_edit(text,integer,text,jsonb) to authenticated;

create function public.can_manage_team(p_org uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.is_platform_super_admin() or exists(select 1 from public.organization_members m join public.organizations o on o.id=m.organization_id where m.organization_id=p_org and m.user_id=auth.uid() and m.role='company_admin' and o.status='active')
$$;
revoke all on function public.can_manage_team(uuid) from public,anon;
grant execute on function public.can_manage_team(uuid) to authenticated;
create function public.team_members(p_org uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not public.can_manage_team(p_org) then raise exception 'Not authorized';end if;
 select jsonb_agg(jsonb_build_object('id',m.user_id,'email',u.email,'role',m.role) order by u.email) into result from public.organization_members m join auth.users u on u.id=m.user_id where m.organization_id=p_org;
 return coalesce(result,'[]'::jsonb);
end;$$;
revoke all on function public.team_members(uuid) from public,anon;
grant execute on function public.team_members(uuid) to authenticated;
create function public.team_member_save(p_org uuid,p_email text,p_role text) returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid;v_previous text;
begin
 perform 1 from public.organizations where id=p_org for update;
 if not found then raise exception 'Company unavailable';end if;
 if not public.can_manage_team(p_org) then raise exception 'Not authorized';end if;
 if p_email is null or length(p_email)>254 or p_role is null or p_role not in ('company_admin','manager','designer','approver','analyst','viewer','remove') then raise exception 'Invalid member';end if;
 select id into v_user from auth.users where lower(email)=lower(trim(p_email)) and email_confirmed_at is not null;
 if v_user is null then raise exception 'A verified account is required';end if;
 select role into v_previous from public.organization_members where organization_id=p_org and user_id=v_user;
 if v_previous='company_admin' and p_role<>'company_admin' and not exists(select 1 from public.organization_members where organization_id=p_org and role='company_admin' and user_id<>v_user) then raise exception 'Keep at least one company administrator';end if;
 if p_role='remove' then delete from public.organization_members where organization_id=p_org and user_id=v_user;
 else insert into public.organization_members(organization_id,user_id,role) values(p_org,v_user,p_role) on conflict(organization_id,user_id) do update set role=excluded.role;end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details) values(p_org,auth.uid(),'team.member_saved','membership',v_user::text,jsonb_build_object('role',p_role));
end;$$;
revoke all on function public.team_member_save(uuid,text,text) from public,anon;
grant execute on function public.team_member_save(uuid,text,text) to authenticated;

create function public.admin_company_settings(p_org uuid,p_status text,p_monthly integer) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_platform_super_admin() then raise exception 'Not authorized';end if;
 if p_status is null or p_status not in ('pending','active','suspended') or (p_monthly is not null and p_monthly not between 0 and 10000000) then raise exception 'Invalid company settings';end if;
 perform 1 from public.organizations where id=p_org for update;if not found then raise exception 'Company unavailable';end if;
 update public.organizations set status=p_status,updated_at=now() where id=p_org;
 update public.organization_subscriptions set quota_overrides=case when p_monthly is null then quota_overrides-'monthly_emails' else jsonb_set(quota_overrides,'{monthly_emails}',to_jsonb(p_monthly),true) end where organization_id=p_org and status='active';
 if p_status<>'active' then update public.campaign_runs set status='paused',last_error='Company is not active' where organization_id=p_org and status in ('queued','running');end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details) values(p_org,auth.uid(),'organization.settings_saved','organization',p_org::text,jsonb_build_object('status',p_status,'monthly_emails',p_monthly));
end;$$;
revoke all on function public.admin_company_settings(uuid,text,integer) from public,anon;
grant execute on function public.admin_company_settings(uuid,text,integer) to authenticated;
-- END 011_cms_administration.sql

-- BEGIN 012_release_hardening.sql
alter table public.payment_transactions add column billing_interval_snapshot text check(billing_interval_snapshot in ('month','year','custom'));
-- Pending older checkouts have no historical interval snapshot; retain the current plan interval.
update public.payment_transactions t set billing_interval_snapshot=p.billing_interval from public.subscription_plans p where p.id=t.plan_id;
create or replace function public.payment_start(p_organization_id uuid,p_plan_id uuid,p_reference text)
returns table(amount_kobo bigint,plan_name text,customer_email text) language plpgsql security definer set search_path='' as $$
declare v_price bigint;v_name text;v_email text;v_interval text;
begin
 perform 1 from public.organizations where id=p_organization_id and status='active' for update;
 if not found then raise exception 'Company not active';end if;
 if not exists(select 1 from public.organization_members where organization_id=p_organization_id and user_id=auth.uid() and role='company_admin') and not public.is_platform_super_admin() then raise exception 'Not authorized';end if;
 if p_reference is null or p_reference !~ '^scc_[a-f0-9]{32}$' then raise exception 'Invalid reference';end if;
 if (select count(*) from public.payment_transactions where organization_id=p_organization_id and created_at>now()-interval '5 minutes')>=5 then raise exception 'Wait before starting another checkout';end if;
 select price_ngn_kobo,name,billing_interval into v_price,v_name,v_interval from public.subscription_plans where id=p_plan_id and is_active and is_public;
 if v_price is null or v_price<100 then raise exception 'Plan not eligible for online checkout';end if;
 select email into v_email from auth.users where id=auth.uid() and email_confirmed_at is not null;if v_email is null then raise exception 'Verified account required';end if;
 insert into public.payment_transactions(organization_id,plan_id,initiated_by,reference,amount_kobo,billing_interval_snapshot) values(p_organization_id,p_plan_id,auth.uid(),p_reference,v_price,v_interval);
 return query select v_price,v_name,v_email;
end;$$;
revoke all on function public.payment_start(uuid,uuid,text) from public,anon;
grant execute on function public.payment_start(uuid,uuid,text) to authenticated;
create or replace function public.payment_finalize(p_reference text,p_transaction_id text,p_amount_kobo bigint,p_currency text,p_paid_at timestamptz)
returns text language plpgsql security definer set search_path='' as $$
declare v_tx public.payment_transactions;v_org uuid;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Service role required';end if;
 select organization_id into v_org from public.payment_transactions where reference=p_reference;
 if v_org is null then return 'unknown_reference';end if;
 perform 1 from public.organizations where id=v_org for update;
 select * into v_tx from public.payment_transactions where reference=p_reference for update;
 if nullif(p_transaction_id,'') is null or length(p_transaction_id)>128 then return 'transaction_conflict';end if;
 if v_tx.status='successful' then
  if v_tx.provider_transaction_id=p_transaction_id and p_amount_kobo=v_tx.amount_kobo and p_currency=v_tx.currency then return 'already_processed';end if;
  return 'transaction_conflict';
 end if;
 if v_tx.status not in ('initiated','pending') then return 'invalid_status';end if;
 if p_amount_kobo is distinct from v_tx.amount_kobo or p_currency is distinct from v_tx.currency then update public.payment_transactions set status='review',updated_at=now() where id=v_tx.id;return 'payment_mismatch';end if;
 if exists(select 1 from public.payment_transactions where provider_transaction_id=p_transaction_id and id<>v_tx.id) then return 'transaction_conflict';end if;
 if v_tx.billing_interval_snapshot is null then raise exception 'Payment interval snapshot unavailable';end if;
 update public.organization_subscriptions set status='cancelled' where organization_id=v_org and status in ('active','pending');
 insert into public.organization_subscriptions(organization_id,plan_id,status,starts_at,expires_at) values(v_org,v_tx.plan_id,'active',now(),case v_tx.billing_interval_snapshot when 'month' then now()+interval '1 month' when 'year' then now()+interval '1 year' else null end);
 update public.payment_transactions set status='successful',provider_transaction_id=p_transaction_id,provider_paid_at=p_paid_at,updated_at=now() where id=v_tx.id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details) values(v_org,v_tx.initiated_by,'subscription.payment_activated','payment_transaction',v_tx.id::text,jsonb_build_object('reference',p_reference,'plan_id',v_tx.plan_id));
 return 'activated';
end;$$;
revoke all on function public.payment_finalize(text,text,bigint,text,timestamptz) from public,anon,authenticated;
grant execute on function public.payment_finalize(text,text,bigint,text,timestamptz) to service_role;
-- END 012_release_hardening.sql

commit;
