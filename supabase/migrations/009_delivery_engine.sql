-- Batch 9: durable queue, consent/suppression, quotas and authenticated event ingestion.
begin;
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
commit;
