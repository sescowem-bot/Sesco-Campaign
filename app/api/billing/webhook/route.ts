import {z} from 'zod';
import {paymentSignatureValid} from '@/lib/payments/signature';
import {boundedBytes,bodyErrorResponse} from '@/lib/security/request';
import {finalizeVerifiedPayment,paystackSecret} from '@/lib/payments/paystack';
import {NextResponse} from 'next/server';
export async function POST(req:Request){
 let secret:string;try{secret=paystackSecret();}catch{return NextResponse.json({error:'Webhook unavailable'},{status:503});}
 let bytes:Uint8Array;try{bytes=await boundedBytes(req,150000);}catch(e){return bodyErrorResponse(e)||NextResponse.json({error:'Invalid payload'},{status:400});}
 if(!paymentSignatureValid(bytes,req.headers.get('x-paystack-signature'),secret))return NextResponse.json({error:'Invalid signature'},{status:401});
 let raw:string;try{raw=new TextDecoder('utf-8',{fatal:true}).decode(bytes);}catch{return NextResponse.json({error:'Invalid payload'},{status:400});}
 let event:{event?:string;data?:{reference?:string}};
 try{event=z.object({event:z.string(),data:z.object({reference:z.string().optional()}).optional()}).parse(JSON.parse(raw));}catch{return NextResponse.json({error:'Invalid JSON'},{status:400});}
 if(event.event!=='charge.success')return NextResponse.json({ok:true});
 const reference=event.data?.reference;
 if(typeof reference!=='string'||!/^scc_[a-f0-9]{32}$/.test(reference))return NextResponse.json({error:'Invalid reference'},{status:400});
 try{const result=await finalizeVerifiedPayment(reference);if(result==='unknown_reference'||result==='payment_mismatch'||result==='transaction_conflict'||result==='invalid_status')return NextResponse.json({error:result},{status:422});if(result==='not_successful')return NextResponse.json({error:result},{status:409});return NextResponse.json({ok:true,result});}
 catch{return NextResponse.json({error:'Unable to process payment'},{status:500});}
}
