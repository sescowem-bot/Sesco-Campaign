import Link from 'next/link';
import {redirect} from 'next/navigation';
import {supabaseServer} from '@/lib/supabase/server';
import {WorkspaceShell} from '@/components/workspace-shell';
import {CmsEditor} from '@/components/cms-editor';
import {cmsSlug,pageDefault,publicContent,siteDefaults,type SiteContent,type PageContent} from '@/lib/cms/content';
export default async function Cms({searchParams}:{searchParams:Promise<{page?:string}>}){
 const selected=cmsSlug.safeParse((await searchParams).page||'site');const slug=selected.success?selected.data:'site';
 const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');const {data:owner}=await db.rpc('is_platform_super_admin');if(!owner)redirect('/dashboard');
 const [{data:pages,error},{data:history}]=await Promise.all([db.from('site_pages').select('slug,draft,revision,published_revision,published_at').order('slug'),db.from('site_page_revisions').select('revision,operation,created_at').eq('slug',slug).order('id',{ascending:false}).limit(10)]);
 const row=pages?.find(p=>p.slug===slug);if(error||!row)return <WorkspaceShell admin title="Website CMS"><p role="alert">CMS data unavailable. Confirm migration 011 is installed.</p></WorkspaceShell>;
 const initial=Object.keys(row.draft).length?publicContent(slug,row.draft):slug==='site'?siteDefaults:pageDefault(slug);
 return <WorkspaceShell admin title="Website CMS"><p className="muted">Manage public copy, navigation and platform identity with draft and publication controls.</p><nav className="cms-page-tabs" aria-label="Editable pages">{pages?.map(p=><Link href={'/admin/cms?page='+p.slug} aria-current={slug===p.slug?'page':undefined} key={p.slug}>{p.slug==='site'?'Identity & navigation':p.slug}</Link>)}</nav><div className="notice">{row.published_at?`Published revision ${row.published_revision}, ${new Date(row.published_at).toISOString()}.`:'Source defaults are currently displayed.'} Current edit revision {row.revision}. Prices remain managed in Plans & pricing. Auth forms and unsubscribe controls remain functional outside CMS content.</div><CmsEditor key={slug+row.revision} slug={slug} revision={row.revision} initial={initial as SiteContent|PageContent}/><section className="panel"><h2>Recent saved history</h2>{history?.length?<ul>{history.map(h=><li key={h.revision}>Revision {h.revision} · {h.operation} · {new Date(h.created_at).toISOString()}</li>)}</ul>:<p className="muted">No changes recorded yet.</p>}</section></WorkspaceShell>;
}
