import {beforeAll,afterAll,describe,it,expect} from 'vitest';
import {createClient,type SupabaseClient} from '@supabase/supabase-js';
import {randomUUID} from 'node:crypto';
const url=process.env.TEST_SUPABASE_URL;const anon=process.env.TEST_SUPABASE_ANON_KEY;const service=process.env.TEST_SUPABASE_SERVICE_ROLE_KEY;
if(!url||!anon||!service)throw new Error('NOT VERIFIED: set TEST_SUPABASE_URL, TEST_SUPABASE_ANON_KEY and TEST_SUPABASE_SERVICE_ROLE_KEY for a disposable local Supabase stack.');
if(!['localhost','127.0.0.1'].includes(new URL(url).hostname))throw new Error('Integration tests only run against disposable local Supabase, never a hosted project.');
const admin=createClient(url,service,{auth:{persistSession:false}});const users:{id:string;email:string;db:SupabaseClient}[]=[];let A:string,B:string,session:string,demo:string,objectKey:string;
const map='10000000-0000-4000-8000-000000000001';
async function rpc(db:SupabaseClient,name:string,args:Record<string,unknown>){const result=await db.rpc(name,args);if(result.error)throw new Error(result.error.message);return result.data;}
beforeAll(async()=>{for(let i=0;i<4;i++){const email=`rz-${randomUUID()}@example.test`,password='Local-tests-'+randomUUID();const result=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{display_name:'Test '+i}});if(result.error)throw result.error;const db=createClient(url!,anon!,{auth:{persistSession:false}});const login=await db.auth.signInWithPassword({email,password});if(login.error)throw login.error;users.push({id:result.data.user.id,email,db});}
 A=await rpc(users[0].db,'create_team',{p_name:'API Alpha',p_slug:'api-a-'+randomUUID().slice(0,8),p_timezone:'America/Sao_Paulo'});B=await rpc(users[1].db,'create_team',{p_name:'API Bravo',p_slug:'api-b-'+randomUUID().slice(0,8),p_timezone:'America/Sao_Paulo'});
 const token=await rpc(users[0].db,'create_invite',{p_team:A,p_email:users[3].email,p_role:'player'});await rpc(users[3].db,'accept_invite',{p_token:token});
 const start=new Date(Date.now()+86400000).toISOString();session=await rpc(users[0].db,'manage_training',{p_action:'create',p_data:{team_id:A,title:'Private API training',starts_at:start,map_id:map,category:'awp',priority:'high',expected_minutes:30,goal:'8 of 10'}});
 demo=await rpc(users[0].db,'create_demo',{p_data:{team_id:A,name:'api.dem',kind:'file',expected_bytes:8}});const metadata=await users[0].db.from('demos').select('*').eq('id',demo).single();objectKey=metadata.data.object_key;
 const uploaded=await admin.storage.from('demos').upload(objectKey,Buffer.from('HL2DEMO\0'),{contentType:'application/octet-stream'});if(uploaded.error)throw uploaded.error;
 await admin.rpc('mark_demo_uploaded',{p_id:demo,p_bytes:8});
});
afterAll(async()=>{if(objectKey)await admin.storage.from('demos').remove([objectKey]);
 // Fixtures have private dependencies; deleting test teams requires explicit order.
 if(A){await admin.from('demos').delete().eq('team_id',A);await admin.from('training_tasks').delete().eq('session_id',session);await admin.from('training_sessions').delete().eq('team_id',A);}
 for(const t of [A,B].filter(Boolean)){await admin.from('team_invites').delete().eq('team_id',t);await admin.from('audit_events').delete().eq('team_id',t);await admin.from('team_members').delete().eq('team_id',t);await admin.from('team_public').delete().eq('team_id',t);await admin.from('teams').delete().eq('id',t);}
 for(const u of users)await admin.auth.admin.deleteUser(u.id);
});
describe('real Data API and Storage isolation',()=>{
 it('the active member can read while B and outsider get empty rows',async()=>{for(const [i,expected] of [[3,1],[1,0],[2,0]]){const result=await users[i].db.from('training_sessions').select('*').eq('id',session);expect(result.error).toBeNull();expect(result.data).toHaveLength(expected);}});
 it('direct role promotion is denied by API, not just by UI',async()=>{const r=await users[3].db.from('team_members').update({access_role:'owner'}).eq('team_id',A).eq('user_id',users[3].id);expect(r.error).not.toBeNull();});
 it('private metadata is invisible to B and outsider',async()=>{for(const i of [1,2]){const r=await users[i].db.from('demos').select('*').eq('id',demo);expect(r.error).toBeNull();expect(r.data).toEqual([]);}});
 it('all user identities, even owner, are denied direct Storage download and signing',async()=>{for(const u of users){expect((await u.db.storage.from('demos').download(objectKey)).error).not.toBeNull();expect((await u.db.storage.from('demos').createSignedUrl(objectKey,3600)).error).not.toBeNull();}});
 it('owner removal cuts off the next API request without refreshing token',async()=>{const before=(await users[3].db.auth.getSession()).data.session?.access_token;await rpc(users[0].db,'manage_member',{p_team:A,p_user:users[3].id,p_action:'remove',p_role:'player'});const r=await users[3].db.from('demos').select('*').eq('id',demo);expect(r.data).toEqual([]);expect((await users[3].db.auth.getSession()).data.session?.access_token).toBe(before);});
 it('anonymous visitors see only intentionally public resources',async()=>{const db=createClient(url!,anon!,{auth:{persistSession:false}});const p=await db.from('team_public').select('*').eq('team_id',A);expect(p.data?.[0]).not.toHaveProperty('email');expect(p.data?.[0]).not.toHaveProperty('password');expect((await db.from('room_instructions').select('*')).error).not.toBeNull();});
});
