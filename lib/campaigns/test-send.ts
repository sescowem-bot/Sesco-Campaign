import {z} from 'zod';
import {renderCampaign} from './render.ts';
const snapshot=z.object({attempt:z.string().uuid(),recipient:z.email(),campaign:z.object({subject:z.string(),design:z.unknown(),preheader:z.string(),revision:z.number().int().positive()}),sender:z.object({domain_id:z.string().uuid(),from_name:z.string(),from_email:z.email(),reply_to:z.email()}),brand:z.object({display_name:z.string(),postal_address:z.string(),primary_color:z.string()})});
type TestInput={name:string;email:string;replyTo:string;to:string;domain:string;subject:string;html:string;attempt:string};
type Dependencies={reserve:()=>Promise<unknown>;verify:(id:string)=>Promise<{verified:boolean;domain:string;send:(input:TestInput)=>Promise<string>}>;record:(id:string,status:'accepted'|'unknown'|'not_sent',message?:string)=>Promise<void>};
/** Reservation chooses the account recipient in PostgreSQL; the browser cannot supply it. */
export async function sendSavedCampaignTest(deps:Dependencies):Promise<{success?:string;error?:string}> {
 const saved=snapshot.parse(await deps.reserve());
 let submitted=false;
 try {
  const rendered=renderCampaign({design:saved.campaign.design,subject:saved.campaign.subject,preheader:saved.campaign.preheader,company:saved.brand.display_name,address:saved.brand.postal_address,color:saved.brand.primary_color,contact:{first_name:'Test reader',email:saved.recipient},testPreview:true});
  const checked=await deps.verify(saved.sender.domain_id);
  if(!checked.verified)throw new Error('Sender verification failed. No test email was sent.');
  submitted=true;
  const message=await checked.send({name:saved.sender.from_name,email:saved.sender.from_email,replyTo:saved.sender.reply_to,to:saved.recipient,domain:checked.domain,subject:'[TEST] '+rendered.subject,html:rendered.html,attempt:saved.attempt});
  try{await deps.record(saved.attempt,'accepted',message);}catch{return {success:'Provider accepted the test, but test history could not be updated. Check the provider dashboard before retrying.'};}
  return {success:`Revision ${saved.campaign.revision} test accepted for ${saved.recipient}. Check your inbox and spam folder. This did not approve or queue the campaign.`};
 }catch(e){
  try{await deps.record(saved.attempt,submitted?'unknown':'not_sent');}catch{/* Keep the reservation so an uncertain send is not silently retried. */}
  return {error:submitted?'Test outcome is unconfirmed. Check the provider dashboard before retrying. No automatic retry was performed.':e instanceof Error?e.message:'Test preparation failed. No email was sent.'};
 }
}
