import {contentSecurityPolicy} from '@/lib/security/headers';
import {NextResponse, type NextRequest} from 'next/server';
import {createServerClient} from '@supabase/ssr';
export async function middleware(request:NextRequest){
 const nonce=btoa(crypto.randomUUID());const policy=contentSecurityPolicy(nonce,process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NODE_ENV!=='production');const requestHeaders=new Headers(request.headers);requestHeaders.set('x-nonce',nonce);requestHeaders.set('Content-Security-Policy',policy);
 const next=()=>{requestHeaders.set('cookie',request.headers.get('cookie')||'');const result=NextResponse.next({request:{headers:requestHeaders}});result.headers.set('Content-Security-Policy',policy);return result;};
 let response=next();
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL;const key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
 if(!url||!key){if(request.nextUrl.pathname.startsWith('/dashboard')||request.nextUrl.pathname.startsWith('/admin'))return NextResponse.redirect(new URL('/login?error=setup',request.url));return response}
 const protectedPage=request.nextUrl.pathname.startsWith('/dashboard')||request.nextUrl.pathname.startsWith('/admin');
 const hasSession=request.cookies.getAll().some(cookie=>cookie.name.startsWith('sb-')&&cookie.name.includes('-auth-token'));
 if(!protectedPage&&!hasSession)return response;
 const client=createServerClient(url,key,{cookies:{getAll(){return request.cookies.getAll()},setAll(items){items.forEach(({name,value})=>request.cookies.set(name,value));response=next();items.forEach(({name,value,options})=>response.cookies.set(name,value,options))}}});
 const {data:{user}}=await client.auth.getUser();
 if(!user&&(request.nextUrl.pathname.startsWith('/dashboard')||request.nextUrl.pathname.startsWith('/admin')))return NextResponse.redirect(new URL('/login',request.url));
 return response;
}
export const config={matcher:['/((?!api/|_next/|favicon.ico|robots.txt|sitemap.xml).*)']};
