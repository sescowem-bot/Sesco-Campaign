-- SESCO Campaign Cloud | Batch 6 | Contacts & audiences
-- Apply after 005_brand_templates.sql. Non-destructive; no demo customer records.
-- The only allowed mutations are through guarded SECURITY DEFINER functions.

create or replace function public.can_manage_contacts(p_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
 select public.is_platform_super_admin() or exists (
  select 1 from public.organization_members m join public.organizations o on o.id=m.organization_id
  where m.organization_id=p_org and m.user_id=(select auth.uid())
    and m.role in ('company_admin','manager') and o.status='active'
 );
$$;
revoke all on function public.can_manage_contacts(uuid) from public,anon;
grant execute on function public.can_manage_contacts(uuid) to authenticated;

create table if not exists public.contacts (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 first_name text not null default '' check(length(first_name)<=100),
 last_name text not null default '' check(length(last_name)<=100),
 email text check(email is null or (length(email)<=254 and email=lower(btrim(email)) and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
 phone text check(phone is null or phone ~ '^\+[1-9][0-9]{7,14}$'),
 source text not null default 'manual' check(source in ('manual','import')),
 consent_status text not null default 'unknown' check(consent_status in ('unknown','granted','denied')),
 consent_evidence text,
 consent_recorded_at timestamptz,
 unsubscribed_at timestamptz,
 attributes jsonb not null default '{}'::jsonb check (jsonb_typeof(attributes)='object' and length(attributes::text)<=4000),
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint contact_needs_identity check(email is not null or phone is not null),
 constraint granted_consent_requires_evidence check (consent_status<>'granted' or (consent_evidence is not null and length(btrim(consent_evidence))>=6 and consent_recorded_at is not null)),
 unique (organization_id,id)
);
create unique index if not exists contacts_org_email_unique on public.contacts(organization_id,email) where email is not null;
create unique index if not exists contacts_org_phone_unique on public.contacts(organization_id,phone) where phone is not null;
create index if not exists contacts_org_created on public.contacts(organization_id,created_at desc);
create index if not exists contacts_org_consent on public.contacts(organization_id,consent_status);

create table if not exists public.contact_lists (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null check(length(btrim(name)) between 2 and 100),
 description text not null default '' check(length(description)<=500),
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 unique(organization_id,id),
 unique(organization_id,name)
);
create table if not exists public.contact_list_members (
 organization_id uuid not null,
 list_id uuid not null,
 contact_id uuid not null,
 added_at timestamptz not null default now(),
 primary key(list_id,contact_id),
 foreign key(organization_id,list_id) references public.contact_lists(organization_id,id) on delete cascade,
 foreign key(organization_id,contact_id) references public.contacts(organization_id,id) on delete cascade
);
create index if not exists list_members_org_contact on public.contact_list_members(organization_id,contact_id);

create table if not exists public.contact_segments (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null check(length(btrim(name)) between 2 and 100),
 description text not null default '' check(length(description)<=500),
 -- Conservative allowlisted filters; evaluated server-side as query conditions, never raw SQL.
 rules jsonb not null default '{}'::jsonb check(jsonb_typeof(rules)='object' and length(rules::text)<=1000),
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 unique(organization_id,name)
);
create table if not exists public.contact_import_batches (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 batch_key uuid not null,
 imported_by uuid not null references auth.users(id),
 inserted_count integer not null default 0,
 skipped_count integer not null default 0,
 rejected_count integer not null default 0,
 created_at timestamptz not null default now(),
 unique(organization_id,batch_key)
);

alter table public.contacts enable row level security;
alter table public.contact_lists enable row level security;
alter table public.contact_list_members enable row level security;
alter table public.contact_segments enable row level security;
alter table public.contact_import_batches enable row level security;

create policy "authorized company staff view contacts" on public.contacts for select to authenticated
 using(public.can_manage_contacts(organization_id));
create policy "authorized company staff view lists" on public.contact_lists for select to authenticated
 using(public.can_manage_contacts(organization_id));
create policy "authorized company staff view list members" on public.contact_list_members for select to authenticated
 using(public.can_manage_contacts(organization_id));
create policy "authorized company staff view segments" on public.contact_segments for select to authenticated
 using(public.can_manage_contacts(organization_id));
create policy "authorized company staff view imports" on public.contact_import_batches for select to authenticated
 using(public.can_manage_contacts(organization_id));
-- No INSERT/UPDATE/DELETE RLS policies. Privileged mutations only through vetted RPC.

create or replace function public.save_contact(
 p_org uuid,p_id uuid,p_first text,p_last text,p_email text,p_phone text,p_consent text,p_evidence text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_email text; v_phone text; v_evidence text;
begin
 if not public.can_manage_contacts(p_org) then raise exception 'Not authorized'; end if;
 v_email:=nullif(lower(btrim(coalesce(p_email,''))),'');
 v_phone:=nullif(btrim(coalesce(p_phone,'')),'');
 v_evidence:=nullif(btrim(coalesce(p_evidence,'')),'');
 if (v_email is null and v_phone is null) or length(coalesce(p_first,''))>100 or length(coalesce(p_last,''))>100
   or (v_email is not null and (length(v_email)>254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'))
   or (v_phone is not null and v_phone !~ '^\+[1-9][0-9]{7,14}$') then raise exception 'Invalid contact details'; end if;
 if p_consent not in ('unknown','granted','denied') then raise exception 'Invalid consent'; end if;
 if p_consent='granted' and (v_evidence is null or length(v_evidence)<6 or length(v_evidence)>500) then
    raise exception 'Document proof of consent (minimum six characters)'; end if;
 if p_id is null then
  insert into public.contacts(organization_id,first_name,last_name,email,phone,consent_status,consent_evidence,consent_recorded_at,created_by)
  values(p_org,btrim(coalesce(p_first,'')),btrim(coalesce(p_last,'')),v_email,v_phone,p_consent,
         case when p_consent='granted' then v_evidence else null end,
         case when p_consent='granted' then now() else null end,auth.uid()) returning id into v_id;
 else
  update public.contacts set first_name=btrim(coalesce(p_first,'')),last_name=btrim(coalesce(p_last,'')),
   email=v_email,phone=v_phone,
   -- Once opted out, do not re-subscribe through an ordinary contact edit.
   consent_status=case when consent_status='denied' and p_consent='granted' then 'denied' else p_consent end,
   consent_evidence=case when consent_status='denied' and p_consent='granted' then consent_evidence when p_consent='granted' then v_evidence else null end,
   consent_recorded_at=case when consent_status='denied' and p_consent='granted' then consent_recorded_at when p_consent='granted' then now() else null end,
   updated_at=now() where organization_id=p_org and id=p_id returning id into v_id;
  if v_id is null then raise exception 'Contact not found in this workspace'; end if;
 end if;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id)
 values(p_org,auth.uid(),'contact.saved','contact',v_id::text);
 return v_id;
end;$$;
revoke all on function public.save_contact(uuid,uuid,text,text,text,text,text,text) from public,anon;
grant execute on function public.save_contact(uuid,uuid,text,text,text,text,text,text) to authenticated;

create or replace function public.save_contact_list(p_org uuid,p_name text,p_description text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not public.can_manage_contacts(p_org) then raise exception 'Not authorized'; end if;
 if length(btrim(coalesce(p_name,''))) not between 2 and 100 or length(coalesce(p_description,''))>500 then raise exception 'Invalid list'; end if;
 insert into public.contact_lists(organization_id,name,description,created_by)
 values(p_org,btrim(p_name),coalesce(p_description,''),auth.uid()) returning id into v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id)
 values(p_org,auth.uid(),'contact_list.created','contact_list',v_id::text);
 return v_id;
end;$$;
revoke all on function public.save_contact_list(uuid,text,text) from public,anon;
grant execute on function public.save_contact_list(uuid,text,text) to authenticated;

create or replace function public.add_contact_to_list(p_org uuid,p_list uuid,p_contact uuid,p_add boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.can_manage_contacts(p_org) then raise exception 'Not authorized'; end if;
 if p_add then
  insert into public.contact_list_members(organization_id,list_id,contact_id) values(p_org,p_list,p_contact)
  on conflict(list_id,contact_id) do nothing;
 else
  delete from public.contact_list_members where organization_id=p_org and list_id=p_list and contact_id=p_contact;
 end if;
end;$$;
revoke all on function public.add_contact_to_list(uuid,uuid,uuid,boolean) from public,anon;
grant execute on function public.add_contact_to_list(uuid,uuid,uuid,boolean) to authenticated;

create or replace function public.save_contact_segment(p_org uuid,p_name text,p_description text,p_rules jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not public.can_manage_contacts(p_org) then raise exception 'Not authorized'; end if;
 if length(btrim(coalesce(p_name,''))) not between 2 and 100 or length(coalesce(p_description,''))>500 then raise exception 'Invalid segment'; end if;
 if p_rules is null or jsonb_typeof(p_rules)<>'object' or length(p_rules::text)>1000 or
    (p_rules - 'consent_status' - 'source' - 'has_email') <> '{}'::jsonb or
    (p_rules ? 'consent_status' and p_rules->>'consent_status' not in ('unknown','granted','denied')) or
    (p_rules ? 'source' and p_rules->>'source' not in ('manual','import')) or
    (p_rules ? 'has_email' and jsonb_typeof(p_rules->'has_email')<>'boolean') then raise exception 'Unsupported segment rules'; end if;
 if p_rules='{}'::jsonb then raise exception 'At least one condition is required'; end if;
 insert into public.contact_segments(organization_id,name,description,rules,created_by)
 values(p_org,btrim(p_name),coalesce(p_description,''),p_rules,auth.uid()) returning id into v_id;
 return v_id;
end;$$;
revoke all on function public.save_contact_segment(uuid,text,text,jsonb) from public,anon;
grant execute on function public.save_contact_segment(uuid,text,text,jsonb) to authenticated;

create or replace function public.import_contact_batch(p_org uuid,p_batch_key uuid,p_rows jsonb)
returns table(inserted integer,skipped integer,rejected integer)
language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_row jsonb; v_email text; v_phone text; v_first text; v_last text;
 v_inserted integer:=0; v_skipped integer:=0; v_rejected integer:=0; v_rows_count int; v_attributes jsonb;
begin
 if not public.can_manage_contacts(p_org) then raise exception 'Not authorized'; end if;
 if p_batch_key is null or p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'Invalid import request'; end if;
 v_rows_count:=jsonb_array_length(p_rows);
 if v_rows_count<1 or v_rows_count>100 or length(p_rows::text)>100000 then raise exception 'Batch exceeds import limits'; end if;
 insert into public.contact_import_batches(organization_id,batch_key,imported_by)
 values(p_org,p_batch_key,auth.uid()) on conflict(organization_id,batch_key) do nothing returning id into v_id;
 if v_id is null then
   return query select b.inserted_count,b.skipped_count,b.rejected_count from public.contact_import_batches b
   where b.organization_id=p_org and b.batch_key=p_batch_key;
   return;
 end if;
 for v_row in select value from jsonb_array_elements(p_rows) loop
  v_email:=nullif(lower(btrim(coalesce(v_row->>'email',''))),'');
  v_phone:=nullif(btrim(coalesce(v_row->>'phone','')),'');
  v_first:=btrim(coalesce(v_row->>'first_name',''));
  v_last:=btrim(coalesce(v_row->>'last_name',''));
  v_attributes:=coalesce(v_row->'attributes','{}'::jsonb);
  if jsonb_typeof(v_attributes)<>'object' or length(v_attributes::text)>4000 then
    v_rejected:=v_rejected+1; continue;
  end if;
  if (select count(*) from jsonb_object_keys(v_attributes))>12 or
     exists(select 1 from jsonb_each(v_attributes) a where
      a.key !~ '^[a-z][a-z0-9_]{0,39}$' or jsonb_typeof(a.value)<>'string' or length(a.value#>>'{}')>500) then
      v_rejected:=v_rejected+1; continue;
  end if;
  if jsonb_typeof(v_row)<>'object' or
     (v_email is null and v_phone is null) or
     (v_email is not null and (length(v_email)>254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')) or
     (v_phone is not null and v_phone !~ '^\+[1-9][0-9]{7,14}$') or
     length(v_first)>100 or length(v_last)>100 then
       v_rejected:=v_rejected+1; continue;
  end if;
  -- Conservative deduplication. Never overwrite existing consent, opt-outs or customer records.
  if exists(select 1 from public.contacts c where c.organization_id=p_org
    and ((v_email is not null and c.email=v_email) or (v_phone is not null and c.phone=v_phone))) then
       v_skipped:=v_skipped+1; continue;
  end if;
  begin
   insert into public.contacts(organization_id,first_name,last_name,email,phone,source,consent_status,attributes,created_by)
   values(p_org,v_first,v_last,v_email,v_phone,'import','unknown',v_attributes,auth.uid());
   v_inserted:=v_inserted+1;
  exception when unique_violation then
   -- Another concurrent import may already have inserted the same address.
   v_skipped:=v_skipped+1;
  end;
 end loop;
 update public.contact_import_batches b set inserted_count=v_inserted,skipped_count=v_skipped,rejected_count=v_rejected where b.id=v_id;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details)
 values(p_org,auth.uid(),'contacts.import_batch','contact_import_batch',v_id::text,
 jsonb_build_object('inserted',v_inserted,'skipped',v_skipped,'rejected',v_rejected));
 return query select v_inserted,v_skipped,v_rejected;
end;$$;
revoke all on function public.import_contact_batch(uuid,uuid,jsonb) from public,anon;
grant execute on function public.import_contact_batch(uuid,uuid,jsonb) to authenticated;
