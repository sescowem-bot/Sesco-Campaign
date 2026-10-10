export function httpsApplicationOrigin(value:string|undefined):boolean {
 try{const url=new URL(value||'');return url.protocol==='https:'&&!url.username&&!url.password&&url.pathname==='/'&&!url.search&&!url.hash;}catch{return false;}
}
export type ReadinessInput={org:string;active:boolean|null;senderReady:boolean|null;addressReady:boolean|null;eligible:number|null;dispatch:boolean;origin:string|undefined;serverCredentials:boolean};
export function ownerReadiness(input:ReadinessInput) {
 const rows:[string,boolean|null,string,string][]=[
 ['Workspace',input.active,'Your brand workspace must be active.','/admin/companies'],
 ['Sending identity',input.senderReady,'Connect an active sender with a verified domain and enabled provider.','/admin/workspace#email-connection'],
 ['Business address',input.addressReady,'Your postal address appears in campaign emails.',`/dashboard/branding?org=${input.org}`],
 ['Opted-in audience',input.eligible===null?null:input.eligible>0,input.eligible===null?'Audience count could not be loaded.':`${input.eligible} eligible contacts across this workspace. A selected list may contain fewer.`,`/dashboard/imports?org=${input.org}`],
 ['Server connection',input.serverCredentials,'The server database credentials must be configured. Presence does not confirm access.','/admin/providers'],
 ['Audience dispatch',input.dispatch&&httpsApplicationOrigin(input.origin),'Audience sending needs dispatch enabled and a valid HTTPS application address. Test emails can be sent separately.',`/dashboard/delivery?org=${input.org}`]
 ];
 return rows.map(([label,ready,detail,href])=>({label,state:ready===null?'Unavailable':ready?'Ready':'Needs attention',detail,href}));
}
