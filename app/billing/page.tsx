import {redirect} from 'next/navigation';
import {supabaseServer} from '@/lib/supabase/server';
import {WorkspaceShell} from '@/components/workspace-shell';
import {BillingCheckout} from '@/components/billing-checkout';
export default async function Billing(){
 const db=await supabaseServer();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/login');
 const [{data:members},{data:staff}]=await Promise.all([db.from('organization_members').select('organization_id,role').eq('user_id',user.id).eq('role','company_admin'),db.from('platform_staff').select('role').eq('user_id',user.id).maybeSingle()]);
 const isOwner=staff?.role==='super_admin';
 const [{data:orgs},{data:plans},{data:transactions}]=await Promise.all([
 db.from('organizations').select('id,name').eq('status','active'),
 db.from('subscription_plans').select('id,name,price_ngn_kobo').eq('is_active',true).eq('is_public',true).gt('price_ngn_kobo',0),
 db.from('payment_transactions').select('id,reference,amount_kobo,status,created_at').order('created_at',{ascending:false}).limit(30)]);
 const allowed=new Set((members||[]).map(x=>x.organization_id));
 const organizations=(orgs||[]).filter(x=>isOwner||allowed.has(x.id));
 return <WorkspaceShell admin={isOwner} title="Billing and subscriptions"><p className="muted">Payments are processed by Paystack. Subscription changes occur only after server verification.</p><BillingCheckout organizations={organizations} plans={plans||[]}/><h2>Recent payment history</h2><div className="table-scroll"><table className="admin-table"><thead><tr><th>Date</th><th>Reference</th><th>Amount</th><th>Status</th></tr></thead><tbody>{(transactions||[]).map(t=><tr key={t.id}><td>{new Date(t.created_at).toLocaleDateString('en-NG')}</td><td>{t.reference}</td><td>₦{(t.amount_kobo/100).toLocaleString('en-NG')}</td><td>{t.status}</td></tr>)}</tbody></table></div></WorkspaceShell>;
}
