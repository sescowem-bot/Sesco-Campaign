import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
const port=Number(process.env.SMOKE_PORT||3107);
const base=`http://127.0.0.1:${port}`;
const server=spawn(process.execPath,['node_modules/next/dist/bin/next','start','-H','127.0.0.1','-p',String(port)],{stdio:'pipe',env:{...process.env,NEXT_PUBLIC_SUPABASE_URL:'',NEXT_PUBLIC_SUPABASE_ANON_KEY:'',NEXT_TELEMETRY_DISABLED:'1'}});
let logs='';server.stdout.on('data',b=>logs+=b);server.stderr.on('data',b=>logs+=b);
try {
 let ready=false;
 for(let i=0;i<100;i++){
  try{const response=await fetch(base+'/api/health');if(response.ok){ready=true;break;}}catch{}
  await new Promise(resolve=>setTimeout(resolve,200));
 }
 assert.ok(ready,'Production server did not start: '+logs);
 const security=await fetch(base+'/');const policy=security.headers.get('content-security-policy')||'';const nonce=policy.match(/'nonce-([^']+)'/)?.[1];assert.ok(nonce);assert.ok(!policy.includes('unsafe-eval'));assert.equal(security.headers.get('x-content-type-options'),'nosniff');assert.equal(security.headers.get('x-frame-options'),'DENY');assert.equal(security.headers.get('referrer-policy'),'no-referrer');assert.equal(security.headers.get('x-powered-by'),null);const html=await security.text();assert.ok(html.includes('nonce="'+nonce+'"'),'Server scripts use the request nonce');for(const tag of html.matchAll(/<script\b([^>]*)>/g))assert.ok(tag[1].includes('nonce="'+nonce+'"'),'Every initial server script is nonced');
 const second=await fetch(base+'/');assert.notEqual(second.headers.get('content-security-policy'),policy,'Nonce changes per request');
 const paths=['/','/about','/features','/solutions','/pricing','/resources','/faq','/contact','/privacy','/terms','/cookies','/acceptable-use','/login','/register','/api/health','/unsubscribe'];
 for(const path of paths){const response=await fetch(base+path);assert.equal(response.status,200,path);}
 for(const path of ['/admin/workspace','/admin/cms','/admin/audit','/dashboard/team?org=20000000-0000-4000-8000-000000000001','/dashboard/reports?org=20000000-0000-4000-8000-000000000001','/dashboard/delivery?org=20000000-0000-4000-8000-000000000001','/admin/providers','/dashboard/senders?org=20000000-0000-4000-8000-000000000001','/dashboard/campaigns?org=20000000-0000-4000-8000-000000000001']){
  const response=await fetch(base+path,{redirect:'manual'});assert.equal(response.status,307,path);assert.ok(response.headers.get('location').includes('/login'));
 }
 for(const path of ['/api/worker/delivery','/api/email/webhooks/brevo']){const response=await fetch(base+path,{method:'POST'});assert.equal(response.status,401,path);}
 const exportCheck=await fetch(base+'/api/reports/campaigns?org=invalid');assert.equal(exportCheck.status,400);assert.equal(exportCheck.headers.get('cache-control'),'private, no-store');
 const invalid=await fetch(base+'/api/email/unsubscribe?token=invalid',{method:'POST'});assert.equal(invalid.status,400);
 for(const path of ['/auth/signout','/api/billing/checkout','/api/billing/verify','/api/contacts/import']){const response=await fetch(base+path,{method:'POST',headers:{Origin:'https://hostile.example'}});assert.equal(response.status,403,path);}
 const webhook=await fetch(base+'/api/billing/webhook',{method:'POST',body:'{}'});assert.equal(webhook.status,503);
 console.log(`${paths.length} public/health routes passed; 9 protected routes redirect to login without setup; 9 API rejection checks passed; response headers and per-request script nonces passed.`);
} finally {server.kill('SIGTERM');}
