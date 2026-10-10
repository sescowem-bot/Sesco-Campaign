import 'server-only';
import {cache} from 'react';
import {createClient} from '@supabase/supabase-js';
import {publicContent,type PageContent,type SiteContent} from './content';
export const publishedContent=cache(async(slug:string)=>{
 let value:unknown=null;
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
 if(url&&key)try{const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(input,init)=>fetch(input,{...init,cache:'no-store',signal:AbortSignal.timeout(5000)})}});const {data,error}=await db.rpc('cms_public',{p_slug:slug});if(!error)value=data;}catch{/* Published source defaults keep routes available during setup/outages. */}
 return publicContent(slug,value);
});
export async function publishedSite(){return await publishedContent('site') as SiteContent;}
export async function publishedPage(slug:string){return await publishedContent(slug) as PageContent;}
