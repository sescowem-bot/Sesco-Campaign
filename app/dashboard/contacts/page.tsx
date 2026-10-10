import Link from 'next/link';
import {redirect} from 'next/navigation';
import {contactsAccess} from '@/lib/contacts/access';
import {WorkspaceShell} from '@/components/workspace-shell';
import {ContactForm} from '@/components/contact-forms';
import {z} from 'zod';
export const dynamic='force-dynamic';
export default async function Contacts({searchParams}:{searchParams:Promise<{org?:string;page?:string;q?:string;edit?:string}>}){
 const params=await searchParams;
 if(!params.org)redirect('/dashboard');
 const {db,user,authorized}=await contactsAccess(params.org);
 if(!user)redirect('/login');if(!authorized)redirect('/dashboard');
 const page=Math.min(1000,Math.max(1,Number.isFinite(Number(params.page))?Math.floor(Number(params.page)):1));
 const q=(params.q||'').trim().slice(0,80).replace(/[%_\\]/g,'');
 const pageSize=25;
 let request=db.from('contacts').select('id,first_name,last_name,email,phone,source,consent_status,created_at',{count:'exact'}).eq('organization_id',params.org).order('created_at',{ascending:false}).range((page-1)*pageSize,page*pageSize-1);
 if(q)request=request.ilike('email',`%${q}%`);
 const {data:contacts,error,count}=await request;
 const editId=z.string().uuid().safeParse(params.edit);
 const {data:editing}=editId.success?await db.from('contacts').select('id,first_name,last_name,email,phone,consent_status,consent_evidence').eq('organization_id',params.org).eq('id',editId.data).maybeSingle():{data:null};
 const previous=new URLSearchParams({org:params.org,page:String(page-1)});
 const next=new URLSearchParams({org:params.org,page:String(page+1)});
 if(q){previous.set('q',q);next.set('q',q);}
 return <WorkspaceShell title="Contacts & audiences" org={params.org}><p className="muted">Manage customer contact data, documented marketing consent and customer lists.</p><div className="workspace-links"><Link href={`/dashboard/imports?org=${params.org}`}>Import CSV / Excel</Link><Link href={`/dashboard/lists?org=${params.org}`}>Contact lists</Link><Link href={`/dashboard/segments?org=${params.org}`}>Dynamic segments</Link></div><div className="audience-kpis"><div className="audience-kpi"><span>Contacts matching search</span><strong>{(count||0).toLocaleString()}</strong></div><div className="audience-kpi"><span>Rows per page</span><strong>{pageSize}</strong></div></div><form className="audience-search" method="get"><input type="hidden" name="org" value={params.org}/><label htmlFor="contact-query">Search by email</label><input id="contact-query" name="q" defaultValue={q} placeholder="customer@example.com"/><button type="submit" className="btn secondary">Search</button></form>{error&&<p role="alert" className="feedback-error">Unable to load contacts: {error.message}</p>}<div className="table-scroll"><table className="admin-table"><thead><tr><th>Contact</th><th>Email</th><th>Phone</th><th>Source</th><th>Marketing consent</th><th></th></tr></thead><tbody>{(contacts||[]).map(c=><tr key={c.id}><td>{[c.first_name,c.last_name].filter(Boolean).join(' ')||'Unnamed contact'}</td><td>{c.email||'—'}</td><td>{c.phone||'—'}</td><td>{c.source}</td><td><span className={`status-chip status-${c.consent_status}`}>{c.consent_status}</span></td><td><Link href={`/dashboard/contacts?org=${params.org}&edit=${c.id}`}>Edit</Link></td></tr>)}</tbody></table></div>{!contacts?.length&&!error&&<p className="muted">No contacts found. Add one manually or import a CSV / Excel file.</p>}<div className="pagination"><span>Page {page} · {count||0} matching</span><div>{page>1&&<Link className="btn secondary" href={`/dashboard/contacts?${previous}`}>Previous</Link>}{page*pageSize<(count||0)&&<Link className="btn secondary" href={`/dashboard/contacts?${next}`}>Next</Link>}</div></div><ContactForm key={editing?.id||'new'} org={params.org} initial={editing||undefined}/>{editing&&<Link href={`/dashboard/contacts?org=${params.org}`} className="btn secondary">Cancel editing</Link>}</WorkspaceShell>;
}
