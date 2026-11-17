import EmbeddedPostgres from 'embedded-postgres';
import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import { resolve } from 'node:path';
import { tmpdir } from 'node:os';
export async function openDatabase() {
  const folder=await mkdtemp(resolve(tmpdir(),'round-zero-db-'));
  const postgres=new EmbeddedPostgres({databaseDir:resolve(folder,'data'),user:'postgres',password:'local-test-only',port:55439,persistent:false,postgresFlags:["-c","unix_socket_directories="],onLog:(m)=>{if(m.includes("ERROR")||m.includes("FATAL"))console.error(m)},onError:(m)=>console.error(m)});
  await postgres.initialise(); await postgres.start();
  const client=postgres.getPgClient(); await client.connect();
  await client.query("set log_min_messages='PANIC'; set log_min_error_statement='PANIC'");
  await client.query(`create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
    create schema auth; create schema storage;
    create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb default '{}');
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function auth.role() returns text language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claim.role',true),''),'anon')$$;
    grant usage on schema auth to anon,authenticated,service_role;
    grant execute on function auth.uid(),auth.role() to anon,authenticated,service_role;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    grant usage on schema public to anon,authenticated,service_role;`);
  for (const file of (await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort()) {
    try {await client.query(await readFile(resolve('supabase/migrations',file),'utf8')); console.log('Migration OK:',file);}
    catch(error){await client.end();await postgres.stop();await rm(folder,{recursive:true,force:true});throw new Error(file+': '+error.message,{cause:error});}
  }
  await client.query(await readFile('supabase/seed.sql','utf8'));
  return {client,postgres,async close(){await client.end();await postgres.stop();await rm(folder,{recursive:true,force:true});}};
}
export async function asUser(client,user,fn) {
 await client.query('begin');
 try {await client.query('set local role authenticated');await client.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[user]);const result=await fn(client);await client.query('commit');return result;}
 catch(error){await client.query('rollback');throw error;}
}
