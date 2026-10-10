import {PublicLayout} from '@/components/public';
import {publishedPage,publishedSite} from '@/lib/cms/server';
export default async function Contact(){
 const [page,site]=await Promise.all([publishedPage('contact'),publishedSite()]);
 return <PublicLayout label={page.label} title={page.title} subtitle={page.subtitle}><section className="shell section"><div className="contact-card">{page.sections.map((section,i)=><section key={i}><h2>{section.title}</h2><p>{section.description}</p></section>)}{site.support_email?<a className="btn" href={'mailto:'+site.support_email}>Email our team</a>:<p>Online contact details are currently unavailable. Please use the contact details provided by your company representative.</p>}</div></section></PublicLayout>;
}
