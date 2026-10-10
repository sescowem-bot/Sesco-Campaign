import test from 'node:test';
import assert from 'node:assert/strict';
import {csvCell,rate,reportArguments,reportCsv,reportFilters,reportSchema} from '../lib/analytics/report.ts';
const org='20000000-0000-4000-8000-000000000001';
test('UTC report defaults span 30 inclusive calendar days',()=>{
 const f=reportFilters(new URLSearchParams({org}),new Date('2026-10-10T01:00:00Z'));
 assert.equal(f.from,'2026-09-11');assert.equal(f.to,'2026-10-10');assert.equal(f.p_until,'2026-10-11T00:00:00.000Z');assert.equal(reportArguments(f).p_offset,0);
});
test('report dates reject calendar rollover, reversed ranges and excessive ranges',()=>{
 for(const [from,to] of [['2026-02-30','2026-03-01'],['2026-10-11','2026-10-10'],['2025-01-01','2026-10-10']])assert.throws(()=>reportFilters(new URLSearchParams({org,from,to})));
 const f=reportFilters(new URLSearchParams({org,from:'2024-01-01',to:'2024-12-31',page:'2'}));assert.equal(reportArguments(f).p_offset,50);assert.equal(reportArguments(f,true).p_limit,1000);
 assert.throws(()=>reportFilters(new URLSearchParams({org,page:'0'})));assert.throws(()=>reportFilters(new URLSearchParams({org,run:'invalid'})));
});
test('CSV neutralizes spreadsheet formulas and preserves quotes, commas and newlines',()=>{
 for(const value of ['=HYPERLINK("https://example.com")',' +1','-2','@SUM(1)','\t=1'])assert.ok(csvCell(value).startsWith('"\''));
 assert.equal(csvCell('Campaign "A", first\nline'),'"Campaign ""A"", first\nline"');assert.equal(csvCell(12),'"12"');assert.equal(csvCell('Normal campaign'),'"Normal campaign"');
});
test('rates distinguish missing denominator and CSV contains aggregates only',()=>{
 assert.equal(rate(0,0),'N/A');assert.equal(rate(1,4),'25.0%');
 const totals=Object.fromEntries(['recipients','submitted','delivered','opened','clicked','bounced','complained','unsubscribed','failed','unknown','skipped','waiting','attempts'].map(k=>[k,0]));
 const report=reportSchema.parse({generated_at:'2026-10-10T00:00:00Z',total_runs:1,totals,runs:[{...totals,id:org,name:'=1',provider:'resend',status:'completed',created_at:'2026-10-10T00:00:00Z',scheduled_at:'2026-10-10T00:00:00Z'}],daily:[]});
 const csv=reportCsv(report);assert.ok(csv.startsWith('\uFEFF'));assert.ok(csv.includes('"\'=1"'));assert.ok(!csv.includes('recipient_email'));assert.ok(!csv.includes('unsubscribe_token'));
});
