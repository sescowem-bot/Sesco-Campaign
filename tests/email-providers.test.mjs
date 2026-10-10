import test from 'node:test';
import assert from 'node:assert/strict';
import {domainName,mailbox,matchesDomain,senderName,escapeHtml} from '../lib/email/validation.ts';
import {providerAdapter,normalizeDomain} from '../lib/email/providers.ts';
const resend={id:'domain-id',name:'mail.example.com',status:'verified',capabilities:{sending:'enabled'},records:[{type:'TXT',name:'resend._domainkey',value:'public-key',status:'verified'}]};
const brevo={domain:'mail.example.com',verified:true,authenticated:true,dns_records:{dkim_record:{host_name:'mail._domainkey',type:'TXT',value:'key',status:true}}};
test('domains normalize case and reject URLs, IPs, invalid labels and header injection',()=>{
 assert.equal(domainName(' MAIL.Example.COM '),'mail.example.com');
 for(const value of ['https://example.com','127.0.0.1','localhost','-bad.example.com','bad_.example.com','a..com','example.com/path','example.com\r\nX: y'])assert.throws(()=>domainName(value));
});
test('sender mailboxes require exact authenticated domain, not a suffix',()=>{
 assert.equal(mailbox('Hello@Example.com'),'hello@example.com');
 assert.equal(matchesDomain('hello@mail.example.com','mail.example.com'),true);
 assert.equal(matchesDomain('hello@evilmail.example.com','mail.example.com'),false);
 assert.equal(matchesDomain('hello@example.com','mail.example.com'),false);
 assert.throws(()=>mailbox('hello@example.com\r\nBcc: other@example.com'));
 assert.throws(()=>senderName('Name <other@example.com>'));
});
test('test email names are escaped before rendering',()=>assert.equal(escapeHtml('<img src=x onerror="x">'),'&lt;img src=x onerror=&quot;x&quot;&gt;'));
test('Resend only verifies fully authenticated sending-enabled domains',()=>{
 assert.equal(normalizeDomain('resend',resend,'mail.example.com').verified,true);
 for(const status of ['pending','partially_verified','failed','not_started'])assert.equal(normalizeDomain('resend',{...resend,status},'mail.example.com').verified,false);
 assert.equal(normalizeDomain('resend',{...resend,capabilities:{sending:'disabled'}},'mail.example.com').verified,false);
 assert.throws(()=>normalizeDomain('resend',resend,'other.example.com'));
});
test('Brevo requires both verified and authenticated true and normalizes DNS',()=>{
 const state=normalizeDomain('brevo',brevo,'mail.example.com','15');assert.equal(state.verified,true);assert.equal(state.records[0].name,'mail._domainkey');
 assert.equal(normalizeDomain('brevo',{...brevo,authenticated:false},'mail.example.com','15').verified,false);
 assert.equal(normalizeDomain('brevo',{...brevo,verified:'true'},'mail.example.com','15').verified,false);
});
test('Resend domain adapter uses fixed authenticated endpoints and async verification poll',async()=>{
 const calls=[];const adapter=providerAdapter('resend','secret',async(url,options)=>{calls.push({url,options});return Response.json(resend);});
 await adapter.create('mail.example.com');await adapter.check('mail.example.com','domain-id',true);
 assert.deepEqual(calls.map(c=>[c.url,c.options.method]),[['https://api.resend.com/domains','POST'],['https://api.resend.com/domains/domain-id/verify','POST'],['https://api.resend.com/domains/domain-id','GET']]);
 assert.equal(calls[0].options.headers.Authorization,'Bearer secret');assert.equal(calls[0].options.cache,'no-store');
});
test('Brevo adapter normalizes create and uses PUT authenticate followed by GET',async()=>{
 const calls=[];const adapter=providerAdapter('brevo','secret',async(url,options)=>{calls.push({url,options});return Response.json({...brevo,id:15});});
 await adapter.create('mail.example.com');await adapter.check('mail.example.com','15',true);
 assert.equal(calls[0].options.headers['api-key'],'secret');assert.equal(calls[1].options.method,'PUT');assert.ok(calls[1].url.endsWith('/authenticate'));
});
test('provider failures redact secret and response body and never retry',async()=>{
 let calls=0;const adapter=providerAdapter('resend','private-secret',async()=>{calls++;return Response.json({message:'private-secret'},{status:429});});
 await assert.rejects(adapter.health(),/rate limit/);assert.equal(calls,1);
 await assert.rejects(adapter.create('example.com'),error=>!error.message.includes('private-secret'));
});
test('test sending requires matching domain and returns provider acknowledgement',async()=>{
 const calls=[];const adapter=providerAdapter('resend','secret',async(url,options)=>{calls.push({url,options});return Response.json({id:'message-id'});});
 const input={name:'Example',email:'hello@mail.example.com',replyTo:'support@example.com',to:'owner@example.com',domain:'mail.example.com',html:'<p>Test</p>',attempt:'attempt-id'};
 assert.equal(await adapter.sendTest(input),'message-id');assert.deepEqual(JSON.parse(calls[0].options.body).to,['owner@example.com']);
 await assert.rejects(adapter.sendTest({...input,email:'hello@evil.example.com'}));assert.equal(calls.length,1);
});
test('missing acknowledgement fails instead of claiming delivery',async()=>{
 const adapter=providerAdapter('brevo','secret',async()=>Response.json({}));
 await assert.rejects(adapter.sendTest({name:'Example',email:'hello@example.com',replyTo:'reply@example.com',to:'owner@example.com',domain:'example.com',html:'Test',attempt:'attempt-id'}),/acknowledgement/);
});
