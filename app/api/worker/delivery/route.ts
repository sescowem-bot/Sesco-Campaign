import {NextResponse} from 'next/server';
import {bearerMatches} from '@/lib/delivery/events';
import {processDelivery} from '@/lib/delivery/worker';
export const runtime='nodejs';
export const maxDuration=120;
export async function POST(request:Request) {
 if(!bearerMatches(request.headers.get('authorization'),process.env.EMAIL_WORKER_SECRET))return NextResponse.json({error:'Unauthorized'},{status:401});
 try {return NextResponse.json(await processDelivery());}catch{return NextResponse.json({error:'Delivery worker requires operational review'},{status:500});}
}
