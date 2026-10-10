import {CampaignReportView} from '@/components/campaign-report';
import Link from 'next/link';
import {redirect} from 'next/navigation';
import {supabaseServer} from '@/lib/supabase/server';
import {WorkspaceShell} from '@/components/workspace-shell';
import {reportArguments,reportFilters,reportSchema} from '@/lib/analytics/report';
export default async function Reports({searchParams}:{searchParams:Promise<Record<string,string|string[]|undefined>>}){
 const raw=await searchParams;const params=new URLSearchParams();for(const [key,value] of Object.entries(raw))if(typeof value==='string')params.set(key,value);
 let f;try{f=reportFilters(params);}catch{return <WorkspaceShell title="Campaign reports"><div className="panel"><h2>Check your report filters</h2><p>Choose a company and valid dates covering up to 366 days.</p><Link className="btn secondary" href="/dashboard">Choose company</Link></div></WorkspaceShell>;}
 const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');
 const {data:member}=await db.rpc('is_organization_member',{org:f.org});const {data:owner}=await db.rpc('is_platform_super_admin');if(!member&&!owner)redirect('/dashboard');
 const {data,error}=await db.rpc('campaign_analytics',reportArguments(f));const parsed=reportSchema.safeParse(data);
 if(error||!parsed.success)return <WorkspaceShell org={f.org} title="Campaign reports"><div className="panel"><h2>Report unavailable</h2><p role="alert">Check the selected run and confirm migration 010 is installed.</p><Link className="btn secondary" href={`/dashboard/reports?org=${f.org}`}>Reset filters</Link></div></WorkspaceShell>;
 return <CampaignReportView filters={f} report={parsed.data}/>;
}
