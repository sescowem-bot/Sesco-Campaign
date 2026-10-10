'use server';
import {revalidatePath} from 'next/cache';
import {z} from 'zod';
import {contactsAccess,organizationIdSchema} from '@/lib/contacts/access';
export type FormResult = {success?: string; error?: string};
const contactSchema=z.object({
 organization_id:organizationIdSchema,
 contact_id:z.union([z.literal(''),z.string().uuid()]),
 first_name:z.string().trim().max(100),
 last_name:z.string().trim().max(100),
 email:z.union([z.literal(''),z.email().max(254)]),
 phone:z.union([z.literal(''),z.string().regex(/^\+[1-9]\d{7,14}$/)]),
 consent_status:z.enum(['unknown','granted','denied']),
 consent_evidence:z.string().max(500)
}).refine(v=>!!v.email||!!v.phone,{message:'Email or phone is required'}).refine(v=>v.consent_status!=='granted'||v.consent_evidence.trim().length>=6,{message:'Provide evidence of opt-in consent'});
export async function saveContact(_:FormResult,form:FormData):Promise<FormResult>{
 const submitted=Object.fromEntries(['organization_id','contact_id','first_name','last_name','email','phone','consent_status','consent_evidence'].map(k=>[k,String(form.get(k)||'').trim()]));
 const parsed=contactSchema.safeParse(submitted);
 if(!parsed.success)return {error:parsed.error.issues[0]?.message||'Invalid contact'};
 const data=parsed.data;
 try{
  const {db,authorized}=await contactsAccess(data.organization_id);
  if(!authorized)return {error:'Not authorized to manage contacts'};
  const {error}=await db.rpc('save_contact',{p_org:data.organization_id,p_id:data.contact_id||null,p_first:data.first_name,p_last:data.last_name,p_email:data.email,p_phone:data.phone,p_consent:data.consent_status,p_evidence:data.consent_evidence});
  if(error)return {error:error.code==='23505'?'A contact with this email or phone already exists':error.message};
  revalidatePath('/dashboard/contacts');return {success:'Contact saved successfully.'};
 }catch{return {error:'Unable to save contact'};}
}
export async function createList(_:FormResult,form:FormData):Promise<FormResult>{
 const parsed=z.object({org:organizationIdSchema,name:z.string().trim().min(2).max(100),description:z.string().max(500)}).safeParse({org:form.get('organization_id'),name:form.get('name'),description:form.get('description')||''});
 if(!parsed.success)return {error:'List name must contain 2–100 characters'};
 try{
  const {db,authorized}=await contactsAccess(parsed.data.org);if(!authorized)return {error:'Not authorized'};
  const {error}=await db.rpc('save_contact_list',{p_org:parsed.data.org,p_name:parsed.data.name,p_description:parsed.data.description});
  if(error)return {error:error.code==='23505'?'This list name already exists':error.message};
  revalidatePath('/dashboard/lists');return {success:'Contact list created.'};
 }catch{return {error:'Unable to create list'};}
}
export async function changeListMembership(_:FormResult,form:FormData):Promise<FormResult>{
 const parsed=z.object({org:organizationIdSchema,list:organizationIdSchema,contact:organizationIdSchema,add:z.enum(['true','false'])}).safeParse({org:form.get('organization_id'),list:form.get('list_id'),contact:form.get('contact_id'),add:form.get('add')});
 if(!parsed.success)return {error:'Invalid membership change'};
 try{
  const {db,authorized}=await contactsAccess(parsed.data.org);if(!authorized)return {error:'Not authorized'};
  const {error}=await db.rpc('add_contact_to_list',{p_org:parsed.data.org,p_list:parsed.data.list,p_contact:parsed.data.contact,p_add:parsed.data.add==='true'});
  if(error)return {error:error.message};revalidatePath('/dashboard/lists');return {success:'List membership updated.'};
 }catch{return {error:'Unable to update list'};}
}
export async function createSegment(_:FormResult,form:FormData):Promise<FormResult>{
 const rules:Record<string,string|boolean>={};
 const consent=String(form.get('consent_status')||'');
 const source=String(form.get('source')||'');
 const hasEmail=String(form.get('has_email')||'');
 if(consent)rules.consent_status=consent;
 if(source)rules.source=source;
 if(hasEmail)rules.has_email=hasEmail==='yes';
 const parsed=z.object({org:organizationIdSchema,name:z.string().trim().min(2).max(100),description:z.string().max(500),rules:z.object({consent_status:z.enum(['unknown','granted','denied']).optional(),source:z.enum(['manual','import']).optional(),has_email:z.boolean().optional()}).refine(r=>Object.keys(r).length>0)}).safeParse({org:form.get('organization_id'),name:form.get('name'),description:form.get('description')||'',rules});
 if(!parsed.success)return {error:'Enter a name and at least one valid filter'};
 try{
  const {db,authorized}=await contactsAccess(parsed.data.org);if(!authorized)return {error:'Not authorized'};
  const {error}=await db.rpc('save_contact_segment',{p_org:parsed.data.org,p_name:parsed.data.name,p_description:parsed.data.description,p_rules:parsed.data.rules});
  if(error)return {error:error.code==='23505'?'This segment name already exists':error.message};
  revalidatePath('/dashboard/segments');return {success:'Dynamic segment created.'};
 }catch{return {error:'Unable to save segment'};}
}
