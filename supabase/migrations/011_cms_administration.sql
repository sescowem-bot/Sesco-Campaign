begin;
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
commit;
