export function contentSecurityPolicy(nonce:string,supabaseUrl:string|undefined,development=false){
 if(!/^[A-Za-z0-9+/=_-]{16,100}$/.test(nonce))throw new Error('Invalid CSP nonce');
 let connect="'self'";if(development)connect+=" ws: wss:";if(supabaseUrl)try{const u=new URL(supabaseUrl);if(u.protocol==='https:'&&!u.username&&!u.password)connect+=` ${u.origin} wss://${u.host}`;}catch{}
 return [`default-src 'self'`,`script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${development?" 'unsafe-eval'":''}`,"style-src 'self' 'unsafe-inline'","img-src 'self' https: data: blob:","font-src 'self'",`connect-src ${connect}`,"object-src 'none'","base-uri 'self'","form-action 'self'","frame-ancestors 'none'"].join('; ');
}
