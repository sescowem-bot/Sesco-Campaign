import 'server-only';
import {cache} from 'react';
import {supabaseServer} from '@/lib/supabase/server';
/** Request-scoped verified identity, never shared across visitors. */
export const currentAccount=cache(async()=>{
 if(!process.env.NEXT_PUBLIC_SUPABASE_URL||!process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)return null;
 try{const db=await supabaseServer();const {data:{user},error}=await db.auth.getUser();if(error||!user)return null;const {data:owner}=await db.rpc('is_platform_super_admin');return {id:user.id,admin:owner===true};}catch{return null;}
});
