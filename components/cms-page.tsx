import {publishedPage} from '@/lib/cms/server';
import {PublicLayout} from '@/components/public';
export async function CmsPage({slug}:{slug:string}){
 const p=await publishedPage(slug);const policy=['privacy','terms','cookies','acceptable-use','contact'].includes(slug);
 return <PublicLayout label={p.label} title={p.title} subtitle={p.subtitle}><section className="shell section"><div className={policy?'policy-content':'feature-grid'}>{p.sections.map((s,i)=>policy?<section key={i}><h2>{s.title}</h2><p className="cms-copy">{s.description}</p></section>:<article className="feature-card" key={i}><div className="feature-icon">✦</div><h3>{s.title}</h3><p className="cms-copy">{s.description}</p></article>)}</div></section></PublicLayout>;
}
