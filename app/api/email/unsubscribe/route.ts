import {NextResponse} from 'next/server';
import {z} from 'zod';
import {emailServiceDb} from '@/lib/email/server';
export const runtime='nodejs';
export async function GET(request:Request) {
 const token=new URL(request.url).searchParams.get('token')||'';
 if(!z.string().uuid().safeParse(token).success)return NextResponse.json({error:'Invalid link'},{status:400});
 return NextResponse.redirect(new URL('/unsubscribe?token='+encodeURIComponent(token),request.url),{headers:{'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
}
export async function POST(request:Request) {
 const token=new URL(request.url).searchParams.get('token')||'';
 if(!z.string().uuid().safeParse(token).success)return NextResponse.json({error:'Invalid link'},{status:400});
 try{const {error}=await emailServiceDb().rpc('delivery_unsubscribe',{p_token:token});if(error)throw error;return new Response('Your unsubscribe request has been processed.',{headers:{'Content-Type':'text/plain; charset=utf-8','Cache-Control':'no-store'}});}catch{return NextResponse.json({error:'Please try again later'},{status:503});}
}
