'use server';
import {revalidatePath} from 'next/cache';
import {z} from 'zod';
import {senderAccess,emailServiceDb,providerFor,refreshDomain} from '@/lib/email/server';
import {domainName,mailbox,senderName,matchesDomain,escapeHtml} from '@/lib/email/validation';
export type SenderResult={error?:string;success?:string};
const uuid=(form:FormData,key:string)=>z.string().uuid().parse(form.get(key));
export async function senderAction(_:SenderResult,form:FormData):Promise<SenderResult> {
  try {
    const org=uuid(form,'organization_id');
    const {db,user}=await senderAccess(org);
    const action=String(form.get('action'));
    if(action==='add_domain') {
      const domain=domainName(String(form.get('domain')||''));
      const provider=z.enum(['resend','brevo']).parse(form.get('provider'));
      const adapter=await providerFor(provider);
      const {data:id,error}=await db.rpc('email_domain_reserve',{p_org:org,p_domain:domain,p_provider:provider});
      if(error) throw new Error(error.message);
      try {
        const state=await adapter.create(domain);
        const {error:save}=await emailServiceDb().rpc('email_domain_sync',{p_id:id,p_provider_id:state.id,p_records:state.records,p_verified:false});
        if(save) throw new Error('Could not persist provider registration.');
      } catch {
        revalidatePath('/dashboard/senders');
        return {error:'Domain reserved, but provider setup needs reconciliation. Ask the platform administrator to check the provider dashboard and link its domain ID. Do not repeatedly register the domain.'};
      }
    } else if(action==='check_domain') {
      const id=uuid(form,'domain_id');
      const {error}=await db.rpc('email_domain_claim_check',{p_org:org,p_id:id});
      if(error) throw new Error(error.message);
      const result=await refreshDomain(org,id,true);
      revalidatePath('/dashboard/senders');
      return {success:result.verified?'Domain ownership and provider authentication verified.':'Verification is pending. Check all DNS records and allow time for propagation.'};
    } else if(action==='revoke_domain') {
      const {error}=await db.rpc('email_domain_revoke',{p_org:org,p_id:uuid(form,'domain_id')});
      if(error) throw new Error(error.message);
    } else if(action==='save_sender') {
      const domainId=uuid(form,'domain_id');
      const name=senderName(String(form.get('from_name')||'')),email=mailbox(String(form.get('from_email')||'')),reply=mailbox(String(form.get('reply_to')||''));
      const {data:domain,error:read}=await db.from('sending_domains').select('domain,provider,verification_status').eq('id',domainId).eq('organization_id',org).single();
      if(read||!domain||domain.verification_status!=='verified'||!matchesDomain(email,domain.domain)) throw new Error('Sender must match a verified domain in this workspace.');
      // Brevo may require a separately registered sender; registration is explicit below.
      const {error}=await db.rpc('email_sender_save',{p_org:org,p_domain:domainId,p_name:name,p_email:email,p_reply:reply});
      if(error) throw new Error(error.message);
    } else if(action==='register_brevo_sender') {
      const {data:sender,error}=await db.from('sender_identities').select('*,sending_domains!inner(provider,verification_status)').eq('id',uuid(form,'sender_id')).eq('organization_id',org).single();
      if(error||!sender||!sender.is_active||sender.sending_domains.provider!=='brevo'||sender.sending_domains.verification_status!=='verified') throw new Error('Verified Brevo sender required.');
      await (await providerFor('brevo')).registerSender(sender.from_name,sender.from_email);
    } else if(action==='test') {
      if(!user.email) throw new Error('Verified account email required.');
      const senderId=uuid(form,'sender_id');
      const {data:sender,error:read}=await db.from('sender_identities').select('*').eq('id',senderId).eq('organization_id',org).eq('is_active',true).single();
      if(read||!sender) throw new Error('Sender unavailable.');
      const {verified,adapter,row}=await refreshDomain(org,sender.domain_id);
      if(!verified) throw new Error('Fresh domain verification failed. Test was not sent.');
      const {data:attempt,error}=await db.rpc('email_test_reserve',{p_org:org,p_sender:senderId});
      if(error) throw new Error(error.message);
      const service=emailServiceDb();
      try {
        const messageId=await adapter.sendTest({name:sender.from_name,email:sender.from_email,replyTo:sender.reply_to,to:user.email,domain:row.domain,attempt,html:`<h1>Sender configuration test</h1><p>This test confirms that ${escapeHtml(sender.from_name)} can submit email using ${escapeHtml(sender.from_email)}.</p><p>This is a configuration test, not a campaign.</p>`});
        const {error:log}=await service.from('email_test_attempts').update({status:'accepted',provider_message_id:messageId}).eq('id',attempt).eq('status','reserved');
        revalidatePath('/dashboard/senders');
        return {success:log?'Provider accepted the test, but history could not be updated. Check the provider dashboard.':`Provider accepted the test for ${user.email}. Acceptance does not confirm inbox delivery.`};
      } catch {
        await service.from('email_test_attempts').update({status:'unknown'}).eq('id',attempt).eq('status','reserved');
        return {error:'Test outcome is unconfirmed. Check the provider dashboard before trying again. No automatic retry was performed.'};
      }
    } else throw new Error('Unknown sender operation.');
    revalidatePath('/dashboard/senders');
    return {success:'Sender settings saved.'};
  } catch(e) { return {error:e instanceof Error?e.message:'Sender request failed.'}; }
}
