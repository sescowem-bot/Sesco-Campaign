import {boundedText,bodyErrorResponse} from '@/lib/security/request';
import {NextResponse} from 'next/server';
import {bearerMatches,brevoEvent} from '@/lib/delivery/events';
import {emailServiceDb} from '@/lib/email/server';
export const runtime='nodejs';
export async function POST(request:Request) {
 if(!bearerMatches(request.headers.get('authorization'),process.env.BREVO_WEBHOOK_SECRET))return NextResponse.json({error:'Unauthorized'},{status:401});
 let event;
 try {const raw=await boundedText(request,64000);event=brevoEvent(raw);}catch(e){const rejected=bodyErrorResponse(e);if(rejected)return rejected;return NextResponse.json({error:'Invalid event payload'},{status:400});}
 if(!event)return NextResponse.json({received:true});
 try{const {error}=await emailServiceDb().rpc('delivery_event',{p_provider:'brevo',p_key:event.key,p_message:event.message,p_type:event.type,p_time:event.time});if(error)throw error;return NextResponse.json({received:true});}catch{return NextResponse.json({error:'Event persistence unavailable'},{status:503});}
}
