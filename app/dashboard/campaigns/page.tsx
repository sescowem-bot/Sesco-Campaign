import Link from 'next/link';
import {redirect} from 'next/navigation';
import {z} from 'zod';
import {supabaseServer} from '@/lib/supabase/server';
import {WorkspaceShell} from '@/components/workspace-shell';
import {CampaignStudio,CampaignWorkflow,type CampaignDraft} from '@/components/campaign-studio';
import {renderCampaign,campaignDesign} from '@/lib/campaigns/render';
export default async function Campaigns({searchParams}:{searchParams:Promise<{org?:string;id?:string;create?:string}>}) {
 const {org,id,create}=await searchParams;if(!org||!z.string().uuid().safeParse(org).success)redirect('/dashboard');
 const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');
 const {data:member}=await db.rpc('is_organization_member',{org});const {data:owner}=await db.rpc('is_platform_super_admin');if(!member&&!owner)redirect('/dashboard');
 const [edit,approve,campaigns,branding]=await Promise.all([
 db.rpc('can_edit_campaigns',{p_org:org}),db.rpc('can_approve_campaigns',{p_org:org}),
 db.from('campaign_drafts').select('*').eq('organization_id',org).order('updated_at',{ascending:false}).limit(100),
 db.from('organization_branding').select('display_name,postal_address,primary_color').eq('organization_id',org).maybeSingle()
 ]);
 const brand={display_name:branding.data?.display_name||'Your company',postal_address:branding.data?.postal_address||'',primary_color:branding.data?.primary_color||'#102b4e'};
 if(campaigns.error)return <WorkspaceShell org={org} title="Campaign studio"><p role="alert">Campaign data could not be loaded. Confirm migration 008 is installed.</p></WorkspaceShell>;
 let selected=null;
 if(id){if(!z.string().uuid().safeParse(id).success)redirect(`/dashboard/campaigns?org=${org}`);const {data,error}=await db.from('campaign_drafts').select('*').eq('organization_id',org).eq('id',id).single();if(error||!data)return <WorkspaceShell org={org} title="Campaign unavailable"><Link href={`/dashboard/campaigns?org=${org}`} className="btn">Return to campaigns</Link></WorkspaceShell>;selected=data;}
 const editable=!!edit.data && (!selected||['draft','rejected','approved'].includes(selected.status));
 const showEditor=editable&&(!!selected||create==='1');
 const [templates,senders,lists,segments,history]=showEditor||selected?await Promise.all([
 db.from('email_templates').select('id,name,subject,design').or(`organization_id.eq.${org},organization_id.is.null`).neq('status','archived').limit(100),
 db.from('sender_identities').select('id,from_name,from_email').eq('organization_id',org).eq('is_active',true),
 db.from('contact_lists').select('id,name').eq('organization_id',org),db.from('contact_segments').select('id,name').eq('organization_id',org),
 selected?db.from('campaign_revisions').select('revision,snapshot,created_at').eq('organization_id',org).eq('campaign_id',selected.id).order('revision',{ascending:false}).limit(30):Promise.resolve({data:[],error:null})
 ]):[{data:[],error:null},{data:[],error:null},{data:[],error:null},{data:[],error:null},{data:[],error:null}];
 if([templates,senders,lists,segments,history].some(r=>r.error))return <WorkspaceShell org={org} title="Campaign studio"><p role="alert">Campaign resources could not be loaded. Retry before editing.</p></WorkspaceShell>;
 const actions:string[]=[];
 if(selected&&edit.data){if(['draft','rejected'].includes(selected.status))actions.push('submit');if(['pending_approval','approved','rejected'].includes(selected.status))actions.push('withdraw');if(selected.status!=='archived')actions.push('archive');}
 if(selected&&approve.data&&selected.status==='pending_approval'&&selected.edited_by!==user.id&&selected.submitted_by!==user.id)actions.push('approve','reject');
 let preview=null,previewError='';if(selected){try{preview=renderCampaign({design:selected.design,subject:selected.subject,preheader:selected.preheader,company:brand.display_name,address:brand.postal_address,color:brand.primary_color});}catch{previewError='Stored campaign content is invalid. Return to draft and repair the design.';}}
 const audienceCount=selected?await db.rpc('campaign_audience_count',{p_org:org,p_type:selected.audience_type,p_audience:selected.audience_id}):null;
 return <WorkspaceShell org={org} title="Campaign studio"><p className="muted">Create your message, select an opted-in audience and request independent review.</p><div className="notice">Campaigns require independent approval before they can be queued for delivery. Open Delivery queue to manage dispatch.</div><div className="workspace-links"><Link href={`/dashboard/campaigns?org=${org}`}>All campaigns</Link>{edit.data&&<Link href={`/dashboard/campaigns?org=${org}&create=1`}>Create campaign</Link>}</div>
 {selected&&<section className="panel"><div className="workspace-heading"><h2>{selected.name}</h2><span className="status-chip">{selected.status.replaceAll('_',' ')} · Revision {selected.revision}</span></div><p>Eligible contacts now: {audienceCount?.error?'Unavailable':audienceCount?.data??0}. Count at submission or approval: {selected.eligible_at_review??'Not reviewed'}.</p><p className="muted">Requested send time: {selected.requested_send_at?new Date(selected.requested_send_at).toISOString():'Not requested'}</p>{selected.review_note&&<p>Review note: {selected.review_note}</p>}{selected.status==='approved'&&<p className="notice">Saving an edit returns this campaign to draft and clears its approval.</p>}{actions.length>0&&<CampaignWorkflow org={org} id={selected.id} revision={selected.revision} actions={actions}/>}</section>}
 {showEditor?<CampaignStudio key={selected?.id||'new'} org={org} initial={selected as CampaignDraft|undefined} brand={brand} templates={(templates.data||[]).filter(t=>campaignDesign.safeParse(t.design).success)} senders={(senders.data||[]).map(s=>({id:s.id,name:`${s.from_name} <${s.from_email}>`}))} lists={lists.data||[]} segments={segments.data||[]}/>:selected&&<section className="studio-preview"><h2>Saved campaign preview</h2>{previewError?<p role="alert">{previewError}</p>:<iframe title="Saved campaign email preview" sandbox="" srcDoc={preview?.html} style={{width:'100%',height:650,border:0}}/>}<p className="muted">Sample recipient and preview unsubscribe link. No email is sent.</p></section>}
 {selected&&<section className="panel sender-domain"><h2>Revision history</h2><p className="muted">Latest 30 saved content and workflow revisions. Expand a revision to inspect its recorded content.</p>{history.data?.map(h=><details key={h.revision} className="campaign-history"><summary>Revision {h.revision} · {String(h.snapshot.status)} · {new Date(h.created_at).toISOString()}</summary><p>Subject: {String(h.snapshot.subject)}</p><p>Review note: {String(h.snapshot.review_note||'None')}</p><pre>{JSON.stringify(h.snapshot.design,null,2)}</pre></details>)}</section>}
 {!selected&&create!=='1'&&<><h2>Recent campaigns</h2>{campaigns.data.length===0?<div className="panel"><h3>No campaigns yet</h3><p className="muted">Create a draft using a saved template or your own content blocks.</p></div>:<div className="table-scroll"><table className="admin-table"><caption className="sr-only">Latest 100 campaigns</caption><thead><tr><th>Name</th><th>Status</th><th>Revision</th><th>Updated (UTC)</th></tr></thead><tbody>{campaigns.data.map(c=><tr key={c.id}><td><Link className="inline-link" href={`/dashboard/campaigns?org=${org}&id=${c.id}`}>{c.name}</Link></td><td>{c.status.replaceAll('_',' ')}</td><td>{c.revision}</td><td>{new Date(c.updated_at).toISOString()}</td></tr>)}</tbody></table></div>}</>}
 </WorkspaceShell>;
}
