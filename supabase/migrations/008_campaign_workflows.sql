-- Batch 8. Apply once after 007. Draft/approval workflow; no campaign dispatch.
begin;
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
commit;
