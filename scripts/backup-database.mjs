process.umask(0o077);
import {spawn} from 'node:child_process';
import {mkdir,rename,chmod,unlink} from 'node:fs/promises';
import {join,resolve} from 'node:path';
const connection=process.env.DATABASE_URL,directory=process.env.BACKUP_DIRECTORY;
if(!connection||!directory)throw new Error('Set server-only DATABASE_URL and an external BACKUP_DIRECTORY.');
const outputDir=resolve(directory);const project=resolve(import.meta.dirname,'..');
if(outputDir===project||outputDir.startsWith(project+'/'))throw new Error('Store database backups outside the source project.');
await mkdir(outputDir,{recursive:true,mode:0o700});
const stamp=new Date().toISOString().replaceAll(':','-');const output=join(outputDir,`sesco-${stamp}.dump`),temporary=output+'.partial';
const child=spawn('pg_dump',['--format=custom','--no-owner','--no-acl','--file',temporary],{env:{PATH:process.env.PATH,HOME:process.env.HOME,PGDATABASE:connection,PGCONNECT_TIMEOUT:'10',...(process.env.PGSSLMODE?{PGSSLMODE:process.env.PGSSLMODE}:{}),...(process.env.PGSSLROOTCERT?{PGSSLROOTCERT:process.env.PGSSLROOTCERT}:{})},stdio:'ignore'});
try{await new Promise((resolve,reject)=>{child.once('error',()=>reject(new Error('pg_dump is unavailable.')));child.once('exit',code=>code===0?resolve():reject(new Error('Database backup failed. Review credentials and database connectivity privately.')));});await chmod(temporary,0o600);await rename(temporary,output);console.log('Database archive created. Encrypt it, copy it off-host and perform a restore rehearsal before treating it as a verified backup.');}
catch(e){await unlink(temporary).catch(()=>{});throw e;}
