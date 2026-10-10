import {createHash,timingSafeEqual} from 'node:crypto';
import {Webhook} from 'svix';
import {z} from 'zod';
export function bearerMatches(value:string|null,secret:string|undefined):boolean {
 if(!secret||secret.length<32||!value?.startsWith('Bearer '))return false;
 const a=Buffer.from(value.slice(7)),b=Buffer.from(secret);return a.length===b.length&&timingSafeEqual(a,b);
}
export type DeliveryEvent={key:string;message:string;type:string;time:string};
export function resendEvent(raw:string,headers:Headers,secret:string):DeliveryEvent|null {
 new Webhook(secret).verify(raw,{'svix-id':headers.get('svix-id')||'','svix-timestamp':headers.get('svix-timestamp')||'','svix-signature':headers.get('svix-signature')||''});
 const payload=JSON.parse(raw);
 const parsed=z.object({type:z.string(),created_at:z.string().datetime(),data:z.object({email_id:z.string().min(1).max(300)})}).parse(payload);
 const map:Record<string,string>={'email.sent':'accepted','email.delivered':'delivered','email.bounced':'bounce','email.complained':'complaint','email.failed':'failed','email.delivery_delayed':'delayed','email.opened':'opened','email.clicked':'clicked'};
 if(!map[parsed.type])return null;
 return {key:headers.get('svix-id')!,message:parsed.data.email_id,type:map[parsed.type],time:parsed.created_at};
}
export function brevoEvent(raw:string):DeliveryEvent|null {
 const data=z.object({event:z.string(),'message-id':z.string().min(1).max(300),ts_event:z.number().finite().optional(),ts:z.number().finite().optional()}).parse(JSON.parse(raw));
 const map:Record<string,string>={request:'accepted',sent:'accepted',delivered:'delivered',hard_bounce:'bounce',hardBounce:'bounce',spam:'complaint',unsubscribed:'unsubscribe',unsubscribe:'unsubscribe',blocked:'blocked',invalid_email:'failed',invalid:'failed',soft_bounce:'delayed',softBounce:'delayed',deferred:'delayed',opened:'opened',unique_opened:'opened',uniqueOpened:'opened',click:'clicked'};
 if(!map[data.event])return null;
 const seconds=data.ts_event??data.ts;if(seconds===undefined)throw new Error('Event timestamp required');
 const time=new Date(seconds*1000).toISOString();
 const message=data['message-id'].replace(/^<|>$/g,'');
 return {key:createHash('sha256').update(JSON.stringify([message,data.event,seconds])).digest('hex'),message,type:map[data.event],time};
}
