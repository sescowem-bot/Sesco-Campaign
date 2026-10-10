import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {boundedBytes,boundedText,applicationOrigin,sameOrigin} from '../lib/security/request.ts';
import {contentSecurityPolicy} from '../lib/security/headers.ts';
import {paymentSignatureValid} from '../lib/payments/signature.ts';
test('request limits enforce bytes for chunked and multibyte bodies',async()=>{
 await assert.rejects(boundedText(new Request('https://example.com',{method:'POST',body:'éé'}),3),e=>e.status===413);
 const body=new ReadableStream({start(c){c.enqueue(new Uint8Array(6));c.enqueue(new Uint8Array(6));c.close();}});
 await assert.rejects(boundedBytes(new Request('https://example.com',{method:'POST',body,duplex:'half'}),10),e=>e.status===413);
 assert.equal(await boundedText(new Request('https://example.com',{method:'POST',body:'hello'}),5),'hello');
});
test('request readers reject stalled streams and invalid UTF-8',async()=>{
 const body=new ReadableStream({start(){}});await assert.rejects(boundedBytes(new Request('https://example.com',{method:'POST',body,duplex:'half'}),10,10),e=>e.status===408);
 await assert.rejects(boundedText(new Request('https://example.com',{method:'POST',body:new Uint8Array([255])}),10),e=>e.status===400);
});
test('browser mutation checks reject absent, hostile and cross-site origins',()=>{
 assert.equal(sameOrigin(new Request('https://example.com/api',{headers:{origin:'https://example.com'}})),true);
 for(const headers of [{},{origin:'https://evil.example'},{origin:'https://example.com','sec-fetch-site':'cross-site'}])assert.equal(sameOrigin(new Request('https://example.com/api',{headers})),false);
});
test('checkout origin uses the documented setting and rejects insecure or conflicting URLs',()=>{
 assert.equal(applicationOrigin({NEXT_PUBLIC_APP_URL:'https://campaign.example'}),'https://campaign.example');
 assert.equal(applicationOrigin({APP_URL:'https://campaign.example/'}),'https://campaign.example');
 for(const env of [{NEXT_PUBLIC_APP_URL:'http://example.com'},{NEXT_PUBLIC_APP_URL:'https://example.com/path'},{NEXT_PUBLIC_APP_URL:'https://example.com',APP_URL:'https://other.example'}])assert.throws(()=>applicationOrigin(env));
});
test('payment signatures authenticate exact bytes and reject tampering',()=>{
 const raw=Buffer.from('{"event":"charge.success"}');const secret='test-key';const sig=createHmac('sha512',secret).update(raw).digest('hex');
 assert.equal(paymentSignatureValid(raw,sig,secret),true);assert.equal(paymentSignatureValid(Buffer.concat([raw,Buffer.from(' ')]),sig,secret),false);assert.equal(paymentSignatureValid(raw,'invalid',secret),false);
});
test('production CSP has nonced scripts, no eval and explicit Supabase connections',()=>{
 const csp=contentSecurityPolicy('abcdefgh12345678','https://project.supabase.co');assert.ok(csp.includes("'nonce-abcdefgh12345678'"));assert.ok(csp.includes('wss://project.supabase.co'));assert.ok(!csp.includes('unsafe-eval'));assert.ok(csp.includes("frame-ancestors 'none'"));assert.throws(()=>contentSecurityPolicy("bad'; script-src *",undefined));
});
test('proxied browser mutations trust configured HTTPS origins but never forwarded host claims',()=>{
 const env={NEXT_PUBLIC_APP_URL:'https://sesco-campaign.vercel.app'};
 const request=origin=>new Request('http://localhost:3000/auth/signout',{headers:{origin,'sec-fetch-site':'same-origin','x-forwarded-host':'evil.example'}});
 assert.equal(sameOrigin(request('https://sesco-campaign.vercel.app'),env),true);
 assert.equal(sameOrigin(request('https://evil.example'),env),false);
 assert.equal(sameOrigin(request('https://preview.vercel.app'),{VERCEL_URL:'preview.vercel.app'}),true);
 assert.equal(sameOrigin(request('https://evil.example'),{NEXT_PUBLIC_APP_URL:'https://evil.example/path'}),false);
 assert.equal(sameOrigin(new Request('http://localhost/auth/signout',{headers:{origin:'https://sesco-campaign.vercel.app','sec-fetch-site':'cross-site'}}),env),false);
});
