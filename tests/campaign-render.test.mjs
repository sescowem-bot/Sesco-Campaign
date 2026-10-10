import test from 'node:test';
import assert from 'node:assert/strict';
import {personalize,renderCampaign} from '../lib/campaigns/render.ts';
const design={version:'1',blocks:[{type:'heading',text:'Hello {{first_name}}'},{type:'paragraph',text:'Welcome to {{company_name}}. {{attributes.account_ref}}'},{type:'button',text:'Learn more',url:'https://example.com'}]};
test('personalization supports company and custom fields with missing-name fallback',()=>{
 assert.equal(personalize('Hello {{first_name}}, {{company_name}} {{attributes.account_ref}}',{attributes:{account_ref:'REF123'}},'Example'),'Hello Customer, Example REF123');
});
test('unsupported and malformed variables are rejected',()=>{
 for(const value of ['{{password}}','{{attributes.constructor}}','{{first_name','{{ first_name }} }}','{{attributes.__proto__}}'])assert.throws(()=>personalize(value,{},'Company'));
});
test('recipient text is escaped and never reinterpreted as a variable',()=>{
 const preview=renderCampaign({design,subject:'Welcome',company:'Company',address:'12 Main Street',contact:{first_name:'<img src=x onerror=alert(1)> {{email}}'}});
 assert.ok(preview.html.includes('&lt;img src=x'));assert.ok(preview.html.includes('{{email}}'));assert.ok(!preview.html.includes('<img'));
});
test('unsafe button URLs and empty designs cannot be rendered',()=>{
 for(const url of ['javascript:alert(1)','http://example.com','data:text/html,hello'])assert.throws(()=>renderCampaign({design:{version:'1',blocks:[{type:'button',text:'Click',url}]},subject:'Test',company:'Company',address:'Address'}));
 assert.throws(()=>renderCampaign({design:{version:'1',blocks:[]},subject:'Test',company:'Company',address:'Address'}));
});
test('email rendering includes fixed footer, HTTPS unsubscribe and a safe color',()=>{
 const preview=renderCampaign({design,subject:'Hi {{first_name}}',preheader:'A preview',company:'Company',address:'12 Main Street',color:'red; background:url(x)',contact:{first_name:'Alex'}});
 assert.equal(preview.subject,'Hi Alex');assert.ok(preview.html.includes('12 Main Street'));assert.ok(preview.html.includes('example.invalid/unsubscribe-preview'));assert.ok(preview.html.includes('bgcolor="#102b4e"'));assert.ok(preview.html.includes('A preview'));assert.ok(preview.html.includes('role="presentation"'));
});
test('rendered subjects reject line breaks introduced by personalization',()=>{
 assert.throws(()=>renderCampaign({design,subject:'Hello {{first_name}}',company:'Company',address:'Address',contact:{first_name:'Name\r\nBcc: other@example.com'}}),/line breaks/);
});
