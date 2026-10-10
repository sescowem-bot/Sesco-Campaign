-- Apply after 013. Repeatable owner campaign preview upgrade.
begin;
alter table public.email_test_attempts add column if not exists campaign_id uuid references public.campaign_drafts(id);
alter table public.email_test_attempts add column if not exists campaign_revision integer check(campaign_revision>0);
alter table public.email_test_attempts drop constraint if exists email_test_attempts_status_check;
alter table public.email_test_attempts add constraint email_test_attempts_status_check check(status in ('reserved','accepted','unknown','not_sent'));
create or replace function public.owner_campaign_test_reserve(p_org uuid,p_campaign uuid,p_revision integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.campaign_drafts;s public.sender_identities;b public.organization_branding;v_attempt uuid;v_email text;
begin
 if not public.is_owner_workspace(p_org) or not public.can_edit_campaigns(p_org) then raise exception 'Owner campaign testing requires your active brand workspace'; end if;
 select email into v_email from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if v_email is null then raise exception 'Verified account email required'; end if;
 select * into c from public.campaign_drafts where id=p_campaign and organization_id=p_org;
 if not found or c.status='archived' then raise exception 'Saved active campaign required'; end if;
 if c.revision is distinct from p_revision then raise exception 'Campaign changed. Reload before testing'; end if;
 select * into s from public.sender_identities where id=c.sender_id and organization_id=p_org and is_active;
 if not found then raise exception 'Select a verified sender and save your draft first'; end if;
 select * into b from public.organization_branding where organization_id=p_org;
 if length(trim(coalesce(b.postal_address,'')))<6 then raise exception 'Save your business postal address before testing'; end if;
 -- Shared provider and workspace quotas include configuration tests and campaign tests.
 v_attempt=public.email_test_reserve(p_org,c.sender_id);
 update public.email_test_attempts set campaign_id=c.id,campaign_revision=c.revision where id=v_attempt;
 insert into public.audit_logs(organization_id,actor_id,action,entity_type,entity_id,details)
 values(p_org,auth.uid(),'campaign.test_reserved','campaign',c.id::text,jsonb_build_object('revision',c.revision,'attempt',v_attempt));
 return jsonb_build_object('attempt',v_attempt,'campaign',to_jsonb(c),'sender',to_jsonb(s),'brand',to_jsonb(b),'recipient',v_email);
end;$$;
revoke all on function public.owner_campaign_test_reserve(uuid,uuid,integer) from public,anon;
grant execute on function public.owner_campaign_test_reserve(uuid,uuid,integer) to authenticated;
commit;
