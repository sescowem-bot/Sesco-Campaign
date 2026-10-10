import {z} from 'zod';
import {escapeHtml} from '../email/validation.ts';
const block=z.discriminatedUnion('type',[
 z.object({type:z.literal('heading'),text:z.string().max(5000)}),
 z.object({type:z.literal('paragraph'),text:z.string().max(5000)}),
 z.object({type:z.literal('button'),text:z.string().max(200),url:z.string().url().startsWith('https://')}),
 z.object({type:z.literal('divider'),text:z.literal('')})
]);
export const campaignDesign=z.object({version:z.literal('1'),blocks:z.array(block).min(1).max(30)});
export type Design=z.infer<typeof campaignDesign>;
export type PreviewContact={first_name?:string;last_name?:string;email?:string;attributes?:Record<string,string>};
const expression=/\{\{\s*([a-z][a-z0-9_.]*)\s*\}\}/g;
export function personalize(text:string,contact:PreviewContact,company:string):string {
 const rendered=text.replace(expression,(_,key:string)=>{
  if(key==='company_name')return company;
  if(['first_name','last_name','email'].includes(key))return String(contact[key as 'first_name'|'last_name'|'email']|| (key==='first_name'?'Customer':''));
  if(/^attributes\.[a-z][a-z0-9_]{0,39}$/.test(key) && !['__proto__','constructor','prototype'].includes(key.split('.')[1]))return contact.attributes?.[key.split('.')[1]]||'';
  throw new Error(`Unsupported personalization variable: ${key}`);
 });
 // Validate only original template syntax, never re-interpret customer-provided values.
 if(text.replace(expression,'').includes('{{')||text.replace(expression,'').includes('}}'))throw new Error('Invalid personalization syntax.');
 return rendered;
}
export function renderCampaign(input:{design:unknown;subject:string;preheader?:string;company:string;address:string;contact?:PreviewContact;color?:string;unsubscribeUrl?:string;testPreview?:boolean}) {
 const design=campaignDesign.parse(input.design),contact=input.contact||{};
 const replace=(text:string)=>escapeHtml(personalize(text,contact,input.company));
 const color=/^#[a-f0-9]{6}$/i.test(input.color||'')?input.color:'#102b4e';
 const unsubscribe=input.unsubscribeUrl||'https://example.invalid/unsubscribe-preview';
 if(!/^https:\/\//.test(unsubscribe))throw new Error('Unsubscribe link must use HTTPS.');
 const content=design.blocks.map(b=>b.type==='heading'?`<h1 style="font-size:26px;line-height:1.3">${replace(b.text)}</h1>`:b.type==='paragraph'?`<p style="line-height:1.7;white-space:pre-wrap">${replace(b.text)}</p>`:b.type==='button'?`<table role="presentation"><tr><td bgcolor="${color}" style="padding:14px 22px"><a href="${escapeHtml(b.url)}" style="color:#ffffff;text-decoration:none">${replace(b.text)}</a></td></tr></table>`:'<hr style="border:0;border-top:1px solid #e2e8f0;margin:24px 0"/>').join('');
 const subject=personalize(input.subject,contact,input.company);
 if(!subject.trim()||subject.length>200||/[\r\n]/.test(subject))throw new Error('Rendered subject must be 1 to 200 characters without line breaks.');
 return {subject,html:`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#f1f5f9;font-family:Arial,sans-serif;color:#13233b"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px"><table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:100%;max-width:600px;background:#ffffff"><tr><td style="padding:24px;background:${color};color:#ffffff;font-weight:bold">${escapeHtml(input.company)}</td></tr><tr><td style="padding:28px"><div style="display:none;max-height:0;overflow:hidden">${replace(input.preheader||'')}</div>${input.testPreview?'<p style="padding:12px;background:#fff7ed;color:#7c2d12">TEST PREVIEW · Sample recipient data. This is not a campaign delivery.</p>':''}${content}</td></tr><tr><td style="padding:24px;background:#f8fafc;font-size:12px;line-height:1.6">${escapeHtml(input.company)}<br>${escapeHtml(input.address)}<br>${input.testPreview?'Unsubscribe is inactive in this test preview.':`<a href="${escapeHtml(unsubscribe)}">Unsubscribe</a>`}</td></tr></table></td></tr></table></body></html>`};
}
