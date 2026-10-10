import {redirect} from 'next/navigation';
import {z} from 'zod';
import {supabaseServer} from '@/lib/supabase/server';
import {WorkspaceShell} from '@/components/workspace-shell';
import {TeamForm} from '@/components/management-forms';
export default async function Team({searchParams}:{searchParams:Promise<{org?:string}>}){
 const {org}=await searchParams;if(!org||!z.string().uuid().safeParse(org).success)redirect('/dashboard');const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');const {data:allowed}=await db.rpc('can_manage_team',{p_org:org});if(!allowed)redirect('/dashboard');
 const {data,error}=await db.rpc('team_members',{p_org:org});const members=z.array(z.object({id:z.string().uuid(),email:z.string(),role:z.string()})).safeParse(data);
 return <WorkspaceShell org={org} title="Team & roles"><p className="muted">Manage verified accounts with access to this company.</p><div className="admin-columns"><TeamForm org={org}/><section className="panel"><h2>Current members</h2>{error||!members.success?<p role="alert">Memberships unavailable. Confirm migration 011 is installed.</p>:members.data.length?<div className="table-scroll"><table className="admin-table"><thead><tr><th scope="col">Account email</th><th scope="col">Role</th></tr></thead><tbody>{members.data.map(m=><tr key={m.id}><td>{m.email}</td><td>{m.role.replaceAll('_',' ')}</td></tr>)}</tbody></table></div>:<p className="muted">No members assigned.</p>}</section></div></WorkspaceShell>;
}
