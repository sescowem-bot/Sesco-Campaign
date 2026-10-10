import 'server-only';
import {cache} from 'react';
import {cookies} from 'next/headers';
import {supabaseServer} from '@/lib/supabase/server';
export const currentAccount=cache(async()=>{
 if(!process.env.NEXT_PUBLIC_SUPABASE_URL||!process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)return null;
 try{
 const db=await supabaseServer();const {data:{user},error}=await db.auth.getUser();if(error||!user)return null;
 const {data:owner}=await db.rpc('is_platform_super_admin');
 const {data:companies}=await db.from('organizations').select('id,name,status').order('name');
 const {data:own}=owner===true?await db.from('platform_workspace').select('organization_id').maybeSingle():{data:null};
 const ownerWorkspace=companies?.find(c=>c.id===own?.organization_id)??null;
 const preferred=(await cookies()).get('sesco-workspace')?.value;
 // Organizations are fetched through the signed-in user's RLS-scoped client.
 const workspace=companies?.find(c=>c.id===preferred)??ownerWorkspace??companies?.find(c=>c.status==='active')??companies?.[0]??null;
 return {id:user.id,admin:owner===true,workspace,ownerWorkspace};
 }catch{return null;}
});
