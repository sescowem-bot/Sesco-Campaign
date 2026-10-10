const origin=process.env.NEXT_PUBLIC_APP_URL;
const secret=process.env.EMAIL_WORKER_SECRET;
if(!origin||!secret||secret.length<32)throw new Error('HTTPS application origin and worker secret required.');
const url=new URL(origin);if(url.protocol!=='https:'||url.pathname!=='/'||url.username||url.password||url.search||url.hash)throw new Error('Use an HTTPS origin.');
const response=await fetch(new URL('/api/worker/delivery',url),{method:'POST',headers:{Authorization:`Bearer ${secret}`},signal:AbortSignal.timeout(120000)});
if(!response.ok)throw new Error(`Worker returned status ${response.status}. Review server operations.`);
console.log(JSON.stringify(await response.json()));
