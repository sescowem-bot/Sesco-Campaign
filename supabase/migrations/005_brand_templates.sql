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
