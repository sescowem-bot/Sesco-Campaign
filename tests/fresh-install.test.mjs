import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
test('consolidated fresh installation creates the owner workspace atomically',async t=>{
 const db=new PGlite();t.after(()=>db.close());
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
 create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.role() returns text language sql stable as $$select nullif(current_setting('request.jwt.claim.role',true),'')$$;`);
 await db.exec(readFileSync(new URL('../supabase/SESCO_Complete_Fresh_Install.sql',import.meta.url),'utf8').replace('create extension if not exists pgcrypto;',''));
 assert.equal((await db.query('select count(*)::int as n from platform_workspace')).rows[0].n,1);
 assert.equal((await db.query('select o.status from organizations o join platform_workspace w on w.organization_id=o.id')).rows[0].status,'active');
});
