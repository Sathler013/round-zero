import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {openDatabase,asUser} from './db-harness.mjs';
const db=await openDatabase();const c=db.client;let passed=0;
const users=Array.from({length:8},()=>randomUUID());const [a,b,third,player,outside,invited,unverified]=users;
const map='10000000-0000-4000-8000-000000000001';const map2='10000000-0000-4000-8000-000000000002';
const run=(u,sql,params=[])=>asUser(c,u,x=>x.query(sql,params));
const value=async(u,sql,params=[])=>Object.values((await run(u,sql,params)).rows[0])[0];
const call=async(u,name,params=[])=>value(u,`select public.${name}(${params.map((_,i)=>'$'+(i+1)).join(',')})`,params);
async function test(name,fn){await fn();passed++;console.log('PASS',name);}
const fails=async(fn,pattern)=>assert.rejects(fn,pattern);
const future=(days,hour=21)=>{const d=new Date();d.setUTCDate(d.getUTCDate()+days);d.setUTCHours(hour,0,0,0);return d.toISOString();};
let A,B,C,session,demo,review,scrim,negotiation;
try{
 for(let i=0;i<users.length;i++)await c.query('insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values($1,$2,$3,$4)',[users[i],`player${i}@example.test`,i===6?null:new Date(),JSON.stringify({display_name:'Player '+i})]);
 A=await call(a,'create_team',['Alpha','alpha','America/Sao_Paulo']);B=await call(b,'create_team',['Bravo','bravo','America/Sao_Paulo']);C=await call(third,'create_team',['Charlie','charlie','America/Sao_Paulo']);
 await test('owner membership is created atomically',async()=>assert.equal(await value(a,'select access_role from public.team_members where team_id=$1 and user_id=$2',[A,a]),'owner'));
 const token=await call(a,'create_invite',[A,'player3@example.test','player']);
 await test('invite rejects wrong email and cannot be reused',async()=>{
  await fails(()=>call(outside,'accept_invite',[token]),/INVALID_INVITE/);assert.equal(await call(player,'accept_invite',[token]),A);await fails(()=>call(player,'accept_invite',[token]),/INVALID_INVITE/);
 });
 await test('expired, revoked and unverified invitations are rejected',async()=>{
  const expired=await call(a,'create_invite',[A,'player5@example.test','player']);await c.query("update public.team_invites set expires_at=now()-interval '1 second' where token_hash=extensions.digest($1,'sha256')",[expired]);await fails(()=>call(invited,'accept_invite',[expired]),/INVALID_INVITE/);
  const revoked=await call(a,'create_invite',[A,'player5@example.test','player']);const rid=(await run(a,'select * from public.list_invites($1)',[A])).rows.find(x=>!x.used_at&&!x.revoked_at&&new Date(x.expires_at)>new Date()).id;await call(a,'revoke_invite',[rid]);await fails(()=>call(invited,'accept_invite',[revoked]),/INVALID_INVITE/);
  const uv=await call(a,'create_invite',[A,'player6@example.test','player']);await fails(()=>call(unverified,'accept_invite',[uv]),/INVALID_INVITE/);
 });
 await test('player cannot self-promote or write directly',async()=>{
  await fails(()=>run(player,"update public.team_members set access_role='owner' where user_id=$1",[player]),/permission denied/);
  await fails(()=>call(player,'manage_member',[A,player,'role','captain']),/FORBIDDEN/);
  await fails(()=>run(outside,"insert into public.team_members(team_id,user_id,access_role) values($1,$2,'owner')",[A,outside]),/permission denied/);
 });
 const body={team_id:A,title:'AWP + flash',starts_at:future(2),map_id:map,side:'TR',category:'awp',priority:'high',assignee_id:player,goal:'8 de 10',expected_minutes:30,checklist:['Abertura','Flash']};
 session=await call(a,'manage_training',['create',body]);
 await test('team isolation and personal isolation under SQL RLS',async()=>{
  const solo=await call(player,'manage_training',['create',{...body,team_id:null,assignee_id:null,title:'Private notes'}]);
  assert.equal(await value(a,'select count(*)::int from public.training_sessions where id=$1',[solo]),0);
  assert.equal(await value(b,'select count(*)::int from public.training_sessions where id=$1',[session]),0);
  assert.equal(await value(outside,'select count(*)::int from public.training_sessions where id=$1',[session]),0);
  assert.equal(await value(player,'select count(*)::int from public.training_sessions where id=$1',[session]),1);
 });
 await test('session duplication resets execution, attendance and checklists',async()=>{
  const task=await value(a,'select id from public.training_tasks where session_id=$1 limit 1',[session]);await call(player,'toggle_task',[task,true]);
  await call(player,'record_training',[session,10,6,30,'Timing','Notas']);await call(player,'respond_attendance',[session,'yes']);await call(a,'manage_training',['status',{id:session,status:'completed'}]);
  const copy=await call(a,'manage_training',['duplicate',{id:session,starts_at:future(3)}]);
  assert.equal(await value(a,'select status from public.training_sessions where id=$1',[copy]),'pending');
  assert.equal(await value(a,'select count(*)::int from public.training_tasks where session_id=$1 and done',[copy]),0);
  assert.equal(await value(a,'select count(*)::int from public.training_results where session_id=$1',[copy]),0);
  assert.equal(await value(a,'select count(*)::int from public.attendance where session_id=$1',[copy]),0);
 });
 await test('invalid results and cross-team assignments fail',async()=>{
  await fails(()=>call(player,'record_training',[session,10,11,20,'','']),/check constraint/);
  await fails(()=>call(a,'manage_training',['create',{...body,assignee_id:b}]),/INVALID_ASSIGNEE/);
  await fails(()=>call(b,'record_training',[session,10,4,20,'','']),/FORBIDDEN/);
 });
 await test('playbook permission is independent of game role',async()=>{
  await call(a,'set_game_role',[A,player,map,'CT','IGL']);
  await fails(()=>call(player,'save_play',[{team_id:A,map_id:map,side:'CT',title:'Secret play'}]),/FORBIDDEN/);
  await call(a,'save_play',[{team_id:A,map_id:map,side:'CT',title:'Secret play',objective:'Defesa',status:'testing'}]);
  assert.equal(await value(b,'select count(*)::int from public.playbook'),0);
 });
 const start=future(5),end=future(5,23);
 const post=await call(a,'publish_scrim',[{team_id:A,starts_at:start,ends_at:end,region:'BR',level:'Intermediário',map_ids:[map,map2],format:1}]);
 negotiation=await call(b,'propose_scrim',[{team_id:B,post_id:post,starts_at:start,ends_at:future(5,22),map_ids:[map]}]);
 await test('only recipient can accept the exact current version',async()=>{
  await fails(()=>call(b,'accept_proposal',[negotiation,1,B]),/WAIT_OTHER_TEAM/);
  await call(a,'propose_scrim',[{team_id:A,post_id:post,negotiation_id:negotiation,version:1,starts_at:start,ends_at:future(5,22),map_ids:[map2]}]);
  await fails(()=>call(b,'accept_proposal',[negotiation,1,B]),/STALE_VERSION/);
  scrim=await call(b,'accept_proposal',[negotiation,2,B]);
  assert.equal(await call(b,'accept_proposal',[negotiation,2,B]),scrim);
  assert.equal((await c.query('select count(*)::int n from public.reservations where scrim_id=$1',[scrim])).rows[0].n,2);
 });
 demo=await call(a,'create_demo',[{team_id:A,scrim_id:scrim,map_id:map,name:'match.dem',kind:'file',expected_bytes:128}]);
 review=await call(a,'save_review',[{team_id:A,scrim_id:scrim,demo_id:demo,map_id:map,title:'Flash antes do avanço',description:'Round 12',difficulty:'Timing',adjustment:'Esperar a chamada',status:'open'}]);
 await test('opponent sees room but never private reviews, demos or source tasks',async()=>{
  await call(a,'save_room',[scrim,A,'server.example.test:27015','secret-test-only','Conectar 10 minutos antes']);
  assert.equal(await value(b,'select count(*)::int from public.room_instructions where scrim_id=$1',[scrim]),1);
  assert.equal(await value(third,'select count(*)::int from public.room_instructions where scrim_id=$1',[scrim]),0);
  assert.equal(await value(b,'select count(*)::int from public.reviews where id=$1',[review]),0);
  assert.equal(await value(b,'select count(*)::int from public.demos where id=$1',[demo]),0);
  const task=await call(a,'review_to_training',[review,future(6),30]);assert.equal(await call(a,'review_to_training',[review,future(6),30]),task);
  assert.equal(await value(b,'select count(*)::int from public.training_sessions where id=$1',[task]),0);
  await fails(()=>call(b,'save_review',[{team_id:B,demo_id:demo,map_id:map,title:'Leak',description:'x',adjustment:'y'}]),/SCOPE_MISMATCH/);
 });
 await test('failed reschedule preserves both original reservations',async()=>{
  await call(b,'manage_block',[B,null,'Indisponível',future(7),future(7,22),true]);
  const ver=await call(a,'propose_reschedule',[scrim,A,future(7),future(7,22),[map2]]);
  await fails(()=>call(b,'resolve_reschedule',[scrim,ver,B,true]),/SCHEDULE_CONFLICT/);
  const rows=(await c.query('select lower(slot) as start from public.reservations where scrim_id=$1 and active',[scrim])).rows;assert.equal(rows.length,2);rows.forEach(r=>assert.equal(r.start.toISOString(),start));
  assert.equal(await value(a,'select state from public.scrim_changes where scrim_id=$1 and version=$2',[scrim,ver]),'pending');
 });
 await test('adjacent [start,end) reservations are allowed and training blocks share the same rule',async()=>{
  await call(b,'manage_block',[B,null,'Adjacente',future(7,22),future(7,23),true]);
  await fails(()=>call(a,'manage_training',['create',{...body,starts_at:start,blocks_time:true}]),/conflicting key value violates exclusion constraint/);
  const info=await call(player,'save_availability',[A,start,future(5,22),'unavailable']);assert.ok(info);
 });
 await test('removing a member revokes the next read with the same identity',async()=>{
  assert.equal(await value(player,'select count(*)::int from public.demos where id=$1',[demo]),1);
  await call(a,'manage_member',[A,player,'remove','player']);
  assert.equal(await value(player,'select count(*)::int from public.demos where id=$1',[demo]),0);
  assert.equal(await value(player,'select count(*)::int from public.training_sessions where id=$1',[session]),0);
  assert.equal(await call(player,'can_manage_demo',[demo]),false);
 });
 await test('cancel is idempotent, frees both slots and retains history',async()=>{
  await call(a,'cancel_scrim',[scrim,A]);await call(a,'cancel_scrim',[scrim,A]);
  assert.equal(await value(b,'select state from public.scrims where id=$1',[scrim]),'cancelled');
  assert.equal((await c.query('select count(*)::int n from public.reservations where scrim_id=$1 and active',[scrim])).rows[0].n,0);
 });
 await test('simultaneous accepts: one wins with no partial reservation or notification',async()=>{
  const prepare=async(u,t)=>{const p=await call(a,'publish_scrim',[{team_id:A,starts_at:future(10),ends_at:future(10,23),region:'BR',level:'Avançado',map_ids:[map],format:1}]);return call(u,'propose_scrim',[{team_id:t,post_id:p,starts_at:future(10),ends_at:future(10,22),map_ids:[map]}]);};
  const n1=await prepare(b,B),n2=await prepare(third,C);const notifBefore=Number((await c.query("select count(*)::int n from public.notifications where kind='confirmed'")).rows[0].n);
  const c1=db.postgres.getPgClient(),c2=db.postgres.getPgClient();await c1.connect();await c2.connect();await c1.query("set log_min_messages='PANIC'; set log_min_error_statement='PANIC'");await c2.query("set log_min_messages='PANIC'; set log_min_error_statement='PANIC'");
  const results=await Promise.allSettled([asUser(c1,a,x=>x.query('select public.accept_proposal($1,1,$2)',[n1,A])),asUser(c2,a,x=>x.query('select public.accept_proposal($1,1,$2)',[n2,A]))]);
  await c1.end();await c2.end();assert.equal(results.filter(x=>x.status==='fulfilled').length,1);assert.match(results.find(x=>x.status==='rejected').reason.message,/SCHEDULE_CONFLICT/);
  const ids=(await c.query('select id from public.scrims where negotiation_id=any($1::uuid[])',[[n1,n2]])).rows;assert.equal(ids.length,1);
  assert.equal((await c.query('select count(*)::int n from public.reservations where scrim_id=$1',[ids[0].id])).rows[0].n,2);
  assert.equal(Number((await c.query("select count(*)::int n from public.notifications where kind='confirmed'")).rows[0].n)-notifBefore,2);
  const loser=results[0].status==='rejected'?n1:n2;assert.equal((await c.query("select count(*)::int n from public.notifications where resource_id=$1 and kind='confirmed'",[loser])).rows[0].n,0);
 });
 await test('command receipts prevent duplicate creation and reject changed retries',async()=>{
  const key=randomUUID();const p={...body,starts_at:future(15),assignee_id:null,action:'create'};
  const one=await call(a,'execute_command',[key,'training.save',p]);assert.equal(await call(a,'execute_command',[key,'training.save',p]),one);
  await fails(()=>call(a,'execute_command',[key,'training.save',{...p,title:'Changed'}]),/IDEMPOTENCY_CONFLICT/);
  const key2=randomUUID();await call(a,'execute_command',[key2,'invite.create',{team_id:A,email:'player5@example.test',role:'player'}]);
  assert.equal((await c.query('select response from private.mutation_receipts where request_key=$1',[key2])).rows[0].response,null);
 });
 await test('one opening is consumed atomically; successful reschedule moves both slots',async()=>{
  const start=future(20),end=future(20,23);
  const p=await call(a,'publish_scrim',[{team_id:A,starts_at:start,ends_at:end,region:'BR',level:'Intermediário',map_ids:[map],format:1}]);
  const n=await call(b,'propose_scrim',[{team_id:B,post_id:p,starts_at:start,ends_at:future(20,22),map_ids:[map]}]);
  const nOther=await call(third,'propose_scrim',[{team_id:C,post_id:p,starts_at:future(20,22),ends_at:end,map_ids:[map]}]);
  const sid=await call(a,'accept_proposal',[n,1,A]);
  await fails(()=>call(a,'accept_proposal',[nOther,1,A]),/PROPOSAL_EXPIRED/);
  const v=await call(a,'propose_reschedule',[sid,A,future(21),future(21,22),[map]]);
  await call(b,'resolve_reschedule',[sid,v,B,true]);
  const reservations=(await c.query('select lower(slot) as st from public.reservations where scrim_id=$1 and active',[sid])).rows;assert.equal(reservations.length,2);reservations.forEach(r=>assert.equal(r.st.toISOString(),future(21)));
  const direct=await call(a,'invite_rematch',[sid,A,future(22),future(22,22)]);
  const postId=await value(a,'select post_id from public.negotiations where id=$1',[direct]);
  assert.equal(await value(third,'select count(*)::int from public.scrim_posts where id=$1',[postId]),0);
  assert.equal(await value(b,'select count(*)::int from public.scrim_posts where id=$1',[postId]),1);
 });
 await test('checklists are editable only within their original session scope',async()=>{
  const task=await call(a,'save_task',[session,null,'Novo exercício',2,false]);
  await fails(()=>call(b,'save_task',[session,task,'Leaked task',2,false]),/FORBIDDEN/);
  await call(a,'save_task',[session,task,'Editado',2,false]);
  assert.equal(await value(a,'select label from public.training_tasks where id=$1',[task]),'Editado');
  await call(a,'save_task',[session,task,'Editado',2,true]);
  assert.equal(await value(a,'select count(*)::int from public.training_tasks where id=$1',[task]),0);
 });
 await test('cleanup cannot purge a recently resumed upload and is service-only',async()=>{
  const pending=await call(a,'create_demo',[{team_id:A,name:'old.dem',kind:'file',expected_bytes:20}]);
  await c.query("update public.demos set created_at=now()-interval '72 hours',activity_at=now()-interval '72 hours' where id=$1",[pending]);
  await fails(()=>call(a,'claim_stale_upload',[pending,new Date(Date.now()-48*3600000).toISOString()]),/permission denied/);
  await call(a,'touch_demo_upload',[pending]);
  const claim=async()=>{await c.query('begin');try{await c.query('set local role service_role');await c.query("select set_config('request.jwt.claim.role','service_role',true)");const r=await c.query("select public.claim_stale_upload($1,now()-interval '48 hours') as claimed",[pending]);await c.query('commit');return r.rows[0].claimed;}catch(e){await c.query('rollback');throw e;}};
  assert.equal(await claim(),false);
  await c.query("update public.demos set activity_at=now()-interval '72 hours' where id=$1",[pending]);
  assert.equal(await claim(),true);assert.equal(await value(a,'select state from public.demos where id=$1',[pending]),'failed');
 });
 await test('bucket is private and privileged finalize cannot be called by a user',async()=>{
  assert.equal((await c.query("select public from storage.buckets where id='demos'")).rows[0].public,false);
  await fails(()=>call(a,'mark_demo_uploaded',[demo,128]),/permission denied/);
  await fails(()=>run(b,'select * from public.demo_transfers'),/permission denied/);
  await fails(()=>run(outside,'select * from public.team_invites'),/permission denied/);
 });
 await test('owner must transfer ownership before leaving',async()=>await fails(()=>call(a,'manage_member',[A,a,'leave','player']),/TRANSFER_OWNER_FIRST/));
 console.log(`\n${passed} database scenarios passed against clean PostgreSQL. Auth/Storage HTTP require the separate Supabase integration suite.`);
}finally{await db.close();}
