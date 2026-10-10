
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
