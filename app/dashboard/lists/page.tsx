import {redirect} from 'next/navigation';
import {contactsAccess} from '@/lib/contacts/access';
import {WorkspaceShell} from '@/components/workspace-shell';
import {ContactListForm,ListMembershipForm} from '@/components/contact-forms';
export const dynamic='force-dynamic';
export default async function Lists({searchParams}:{searchParams:Promise<{org?:string}>}){
 const {org}=await searchParams;if(!org)redirect('/dashboard');
 const {db,user,authorized}=await contactsAccess(org);
 if(!user)redirect('/login');if(!authorized)redirect('/dashboard');
 const [{data:lists,error},{data:contacts},{data:members}]=await Promise.all([
 db.from('contact_lists').select('id,name,description,created_at').eq('organization_id',org).order('created_at',{ascending:false}).limit(100),
 db.from('contacts').select('id,first_name,last_name,email,phone').eq('organization_id',org).order('created_at',{ascending:false}).limit(100),
 db.from('contact_list_members').select('list_id,contact_id').eq('organization_id',org).limit(5000)
 ]);
 const counts=new Map<string,number>();for(const m of members||[])counts.set(m.list_id,(counts.get(m.list_id)||0)+1);
 return <WorkspaceShell org={org} title="Contact lists"><p className="muted">Organize contacts into reusable static audiences for future campaigns.</p><div className="table-scroll"><table className="admin-table"><thead><tr><th>List</th><th>Description</th><th>Members (preview)</th></tr></thead><tbody>{(lists||[]).map(l=><tr key={l.id}><td>{l.name}</td><td>{l.description||'—'}</td><td>{counts.get(l.id)||0}</td></tr>)}</tbody></table></div>{error&&<p role="alert">Could not load lists.</p>}{members?.length===5000&&<p className="muted">Member counts are limited to 5,000 records in this preview. Full counts will be added to a later reporting release.</p>}<div className="admin-columns"><ContactListForm org={org}/><ListMembershipForm org={org} lists={lists||[]} contacts={(contacts||[]).map(c=>({id:c.id,name:([c.first_name,c.last_name].filter(Boolean).join(' ')||c.email||c.phone||c.id)}))}/></div></WorkspaceShell>;
}
