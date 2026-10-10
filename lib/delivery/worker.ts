import 'server-only';
import {emailServiceDb,refreshDomain} from '@/lib/email/server';
import {renderCampaign,type PreviewContact} from '@/lib/campaigns/render';
import {sendQueuedEmail} from './transport';
import {z} from 'zod';
const claimSchema=z.object({delivery:z.object({id:z.string().uuid(),organization_id:z.string().uuid(),lease_token:z.string().uuid(),recipient_email:z.string(),recipient:z.custom<PreviewContact>(),unsubscribe_token:z.string().uuid()}),run:z.object({id:z.string().uuid(),provider:z.enum(['resend','brevo']),snapshot:z.object({campaign:z.object({design:z.unknown(),subject:z.string(),preheader:z.string()}),sender:z.object({id:z.string().uuid(),domain_id:z.string().uuid(),from_name:z.string(),from_email:z.string(),reply_to:z.string()}),brand:z.object({display_name:z.string(),postal_address:z.string(),primary_color:z.string()})})})});
export async function processDelivery() {
 if(process.env.EMAIL_DELIVERY_ENABLED!=='true')return {result:'disabled'};
 const url=process.env.NEXT_PUBLIC_APP_URL;if(!url)throw new Error('Public application URL is missing');
 const origin=new URL(url);if(origin.protocol!=='https:'||origin.username||origin.password||origin.pathname!=='/'||origin.search||origin.hash)throw new Error('Public application URL must be an HTTPS origin');
 const db=emailServiceDb();const {error:recovery}=await db.rpc('delivery_recover');if(recovery)throw new Error('Lease recovery failed');const {data:claim,error}=await db.rpc('delivery_claim');if(error)throw new Error('Queue claim failed');if(!claim)return {result:'idle'};
 const parsed=claimSchema.safeParse(claim);if(!parsed.success)throw new Error('Invalid queue snapshot');
 const {delivery:d,run:r}=parsed.data;
 const unsubscribe=new URL('/api/email/unsubscribe',origin);unsubscribe.searchParams.set('token',d.unsubscribe_token);
 let domain:string,html:string,subject:string,key:string;
 try {
  key=process.env[r.provider==='resend'?'RESEND_API_KEY':'BREVO_API_KEY']||'';if(!key)throw new Error('Provider key missing');
  const fresh=await refreshDomain(d.organization_id,r.snapshot.sender.domain_id);if(!fresh.verified)throw new Error('Fresh domain ownership or authentication failed');domain=fresh.row.domain;
  const rendered=renderCampaign({design:r.snapshot.campaign.design,subject:r.snapshot.campaign.subject,preheader:r.snapshot.campaign.preheader,company:r.snapshot.brand.display_name,address:r.snapshot.brand.postal_address,color:r.snapshot.brand.primary_color,contact:d.recipient,unsubscribeUrl:unsubscribe.href});html=rendered.html;subject=rendered.subject;
 }catch{
  const {error}=await db.rpc('delivery_hold',{p_id:d.id,p_lease:d.lease_token,p_reason:'Preparation failed: verify domain, credentials and campaign content'});if(error)throw new Error('Queue hold failed');return {result:'paused'};
 }
 const {data:decision,error:begin}=await db.rpc('delivery_begin',{p_id:d.id,p_lease:d.lease_token});if(begin)throw new Error('Dispatch reservation failed');if(decision!=='dispatch')return {result:String(decision)};
 let result;
 try{result=await sendQueuedEmail({provider:r.provider,key,id:d.id,name:r.snapshot.sender.from_name,from:r.snapshot.sender.from_email,replyTo:r.snapshot.sender.reply_to,domain,to:d.recipient_email,subject,html,unsubscribe:unsubscribe.href});}catch{result={status:'failed' as const,reason:'invalid_dispatch_content'};}
 const {error:finish}=await db.rpc('delivery_finish',{p_id:d.id,p_lease:d.lease_token,p_status:result.status,p_message:result.message||null,p_reason:result.reason});
 if(finish)throw new Error('Delivery outcome could not be saved. Do not manually resend; inspect the provider.');
 if(result.status==='unknown'||['provider_http_401','provider_http_403'].includes(result.reason))await db.from('campaign_runs').update({status:'paused',last_error:result.reason}).eq('id',r.id).in('status',['queued','running']);
 return {result:result.status};
}
