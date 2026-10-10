import {sameOrigin,boundedText,bodyErrorResponse,applicationOrigin} from '@/lib/security/request';
import {NextResponse} from 'next/server';
import {randomUUID} from 'node:crypto';
import {z} from 'zod';
import {supabaseServer} from '@/lib/supabase/server';
import {paystackRequest} from '@/lib/payments/paystack';
const schema=z.object({organization_id:z.string().uuid(),plan_id:z.string().uuid()});
export async function POST(req:Request){
 if(!sameOrigin(req))return NextResponse.json({error:'Cross-origin request denied'},{status:403});
 if(!(req.headers.get('content-type')||'').startsWith('application/json'))return NextResponse.json({error:'JSON required'},{status:415});
 try{
  const input=schema.safeParse(JSON.parse(await boundedText(req,4000)));if(!input.success)return NextResponse.json({error:'Invalid request'},{status:400});
  const appUrl=applicationOrigin(process.env);
  const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user)return NextResponse.json({error:'Sign in required'},{status:401});
  const reference='scc_'+randomUUID().replaceAll('-','');
  const {data,error}=await db.rpc('payment_start',{p_organization_id:input.data.organization_id,p_plan_id:input.data.plan_id,p_reference:reference});
  if(error)return NextResponse.json({error:'Unable to start checkout: '+error.message},{status:403});
  const row=Array.isArray(data)?data[0]:data;if(!row)return NextResponse.json({error:'Payment not initialized'},{status:500});
  const callback=new URL('/billing/return',appUrl);callback.searchParams.set('reference',reference);
  const pay=await paystackRequest('/transaction/initialize',{method:'POST',body:JSON.stringify({email:row.customer_email,amount:row.amount_kobo,currency:'NGN',reference,callback_url:callback.toString(),metadata:{organization_id:input.data.organization_id,plan_id:input.data.plan_id}})});
  if(typeof pay.authorization_url!=='string'||!pay.authorization_url.startsWith('https://checkout.paystack.com/'))throw Error('Unexpected checkout URL');
  return NextResponse.json({checkout_url:pay.authorization_url});
 }catch(e){const rejected=bodyErrorResponse(e);if(rejected)return rejected;return NextResponse.json({error:'Checkout could not be initialized. Please retry.'},{status:500});}
}
