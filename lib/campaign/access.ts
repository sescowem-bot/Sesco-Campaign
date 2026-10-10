import {supabaseServer} from '@/lib/supabase/server';
export async function companyAccess(org:string){
 const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();
 if(!user)return {db,user:null,canEdit:false,canView:false};
 const [{data:member},{data:staff}]=await Promise.all([
 db.from('organization_members').select('role').eq('organization_id',org).eq('user_id',user.id).maybeSingle(),
 db.from('platform_staff').select('role').eq('user_id',user.id).maybeSingle()
 ]);
 const owner=staff?.role==='super_admin';
 return {db,user,canEdit:owner||['company_admin','manager','designer'].includes(member?.role||''),canView:owner||!!member};
}
