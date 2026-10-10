begin;
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
commit;
