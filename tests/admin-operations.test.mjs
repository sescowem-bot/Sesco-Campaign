import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {selectOperationCompany,operationLinks} from '../lib/admin-operations.ts';
const a={id:'20000000-0000-4000-8000-000000000001',name:'A',status:'suspended'};
const b={id:'20000000-0000-4000-8000-000000000002',name:'B',status:'active'};
test('admin company selection uses active default and never substitutes an invalid requested company',()=>{
 assert.equal(selectOperationCompany([a,b]),b);assert.equal(selectOperationCompany([a,b],a.id),a);
 assert.equal(selectOperationCompany([a,b],'bad'),null);assert.equal(selectOperationCompany([a],b.id),null);assert.equal(selectOperationCompany([]),null);
});
test('every campaign operation keeps the selected tenant and resolves to an implemented page',()=>{
 for(const link of operationLinks(b.id)){const url=new URL(link.href,'https://example.com');assert.equal(url.searchParams.get('org'),b.id);assert.ok(existsSync(new URL('../app'+url.pathname+'/page.tsx',import.meta.url)));}
 assert.equal(new URL(operationLinks(b.id)[0].href,'https://example.com').searchParams.get('create'),'1');
 assert.throws(()=>operationLinks('bad'));
});
