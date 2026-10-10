const headers=[{key:'X-Content-Type-Options',value:'nosniff'},{key:'X-Frame-Options',value:'DENY'},{key:'Referrer-Policy',value:'no-referrer'},{key:'Permissions-Policy',value:'camera=(), microphone=(), geolocation=()'}];
if(process.env.NODE_ENV==='production')headers.push({key:'Strict-Transport-Security',value:'max-age=31536000'});
const config={poweredByHeader:false,async headers(){return [{source:'/:path*',headers}];}};
export default config;
