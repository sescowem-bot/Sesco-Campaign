import {sameOrigin} from '@/lib/security/request';
import {NextResponse} from 'next/server';import {supabaseServer} from '@/lib/supabase/server';
export async function POST(request:Request){if(!sameOrigin(request))return NextResponse.json({error:'Cross-origin request denied'},{status:403});const origin=request.headers.get('origin')!;const client=await supabaseServer();const {error}=await client.auth.signOut();if(error)return NextResponse.json({error:'Sign out could not be completed. Please retry.'},{status:503});return NextResponse.redirect(new URL('/login',origin),303)}
