'use client';
import {useActionState} from 'react';
import {senderAction} from '@/app/dashboard/senders/actions';
export function SenderForm({org,action,label,children}:{org:string;action:string;label:string;children?:React.ReactNode}) {
 const [result,submit,pending]=useActionState(senderAction,{});
 return <form action={submit} className="admin-form sender-form"><input type="hidden" name="organization_id" value={org}/><input type="hidden" name="action" value={action}/>{children}<button className="btn" disabled={pending}>{pending?'Processing…':label}</button><div aria-live="polite">{result.error&&<p className="feedback-error" role="alert">{result.error}</p>}{result.success&&<p className="feedback-success">{result.success}</p>}</div></form>;
}
