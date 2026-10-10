'use client';
import {useEffect,useState} from 'react';
import Link from 'next/link';
export function PaymentReturn({reference}:{reference:string}){
 const [message,setMessage]=useState('Verifying your payment securely…');
 useEffect(()=>{if(!reference){setMessage('Missing payment reference.');return;}let cancelled=false;
 fetch('/api/billing/verify',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({reference})}).then(async r=>{const b=await r.json();if(!r.ok)throw Error(b.error||'Unable to verify payment');return b;}).then(b=>{if(!cancelled)setMessage(['activated','already_processed'].includes(b.result)?'Payment verified. Your subscription is active.':'Payment status: '+b.result+'. Contact support if you were charged.');}).catch(e=>{if(!cancelled)setMessage(e instanceof Error?e.message:'Verification unavailable. Please try again later.');});return()=>{cancelled=true;};
 },[reference]);return <div className="shell section"><h1>Payment verification</h1><p role="status">{message}</p><Link href="/billing" className="btn secondary">Back to billing</Link></div>;
}
