
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
