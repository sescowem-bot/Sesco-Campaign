import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const script=new URL('../scripts/check-release.mjs',import.meta.url);
const jwt=role=>'header.'+Buffer.from(JSON.stringify({role})).toString('base64url')+'.signature';
test('release configuration validation is read-only and does not print secret values',()=>{
 const env={NEXT_PUBLIC_APP_URL:'https://campaign.example',NEXT_PUBLIC_SUPABASE_URL:'https://project.supabase.co',NEXT_PUBLIC_SUPABASE_ANON_KEY:jwt('anon'),SUPABASE_SERVICE_ROLE_KEY:jwt('service_role'),PAYSTACK_SECRET_KEY:'sk_test_do_not_print',EMAIL_WORKER_SECRET:'worker-do-not-print-'.repeat(3),RESEND_API_KEY:'resend-do-not-print',RESEND_WEBHOOK_SECRET:'whsec_do-not-print',EMAIL_DELIVERY_ENABLED:'false'};
 const result=spawnSync(process.execPath,[script.pathname],{env,encoding:'utf8'});assert.equal(result.status,0);assert.ok(!result.stdout.includes('do-not-print'));assert.ok(!result.stdout.includes('sk_test_'));
 env.NEXT_PUBLIC_SUPABASE_ANON_KEY=jwt('service_role');const bad=spawnSync(process.execPath,[script.pathname],{env,encoding:'utf8'});assert.equal(bad.status,1);assert.ok(bad.stdout.includes('FAIL Public key'));
});
