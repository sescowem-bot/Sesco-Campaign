import test from 'node:test';
import assert from 'node:assert/strict';
import {sendQueuedEmail} from '../lib/delivery/transport.ts';
import {bearerMatches,brevoEvent,resendEvent} from '../lib/delivery/events.ts';
import {Webhook} from 'svix';
const input={provider:'resend',key:'private-secret',id:'40000000-0000-4000-8000-000000000001',name:'Example',from:'hello@mail.example.com',replyTo:'reply@example.com',domain:'mail.example.com',to:'recipient@example.com',subject:'Update',html:'<p>Update</p>',unsubscribe:'https://app.example.com/api/email/unsubscribe?token=token'};
test('queued send carries stable idempotency and one-click unsubscribe headers',async()=>{
 let request;const result=await sendQueuedEmail(input,async(url,options)=>{request={url,options};return Response.json({id:'message-id'});});
 assert.equal(result.status,'accepted');assert.equal(request.options.headers['Idempotency-Key'],'campaign-delivery/'+input.id);
 const body=JSON.parse(request.options.body);assert.equal(body.headers['List-Unsubscribe-Post'],'List-Unsubscribe=One-Click');assert.deepEqual(body.to,['recipient@example.com']);
});
test('only an explicit 429 retries; timeouts and 5xx are unknown without blind retries',async()=>{
 let calls=0;
 for(const [status,expected] of [[429,'retry'],[400,'failed'],[401,'failed'],[408,'unknown'],[500,'unknown']]){
  const result=await sendQueuedEmail(input,async()=>{calls++;return Response.json({message:'private-secret'},{status});});assert.equal(result.status,expected);assert.ok(!result.reason.includes('private-secret'));
 }
 assert.equal(calls,5);assert.equal((await sendQueuedEmail(input,async()=>{throw new Error('Timeout');})).status,'unknown');
});
test('Brevo delivery uses one recipient, normalized message ID and fixed endpoint',async()=>{
 let body;const result=await sendQueuedEmail({...input,provider:'brevo'},async(url,options)=>{assert.equal(url,'https://api.brevo.com/v3/smtp/email');body=JSON.parse(options.body);return Response.json({messageId:'<brevo-id>'});});
 assert.equal(result.message,'brevo-id');assert.equal(body.headers['X-Mailin-custom'],'sesco_delivery='+input.id);
});
test('worker and Brevo bearer secrets reject missing and incorrect values',()=>{
 const secret='s'.repeat(40);assert.ok(bearerMatches('Bearer '+secret,secret));assert.equal(bearerMatches('Bearer wrong',secret),false);assert.equal(bearerMatches(null,secret),false);assert.equal(bearerMatches('Bearer short','short'),false);
});
test('Brevo normalizes event names and replay keys',()=>{
 const payload=JSON.stringify({event:'hard_bounce','message-id':'<message>',ts_event:1700000000});const event=brevoEvent(payload);
 assert.equal(event.type,'bounce');assert.equal(event.message,'message');assert.equal(event.key,brevoEvent(payload).key);assert.equal(brevoEvent(JSON.stringify({event:'unsupported','message-id':'message',ts:1700000000})),null);
});
test('Resend verifies original signed bytes and rejects tampering',()=>{
 const secret='whsec_'+Buffer.from('secret-for-webhook-test-32-bytes!!').toString('base64');const webhook=new Webhook(secret);const id='msg_test';const time=new Date();
 const raw=JSON.stringify({type:'email.delivered',created_at:time.toISOString(),data:{email_id:'email-id'}});const signature=webhook.sign(id,time,raw);
 const headers=new Headers({'svix-id':id,'svix-timestamp':String(Math.floor(time.getTime()/1000)),'svix-signature':signature});
 assert.equal(resendEvent(raw,headers,secret).type,'delivered');assert.throws(()=>resendEvent(raw+' ',headers,secret));
});
