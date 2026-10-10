import {createHmac,timingSafeEqual} from 'node:crypto';
export function paymentSignatureValid(raw:Uint8Array,signature:string|null,secret:string){if(!secret||!signature||!/^[0-9a-f]{128}$/i.test(signature))return false;const expected=createHmac('sha512',secret).update(raw).digest();const actual=Buffer.from(signature,'hex');return actual.length===expected.length&&timingSafeEqual(actual,expected);}
