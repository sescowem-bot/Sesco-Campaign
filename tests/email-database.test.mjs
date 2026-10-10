import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
const ids={owner:'10000000-0000-4000-8000-000000000001',a:'10000000-0000-4000-8000-000000000002',b:'10000000-0000-4000-8000-000000000003',viewer:'10000000-0000-4000-8000-000000000004',orgA:'20000000-0000-4000-8000-000000000001',orgB:'20000000-0000-4000-8000-000000000002'};
test('migrations 001–012 and tenant/security flows in isolated PostgreSQL',async t=>{
 const db=new PGlite();t.after(()=>db.close());
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
 create schema auth; create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.role() returns text language sql stable as $$select nullif(current_setting('request.jwt.claim.role',true),'')$$;
 grant usage on schema public,auth to anon,authenticated,service_role;grant execute on function auth.uid() to anon,authenticated,service_role;`);
 for(const name of readdirSync(new URL('../supabase/migrations/',import.meta.url)).filter(n=>n.endsWith('.sql')).sort()) {
  // PGlite has core gen_random_uuid(), but does not ship pgcrypto. All remaining SQL is unchanged.
  const sql=readFileSync(new URL('../supabase/migrations/'+name,import.meta.url),'utf8').replace('create extension if not exists pgcrypto;','');
  await db.exec(sql);
 }
 await db.exec(`grant select,insert,update,delete on all tables in schema public to anon,authenticated,service_role;
 grant usage,select on all sequences in schema public to authenticated,service_role;
 insert into auth.users(id,email,email_confirmed_at) values ('${ids.owner}','owner@example.com',now()),('${ids.a}','a@example.com',now()),('${ids.b}','b@example.com',now()),('${ids.viewer}','viewer@example.com',now());
 insert into public.platform_staff(user_id,role) values ('${ids.owner}','super_admin');
 insert into public.organizations(id,name,slug,status) values('${ids.orgA}','Company A','company-a','active'),('${ids.orgB}','Company B','company-b','active');
 insert into public.organization_members(organization_id,user_id,role) values('${ids.orgA}','${ids.a}','company_admin'),('${ids.orgB}','${ids.b}','company_admin'),('${ids.orgA}','${ids.viewer}','viewer');`);
 await db.exec("insert into subscription_plans(code,name,is_public,is_active) values ('published','Published',true,true),('private','Private',false,true)");
 const as=async(user,role='authenticated')=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.query("select set_config('request.jwt.claim.role',$1,false)",[role]);await db.exec(`set role ${role}`);};
 await t.test('anonymous pricing reads published plans without access to admin functions',async()=>{
  await as('', 'anon');assert.deepEqual((await db.query('select code from subscription_plans')).rows.map(r=>r.code),['published']);
 });
 await t.test('owner alone can enable provider',async()=>{
  await as(ids.a);await assert.rejects(db.query("select admin_email_provider_save('resend',true)"),/Not authorized/);
  await as(ids.owner);await db.query("select admin_email_provider_save('resend',true)");
 });
 let domainId,senderId;
 await t.test('company admin reserves domain; another tenant cannot see or sync it',async()=>{
  await as(ids.a);const result=await db.query('select email_domain_reserve($1,$2,$3) as id',[ids.orgA,'mail.example.com','resend']);domainId=result.rows[0].id;
  await assert.rejects(db.query('select email_domain_sync($1,$2,$3,$4)',[domainId,'provider-id','[]',true]),/permission denied/);
  await as(ids.b);assert.equal((await db.query('select * from sending_domains')).rows.length,0);
  await assert.rejects(db.query('select email_domain_revoke($1,$2)',[ids.orgA,domainId]),/Not authorized/);
 });
 await t.test('unverified domain cannot create sender; service verification permits exact domain',async()=>{
  await as(ids.a);await assert.rejects(db.query('select email_sender_save($1,$2,$3,$4,$5)',[ids.orgA,domainId,'Company','hello@mail.example.com','reply@example.com']),/Verify the domain/);
  await as(ids.owner,'service_role');await db.query('select email_domain_sync($1,$2,$3,$4)',[domainId,'provider-id','[]',true]);
  await as(ids.a);await assert.rejects(db.query('select email_sender_save($1,$2,$3,$4,$5)',[ids.orgA,domainId,'Company','hello@other.example.com','reply@example.com']),/Invalid sender/);
  senderId=(await db.query('select email_sender_save($1,$2,$3,$4,$5) as id',[ids.orgA,domainId,'Company','hello@mail.example.com','reply@example.com'])).rows[0].id;
 });
 await t.test('viewer and other company cannot reserve a test; direct writes are blocked',async()=>{
  await as(ids.viewer);await assert.rejects(db.query('select email_test_reserve($1,$2)',[ids.orgA,senderId]),/Not authorized/);
  await as(ids.b);await assert.rejects(db.query('select email_test_reserve($1,$2)',[ids.orgB,senderId]),/unavailable/);
  await as(ids.a);await assert.rejects(db.query("insert into email_provider_settings(provider) values('brevo')"),/row-level security/);
 });
 await t.test('test quota reserves before delivery and blocks immediate duplicate',async()=>{
  await as(ids.a);await db.query('select email_test_reserve($1,$2)',[ids.orgA,senderId]);
  await assert.rejects(db.query('select email_test_reserve($1,$2)',[ids.orgA,senderId]),/Test limit|spacing/);
 });
 let campaignId;
 await t.test('campaign drafts reject other-tenant senders and count only opted-in contacts',async()=>{
  await db.exec('reset role');
  await db.query("insert into contacts(organization_id,first_name,email,consent_status,consent_evidence,consent_recorded_at) values ($1,'Opted','opted@example.com','granted','Written consent',now()),($1,'Unknown','unknown@example.com','unknown',null,null),($1,'Denied','denied@example.com','denied',null,null)",[ids.orgA]);
  await db.query("insert into organization_branding(organization_id,display_name,postal_address) values($1,'Company A','12 Main Street')",[ids.orgA]);
  await as(ids.a);
  assert.equal((await db.query("select campaign_audience_count($1,'all',null) as count",[ids.orgA])).rows[0].count,1);
  const design=JSON.stringify({version:'1',blocks:[{type:'heading',text:'Hello {{first_name}}'}]});
  const args=[ids.orgA,null,0,'Campaign A','Hello','',design,senderId,'all',null,null];
  campaignId=(await db.query('select campaign_save($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) as id',args)).rows[0].id;
  await as(ids.b);await assert.rejects(db.query('select campaign_save($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',[ids.orgB,null,0,'Campaign B','Hello','',design,senderId,'all',null,null]),/Sender unavailable/);
  assert.equal((await db.query('select * from campaign_drafts')).rows.length,0);
 });
 await t.test('direct campaign RPC rejects invalid variables and another-tenant audiences',async()=>{
  await db.exec('reset role');const listId=(await db.query("insert into contact_lists(organization_id,name) values($1,'Other list') returning id",[ids.orgB])).rows[0].id;
  await as(ids.a);const bad=JSON.stringify({version:'1',blocks:[{type:'heading',text:'{{password}}'}]});
  await assert.rejects(db.query('select campaign_save($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',[ids.orgA,null,0,'Bad campaign','Hello','',bad,senderId,'all',null,null]),/Unsupported personalization/);
  const good=JSON.stringify({version:'1',blocks:[{type:'heading',text:'Hello'}]});
  await assert.rejects(db.query('select campaign_save($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',[ids.orgA,null,0,'Bad audience','Hello','',good,senderId,'list',listId,null]),/List unavailable/);
 });
 await t.test('campaign revisions prevent stale writes and self approval; owner can independently approve',async()=>{
  await as(ids.a);
  await db.query("select campaign_transition($1,$2,1,'submit','')",[ids.orgA,campaignId]);
  await assert.rejects(db.query("select campaign_transition($1,$2,1,'withdraw','')",[ids.orgA,campaignId]),/Campaign changed/);
  await assert.rejects(db.query("select campaign_transition($1,$2,2,'approve','')",[ids.orgA,campaignId]),/different authorized person/);
  await as(ids.owner);await db.query("select campaign_transition($1,$2,2,'approve','Checked')",[ids.orgA,campaignId]);
  assert.equal((await db.query('select status from campaign_drafts where id=$1',[campaignId])).rows[0].status,'approved');
  assert.equal((await db.query('select count(*)::int as count from campaign_revisions where campaign_id=$1',[campaignId])).rows[0].count,3);
  await as(ids.a);const design=JSON.stringify({version:'1',blocks:[{type:'heading',text:'Revised'}]});
  await db.query('select campaign_save($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',[ids.orgA,campaignId,3,'Revised campaign','Revised','',design,senderId,'all',null,null]);
  const result=(await db.query('select status,reviewed_by from campaign_drafts where id=$1',[campaignId])).rows[0];assert.equal(result.status,'draft');assert.equal(result.reviewed_by,null);
 });
 await t.test('viewer cannot edit or transition campaigns and history is read-only',async()=>{
  await as(ids.viewer);await assert.rejects(db.query("select campaign_transition($1,$2,4,'submit','')",[ids.orgA,campaignId]),/Not authorized/);
  await as(ids.a);const update=await db.query("update campaign_revisions set snapshot='{}' where campaign_id=$1 returning id",[campaignId]);assert.equal(update.rows.length,0);
 });
 let runId;
 await t.test('queue freezes approved content and prevents duplicate enqueue',async()=>{
  await db.exec('reset role');
  const plan=(await db.query("insert into subscription_plans(code,name,limits) values('queue_test','Queue test','{\"monthly_emails\":10}') returning id")).rows[0].id;
  await db.query("insert into organization_subscriptions(organization_id,plan_id,status,starts_at) values($1,$2,'active',now())",[ids.orgA,plan]);
  await db.query("insert into contacts(organization_id,first_name,email,consent_status,consent_evidence,consent_recorded_at) values($1,'Second','second@example.com','granted','Written consent',now())",[ids.orgA]);
  await db.exec("update email_provider_settings set last_dispatch_at=now()-interval '1 day'");
  await as(ids.a);await db.query("select campaign_transition($1,$2,4,'submit','')",[ids.orgA,campaignId]);
  await as(ids.owner);await db.query("select campaign_transition($1,$2,5,'approve','Checked')",[ids.orgA,campaignId]);
  await as(ids.a);runId=(await db.query('select campaign_enqueue($1,$2,6) as id',[ids.orgA,campaignId])).rows[0].id;
  await assert.rejects(db.query('select campaign_enqueue($1,$2,6)',[ids.orgA,campaignId]),/already queued/);
  await assert.rejects(db.query("select campaign_transition($1,$2,6,'withdraw','')",[ids.orgA,campaignId]),/Cancel the active/);
  await as(ids.b);assert.equal((await db.query('select * from campaign_runs')).rows.length,0);await assert.rejects(db.query('select delivery_summary($1,$2)',[ids.orgA,runId]),/Not authorized/);
  await as(ids.a);await assert.rejects(db.query('select delivery_claim()'),/permission denied/);
 });
 await t.test('worker rechecks unsubscribe, reserves quotas and persists accepted events idempotently',async()=>{
  await as(ids.owner,'service_role');
  let claim=(await db.query('select delivery_claim() as claim')).rows[0].claim;
  await db.query('select delivery_unsubscribe($1)',[claim.delivery.unsubscribe_token]);
  assert.equal((await db.query('select delivery_begin($1,$2) as decision',[claim.delivery.id,claim.delivery.lease_token])).rows[0].decision,'suppressed');
  claim=(await db.query('select delivery_claim() as claim')).rows[0].claim;
  assert.equal((await db.query('select delivery_begin($1,$2) as decision',[claim.delivery.id,claim.delivery.lease_token])).rows[0].decision,'dispatch');
  await db.query("select delivery_event('resend','early-event','message-queue','delivered',now())");
  await db.query("select delivery_finish($1,$2,'accepted','message-queue','ack')",[claim.delivery.id,claim.delivery.lease_token]);
  assert.equal((await db.query('select status from email_deliveries where id=$1',[claim.delivery.id])).rows[0].status,'delivered');
  await db.query("select delivery_event('resend','early-event','message-queue','delivered',now())");
  assert.equal((await db.query("select count(*)::int as count from email_delivery_events where event_key='early-event'")).rows[0].count,1);
  await db.query("select delivery_event('resend','complaint-event','message-queue','complaint',now())");
  await db.query("select delivery_event('resend','late-delivery','message-queue','delivered',now())");
  assert.equal((await db.query('select status from email_deliveries where id=$1',[claim.delivery.id])).rows[0].status,'complained');
  assert.equal((await db.query('select count(*)::int as count from delivery_quota_reservations')).rows[0].count,1);
  await db.query('select delivery_claim()');
  assert.equal((await db.query('select status from campaign_runs where id=$1',[runId])).rows[0].status,'completed');
 });
 const reportBounds=[new Date(Date.now()-86400000).toISOString(),new Date(Date.now()+86400000).toISOString()];
 const reportQuery='select campaign_analytics($1,$2,$3,$4,$5,$6) as report';
 await t.test('analytics aggregate unique recipients across repeated and overlapping provider events',async()=>{
  await as(ids.owner,'service_role');
  await db.query("select delivery_event('resend','open-1','message-queue','opened',now())");
  await db.query("select delivery_event('resend','open-2','message-queue','opened',now())");
  await db.query("select delivery_event('resend','click-1','message-queue','clicked',now())");
  await as(ids.a);
  const report=(await db.query(reportQuery,[ids.orgA,...reportBounds,null,50,0])).rows[0].report;
  assert.equal(report.total_runs,1);assert.equal(report.totals.recipients,2);assert.equal(report.totals.submitted,1);
  assert.equal(report.totals.delivered,1);assert.equal(report.totals.opened,1);assert.equal(report.totals.clicked,1);
  assert.equal(report.totals.complained,1);assert.equal(report.totals.unsubscribed,1);assert.equal(report.totals.skipped,1);
  assert.equal(report.runs[0].id,runId);assert.equal(report.daily.length,1);assert.equal(report.daily[0].recipients,2);
  const serialized=JSON.stringify(report);assert.ok(!serialized.includes('example.com'));assert.ok(!serialized.includes('unsubscribe_token'));
 });
 await t.test('analytics totals remain complete on empty pagination and absent cohorts',async()=>{
  await as(ids.viewer);
  const report=(await db.query(reportQuery,[ids.orgA,...reportBounds,runId,1,1])).rows[0].report;
  assert.equal(report.runs.length,0);assert.equal(report.total_runs,1);assert.equal(report.totals.recipients,2);
  const empty=(await db.query(reportQuery,[ids.orgA,'2000-01-01','2000-01-02',null,50,0])).rows[0].report;
  assert.equal(empty.total_runs,0);assert.equal(empty.totals.recipients,0);assert.deepEqual(empty.daily,[]);
 });
 await t.test('analytics enforce company scope, anonymous denial and bounded inputs in PostgreSQL',async()=>{
  await as(ids.b);await assert.rejects(db.query(reportQuery,[ids.orgA,...reportBounds,null,50,0]),/Not authorized/);
  await assert.rejects(db.query(reportQuery,[ids.orgB,...reportBounds,runId,50,0]),/Run unavailable/);
  await as(ids.owner);assert.equal((await db.query(reportQuery,[ids.orgA,...reportBounds,null,50,0])).rows[0].report.total_runs,1);
  await assert.rejects(db.query(reportQuery,[ids.orgA,'2020-01-01','2022-01-01',null,50,0]),/Invalid report range/);
  await assert.rejects(db.query(reportQuery,[ids.orgA,...reportBounds,null,1001,0]),/Invalid report range/);
  await as('', 'anon');await assert.rejects(db.query(reportQuery,[ids.orgA,...reportBounds,null,50,0]),/permission denied/);
 });
 await t.test('expired leases recover safely without retrying uncertain external sends',async()=>{
  await db.exec('reset role; set role service_role');
  const row=(await db.query('select id from email_deliveries where run_id=$1 limit 1',[runId])).rows[0];
  await db.query("update email_deliveries set status='leased',lease_token=gen_random_uuid(),lease_until=now()-interval '1 minute' where id=$1",[row.id]);
  await db.query('select delivery_recover()');
  assert.equal((await db.query('select status,lease_token from email_deliveries where id=$1',[row.id])).rows[0].status,'pending');
  await db.query("update email_deliveries set status='dispatching',lease_token=gen_random_uuid(),lease_until=now()-interval '1 minute' where id=$1",[row.id]);
  await db.query('select delivery_recover()');
  const recovered=(await db.query('select status,reason from email_deliveries where id=$1',[row.id])).rows[0];
  assert.equal(recovered.status,'unknown');assert.equal(recovered.reason,'dispatch_lease_expired');
  await db.query('select delivery_recover()');assert.equal((await db.query('select status from email_deliveries where id=$1',[row.id])).rows[0].status,'unknown');
 });
 await t.test('payment finalization verifies amount, identity and purchased interval idempotently',async()=>{
  await db.exec('reset role');
  const plan=(await db.query("insert into subscription_plans(code,name,price_ngn_kobo,billing_interval,is_public,limits) values('payment_test','Payment test',10000,'month',true,'{}') returning id")).rows[0].id;
  const ref='scc_'+'1'.repeat(32),other='scc_'+'2'.repeat(32),bad='scc_'+'3'.repeat(32);
  await as(ids.b);await assert.rejects(db.query('select * from payment_start($1,$2,$3)',[ids.orgA,plan,ref]),/Not authorized/);
  await as(ids.a);await db.query('select * from payment_start($1,$2,$3)',[ids.orgA,plan,ref]);await db.query('select * from payment_start($1,$2,$3)',[ids.orgA,plan,other]);await db.query('select * from payment_start($1,$2,$3)',[ids.orgA,plan,bad]);
  await assert.rejects(db.query("select payment_finalize($1,'txn-1',10000,'NGN',now())",[ref]),/permission denied/);
  await db.exec('reset role');await db.query("update subscription_plans set billing_interval='year' where id=$1",[plan]);
  await as(ids.owner,'service_role');
  assert.equal((await db.query("select payment_finalize($1,'txn-bad',9000,'NGN',now()) as result",[bad])).rows[0].result,'payment_mismatch');
  assert.equal((await db.query("select payment_finalize($1,'txn-1',10000,'NGN',now()) as result",[ref])).rows[0].result,'activated');
  assert.equal((await db.query("select payment_finalize($1,'txn-1',10000,'NGN',now()) as result",[ref])).rows[0].result,'already_processed');
  assert.equal((await db.query("select payment_finalize($1,'txn-1',10000,'NGN',now()) as result",[other])).rows[0].result,'transaction_conflict');
  const active=(await db.query("select expires_at from organization_subscriptions where organization_id=$1 and status='active'",[ids.orgA])).rows;
  assert.equal(active.length,1);assert.ok(new Date(active[0].expires_at).valueOf()<Date.now()+40*86400000);
  assert.equal((await db.query("select count(*)::int as count from audit_logs where action='subscription.payment_activated'")).rows[0].count,1);
  await db.query("select set_config('request.jwt.claim.role','',false)");await assert.rejects(db.query("select payment_finalize($1,'txn-2',10000,'NGN',now())",[other]),/Service role required/);
  await as(ids.a);for(const digit of ['4','5'])await db.query('select * from payment_start($1,$2,$3)',[ids.orgA,plan,'scc_'+digit.repeat(32)]);
  await assert.rejects(db.query('select * from payment_start($1,$2,$3)',[ids.orgA,plan,'scc_'+'6'.repeat(32)]),/Wait before/);
 });
 await t.test('CMS publication hides drafts and rejects stale or unauthorized edits',async()=>{
  await as(ids.a);await assert.rejects(db.query("select cms_edit('about',0,'save','{}')"),/Not authorized/);
  await as(ids.owner);await db.query("select cms_edit('about',0,'save',$1)",[JSON.stringify({title:'Private draft'})]);
  await as('', 'anon');assert.equal((await db.query("select cms_public('about') as content")).rows[0].content,null);
  assert.equal((await db.query('select * from site_pages')).rows.length,0);
  await as(ids.owner);await db.query("select cms_edit('about',1,'publish',null)");
  await assert.rejects(db.query("select cms_edit('about',1,'save','{}')"),/Page changed/);
  await as('', 'anon');assert.equal((await db.query("select cms_public('about') as content")).rows[0].content.title,'Private draft');
  await as(ids.owner);await db.query("select cms_edit('about',2,'save',$1)",[JSON.stringify({title:'New private draft'})]);
  await as('', 'anon');assert.equal((await db.query("select cms_public('about') as content")).rows[0].content.title,'Private draft');
  await as(ids.owner);await db.query("select cms_edit('about',3,'unpublish',null)");
  assert.equal((await db.query("select count(*)::int as count from site_page_revisions where slug='about'")).rows[0].count,4);
  await as('', 'anon');assert.equal((await db.query("select cms_public('about') as content")).rows[0].content,null);
 });
 await t.test('team administration protects company scope and last administrator',async()=>{
  await as(ids.viewer);await assert.rejects(db.query('select team_members($1)',[ids.orgA]),/Not authorized/);
  await assert.rejects(db.query("select team_member_save($1,'b@example.com','manager')",[ids.orgA]),/Not authorized/);
  await as(ids.b);await assert.rejects(db.query('select team_members($1)',[ids.orgA]),/Not authorized/);
  await as(ids.a);await assert.rejects(db.query("select team_member_save($1,'a@example.com','viewer')",[ids.orgA]),/Keep at least/);
  await assert.rejects(db.query("select team_member_save($1,'missing@example.com','viewer')",[ids.orgA]),/verified account/);
  await db.query("select team_member_save($1,'viewer@example.com','manager')",[ids.orgA]);
  assert.equal((await db.query('select team_members($1) as members',[ids.orgA])).rows[0].members.find(m=>m.id===ids.viewer).role,'manager');
  await db.query("select team_member_save($1,'viewer@example.com','viewer')",[ids.orgA]);
 });
 await t.test('company status and quota controls require owner and preserve other overrides',async()=>{
  await as(ids.a);await assert.rejects(db.query("select admin_company_settings($1,'suspended',0)",[ids.orgA]),/Not authorized/);
  await db.exec('reset role');await db.query("update campaign_runs set status='queued' where id=$1",[runId]);await db.query("update organization_subscriptions set quota_overrides=$2 where organization_id=$1 and status='active'",[ids.orgA,JSON.stringify({contacts:200})]);
  await as(ids.owner);await db.query("select admin_company_settings($1,'suspended',25)",[ids.orgA]);
  assert.equal((await db.query('select status from campaign_runs where id=$1',[runId])).rows[0].status,'paused');
  assert.equal((await db.query('select can_manage_team($1) as allowed',[ids.orgA])).rows[0].allowed,true);
  await as(ids.a);assert.equal((await db.query('select can_manage_team($1) as allowed',[ids.orgA])).rows[0].allowed,false);
  await as(ids.owner);await db.query("select admin_company_settings($1,'active',null)",[ids.orgA]);
  const overrides=(await db.query("select quota_overrides from organization_subscriptions where organization_id=$1 and status='active'",[ids.orgA])).rows[0].quota_overrides;
  assert.deepEqual(overrides,{contacts:200});
 });
 await t.test('revocation deactivates senders and cannot be undone by a provider callback',async()=>{
  await as(ids.a);await db.query('select email_domain_revoke($1,$2)',[ids.orgA,domainId]);assert.equal((await db.query('select is_active from sender_identities where id=$1',[senderId])).rows[0].is_active,false);
  await as(ids.owner,'service_role');await assert.rejects(db.query('select email_domain_sync($1,$2,$3,$4)',[domainId,'provider-id','[]',true]),/unavailable/);
 });
 await t.test('suspended workspace cannot manage senders',async()=>{
  await db.exec('reset role');await db.query("update organizations set status='suspended' where id=$1",[ids.orgA]);
  await as(ids.a);assert.equal((await db.query('select can_manage_senders($1) as allowed',[ids.orgA])).rows[0].allowed,false);
 });
});
