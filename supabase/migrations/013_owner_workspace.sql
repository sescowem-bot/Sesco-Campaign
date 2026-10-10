-- 013: dedicated platform owner workspace. Apply after 012; safe to rerun.
begin;
create table if not exists public.platform_workspace (
 id boolean primary key default true check(id),
 organization_id uuid not null unique references public.organizations(id),
 monthly_email_limit integer not null default 10000 check(monthly_email_limit between 1 and 10000000)
);
alter table public.platform_workspace enable row level security;
drop policy if exists "owner reads own workspace" on public.platform_workspace;
create policy "owner reads own workspace" on public.platform_workspace for select to authenticated using(public.is_platform_super_admin());
revoke all on public.platform_workspace from anon,authenticated;
grant select on public.platform_workspace to authenticated,service_role;
do $$
declare v_id uuid; v_name text;
begin
 perform pg_advisory_xact_lock(130013);
 if not exists(select 1 from public.platform_workspace) then
  select display_name into v_name from public.platform_branding where id;
  v_id=gen_random_uuid();
  insert into public.organizations(id,name,slug,status) values(v_id,coalesce(v_name,'My brand'),'owner-'||v_id::text,'active');
  insert into public.organization_branding(organization_id,display_name) values(v_id,coalesce(v_name,'My brand'));
  insert into public.platform_workspace(organization_id) values(v_id);
 end if;
end;$$;
create or replace function public.is_owner_workspace(p_org uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select public.is_platform_super_admin() and exists(select 1 from public.platform_workspace where organization_id=p_org);
$$;
revoke all on function public.is_owner_workspace(uuid) from public,anon;
grant execute on function public.is_owner_workspace(uuid) to authenticated;
alter table public.campaign_drafts alter column sender_id drop not null;
create or replace function public.campaign_save(p_org uuid,p_id uuid,p_expected integer,p_name text,p_subject text,p_preheader text,p_design jsonb,p_sender uuid,p_type text,p_audience uuid,p_requested timestamptz) returns uuid
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
 if p_sender is not null and not exists(select 1 from public.sender_identities where id=p_sender and organization_id=p_org and is_active) then raise exception 'Sender unavailable'; end if;
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

create or replace function public.campaign_transition(p_org uuid,p_id uuid,p_expected integer,p_action text,p_note text) returns void
language plpgsql security definer set search_path='' as $$
declare v_row public.campaign_drafts; v_status text; v_eligible integer;
begin
 if not (public.can_edit_campaigns(p_org) or public.can_approve_campaigns(p_org)) then raise exception 'Not authorized'; end if;
 select * into v_row from public.campaign_drafts where id=p_id and organization_id=p_org for update;
 if not found then raise exception 'Campaign unavailable'; end if;
 if v_row.revision is distinct from p_expected then raise exception 'Campaign changed. Reload before continuing'; end if;
 if length(coalesce(p_note,''))>1000 then raise exception 'Review note too long'; end if;
 if p_action='owner_approve' then
  if not public.is_owner_workspace(p_org) or not public.can_approve_campaigns(p_org) then raise exception 'Owner approval is available only in your own workspace'; end if;
  if v_row.status not in ('draft','rejected','pending_approval') then raise exception 'Return this campaign to draft before approval'; end if;
  v_status='approved';
 elsif p_action in ('approve','reject') then
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
 if p_action in ('submit','approve','owner_approve') then
  if not exists(select 1 from public.sender_identities s join public.sending_domains d on d.id=s.domain_id and d.organization_id=s.organization_id join public.email_provider_settings p on p.provider=d.provider where s.id=v_row.sender_id and s.organization_id=p_org and s.is_active and d.verification_status='verified' and p.enabled) then raise exception 'Verified sender and enabled provider required'; end if;
  if not exists(select 1 from public.organization_branding where organization_id=p_org and length(trim(coalesce(postal_address,'')))>=6) then raise exception 'Save a company postal address in Brand Studio first'; end if;
  v_eligible=public.campaign_audience_count(p_org,v_row.audience_type,v_row.audience_id);
  if v_eligible=0 then raise exception 'No eligible opted-in contacts'; end if;
  if v_row.requested_send_at is not null and v_row.requested_send_at<=now() then raise exception 'Requested send time has passed. Revise the draft'; end if;
 end if;
 update public.campaign_drafts set status=v_status,revision=revision+1,
 submitted_by=case when p_action='submit' then auth.uid() when p_action='withdraw' then null else submitted_by end,
 reviewed_by=case when p_action in ('approve','reject','owner_approve') then auth.uid() when p_action='withdraw' then null else reviewed_by end,
 review_note=case when p_action in ('approve','reject','owner_approve') then coalesce(p_note,'') when p_action='withdraw' then '' else review_note end,
 eligible_at_review=case when p_action in ('submit','approve','owner_approve') then v_eligible when p_action='withdraw' then null else eligible_at_review end,updated_at=now()
 where id=p_id returning * into v_row;
 insert into public.campaign_revisions(organization_id,campaign_id,revision,snapshot,actor_id) values(p_org,p_id,v_row.revision,to_jsonb(v_row),auth.uid());
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details) values(p_org,auth.uid(),'campaign.'||p_action,'campaign',p_id::text,jsonb_build_object('revision',v_row.revision));
end;$$;
revoke all on function public.campaign_transition(uuid,uuid,integer,text,text) from public,anon;
grant execute on function public.campaign_transition(uuid,uuid,integer,text,text) to authenticated;
create or replace function public.delivery_monthly_limit(p_org uuid) returns integer language plpgsql stable security definer set search_path='' as $$
declare v_value jsonb;
begin
 if exists(select 1 from public.platform_workspace where organization_id=p_org) then
  return (select monthly_email_limit from public.platform_workspace where organization_id=p_org);
 end if;
 select coalesce(s.quota_overrides->'monthly_emails',p.limits->'monthly_emails') into v_value
 from public.organization_subscriptions s join public.subscription_plans p on p.id=s.plan_id
 where s.organization_id=p_org and s.status='active' and p.is_active and (s.starts_at is null or s.starts_at<=now()) and (s.expires_at is null or s.expires_at>now());
 if v_value is null or jsonb_typeof(v_value)<>'number' or v_value::text !~ '^[0-9]+$' then return 0; end if;
 return least((v_value::text)::numeric,10000000)::integer;
