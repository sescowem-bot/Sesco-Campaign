import {redirect} from 'next/navigation';
import {contactsAccess} from '@/lib/contacts/access';
import {WorkspaceShell} from '@/components/workspace-shell';
import {SegmentForm} from '@/components/contact-forms';
export const dynamic='force-dynamic';
type Rules={consent_status?:'granted'|'denied'|'unknown';source?:'manual'|'import';has_email?:boolean};
export default async function Segments({searchParams}:{searchParams:Promise<{org?:string}>}){
 const {org}=await searchParams;if(!org)redirect('/dashboard');
 const {db,user,authorized}=await contactsAccess(org);
 if(!user)redirect('/login');if(!authorized)redirect('/dashboard');
 const {data:segments,error}=await db.from('contact_segments').select('id,name,description,rules').eq('organization_id',org).order('created_at',{ascending:false}).limit(40);
 const summaries=await Promise.all((segments||[]).map(async segment=>{
  const rules=segment.rules as Rules;
  let query=db.from('contacts').select('id',{head:true,count:'exact'}).eq('organization_id',org);
  if(rules?.consent_status)query=query.eq('consent_status',rules.consent_status);
  if(rules?.source)query=query.eq('source',rules.source);
  if(rules?.has_email===true)query=query.not('email','is',null);
  if(rules?.has_email===false)query=query.is('email',null);
  const {count,error:countError}=await query;
  return {...segment,count:countError?null:count};
 }));
 return <WorkspaceShell org={org} title="Dynamic segments"><p className="muted">Create automatically updating audiences using allowlisted contact filters. Multiple conditions are combined with AND.</p><div className="table-scroll"><table className="admin-table"><thead><tr><th>Segment</th><th>Conditions</th><th>Matches now</th></tr></thead><tbody>{summaries.map(s=><tr key={s.id}><td>{s.name}<p className="muted">{s.description}</p></td><td>{Object.entries(s.rules as Record<string,unknown>).map(([k,v])=>`${k.replaceAll('_',' ')}: ${String(v)}`).join(' · ')}</td><td>{s.count===null?'Unavailable':s.count}</td></tr>)}</tbody></table></div>{error&&<p role="alert">Unable to load segments.</p>}{!segments?.length&&<p className="muted">No segments yet. Add an audience rule below.</p>}<SegmentForm org={org}/></WorkspaceShell>;
}
