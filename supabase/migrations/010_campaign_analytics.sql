begin;

-- Keep reporting aggregate-only. Raw recipients, tokens and events remain service-only.
alter table public.email_deliveries add column unsubscribe_recorded_at timestamptz;
create index analytics_runs_cohort on public.campaign_runs(organization_id,created_at desc,id);
create index analytics_delivery_events on public.email_delivery_events(delivery_id,event_type) where delivery_id is not null;

create or replace function public.delivery_unsubscribe(p_token uuid) returns void language plpgsql security definer set search_path='' as $$
declare d public.email_deliveries;
begin
 select * into d from public.email_deliveries where unsubscribe_token=p_token;
 if not found then return;end if;
 insert into public.email_suppressions(organization_id,email,reason) values(d.organization_id,d.recipient_email,'unsubscribe') on conflict(organization_id,email) do nothing;
 update public.contacts set unsubscribed_at=coalesce(unsubscribed_at,now()),consent_status='denied',updated_at=now() where organization_id=d.organization_id and email=d.recipient_email;
 update public.email_deliveries set unsubscribe_recorded_at=coalesce(unsubscribe_recorded_at,now()) where id=d.id;
end;$$;
revoke all on function public.delivery_unsubscribe(uuid) from public,anon,authenticated;
grant execute on function public.delivery_unsubscribe(uuid) to service_role;

create function public.campaign_analytics(p_org uuid,p_from timestamptz,p_until timestamptz,p_run uuid default null,p_limit integer default 50,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
 if not(public.is_organization_member(p_org) or public.is_platform_super_admin()) then raise exception 'Not authorized';end if;
 if p_org is null or p_from is null or p_until is null or p_until<=p_from or p_until-p_from>interval '366 days'
 or p_limit is null or p_limit not between 1 and 1000 or p_offset is null or p_offset not between 0 and 100000 then raise exception 'Invalid report range';end if;
 if p_run is not null and not exists(select 1 from public.campaign_runs where id=p_run and organization_id=p_org) then raise exception 'Run unavailable';end if;
 with cohort as materialized (
  select r.id,r.snapshot->'campaign'->>'name' as name,r.provider,r.status,r.created_at,r.scheduled_at
  from public.campaign_runs r where r.organization_id=p_org and r.created_at>=p_from and r.created_at<p_until and (p_run is null or r.id=p_run)
 ), flags as (
  select d.run_id,d.status,d.provider_message_id is not null as submitted,d.attempts,
   coalesce(e.delivered,false) as delivered,coalesce(e.opened,false) as opened,coalesce(e.clicked,false) as clicked,
   coalesce(e.bounced,false) as bounced,coalesce(e.complained,false) as complained,
   (d.unsubscribe_recorded_at is not null or coalesce(e.unsubscribed,false)) as unsubscribed
  from public.email_deliveries d join cohort c on c.id=d.run_id
  left join lateral (select bool_or(event_type='delivered') as delivered,bool_or(event_type='opened') as opened,bool_or(event_type='clicked') as clicked,
   bool_or(event_type='bounce') as bounced,bool_or(event_type='complaint') as complained,bool_or(event_type='unsubscribe') as unsubscribed
   from public.email_delivery_events where delivery_id=d.id) e on true
  where d.organization_id=p_org
 ), metrics as materialized (
  select c.id,c.name,c.provider,c.status,c.created_at,c.scheduled_at,
   count(f.run_id) as recipients,count(*) filter(where f.submitted) as submitted,
   count(*) filter(where f.delivered) as delivered,count(*) filter(where f.opened) as opened,count(*) filter(where f.clicked) as clicked,
   count(*) filter(where f.bounced) as bounced,count(*) filter(where f.complained) as complained,count(*) filter(where f.unsubscribed) as unsubscribed,
   count(*) filter(where f.status='failed') as failed,count(*) filter(where f.status='unknown') as unknown,
   count(*) filter(where f.status='skipped') as skipped,count(*) filter(where f.status in ('pending','leased','dispatching')) as waiting,
   coalesce(sum(f.attempts),0) as attempts
  from cohort c left join flags f on f.run_id=c.id group by c.id,c.name,c.provider,c.status,c.created_at,c.scheduled_at
 ), daily as (
  select (created_at at time zone 'UTC')::date as day,count(*) as runs,sum(recipients) as recipients,sum(submitted) as submitted,sum(delivered) as delivered
  from metrics group by (created_at at time zone 'UTC')::date
 )
 select jsonb_build_object('generated_at',now(),'total_runs',(select count(*) from metrics),
  'totals',(select jsonb_build_object('recipients',coalesce(sum(recipients),0),'submitted',coalesce(sum(submitted),0),'delivered',coalesce(sum(delivered),0),
   'opened',coalesce(sum(opened),0),'clicked',coalesce(sum(clicked),0),'bounced',coalesce(sum(bounced),0),'complained',coalesce(sum(complained),0),
   'unsubscribed',coalesce(sum(unsubscribed),0),'failed',coalesce(sum(failed),0),'unknown',coalesce(sum(unknown),0),'skipped',coalesce(sum(skipped),0),
   'waiting',coalesce(sum(waiting),0),'attempts',coalesce(sum(attempts),0)) from metrics),
  'runs',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc) from (select * from metrics order by created_at desc,id desc limit p_limit offset p_offset) x),'[]'::jsonb),
  'daily',coalesce((select jsonb_agg(to_jsonb(daily) order by day) from daily),'[]'::jsonb)) into v_result;
 return v_result;
end;$$;
revoke all on function public.campaign_analytics(uuid,timestamptz,timestamptz,uuid,integer,integer) from public,anon;
grant execute on function public.campaign_analytics(uuid,timestamptz,timestamptz,uuid,integer,integer) to authenticated;
commit;
