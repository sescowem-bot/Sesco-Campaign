'use server';
import {revalidatePath} from 'next/cache';
import {z} from 'zod';
import {supabaseServer} from '@/lib/supabase/server';
import {emailServiceDb} from '@/lib/email/server';
import {providerAdapter} from '@/lib/email/providers';
import {mailbox,senderName} from '@/lib/email/validation';
export async function connectOwnerSender(_: {error?:string;success?:string},form:FormData):Promise<{error?:string;success?:string}> {
 try {
  const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();
  const {data:owner,error}=await db.rpc('is_platform_super_admin');
  if(error||!owner||!user?.email_confirmed_at)throw new Error('Verified super admin access required.');
  const email=mailbox(String(form.get('email')||'')),reply=mailbox(String(form.get('reply')||email));
  const name=senderName(String(form.get('name')||''));
  const providerId=z.string().uuid().parse(String(form.get('domain_id')||'').trim());
  const address=z.string().trim().min(6).max(500).parse(form.get('address'));
  // Read an EXISTING domain using server credentials. Never create a provider domain here.
  const state=await providerAdapter('resend',process.env.RESEND_API_KEY||'').check(email.split('@')[1],providerId);
  if(!state.verified)throw new Error('Resend has not verified this domain for sending. Check its status in your Resend account.');
  const {error:save}=await emailServiceDb().rpc('owner_connect_resend',{p_actor:user.id,p_domain:state.domain,p_provider_id:state.id,p_records:state.records,p_name:name,p_email:email,p_reply:reply,p_address:address});
  if(save)throw new Error(save.message);
  revalidatePath('/admin/workspace');revalidatePath('/dashboard/senders');revalidatePath('/dashboard/campaigns');
  return {success:'Your existing Resend sender is connected. You can now select it in Campaign studio.'};
 }catch(e){return {error:e instanceof z.ZodError?'Check the Resend domain ID and postal address.':e instanceof Error?e.message:'Connection failed. Please retry.'};}
}
