import {sameOrigin,boundedText,bodyErrorResponse} from '@/lib/security/request';
import {NextResponse} from 'next/server';
import {supabaseServer} from '@/lib/supabase/server';
import {finalizeVerifiedPayment} from '@/lib/payments/paystack';
export async function POST(req:Request){
 if(!sameOrigin(req))return NextResponse.json({error:'Cross-origin request denied'},{status:403});
 try{
 const {reference}=JSON.parse(await boundedText(req,4000));if(typeof reference!=='string'||!/^scc_[a-f0-9]{32}$/.test(reference))return NextResponse.json({error:'Invalid reference'},{status:400});
 const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user)return NextResponse.json({error:'Sign in required'},{status:401});
 const {data:payment}=await db.from('payment_transactions').select('id,initiated_by,status').eq('reference',reference).maybeSingle();
 if(!payment||payment.initiated_by!==user.id)return NextResponse.json({error:'Not authorized'},{status:403});
 const result=await finalizeVerifiedPayment(reference);
 return NextResponse.json({result});
 }catch(e){const rejected=bodyErrorResponse(e);if(rejected)return rejected;return NextResponse.json({error:'Verification temporarily unavailable'},{status:503});}
}
