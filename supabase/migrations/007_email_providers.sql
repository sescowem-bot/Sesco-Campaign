-- Batch 7: additive migration. Apply after 006. Provider keys remain server env only.
begin;
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
commit;
