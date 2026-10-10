import {z} from 'zod';
const count=z.number().int().nonnegative();
const metrics={recipients:count,submitted:count,delivered:count,opened:count,clicked:count,bounced:count,complained:count,unsubscribed:count,failed:count,unknown:count,skipped:count,waiting:count,attempts:count};
export const reportSchema=z.object({generated_at:z.string().datetime({offset:true}),total_runs:count,totals:z.object(metrics),runs:z.array(z.object({...metrics,id:z.string().uuid(),name:z.string().nullable(),provider:z.enum(['resend','brevo']),status:z.string(),created_at:z.string().datetime({offset:true}),scheduled_at:z.string().datetime({offset:true})})),daily:z.array(z.object({day:z.string(),runs:count,recipients:count,submitted:count,delivered:count}))});
export type CampaignReport=z.infer<typeof reportSchema>;
const dateSchema=z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value=>{const d=new Date(value+'T00:00:00.000Z');return !Number.isNaN(d.valueOf())&&d.toISOString().slice(0,10)===value;},'Use a valid calendar date.');
export function reportFilters(params:URLSearchParams,now=new Date()) {
 const endDefault=now.toISOString().slice(0,10);
 const startDefault=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth(),now.getUTCDate()-29)).toISOString().slice(0,10);
 const org=z.string().uuid().parse(params.get('org'));
 const from=dateSchema.parse(params.get('from')||startDefault),to=dateSchema.parse(params.get('to')||endDefault);
 const start=new Date(from+'T00:00:00.000Z'),until=new Date(new Date(to+'T00:00:00.000Z').valueOf()+86400000);
 if(until<=start||until.valueOf()-start.valueOf()>366*86400000)throw new Error('Choose up to 366 days with the start on or before the end.');
 const run=params.get('run')?z.string().uuid().parse(params.get('run')):null;
 const page=z.coerce.number().int().min(1).max(2001).parse(params.get('page')||'1');
 return {org,from,to,run,page,p_from:start.toISOString(),p_until:until.toISOString()};
}
export function reportArguments(f:ReturnType<typeof reportFilters>,exporting=false){return {p_org:f.org,p_from:f.p_from,p_until:f.p_until,p_run:f.run,p_limit:exporting?1000:50,p_offset:exporting?0:(f.page-1)*50};}
export function rate(numerator:number,denominator:number){return denominator>0?(100*numerator/denominator).toFixed(1)+'%':'N/A';}
// Quote every cell; neutralize spreadsheet formulas even after leading whitespace.
export function csvCell(value:string|number){let s=String(value);if(/^\s*[=+\-@]/.test(s)||/^[\t\r\n]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';}
export function reportCsv(report:CampaignReport){
 const keys=['id','name','provider','status','created_at','scheduled_at','recipients','attempts','submitted','delivered','opened','clicked','bounced','complained','unsubscribed','failed','unknown','skipped','waiting'] as const;
 return '\uFEFF'+[keys.map(csvCell).join(','),...report.runs.map(run=>keys.map(k=>csvCell(run[k]??'')).join(','))].join('\r\n')+'\r\n';
}
