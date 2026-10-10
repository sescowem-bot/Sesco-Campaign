'use server';
import {revalidatePath} from 'next/cache';
import {z} from 'zod';
import {supabaseServer} from '@/lib/supabase/server';
export type ManagementResult={error?:string;success?:string};
export async function teamAction(_:ManagementResult,form:FormData):Promise<ManagementResult>{
 try{const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user?.email_confirmed_at)throw new Error('Verified sign-in required.');const org=z.string().uuid().parse(form.get('org'));const email=z.string().email().max(254).parse(form.get('email'));const role=z.enum(['company_admin','manager','designer','approver','analyst','viewer','remove']).parse(form.get('role'));const {error}=await db.rpc('team_member_save',{p_org:org,p_email:email,p_role:role});if(error)throw new Error(error.message);revalidatePath('/dashboard/team');revalidatePath('/dashboard');return {success:'Company membership updated. No invitation email was sent.'};}catch(e){return {error:e instanceof Error?e.message:'Team update failed.'};}
}
export async function companySettingsAction(_:ManagementResult,form:FormData):Promise<ManagementResult>{
 try{const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user?.email_confirmed_at)throw new Error('Verified sign-in required.');const org=z.string().uuid().parse(form.get('org')),status=z.enum(['pending','active','suspended']).parse(form.get('status'));const raw=form.get('monthly');const monthly=raw===''?null:z.coerce.number().int().min(0).max(10000000).parse(raw);const {error}=await db.rpc('admin_company_settings',{p_org:org,p_status:status,p_monthly:monthly});if(error)throw new Error(error.message);revalidatePath('/admin/companies');revalidatePath('/dashboard/delivery');return {success:'Company settings updated. Paused campaigns require manual review and resume.'};}catch(e){return {error:e instanceof Error?e.message:'Company update failed.'};}
}
