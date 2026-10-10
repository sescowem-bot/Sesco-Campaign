import type {Provider} from './validation.ts';
import {domainName, mailbox, senderName, matchesDomain} from './validation.ts';
export type DnsRecord = {type:string;name:string;value:string;status:string;priority?:number};
export type DomainState = {id:string;domain:string;verified:boolean;records:DnsRecord[]};
type Json = Record<string, unknown>;
const obj = (v:unknown):Json => v && typeof v==='object' && !Array.isArray(v) ? v as Json : {};
export function normalizeDomain(provider:Provider, raw:unknown, expected:string, id?:string):DomainState {
  const data=obj(raw);
  const domain=domainName(String(data.name ?? data.domain ?? data.domain_name ?? ''));
  if(domain!==domainName(expected)) throw new Error('Provider returned a different domain.');
  const providerId=String(data.id ?? id ?? '');
  if(!providerId || providerId.length>200) throw new Error('Provider domain identifier missing.');
  const records:DnsRecord[]=[];
  if(provider==='resend') {
    for(const item of Array.isArray(data.records)?data.records:[]) {
      const r=obj(item); records.push({type:String(r.type??''),name:String(r.name??''),value:String(r.value??''),status:String(r.status??'pending'),...(typeof r.priority==='number'?{priority:r.priority}:{})});
    }
  } else {
    for(const r of Object.values(obj(data.dns_records)).map(obj)) records.push({type:String(r.type??''),name:String(r.host_name??''),value:String(r.value??''),status:r.status===true?'verified':'pending'});
  }
  return {id:providerId,domain,records,verified:provider==='resend'?data.status==='verified' && obj(data.capabilities).sending==='enabled':data.verified===true && data.authenticated===true};
}
/** Fixed endpoints, no arbitrary URLs, no automatic retries of external mutations. */
export function providerAdapter(provider:Provider,key:string,transport:typeof fetch=fetch) {
  if(!key) throw new Error('Provider credentials are not configured.');
  const base=provider==='resend'?'https://api.resend.com':'https://api.brevo.com/v3';
  async function request(path:string,method='GET',body?:unknown):Promise<Json> {
    let response:Response;
    try { response=await transport(base+path,{method,headers:{'Content-Type':'application/json',...(provider==='resend'?{Authorization:`Bearer ${key}`}:{'api-key':key})},...(body===undefined?{}:{body:JSON.stringify(body)}),cache:'no-store',signal:AbortSignal.timeout(15000)}); }
    catch { throw new Error('Provider connection failed. The operation may have completed; check its status before retrying.'); }
    if(!response.ok) throw new Error(response.status===429?'Provider rate limit reached. Try again later.':`Provider request failed (${response.status}). Check the provider dashboard.`);
    return obj(await response.json().catch(()=>({})));
  }
  const path=(domain:string,id:string)=>provider==='resend'?`/domains/${encodeURIComponent(id)}`:`/senders/domains/${encodeURIComponent(domainName(domain))}`;
  return {
    async create(domain:string) { const name=domainName(domain); const data=await request(provider==='resend'?'/domains':'/senders/domains','POST',{name}); return normalizeDomain(provider,data,name); },
    async check(domain:string,id:string,trigger=false) {
      if(!id) throw new Error('Provider domain registration needs administrator reconciliation.');
      if(trigger) await request(path(domain,id)+(provider==='resend'?'/verify':'/authenticate'),provider==='resend'?'POST':'PUT');
      return normalizeDomain(provider,await request(path(domain,id)),domain,id);
    },
    async health() { await request(provider==='resend'?'/domains?limit=1':'/account'); },
    async registerSender(name:string,email:string) {
      if(provider==='resend') return;
      await request('/senders','POST',{name:senderName(name),email:mailbox(email)});
    },
    async sendTest(input:{name:string;email:string;replyTo:string;to:string;domain:string;html:string;attempt:string}) {
      if(!matchesDomain(input.email,input.domain)) throw new Error('Sender address must match the verified domain.');
      const name=senderName(input.name),email=mailbox(input.email),to=mailbox(input.to),replyTo=mailbox(input.replyTo);
      const subject='Sender configuration test';
      const body=provider==='resend'?{from:`${name} <${email}>`,to:[to],reply_to:replyTo,subject,html:input.html}:{sender:{name,email},to:[{email:to}],replyTo:{email:replyTo},subject,htmlContent:input.html,headers:{'X-Sesco-Test-ID':input.attempt}};
      const result=await request(provider==='resend'?'/emails':'/smtp/email','POST',body);
      const id=String(result.id??result.messageId??'');
      if(!id) throw new Error('Provider acknowledgement missing. Check its dashboard before retrying.');
      return id;
    }
  };
}
