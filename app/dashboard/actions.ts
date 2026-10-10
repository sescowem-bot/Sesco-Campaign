'use server';
import {revalidatePath} from 'next/cache';
import {companyAccess} from '@/lib/campaign/access';
import {designSchema} from '@/lib/campaign/design';
import {z} from 'zod';
export type Result={error?:string;success?:string};
const orgSchema=z.string().uuid();
export async function saveBrand(_:Result,form:FormData):Promise<Result>{
 try{
  const org=orgSchema.parse(form.get('organization_id'));const {db,canEdit}=await companyAccess(org);if(!canEdit)return {error:'Not authorized'};
  const links=Object.fromEntries(['facebook','instagram','linkedin','x'].map(k=>[k,String(form.get(k)||'').trim()]).filter(([,v])=>v));
  for(const value of Object.values(links))if(!z.string().url().startsWith('https://').safeParse(value).success)return {error:'Social links must be HTTPS URLs'};
  const {error}=await db.rpc('save_company_brand',{p_org:org,p_name:String(form.get('display_name')||''),p_tagline:String(form.get('tagline')||''),p_primary:String(form.get('primary_color')||''),p_secondary:String(form.get('secondary_color')||''),p_website:String(form.get('website_url')||''),p_email:String(form.get('contact_email')||''),p_address:String(form.get('postal_address')||''),p_social:links});
  if(error)return {error:error.message};revalidatePath('/dashboard/branding');return {success:'Company branding saved.'};
 }catch{return {error:'Invalid branding details'};}
}
export async function saveTemplate(_:Result,form:FormData):Promise<Result>{
 try{
  const org=orgSchema.parse(form.get('organization_id'));const {db,canEdit}=await companyAccess(org);if(!canEdit)return {error:'Not authorized'};
  const design=designSchema.parse(JSON.parse(String(form.get('design')||'')));
  const {error}=await db.rpc('save_email_template',{p_id:String(form.get('template_id')||'')||null,p_org:org,p_name:String(form.get('name')||''),p_subject:String(form.get('subject')||''),p_description:String(form.get('description')||''),p_category:String(form.get('category')||'general'),p_design:design});
  if(error)return {error:error.message};revalidatePath('/dashboard/templates');return {success:'Template saved as draft.'};
 }catch{return {error:'Invalid template design. Check content and links.'};}
}
export async function saveFooter(_:Result,form:FormData):Promise<Result>{
 try{
  const org=orgSchema.parse(form.get('organization_id'));const {db,canEdit}=await companyAccess(org);if(!canEdit)return {error:'Not authorized'};
  const design={company_name:String(form.get('company_name')||''),address:String(form.get('address')||''),contact_email:String(form.get('contact_email')||''),website_url:String(form.get('website_url')||''),disclaimer:String(form.get('disclaimer')||'')};
  if(Object.values(design).some(v=>v.length>1200))return {error:'Footer content too long'};
  const {error}=await db.rpc('save_email_footer',{p_id:String(form.get('footer_id')||'')||null,p_org:org,p_name:String(form.get('name')||''),p_design:design,p_default:form.get('is_default')==='on'});
  if(error)return {error:error.message};revalidatePath('/dashboard/footers');return {success:'Footer saved.'};
 }catch{return {error:'Invalid footer details'};}
}
