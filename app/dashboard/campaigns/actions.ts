'use server';
import {revalidatePath} from 'next/cache';
import {z} from 'zod';
import {supabaseServer} from '@/lib/supabase/server';
import {sendSavedCampaignTest} from '@/lib/campaigns/test-send';
import {emailServiceDb,refreshDomain} from '@/lib/email/server';
import {campaignDesign,renderCampaign} from '@/lib/campaigns/render';
export type CampaignResult={error?:string;success?:string;id?:string};
export async function campaignAction(_:CampaignResult,form:FormData):Promise<CampaignResult> {
 try {
  const org=z.string().uuid().parse(form.get('organization_id'));
  const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user?.email_confirmed_at)throw new Error('Verified sign-in required.');
  const action=String(form.get('action'));
  const revision=z.coerce.number().int().nonnegative().parse(form.get('revision')||0);
  if(action==='save') {
   const {data:allowed}=await db.rpc('can_edit_campaigns',{p_org:org});if(!allowed)throw new Error('Campaign editing access required.');
   const design=campaignDesign.parse(JSON.parse(String(form.get('design'))));
   const subject=z.string().trim().min(1).max(200).refine(s=>!/[\r\n]/.test(s)).parse(form.get('subject'));
   renderCampaign({design,subject,company:'Your company',address:'Preview address'});
   const type=z.enum(['all','list','segment']).parse(form.get('audience_type'));
   const rawTime=String(form.get('requested_send_at')||'');
   if(rawTime&&!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(rawTime))throw new Error('Invalid requested UTC time.');
   const scheduled=rawTime?rawTime+'Z':'';
   if(scheduled&&(!Number.isFinite(Date.parse(scheduled))||Date.parse(scheduled)<=Date.now()))throw new Error('Choose a future requested send time.');
   const {data:id,error}=await db.rpc('campaign_save',{p_org:org,p_id:form.get('campaign_id')?z.string().uuid().parse(form.get('campaign_id')):null,p_expected:revision,p_name:z.string().trim().min(2).max(120).parse(form.get('name')),p_subject:subject,p_preheader:z.string().max(250).parse(form.get('preheader')||''),p_design:design,p_sender:form.get('sender_id')?z.string().uuid().parse(form.get('sender_id')):null,p_type:type,p_audience:type==='all'?null:z.string().uuid().parse(form.get('audience_id')),p_requested:scheduled?new Date(scheduled).toISOString():null});
   if(error)throw new Error(error.message);
   revalidatePath('/dashboard/campaigns');return {id,success:'Draft saved. Open the saved campaign to prepare approval and delivery.'};
  }
  const id=z.string().uuid().parse(form.get('campaign_id'));
  if(action==='test') {
   const result=await sendSavedCampaignTest({
    reserve:async()=>{const {data,error}=await db.rpc('owner_campaign_test_reserve',{p_org:org,p_campaign:id,p_revision:revision});if(error)throw new Error(error.message);return data;},
    verify:async domain=>{const checked=await refreshDomain(org,domain);return {verified:checked.verified,domain:checked.row.domain,send:checked.adapter.sendTest};},
    record:async(attempt,status,message)=>{const {error}=await emailServiceDb().from('email_test_attempts').update({status,provider_message_id:message||null}).eq('id',attempt).eq('organization_id',org).eq('actor_id',user.id).eq('status','reserved');if(error)throw new Error('Test history could not be saved.');}
   });
   revalidatePath('/dashboard/campaigns');revalidatePath('/dashboard/senders');return result;
  }
  const transition=z.enum(['submit','approve','reject','withdraw','archive','owner_approve']).parse(action);
  // Validate the stored design on review too; direct database drafts cannot bypass render validation.
  if(transition==='submit'||transition==='approve'||transition==='owner_approve') {
   const {data:row,error}=await db.from('campaign_drafts').select('design,subject').eq('id',id).eq('organization_id',org).single();if(error||!row)throw new Error('Campaign unavailable.');
   renderCampaign({design:row.design,subject:row.subject,company:'Your company',address:'Preview address'});
  }
  const {error}=await db.rpc('campaign_transition',{p_org:org,p_id:id,p_expected:revision,p_action:transition,p_note:z.string().max(1000).parse(form.get('review_note')||'')});if(error)throw new Error(error.message);
  revalidatePath('/dashboard/campaigns');return {success:transition==='approve'?'Campaign approved. Open Delivery queue to prepare dispatch.':'Campaign status updated.'};
 }catch(e){return {error:e instanceof Error?e.message:'Campaign request failed.'};}
}
