import {NextRequest,NextResponse} from 'next/server';
import {supabaseServer} from '@/lib/supabase/server';
export async function GET(request:NextRequest){const code=request.nextUrl.searchParams.get('code');if(!code)return NextResponse.redirect(new URL('/login?error=invalid_link',request.url));const client=await supabaseServer();const {error}=await client.auth.exchangeCodeForSession(code);return NextResponse.redirect(new URL(error?'/login?error=confirmation':'/dashboard',request.url))}
