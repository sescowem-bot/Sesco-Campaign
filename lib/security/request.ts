export class RequestBodyError extends Error{status:number;constructor(message:string,status:number){super(message);this.status=status;}}
export async function boundedBytes(request:Request,maxBytes:number,timeoutMs=10000):Promise<Uint8Array>{
 const length=request.headers.get('content-length');
 if(length&&(!/^\d+$/.test(length)||Number(length)>maxBytes))throw new RequestBodyError('Request body too large or invalid',413);
 if(!request.body)return new Uint8Array();
 const reader=request.body.getReader();let timer:ReturnType<typeof setTimeout>|undefined;
 const collect=async()=>{const chunks:Uint8Array[]=[];let total=0;while(true){const {done,value}=await reader.read();if(done)break;total+=value.byteLength;if(total>maxBytes)throw new RequestBodyError('Request body too large',413);chunks.push(value);}const bytes=new Uint8Array(total);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}return bytes;};
 try{return await Promise.race([collect(),new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(new RequestBodyError('Request body timed out',408)),timeoutMs);})]);}
 finally{clearTimeout(timer);void reader.cancel().catch(()=>{});}
}
export async function boundedText(request:Request,maxBytes:number){try{return new TextDecoder('utf-8',{fatal:true}).decode(await boundedBytes(request,maxBytes));}catch(e){if(e instanceof RequestBodyError)throw e;throw new RequestBodyError('Invalid UTF-8 payload',400);}}
export function bodyErrorResponse(error:unknown){return error instanceof RequestBodyError?Response.json({error:error.message},{status:error.status}):null;}
export function sameOrigin(request:Request){const origin=request.headers.get('origin');return origin===new URL(request.url).origin&&request.headers.get('sec-fetch-site')!=='cross-site';}
export function applicationOrigin(env:Record<string,string|undefined>){const current=env.NEXT_PUBLIC_APP_URL,legacy=env.APP_URL;if(current&&legacy&&new URL(current).origin!==new URL(legacy).origin)throw new Error('Application origins disagree');const value=current||legacy;if(!value)throw new Error('Application origin missing');const url=new URL(value);if(url.protocol!=='https:'||url.username||url.password||url.pathname!=='/'||url.search||url.hash)throw new Error('An HTTPS application origin is required');return url.origin;}
