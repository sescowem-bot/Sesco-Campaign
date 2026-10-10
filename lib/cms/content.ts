import {z} from 'zod';
import defaults from './defaults.json' with {type:'json'};
export const pageSlugs=['home','features','solutions','pricing','about','resources','faq','contact','privacy','terms','cookies','acceptable-use','login','register'] as const;
export const cmsSlug=z.enum(['site',...pageSlugs]);
const publicHref=z.enum(['/','/features','/solutions','/pricing','/about','/resources','/faq','/contact','/privacy','/terms','/cookies','/acceptable-use','/login','/register']);
const text=(max:number)=>z.string().trim().max(max);
export const pageSchema=z.object({label:text(80),title:text(180).min(1),subtitle:text(500),sections:z.array(z.object({title:text(180).min(1),description:text(2000)})).max(20),primary_label:text(60),primary_href:publicHref,secondary_label:text(60),secondary_href:publicHref,section_title:text(180),section_subtitle:text(500),highlight_title:text(180),highlight_text:text(1000)});
const logo=z.string().max(500).refine(value=>{if(!value)return true;try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password;}catch{return false;}},'Use an HTTPS image URL without credentials.');
export const siteSchema=z.object({display_name:text(120).min(2),tagline:text(240),primary_color:z.string().regex(/^#[0-9a-fA-F]{6}$/),logo_url:logo,font:z.enum(['system','arial','georgia']),operator_name:text(120).min(1),footer_text:text(500),support_email:z.union([z.literal(''),z.string().email().max(254)]),nav:z.array(z.object({label:text(60).min(1),href:publicHref})).min(1).max(8)});
export type PageContent=z.infer<typeof pageSchema>;
export type SiteContent=z.infer<typeof siteSchema>;
export const siteDefaults:SiteContent={display_name:'SESCO Campaign Cloud',tagline:'Professional business communication',primary_color:'#102b4e',logo_url:'',font:'system',operator_name:'Sesco Studio',footer_text:'Professional business communication, thoughtfully designed.',support_email:'',nav:[{label:'Features',href:'/features'},{label:'Solutions',href:'/solutions'},{label:'Pricing',href:'/pricing'},{label:'About',href:'/about'},{label:'Resources',href:'/resources'},{label:'Contact',href:'/contact'}]};
export function pageDefault(slug:string):PageContent{return pageSchema.parse(defaults[slug as keyof typeof defaults]);}
export function validateContent(slug:string,value:unknown){return slug==='site'?siteSchema.parse(value):pageSchema.parse(value);}
export function publicContent(slug:string,value:unknown){const fallback=slug==='site'?siteDefaults:pageDefault(slug);const merged=slug==='site'&&value&&typeof value==='object'?{...siteDefaults,...value}:value;const parsed=(slug==='site'?siteSchema:pageSchema).safeParse(merged);return parsed.success?parsed.data:fallback;}
export function contrastInk(hex:string){const channels=hex.slice(1).match(/../g)!.map(v=>{const c=parseInt(v,16)/255;return c<=0.04045?c/12.92:((c+0.055)/1.055)**2.4;});return channels[0]*0.2126+channels[1]*0.7152+channels[2]*0.0722>0.179?'#102033':'#ffffff';}
