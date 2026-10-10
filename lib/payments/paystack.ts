import 'server-only';
import {createClient} from '@supabase/supabase-js';
const base='https://api.paystack.co';
export function paystackSecret(){const key=process.env.PAYSTACK_SECRET_KEY;if(!key)throw new Error('PAYSTACK_SECRET_KEY is not configured');return key;}
export function serviceDb(){const url=process.env.NEXT_PUBLIC_SUPABASE_URL;const key=process.env.SUPABASE_SERVICE_ROLE_KEY;if(!url||!key)throw new Error('Supabase service credentials missing');return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});}
export async function paystackRequest(path:string,options:RequestInit={}){const res=await fetch(base+path,{...options,headers:{Authorization:`Bearer ${paystackSecret()}`,'Content-Type':'application/json',...(options.headers||{})},cache:'no-store',signal:AbortSignal.timeout(15000)});const body=await res.json().catch(()=>null);if(!res.ok||!body?.status)throw new Error('Paystack request failed');return body.data;}
export type VerifiedTransaction={reference:string;id:number|string;amount:number;currency:string;status:string;paid_at:string|null};
export async function finalizeVerifiedPayment(reference:string){
 const tx=(await paystackRequest('/transaction/verify/'+encodeURIComponent(reference))) as VerifiedTransaction;
 if(tx.reference!==reference||tx.status!=='success'||!Number.isSafeInteger(tx.amount))return 'not_successful';
 const {data,error}=await serviceDb().rpc('payment_finalize',{p_reference:reference,p_transaction_id:String(tx.id),p_amount_kobo:tx.amount,p_currency:tx.currency,p_paid_at:tx.paid_at});
 if(error)throw new Error('Payment finalization failed: '+error.message);
 return String(data);
}
