import {sameOrigin} from '@/lib/security/request';
import {NextResponse} from 'next/server';import {supabaseServer} from '@/lib/supabase/server';
export async function POST(request:Request){if(!sameOrigin(request))return NextResponse.json({error:'Cross-origin request denied'},{status:403});const origin=new URL(request.url).origin;const client=await supabaseServer();await client.auth.signOut();return NextResponse.redirect(new URL('/login',origin),303)}
