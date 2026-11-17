create table public.demos (
 id uuid primary key default gen_random_uuid(),
 team_id uuid references public.teams,
 owner_id uuid not null references public.profiles,
 scrim_id uuid references public.scrims,
 map_id uuid references public.maps,
 name text not null check(length(name) between 1 and 180),
 kind text not null check(kind in ('file','external')),
 external_url text check(external_url is null or external_url ~ '^https://[^[:space:]]+$'),
 object_key text unique,
 expected_bytes bigint check(expected_bytes between 1 and 524288000),
 state text not null check(state in ('pending','ready','failed')),
 created_at timestamptz not null default now(),
 check((kind='external' and external_url is not null and object_key is null and expected_bytes is null and state='ready') or (kind='file' and external_url is null and object_key is not null and expected_bytes is not null and lower(right(name,4))='.dem'))
);
create index demos_team_created on public.demos(team_id,created_at desc);
create index demos_solo on public.demos(owner_id,created_at desc) where team_id is null;
create table public.demo_transfers (
 demo_id uuid primary key references public.demos on delete cascade,
 upload_path text not null,
 updated_at timestamptz not null default now()
);
create table public.reviews (
 id uuid primary key default gen_random_uuid(),
 team_id uuid references public.teams,
 owner_id uuid not null references public.profiles,
 scrim_id uuid references public.scrims,
 demo_id uuid references public.demos,
 map_id uuid not null references public.maps,
 title text not null check(length(title) between 2 and 120),
 round_number integer check(round_number between 1 and 999),
 minute text check(length(minute)<=20),
 description text not null check(length(description)<=5000),
 difficulty text not null default '' check(length(difficulty)<=2000),
 adjustment text not null check(length(adjustment) between 1 and 3000),
 assignee_id uuid references public.profiles,
 status text not null default 'open' check(status in ('open','applied','archived')),
 created_at timestamptz not null default now()
);
create index reviews_team_date on public.reviews(team_id,created_at desc);
create table public.review_tasks (
 review_id uuid primary key references public.reviews,
 session_id uuid not null unique references public.training_sessions
);
alter table public.training_sessions add constraint training_source_review foreign key(source_review_id) references public.reviews;

create function private.validate_private_links() returns trigger language plpgsql security definer set search_path='' as $$
 declare st uuid; su uuid; s public.scrims;
 begin
 if tg_table_name in ('demos','reviews') then
 if new.scrim_id is not null then
 select * into s from public.scrims where id=new.scrim_id;
 if new.team_id is null or new.team_id not in (s.home_team,s.away_team) then raise exception 'SCOPE_MISMATCH'; end if;
 end if;
 end if;
 if tg_table_name='reviews' then
 if new.demo_id is not null then
 select team_id,owner_id into st,su from public.demos where id=new.demo_id;
 if not found or st is distinct from new.team_id or (st is null and su<>new.owner_id) then raise exception 'SCOPE_MISMATCH'; end if;
 end if;
 if new.assignee_id is not null then
 if new.team_id is null and new.assignee_id<>new.owner_id or new.team_id is not null and not exists(select 1 from public.team_members where team_id=new.team_id and user_id=new.assignee_id and active) then raise exception 'INVALID_ASSIGNEE'; end if;
 end if;
 elsif tg_table_name='training_sessions' and new.source_review_id is not null then
 select team_id,owner_id into st,su from public.reviews where id=new.source_review_id;
 if not found or st is distinct from new.team_id or (st is null and su<>new.owner_id) then raise exception 'SCOPE_MISMATCH'; end if;
 end if;
 return new;
 end
$$;
create trigger demo_links before insert or update on public.demos for each row execute function private.validate_private_links();
create trigger review_links before insert or update on public.reviews for each row execute function private.validate_private_links();
create trigger training_links before insert or update on public.training_sessions for each row execute function private.validate_private_links();

