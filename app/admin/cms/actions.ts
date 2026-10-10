'use server';
import {revalidatePath} from 'next/cache';
import {z} from 'zod';
import {supabaseServer} from '@/lib/supabase/server';
import {cmsSlug,validateContent} from '@/lib/cms/content';
export type CmsResult={revision?:number;success?:string;error?:string};
export async function cmsAction(previous:CmsResult,form:FormData):Promise<CmsResult>{
 try{
  const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user?.email_confirmed_at)throw new Error('Verified sign-in required.');
  const {data:owner}=await db.rpc('is_platform_super_admin');if(!owner)throw new Error('Super Admin access required.');
  const slug=cmsSlug.parse(form.get('slug')),revision=z.coerce.number().int().nonnegative().parse(form.get('revision')),operation=z.enum(['save','publish','unpublish']).parse(form.get('operation'));
  let content=null;
  if(operation==='save'){const raw=String(form.get('content')||'');if(Buffer.byteLength(raw)>60000)throw new Error('Content exceeds the page limit.');content=validateContent(slug,JSON.parse(raw));}
  if(operation==='publish'){const {data,error}=await db.from('site_pages').select('draft').eq('slug',slug).single();if(error||!data)throw new Error('Draft unavailable.');validateContent(slug,data.draft);}
  const {data,error}=await db.rpc('cms_edit',{p_slug:slug,p_revision:revision,p_operation:operation,p_content:content});if(error)throw new Error(error.message);
  revalidatePath('/','layout');revalidatePath('/admin/cms');return {revision:Number(data),success:operation==='save'?'Draft saved. Publish the saved draft to update the website.':operation==='publish'?'Saved draft published.':'Publication removed. The source defaults are shown.'};
 }catch(e){return {revision:previous.revision,error:e instanceof z.ZodError?'Check the content fields, links and image URL.':e instanceof Error?e.message:'CMS request failed.'};}
}
