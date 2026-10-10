import {supabaseServer} from '@/lib/supabase/server';
import {z} from 'zod';
export const organizationIdSchema = z.string().uuid();
/** Contact PII is restricted to company admins, managers, and platform super admins. */
export async function contactsAccess(organizationId: string) {
 const org = organizationIdSchema.safeParse(organizationId);
 const db = await supabaseServer();
 const {data:{user}} = await db.auth.getUser();
 if (!user || !org.success) return {db,user,authorized:false};
 const [{data:member},{data:staff},{data:organization}] = await Promise.all([
  db.from('organization_members').select('role').eq('organization_id',org.data).eq('user_id',user.id).maybeSingle(),
  db.from('platform_staff').select('role').eq('user_id',user.id).maybeSingle(),
  db.from('organizations').select('status').eq('id',org.data).maybeSingle()
 ]);
 const authorized=staff?.role==='super_admin'||(organization?.status==='active'&&['company_admin','manager'].includes(member?.role||''));
 return {db,user,authorized};
}
