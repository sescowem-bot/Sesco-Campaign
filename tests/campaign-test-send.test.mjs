import test from 'node:test';
import assert from 'node:assert/strict';
import {sendSavedCampaignTest} from '../lib/campaigns/test-send.ts';
import {ownerReadiness,httpsApplicationOrigin} from '../lib/campaigns/readiness.ts';
const saved={attempt:'30000000-0000-4000-8000-000000000001',recipient:'owner@example.com',campaign:{subject:'Hello {{first_name}}',preheader:'Preview',revision:3,design:{version:'1',blocks:[{type:'paragraph',text:'Account: {{email}}'}]}},sender:{domain_id:'30000000-0000-4000-8000-000000000002',from_name:'Brand',from_email:'hello@example.com',reply_to:'reply@example.com'},brand:{display_name:'Brand',postal_address:'12 Main Street',primary_color:'#102b4e'}};
test('saved campaign test targets only the account recipient with a marked preview and inactive unsubscribe',async()=>{
 const sent=[],records=[];
 const result=await sendSavedCampaignTest({reserve:async()=>saved,verify:async()=>({verified:true,domain:'example.com',send:async input=>{sent.push(input);return 'message-1';}}),record:async(...args)=>records.push(args)});
 assert.equal(sent.length,1);assert.equal(sent[0].to,'owner@example.com');assert.equal(sent[0].subject,'[TEST] Hello Test reader');assert.ok(sent[0].html.includes('TEST PREVIEW'));assert.ok(sent[0].html.includes('Account: owner@example.com'));assert.ok(!sent[0].html.includes('href="https://example.invalid'));assert.deepEqual(records,[[saved.attempt,'accepted','message-1']]);assert.match(result.success,/Revision 3/);
});
test('reservation denial stops verification and all outbound calls',async()=>{
 let touched=false;await assert.rejects(sendSavedCampaignTest({reserve:async()=>{throw new Error('Not authorized');},verify:async()=>{touched=true;},record:async()=>{touched=true;}}),/Not authorized/);assert.equal(touched,false);
});
test('invalid content and failed domain verification record not sent without contacting the send endpoint',async()=>{
 for(const value of [saved,{...saved,campaign:{...saved.campaign,design:{version:'1',blocks:[]}}}]){
  const records=[];let sends=0;
  const result=await sendSavedCampaignTest({reserve:async()=>value,verify:async()=>({verified:false,domain:'example.com',send:async()=>{sends++;}}),record:async(...args)=>records.push(args)});
  assert.ok(result.error);assert.equal(sends,0);assert.equal(records[0][1],'not_sent');
 }
});
test('uncertain provider outcomes are recorded once and never retried',async()=>{
 let sends=0;const records=[];const result=await sendSavedCampaignTest({reserve:async()=>saved,verify:async()=>({verified:true,domain:'example.com',send:async()=>{sends++;throw new Error('Timeout');}}),record:async(...args)=>records.push(args)});
 assert.equal(sends,1);assert.equal(records[0][1],'unknown');assert.match(result.error,/unconfirmed/);
});
test('accepted provider message is reported honestly if history persistence fails',async()=>{
 const result=await sendSavedCampaignTest({reserve:async()=>saved,verify:async()=>({verified:true,domain:'example.com',send:async()=>'message'}),record:async()=>{throw new Error('Database unavailable');}});assert.match(result.success,/history could not be updated/);
});
test('readiness does not label failed reads or insecure origins ready',()=>{
 for(const url of [undefined,'http://example.com','https://user:pass@example.com','https://example.com/path','https://example.com/?secret=1'])assert.equal(httpsApplicationOrigin(url),false);
 assert.equal(httpsApplicationOrigin('https://sesco-campaign.vercel.app'),true);
 const rows=ownerReadiness({org:'org',active:true,senderReady:null,addressReady:false,eligible:null,dispatch:true,origin:'http://example.com',serverCredentials:false});assert.equal(rows[1].state,'Unavailable');assert.equal(rows[3].state,'Unavailable');assert.equal(rows[5].state,'Needs attention');
});
