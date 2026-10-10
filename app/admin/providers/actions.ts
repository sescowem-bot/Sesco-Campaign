'use server';
import {revalidatePath} from 'next/cache';
import {z} from 'zod';
import {supabaseServer} from '@/lib/supabase/server';
import {emailServiceDb} from '@/lib/email/server';
import {providerAdapter} from '@/lib/email/providers';
export type ProviderResult={error?:string;success?:string};
export async function providerAction(_:ProviderResult,form:FormData):Promise<ProviderResult> {
 try {
  const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user?.email_confirmed_at)throw new Error('Verified sign-in required.');
  const {data:owner,error}=await db.rpc('is_platform_super_admin');if(error||!owner)throw new Error('Super Admin access required.');
  const provider=z.enum(['resend','brevo']).parse(form.get('provider'));
  if(form.get('action')==='save') {
   const {error}=await db.rpc('admin_email_provider_save',{p_provider:provider,p_enabled:form.get('enabled')==='on'});if(error)throw new Error(error.message);
  } else if(form.get('action')==='limits') {
   const daily=z.coerce.number().int().min(1).max(1000000).parse(form.get('daily_limit'));
   const interval=z.coerce.number().int().min(1).max(3600).parse(form.get('minimum_interval_seconds'));
   const {error}=await db.rpc('admin_provider_limits',{p_provider:provider,p_daily:daily,p_interval:interval});if(error)throw new Error(error.message);
  } else if(form.get('action')==='health') {
   const key=process.env[provider==='resend'?'RESEND_API_KEY':'BREVO_API_KEY']||'';
   const service=emailServiceDb();
   const {data:settings}=await service.from('email_provider_settings').select('checked_at').eq('provider',provider).single();
   if(settings?.checked_at&&Date.now()-Date.parse(settings.checked_at)<30000)throw new Error('Wait 30 seconds before checking again.');
   let healthy=true;try{await providerAdapter(provider,key).health();}catch{healthy=false;}
   const {error}=await service.from('email_provider_settings').update({health_status:healthy?'healthy':'error',checked_at:new Date().toISOString()}).eq('provider',provider);
   if(error)throw new Error('Provider health could not be recorded.');
   revalidatePath('/admin/providers');return healthy?{success:'Provider API connection verified. This does not confirm delivery or sending allowance.'}:{error:'Provider connection failed. Check the server API key, account permissions and provider dashboard.'};
  } else if(form.get('action')==='reconcile') {
   const id=z.string().uuid().parse(form.get('domain_id'));
   const providerId=z.string().trim().min(1).max(200).parse(form.get('provider_domain_id'));
   const service=emailServiceDb();
   const {data:domain,error:read}=await service.from('sending_domains').select('domain,provider,provider_domain_id,verification_status').eq('id',id).single();
   if(read||!domain||domain.provider!==provider||domain.provider_domain_id||domain.verification_status==='revoked')throw new Error('Unresolved domain not found for this provider.');
   const key=process.env[provider==='resend'?'RESEND_API_KEY':'BREVO_API_KEY']||'';
   const result=await providerAdapter(provider,key).check(domain.domain,providerId);
   const {error:save}=await service.rpc('email_domain_sync',{p_id:id,p_provider_id:result.id,p_records:result.records,p_verified:false});
   if(save)throw new Error('Reconciliation could not be saved.');
   const {error:audit}=await service.from('audit_logs').insert({actor_id:user.id,action:'domain.reconciled',entity_type:'sending_domain',entity_id:id});
   if(audit)return {error:'Domain was linked, but audit write failed. Review database logging before continuing.'};
   revalidatePath('/dashboard/senders');
  } else throw new Error('Unknown operation.');
  revalidatePath('/admin/providers');return {success:'Provider settings saved.'};
 }catch(e){return {error:e instanceof Error?e.message:'Provider request failed.'};}
}
