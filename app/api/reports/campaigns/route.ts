import {supabaseServer} from '@/lib/supabase/server';
import {reportArguments,reportCsv,reportFilters,reportSchema} from '@/lib/analytics/report';
export const runtime='nodejs';
export async function GET(request:Request){
 const headers={'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'};
 let filters;try{filters=reportFilters(new URL(request.url).searchParams);}catch{return Response.json({error:'Invalid report filters. Use a company ID and a valid range of up to 366 days.'},{status:400,headers});}
 try{
  const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user?.email_confirmed_at)return Response.json({error:'Verified sign-in required'},{status:401,headers});
  const {data:member}=await db.rpc('is_organization_member',{org:filters.org});const {data:owner}=await db.rpc('is_platform_super_admin');if(!member&&!owner)return Response.json({error:'Access denied'},{status:403,headers});
  const {data,error}=await db.rpc('campaign_analytics',reportArguments(filters,true));if(error)return Response.json({error:'Report unavailable. Check the selected run and database setup.'},{status:400,headers});
  const report=reportSchema.parse(data);
  return new Response(reportCsv(report),{headers:{...headers,'Content-Type':'text/csv; charset=utf-8','Content-Disposition':`attachment; filename="campaign-report-${filters.from}-${filters.to}.csv"`,'X-Report-Total-Runs':String(report.total_runs),'X-Report-Exported-Runs':String(report.runs.length)}});
 }catch{return Response.json({error:'Report service unavailable'},{status:503,headers});}
}
