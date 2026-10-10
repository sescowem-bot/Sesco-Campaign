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
