'use client';
import {useActionState} from 'react';
import {saveBrand} from '@/app/dashboard/actions';
type Brand={display_name?:string;tagline?:string;primary_color?:string;secondary_color?:string;website_url?:string;contact_email?:string;postal_address?:string;social_links?:Record<string,string>};
export function CompanyBrandEditor({org,brand}:{org:string;brand:Brand|null}){
 const [state,action,pending]=useActionState(saveBrand,{});
 return <form className="admin-form" action={action}><input type="hidden" name="organization_id" value={org}/><h2>Company identity</h2>
 <label>Display name<input name="display_name" required minLength={2} maxLength={160} defaultValue={brand?.display_name||''}/></label>
 <label>Tagline<input name="tagline" maxLength={240} defaultValue={brand?.tagline||''}/></label>
 <div className="form-two"><label>Primary color<input type="color" name="primary_color" defaultValue={brand?.primary_color||'#102b4e'}/></label><label>Accent color<input type="color" name="secondary_color" defaultValue={brand?.secondary_color||'#356df3'}/></label></div>
 <label>Website URL<input type="url" name="website_url" placeholder="https://company.example" defaultValue={brand?.website_url||''}/></label>
 <label>Contact email<input type="email" name="contact_email" defaultValue={brand?.contact_email||''}/></label>
 <label>Postal address<textarea name="postal_address" rows={3} defaultValue={brand?.postal_address||''}/></label>
 <h3>Social links</h3>{(['facebook','instagram','linkedin','x'] as const).map(key=><label key={key}>{key}<input type="url" name={key} placeholder="https://" defaultValue={brand?.social_links?.[key]||''}/></label>)}
 <button className="btn" disabled={pending}>{pending?'Saving…':'Save company branding'}</button><p role="status">{state.error||state.success}</p><p className="muted">Logo upload and media library are planned for a subsequent batch. Brand colors and text save to Supabase.</p></form>;
}
