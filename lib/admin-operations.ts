import {z} from 'zod';
export type OperationCompany={id:string;name:string;status:string};
export function selectOperationCompany(companies:OperationCompany[],requested?:string){
 if(requested){if(!z.string().uuid().safeParse(requested).success)return null;return companies.find(c=>c.id===requested)??null;}
 return companies.find(c=>c.status==='active')??companies[0]??null;
}
export function operationLinks(org:string){
 if(!z.string().uuid().safeParse(org).success)throw new Error('Invalid company');
 return [
 ['Create campaign','Design a message and select its audience.','campaigns','&create=1'],
 ['Upload contacts','Import CSV or Excel with mapping and preview.','imports',''],
 ['Campaign studio','Review drafts, approvals and saved campaigns.','campaigns',''],
 ['Delivery queue','Queue approved campaigns and manage dispatch.','delivery',''],
 ['Reports & analytics','Review delivery outcomes and export reports.','reports',''],
 ['Contacts & audiences','Manage customer records and consent.','contacts',''],
 ['Email templates','Build reusable branded message designs.','templates',''],
 ['Senders & domains','Verify sending domains and sender identities.','senders',''],
 ['Team & roles','Assign verified staff to this company.','team',''],
 ['Brand Studio','Manage the company identity and email branding.','branding',''],
 ['Lists','Organize contacts into reusable lists.','lists',''],
 ['Segments','Define targeted audiences for campaigns.','segments',''],
 ['Email footers','Maintain company details and reusable footers.','footers','']
 ].map(([title,description,path,suffix])=>({title,description,href:`/dashboard/${path}?org=${org}${suffix}`}));
}
