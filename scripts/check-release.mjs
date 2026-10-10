// Read-only validation; this does not contact services, validate acceptance, or deploy.
const env=process.env;const checks=[];const add=(name,ok)=>checks.push({name,ok:Boolean(ok)});
function httpsOrigin(value){try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&u.pathname==='/'&&!u.search&&!u.hash;}catch{return false;}}
function role(key){try{return JSON.parse(Buffer.from(key.split('.')[1],'base64url').toString()).role;}catch{return null;}}
add('Node 24',process.versions.node.split('.')[0]==='24');
add('HTTPS application origin',httpsOrigin(env.NEXT_PUBLIC_APP_URL));
add('Legacy origin agrees',!env.APP_URL||env.APP_URL.replace(/\/$/,'')===env.NEXT_PUBLIC_APP_URL?.replace(/\/$/,''));
add('HTTPS Supabase origin',httpsOrigin(env.NEXT_PUBLIC_SUPABASE_URL));
add('Public key has public role',env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.startsWith('sb_publishable_')||role(env.NEXT_PUBLIC_SUPABASE_ANON_KEY||'')==='anon');
add('Service key is server-only role',env.SUPABASE_SERVICE_ROLE_KEY?.startsWith('sb_secret_')||role(env.SUPABASE_SERVICE_ROLE_KEY||'')==='service_role');
for(const key of Object.keys(env).filter(k=>k.startsWith('NEXT_PUBLIC_')&&/(SECRET|SERVICE_ROLE|API_KEY)/.test(k)))add('No public secret variable: '+key,false);
add('Paystack key configured',/^sk_(test|live)_/.test(env.PAYSTACK_SECRET_KEY||''));
add('Worker secret configured',(env.EMAIL_WORKER_SECRET||'').length>=32);
add('At least one email provider key',env.RESEND_API_KEY||env.BREVO_API_KEY);
if(env.RESEND_API_KEY)add('Resend webhook signing secret',env.RESEND_WEBHOOK_SECRET?.startsWith('whsec_'));
if(env.BREVO_API_KEY){add('Brevo webhook secret',(env.BREVO_WEBHOOK_SECRET||'').length>=32);add('Independent worker and Brevo secrets',env.BREVO_WEBHOOK_SECRET!==env.EMAIL_WORKER_SECRET);}
add('Delivery stays disabled before acceptance',env.EMAIL_DELIVERY_ENABLED==='false');
for(const c of checks)console.log(`${c.ok?'PASS':'FAIL'} ${c.name}`);
console.log('Configuration only. Hosted access, DNS, payment, sending, restore and browser acceptance are separate gates.');
if(checks.some(c=>!c.ok))process.exitCode=1;
