import 'server-only';
import {Resolver} from 'node:dns/promises';
import {createClient} from '@supabase/supabase-js';
import {supabaseServer} from '@/lib/supabase/server';
import {providerAdapter} from './providers';
import {domainName, type Provider} from './validation';
export function emailServiceDb() {
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!url||!key) throw new Error('Server database credentials are not configured.');
  return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
}
export async function senderAccess(org:string) {
  const db=await supabaseServer();
  const {data:{user},error}=await db.auth.getUser();
  if(error||!user||!user.email_confirmed_at) throw new Error('Sign in with a verified email address.');
  const {data:allowed,error:accessError}=await db.rpc('can_manage_senders',{p_org:org});
  if(accessError||!allowed) throw new Error('Company administrator access to an active workspace is required.');
  return {db,user};
}
export async function providerFor(provider:Provider) {
  const db=emailServiceDb();
  const {data,error}=await db.from('email_provider_settings').select('enabled').eq('provider',provider).single();
  if(error||!data?.enabled) throw new Error('This provider is disabled. Contact the platform administrator.');
  const key=process.env[provider==='resend'?'RESEND_API_KEY':'BREVO_API_KEY'];
  return providerAdapter(provider,key||'');
}
export async function ownershipVerified(domain:string,token:string):Promise<boolean> {
  try { const resolver=new Resolver({timeout:5000,tries:1});const records=await resolver.resolveTxt('_sesco-campaign.'+domainName(domain)); return records.some(parts=>parts.join('')==='sesco-verification='+token); }
  catch { return false; }
}
export async function refreshDomain(org:string,id:string,trigger=false) {
  const db=emailServiceDb();
  const {data:row,error}=await db.from('sending_domains').select('*').eq('id',id).eq('organization_id',org).single();
  if(error||!row||row.verification_status==='revoked') throw new Error('Active sender domain not found in this workspace.');
  const adapter=await providerFor(row.provider as Provider);
  // Invalidate cached verification before a network check. Failure must close access.
  const {error:invalidate}=await db.from('sending_domains').update({verification_status:'pending'}).eq('id',id).neq('verification_status','revoked');
  if(invalidate) throw new Error('Cannot refresh domain verification.');
  const state=await adapter.check(row.domain,row.provider_domain_id,trigger);
  const owned=await ownershipVerified(row.domain,row.ownership_token);
  const {error:save}=await db.rpc('email_domain_sync',{p_id:id,p_provider_id:state.id,p_records:state.records,p_verified:state.verified&&owned});
  if(save) throw new Error('Domain status could not be saved.');
  return {row,adapter,verified:state.verified&&owned};
}
