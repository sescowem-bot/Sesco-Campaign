export const metadata={robots:{index:false,follow:false},referrer:'no-referrer' as const};
import {z} from 'zod';
import {PublicLayout} from '@/components/public';
export default async function Unsubscribe({searchParams}:{searchParams:Promise<{token?:string}>}) {
 const {token}=await searchParams;const valid=z.string().uuid().safeParse(token).success;
 return <PublicLayout label="EMAIL PREFERENCES" title="Unsubscribe from marketing emails" subtitle="Confirm your request to stop marketing messages from the company that sent this email."><section className="shell section"><div className="contact-card">{valid?<form action={`/api/email/unsubscribe?token=${encodeURIComponent(token!)}`} method="post"><p>Opening this page does not change your preferences. Use the button below to confirm.</p><button className="btn" type="submit">Confirm unsubscribe</button></form>:<p>Open the unsubscribe link in the email you received.</p>}</div></section></PublicLayout>;
}
