import test from 'node:test';
import assert from 'node:assert/strict';
import {readdirSync} from 'node:fs';
import {pageDefault,pageSchema,publicContent,siteDefaults,siteSchema,contrastInk} from '../lib/cms/content.ts';
test('CMS link and image validation reject executable schemes and arbitrary routes',()=>{
 assert.throws(()=>siteSchema.parse({...siteDefaults,logo_url:'javascript:alert(1)'}));
 assert.throws(()=>siteSchema.parse({...siteDefaults,logo_url:'https://user:pass@example.com/logo.png'}));
 assert.throws(()=>siteSchema.parse({...siteDefaults,nav:[{label:'Bad link',href:'//other.example.com'}]}));
 assert.throws(()=>pageSchema.parse({...pageDefault('home'),primary_href:'/admin'}));
 assert.throws(()=>siteSchema.parse({...siteDefaults,font:'url(https://example.com)'}));
});
test('CMS public reads fall back safely and preserve partial legacy brand identity',()=>{
 assert.equal(publicContent('site',{display_name:'Existing Brand',tagline:'Existing tagline',primary_color:'#123456'}).display_name,'Existing Brand');
 assert.deepEqual(publicContent('home',{title:'Malformed published content'}),pageDefault('home'));
 assert.deepEqual(publicContent('site',{...siteDefaults,primary_color:'invalid'}),siteDefaults);
 for(const slug of ['home','features','solutions','pricing','about','resources','faq','contact','privacy','terms','cookies','acceptable-use','login','register'])assert.ok(pageDefault(slug).title);
});
test('theme contrast uses legible foreground for light and dark backgrounds',()=>{
 assert.equal(contrastInk('#ffffff'),'#102033');assert.equal(contrastInk('#000000'),'#ffffff');assert.equal(contrastInk('#102b4e'),'#ffffff');
});
test('all authored Markdown lives in MD except the GitHub README',()=>{
 const root=new URL('../',import.meta.url);const found=[];
 const walk=(url,prefix='')=>{for(const item of readdirSync(url,{withFileTypes:true})){if(['node_modules','.next','.git'].includes(item.name))continue;const path=prefix+item.name;if(item.isDirectory())walk(new URL(item.name+'/',url),path+'/');else if(item.name.endsWith('.md'))found.push(path);}};
 walk(root);assert.ok(found.includes('README.md'));assert.ok(found.includes('MD/AGENTS.md'));assert.ok(found.every(path=>path==='README.md'||path.startsWith('MD/')));
});