end;$$;
revoke all on function public.delivery_monthly_limit(uuid) from public,anon,authenticated;
grant execute on function public.delivery_monthly_limit(uuid) to service_role;


-- Owner reuses the domain already verified in the platform's Resend account.
-- Client domain registration and custom TXT ownership checks stay unchanged.
alter table public.sending_domains add column if not exists ownership_method text not null default 'dns' check(ownership_method in ('dns','provider_account'));
alter table public.sending_domains drop constraint if exists sending_domains_domain_key;
create unique index if not exists customer_domain_unique on public.sending_domains(domain) where ownership_method='dns';
create unique index if not exists workspace_domain_unique on public.sending_domains(organization_id,domain);
create or replace function public.owner_connect_resend(p_actor uuid,p_domain text,p_provider_id text,p_records jsonb,p_name text,p_email text,p_reply text,p_address text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_org uuid; v_domain uuid; v_sender uuid;
begin
 if auth.role() is distinct from 'service_role' or not exists(select 1 from public.platform_staff where user_id=p_actor and role='super_admin') then raise exception 'Not authorized'; end if;
 select organization_id into v_org from public.platform_workspace where id for update;
 if v_org is null or not exists(select 1 from public.organizations where id=v_org and status='active') then raise exception 'Active owner workspace required'; end if;
 if p_domain is null or p_domain !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$' or length(p_domain)>253 or p_provider_id is null or length(p_provider_id) not between 1 and 200 then raise exception 'Invalid domain'; end if;
 if p_email is null or split_part(p_email,'@',2)<>p_domain or p_email !~ '^[^[:space:]@<>]+@[^[:space:]@<>]+$' or p_reply is null or p_reply !~ '^[^[:space:]@<>]+@[^[:space:]@<>]+$' or p_name is null or length(trim(p_name)) not between 1 and 100 or p_name ~ '[<>\r\n]' or length(trim(coalesce(p_address,''))) not between 6 and 500 then raise exception 'Valid sender details and postal address required'; end if;
 insert into public.sending_domains(organization_id,domain,provider,provider_domain_id,verification_status,dns_records,ownership_method,last_checked_at,created_by)
 values(v_org,p_domain,'resend',p_provider_id,'verified',p_records,'provider_account',now(),p_actor)
 on conflict(organization_id,domain) do update set provider='resend',provider_domain_id=excluded.provider_domain_id,verification_status='verified',dns_records=excluded.dns_records,ownership_method='provider_account',last_checked_at=now(),updated_at=now() returning id into v_domain;
 insert into public.sender_identities(organization_id,domain_id,from_name,from_email,reply_to)
 values(v_org,v_domain,p_name,p_email,p_reply)
 on conflict(organization_id,from_email) do update set domain_id=excluded.domain_id,from_name=excluded.from_name,reply_to=excluded.reply_to,is_active=true returning id into v_sender;
 update public.organization_branding set postal_address=trim(p_address),updated_at=now() where organization_id=v_org;
 update public.email_provider_settings set enabled=true,health_status='healthy',checked_at=now(),updated_at=now() where provider='resend';
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id) values(v_org,p_actor,'owner.resend_connected','sender_identity',v_sender::text);
 return v_sender;
end;$$;
revoke all on function public.owner_connect_resend(uuid,text,text,jsonb,text,text,text,text) from public,anon,authenticated;
grant execute on function public.owner_connect_resend(uuid,text,text,jsonb,text,text,text,text) to service_role;

-- Manual owner dispatch claims only the selected owner run, never a client run.
create or replace function public.owner_delivery_claim(p_org uuid,p_run uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d public.email_deliveries; r public.campaign_runs;
begin
 if auth.role() is distinct from 'service_role' or not exists(select 1 from public.platform_workspace where organization_id=p_org) then raise exception 'Not authorized'; end if;
 select * into r from public.campaign_runs where id=p_run and organization_id=p_org and status in ('queued','running') and scheduled_at<=now() for update skip locked;
 if not found then return null; end if;
 update public.email_deliveries set status='pending',lease_token=null,lease_until=null where run_id=p_run and status='leased' and lease_until<now();
 update public.email_deliveries set status='unknown',reason='dispatch_lease_expired',updated_at=now() where run_id=p_run and status='dispatching' and lease_until<now();
 select * into d from public.email_deliveries where run_id=p_run and status='pending' and available_at<=now() order by id limit 1 for update skip locked;
 if not found then
  update public.campaign_runs set status='completed' where id=p_run and not exists(select 1 from public.email_deliveries where run_id=p_run and status in ('pending','leased','dispatching'));
  return null;
 end if;
 update public.email_deliveries set status='leased',lease_token=gen_random_uuid(),lease_until=now()+interval '2 minutes' where id=d.id returning * into d;
 return jsonb_build_object('delivery',to_jsonb(d),'run',to_jsonb(r));
end;$$;
revoke all on function public.owner_delivery_claim(uuid,uuid) from public,anon,authenticated;
grant execute on function public.owner_delivery_claim(uuid,uuid) to service_role;
commit;