alter table public.demos enable row level security;
alter table public.demo_transfers enable row level security;
alter table public.reviews enable row level security;
alter table public.review_tasks enable row level security;
create policy demos_read on public.demos for select to authenticated using(private.scope_read(team_id,owner_id));
create policy reviews_read on public.reviews for select to authenticated using(private.scope_read(team_id,owner_id));
create policy review_tasks_read on public.review_tasks for select to authenticated using(exists(select 1 from public.reviews r where r.id=review_id and private.scope_read(r.team_id,r.owner_id)));
grant select on public.demos,public.reviews,public.review_tasks to authenticated;
revoke all on public.demo_transfers from anon,authenticated;
grant all on public.demo_transfers to service_role;

-- No Storage policies for anon/authenticated on this bucket. Even an active member
-- cannot generate a reusable signed URL. All file operations recheck metadata RLS.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('demos','demos',false,524288000,array['application/octet-stream'])
on conflict(id) do nothing;

create function public.create_demo(p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
 declare t uuid:=nullif(p_data->>'team_id','')::uuid; u uuid:=private.require_user(); rid uuid:=gen_random_uuid(); k text:=p_data->>'kind'; object_name text; clean_name text;
 begin
 if t is not null and not private.operator(t) then raise exception 'FORBIDDEN'; end if;
 clean_name:=regexp_replace(p_data->>'name','[\\/[:cntrl:]]','_','g');
 if k='file' then object_name:=coalesce(t::text,u::text)||'/'||rid::text||'.dem'; end if;
 insert into public.demos(id,team_id,owner_id,scrim_id,map_id,name,kind,external_url,object_key,expected_bytes,state)
 values(rid,t,u,nullif(p_data->>'scrim_id','')::uuid,nullif(p_data->>'map_id','')::uuid,clean_name,k,nullif(p_data->>'external_url',''),object_name,(p_data->>'expected_bytes')::bigint,case when k='file' then 'pending' else 'ready' end); return rid;
 end
$$;
create function public.can_manage_demo(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select private.scope_write(team_id,owner_id) from public.demos where id=p_id),false)
$$;
create function public.retry_demo(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
 begin
 if not public.can_manage_demo(p_id) then raise exception 'FORBIDDEN'; end if;
 update public.demos set state='pending' where id=p_id and kind='file' and state='failed';
 end
$$;
create function public.mark_demo_uploaded(p_id uuid,p_bytes bigint) returns void language plpgsql security definer set search_path='' as $$
 begin
 if auth.role()<>'service_role' then raise exception 'FORBIDDEN'; end if;
 update public.demos set state='ready' where id=p_id and kind='file' and expected_bytes=p_bytes;
 if not found then raise exception 'UPLOAD_SIZE_MISMATCH'; end if;
 end
$$;
create function public.fail_demo(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
 begin
 if not public.can_manage_demo(p_id) then raise exception 'FORBIDDEN'; end if;
 update public.demos set state='failed' where id=p_id and kind='file' and state<>'ready';
 end
$$;
create function public.delete_demo_metadata(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
 begin
 if not public.can_manage_demo(p_id) then raise exception 'FORBIDDEN'; end if;
 update public.reviews set demo_id=null where demo_id=p_id;
 delete from public.demos where id=p_id;
 end
$$;
create function public.save_review(p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
 declare r public.reviews; t uuid:=nullif(p_data->>'team_id','')::uuid; rid uuid; u uuid:=private.require_user();
 begin
 if p_data->>'id' is not null then
 select * into r from public.reviews where id=(p_data->>'id')::uuid for update;
 if r.id is null or not private.scope_write(r.team_id,r.owner_id) then raise exception 'FORBIDDEN'; end if;
 t:=r.team_id; rid:=r.id;
 else
 if t is not null and not private.operator(t) then raise exception 'FORBIDDEN'; end if;
 insert into public.reviews(team_id,owner_id,map_id,title,description,adjustment) values(t,u,(p_data->>'map_id')::uuid,p_data->>'title',p_data->>'description',p_data->>'adjustment') returning id into rid;
 end if;
 update public.reviews set scrim_id=nullif(p_data->>'scrim_id','')::uuid,demo_id=nullif(p_data->>'demo_id','')::uuid,map_id=(p_data->>'map_id')::uuid,title=p_data->>'title',round_number=nullif(p_data->>'round_number','')::int,minute=p_data->>'minute',description=p_data->>'description',difficulty=coalesce(p_data->>'difficulty',''),adjustment=p_data->>'adjustment',assignee_id=nullif(p_data->>'assignee_id','')::uuid,status=coalesce(p_data->>'status','open') where id=rid;
 return rid;
 end
$$;
create function public.review_to_training(p_review uuid,p_start timestamptz,p_minutes integer) returns uuid language plpgsql security definer set search_path='' as $$
 declare r public.reviews; rid uuid; begin
 select * into r from public.reviews where id=p_review for update;
 if r.id is null or not private.scope_write(r.team_id,r.owner_id) then raise exception 'FORBIDDEN'; end if;
 select session_id into rid from public.review_tasks where review_id=r.id;
 if rid is not null then return rid; end if;
 insert into public.training_sessions(team_id,owner_id,title,starts_at,ends_at,map_id,category,priority,assignee_id,goal,expected_minutes,source_review_id)
 values(r.team_id,auth.uid(),r.title,p_start,p_start+make_interval(mins=>p_minutes),r.map_id,'revisao','high',r.assignee_id,r.adjustment,p_minutes,r.id) returning id into rid;
 insert into public.review_tasks values(r.id,rid); return rid;
 end
$$;
-- Close the default EXECUTE-on-PUBLIC surface, then grant only the documented API.
revoke execute on all functions in schema public from public,anon,authenticated;
revoke execute on all functions in schema private from public,anon,authenticated;
grant execute on function private.member(uuid),private.operator(uuid),private.admin(uuid),private.scope_read(uuid,uuid),private.scope_write(uuid,uuid),private.participant(uuid),private.moderator() to authenticated;
-- The public mural policy uses membership even when anonymous (always false).
grant usage on schema private to anon;
grant execute on function private.member(uuid) to anon;
grant execute on function public.update_profile(text,text,text),public.create_team(text,text,text),public.manage_member(uuid,uuid,text,text),public.create_invite(uuid,text,text),public.list_invites(uuid),public.revoke_invite(uuid),public.accept_invite(text),public.set_game_role(uuid,uuid,uuid,text,text),public.mark_notifications_read() to authenticated;
grant execute on function public.manage_training(text,jsonb),public.duplicate_week(uuid,timestamptz,timestamptz),public.record_training(uuid,integer,integer,integer,text,text),public.toggle_task(uuid,boolean),public.respond_attendance(uuid,text),public.save_goal(jsonb),public.save_availability(uuid,timestamptz,timestamptz,text),public.save_play(jsonb),public.add_map(uuid,text) to authenticated;
grant execute on function public.publish_scrim(jsonb),public.close_scrim_post(uuid),public.propose_scrim(jsonb),public.accept_proposal(uuid,integer,uuid),public.resolve_proposal(uuid,integer,uuid,text),public.propose_reschedule(uuid,uuid,timestamptz,timestamptz,uuid[]),public.resolve_reschedule(uuid,integer,uuid,boolean),public.cancel_scrim(uuid,uuid),public.save_room(uuid,uuid,text,text,text),public.report_score(uuid,uuid,jsonb),public.manage_block(uuid,uuid,text,timestamptz,timestamptz,boolean),public.report_post(uuid,text),public.moderate_post(uuid,boolean) to authenticated;
grant execute on function public.create_demo(jsonb),public.can_manage_demo(uuid),public.retry_demo(uuid),public.fail_demo(uuid),public.delete_demo_metadata(uuid),public.save_review(jsonb),public.review_to_training(uuid,timestamptz,integer) to authenticated;
grant execute on function public.mark_demo_uploaded(uuid,bigint) to service_role;
-- All exposed tables are read-only through Data API. Transitions happen in RPCs.
revoke insert,update,delete,truncate,references,trigger on all tables in schema public from anon,authenticated;
