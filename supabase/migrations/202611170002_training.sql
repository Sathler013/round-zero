create table public.library_templates (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 description text not null,
 category text not null,
 game_role text,
 minutes integer not null check(minutes between 1 and 720),
 goal text not null,
 checklist jsonb not null default '[]',
 published boolean not null default true
);
create table public.training_sessions (
 id uuid primary key default gen_random_uuid(),
 team_id uuid references public.teams,
 owner_id uuid not null references public.profiles,
 title text not null check(char_length(title) between 2 and 120),
 starts_at timestamptz not null,
 ends_at timestamptz not null check(ends_at>starts_at),
 map_id uuid references public.maps,
 side text check(side in ('TR','CT','Ambos')),
 category text not null check(category in ('mira','posicionamento','movimentacao','awp','leitura','decisao','comunicacao','revisao')),
 priority text not null default 'normal' check(priority in ('low','normal','high')),
 status text not null default 'pending' check(status in ('pending','in_progress','completed','cancelled','archived')),
 game_role text,
 assignee_id uuid references public.profiles,
 situation text not null default '',
 goal text not null default '',
 expected_minutes integer not null check(expected_minutes between 1 and 720),
 blocks_time boolean not null default false,
 source_review_id uuid,
 created_at timestamptz not null default now(),
 unique(id,team_id),
 check(team_id is not null or (assignee_id is null or assignee_id=owner_id)),
 check(team_id is not null or not blocks_time)
);
create index sessions_team_date on public.training_sessions(team_id,starts_at);
create index sessions_solo_date on public.training_sessions(owner_id,starts_at) where team_id is null;
create table public.training_tasks (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.training_sessions on delete cascade,
 label text not null check(char_length(label) between 1 and 200),
 done boolean not null default false,
 position integer not null default 0
);
create table public.training_results (
 session_id uuid not null references public.training_sessions,
 user_id uuid not null references public.profiles,
 attempts integer check(attempts>=0),
 hits integer check(hits>=0 and hits<=attempts),
 actual_minutes integer not null default 0 check(actual_minutes between 0 and 1440),
 difficulty text not null default '' check(length(difficulty)<=2000),
 notes text not null default '' check(length(notes)<=5000),
 recorded_at timestamptz not null default now(),
 primary key(session_id,user_id),
 check ((attempts is null and hits is null) or (attempts is not null and hits is not null))
);
create table public.attendance (
 session_id uuid not null references public.training_sessions,
 user_id uuid not null references public.profiles,
 response text not null check(response in ('yes','no','maybe')),
 primary key(session_id,user_id)
);
create table public.goals (
 id uuid primary key default gen_random_uuid(),
 team_id uuid references public.teams,
 owner_id uuid not null references public.profiles,
 title text not null check(char_length(title) between 2 and 120),
 definition text not null check(length(definition) between 1 and 500),
 unit text not null check(length(unit) between 1 and 40),
 target numeric not null check(target>0),
 current_value numeric not null default 0 check(current_value>=0),
 due_at timestamptz,
 created_at timestamptz not null default now()
);
create table public.availability (
 id uuid primary key default gen_random_uuid(),
 team_id uuid not null references public.teams,
 user_id uuid not null references public.profiles,
 starts_at timestamptz not null,
 ends_at timestamptz not null check(ends_at>starts_at),
 kind text not null check(kind in ('available','unavailable')),
 created_at timestamptz not null default now()
);
create table public.playbook (
 id uuid primary key default gen_random_uuid(),
 team_id uuid not null references public.teams,
 map_id uuid not null references public.maps,
 side text not null check(side in ('TR','CT')),
 title text not null check(length(title) between 2 and 120),
 objective text not null default '',
 positions text not null default '',
 utilities text not null default '',
 roles text not null default '',
 calls text not null default '',
 plan_b text not null default '',
 external_url text check(external_url is null or external_url ~ '^https://[^[:space:]]+$'),
 status text not null default 'testing' check(status in ('testing','ready','needs_review','archived')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index playbook_team_map on public.playbook(team_id,map_id,side);

alter table public.library_templates enable row level security;
alter table public.training_sessions enable row level security;
alter table public.training_tasks enable row level security;
alter table public.training_results enable row level security;
alter table public.attendance enable row level security;
alter table public.goals enable row level security;
alter table public.availability enable row level security;
alter table public.playbook enable row level security;
create policy library_read on public.library_templates for select to anon,authenticated using(published);
create policy sessions_read on public.training_sessions for select to authenticated using(private.scope_read(team_id,owner_id));
create policy tasks_read on public.training_tasks for select to authenticated using(exists(select 1 from public.training_sessions s where s.id=session_id and private.scope_read(s.team_id,s.owner_id)));
create policy results_read on public.training_results for select to authenticated using(exists(select 1 from public.training_sessions s where s.id=session_id and private.scope_read(s.team_id,s.owner_id)));
create policy attendance_read on public.attendance for select to authenticated using(exists(select 1 from public.training_sessions s where s.id=session_id and private.scope_read(s.team_id,s.owner_id)));
create policy goals_read on public.goals for select to authenticated using(private.scope_read(team_id,owner_id));
create policy availability_read on public.availability for select to authenticated using(private.member(team_id));
create policy playbook_read on public.playbook for select to authenticated using(private.member(team_id));
grant select on public.library_templates to anon,authenticated;
grant select on public.training_sessions,public.training_tasks,public.training_results,public.attendance,public.goals,public.availability,public.playbook to authenticated;

create function private.validate_session_assignment() returns trigger language plpgsql set search_path = '' as $$
 begin
 if new.team_id is not null and new.assignee_id is not null and not exists(select 1 from public.team_members where team_id=new.team_id and user_id=new.assignee_id and active) then raise exception 'INVALID_ASSIGNEE'; end if;
 return new;
 end
$$;
create trigger session_assignment before insert or update on public.training_sessions for each row execute function private.validate_session_assignment();

-- Structure and execution are distinct: duplication never copies results, attendance or task completion.
create function public.manage_training(p_action text,p_data jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
 declare s public.training_sessions; rid uuid; t uuid; u uuid:=private.require_user(); old_id uuid; start_time timestamptz; template public.library_templates; item jsonb;
 begin
 old_id:=nullif(p_data->>'id','')::uuid;
 if old_id is not null then
 select * into s from public.training_sessions where id=old_id for update;
 if s.id is null or not private.scope_write(s.team_id,s.owner_id) then raise exception 'FORBIDDEN'; end if;
 end if;
 if p_action in ('create','template') then
 t:=nullif(p_data->>'team_id','')::uuid;
 if t is not null and not private.operator(t) then raise exception 'FORBIDDEN'; end if;
 start_time:=(p_data->>'starts_at')::timestamptz;
 if p_action='template' then
 select * into template from public.library_templates where id=(p_data->>'template_id')::uuid and published;
 if template.id is null then raise exception 'NOT_FOUND'; end if;
 end if;
 insert into public.training_sessions(team_id,owner_id,title,starts_at,ends_at,map_id,side,category,priority,game_role,assignee_id,situation,goal,expected_minutes,blocks_time)
 values(t,u,coalesce(template.title,p_data->>'title'),start_time,start_time+make_interval(mins=>coalesce(template.minutes,(p_data->>'expected_minutes')::int)),
 nullif(p_data->>'map_id','')::uuid,nullif(p_data->>'side',''),coalesce(template.category,p_data->>'category'),coalesce(p_data->>'priority','normal'),
 coalesce(template.game_role,p_data->>'game_role'),nullif(p_data->>'assignee_id','')::uuid,coalesce(p_data->>'situation',''),coalesce(template.goal,p_data->>'goal',''),coalesce(template.minutes,(p_data->>'expected_minutes')::int),coalesce((p_data->>'blocks_time')::boolean,false)) returning id into rid;
 for item in select value from jsonb_array_elements(coalesce(template.checklist,p_data->'checklist','[]'::jsonb)) loop
 insert into public.training_tasks(session_id,label) values(rid,item#>>'{}'); end loop;
 elsif p_action='duplicate' then
 start_time:=(p_data->>'starts_at')::timestamptz;
 insert into public.training_sessions(team_id,owner_id,title,starts_at,ends_at,map_id,side,category,priority,game_role,assignee_id,situation,goal,expected_minutes,blocks_time,source_review_id)
 values(s.team_id,u,s.title,start_time,start_time+(s.ends_at-s.starts_at),s.map_id,s.side,s.category,s.priority,s.game_role,s.assignee_id,s.situation,s.goal,s.expected_minutes,s.blocks_time,s.source_review_id) returning id into rid;
 insert into public.training_tasks(session_id,label,position) select rid,label,position from public.training_tasks where session_id=s.id;
 elsif p_action='update' then
 update public.training_sessions set title=p_data->>'title',map_id=nullif(p_data->>'map_id','')::uuid,side=nullif(p_data->>'side',''),category=p_data->>'category',priority=p_data->>'priority',game_role=p_data->>'game_role',assignee_id=nullif(p_data->>'assignee_id','')::uuid,situation=coalesce(p_data->>'situation',''),goal=coalesce(p_data->>'goal',''),expected_minutes=(p_data->>'expected_minutes')::int,ends_at=starts_at+make_interval(mins=>(p_data->>'expected_minutes')::int),blocks_time=coalesce((p_data->>'blocks_time')::boolean,false) where id=s.id;
 rid:=s.id;
 elsif p_action='reschedule' then
 start_time:=(p_data->>'starts_at')::timestamptz;
 update public.training_sessions set starts_at=start_time,ends_at=start_time+(s.ends_at-s.starts_at) where id=s.id; rid:=s.id;
 elsif p_action='status' then
 if s.status in ('cancelled','archived') and p_data->>'status' not in ('pending','archived') then raise exception 'INVALID_TRANSITION'; end if;
 update public.training_sessions set status=p_data->>'status' where id=s.id; rid:=s.id;
 else raise exception 'INVALID_ACTION'; end if;
 return rid;
 end
$$;
create function public.duplicate_week(p_team uuid,p_from timestamptz,p_to timestamptz) returns integer language plpgsql security definer set search_path = '' as $$
 declare s record; n int:=0; u uuid:=private.require_user(); tz text; from_date date; to_date date; next_start timestamptz;
 begin
 if p_team is not null and not private.operator(p_team) then raise exception 'FORBIDDEN'; end if;
 if p_team is null then select timezone into tz from public.profiles where id=u; else select timezone into tz from public.teams where id=p_team; end if;
 from_date:=(p_from at time zone tz)::date; to_date:=(p_to at time zone tz)::date;
 if extract(isodow from from_date)<>1 or extract(isodow from to_date)<>1 or from_date=to_date then raise exception 'WEEK_MUST_START_MONDAY'; end if;
 for s in select * from public.training_sessions where team_id is not distinct from p_team and (p_team is not null or owner_id=u) and starts_at >= (from_date::timestamp at time zone tz) and starts_at < ((from_date+7)::timestamp at time zone tz) and status not in ('cancelled','archived') loop
 next_start:=((s.starts_at at time zone tz)+(to_date-from_date)*interval '1 day') at time zone tz;
 perform public.manage_training('duplicate',jsonb_build_object('id',s.id,'starts_at',next_start)); n:=n+1;
 end loop; return n;
 end
$$;
create function public.record_training(p_session uuid,p_attempts integer,p_hits integer,p_minutes integer,p_difficulty text,p_notes text) returns void language plpgsql security definer set search_path = '' as $$
 declare s public.training_sessions; u uuid:=private.require_user();
 begin
 select * into s from public.training_sessions where id=p_session for update;
 if s.id is null or not private.scope_read(s.team_id,s.owner_id) then raise exception 'FORBIDDEN'; end if;
 if s.team_id is not null and not private.operator(s.team_id) and s.assignee_id is distinct from u then raise exception 'NOT_ASSIGNED'; end if;
 insert into public.training_results values(p_session,u,p_attempts,p_hits,p_minutes,p_difficulty,p_notes,now())
 on conflict(session_id,user_id) do update set attempts=excluded.attempts,hits=excluded.hits,actual_minutes=excluded.actual_minutes,difficulty=excluded.difficulty,notes=excluded.notes,recorded_at=now();
 end
$$;
create function public.toggle_task(p_task uuid,p_done boolean) returns void language plpgsql security definer set search_path = '' as $$
 declare s public.training_sessions;
 begin
 select s1.* into s from public.training_sessions s1 join public.training_tasks t on t.session_id=s1.id where t.id=p_task;
 if not private.scope_write(s.team_id,s.owner_id) and not (private.member(s.team_id) and s.assignee_id=auth.uid()) then raise exception 'FORBIDDEN'; end if;
 update public.training_tasks set done=p_done where id=p_task;
 end
$$;
create function public.respond_attendance(p_session uuid,p_response text) returns void language plpgsql security definer set search_path = '' as $$
 declare s public.training_sessions; u uuid:=private.require_user();
 begin
 select * into s from public.training_sessions where id=p_session;
 if s.id is null or not private.scope_read(s.team_id,s.owner_id) then raise exception 'FORBIDDEN'; end if;
 insert into public.attendance values(p_session,u,p_response) on conflict(session_id,user_id) do update set response=excluded.response;
 end
$$;
create function public.save_goal(p_data jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
 declare g public.goals; rid uuid; t uuid:=nullif(p_data->>'team_id','')::uuid; u uuid:=private.require_user();
 begin
 if p_data->>'id' is not null then
 select * into g from public.goals where id=(p_data->>'id')::uuid for update;
 if g.id is null or not private.scope_write(g.team_id,g.owner_id) then raise exception 'FORBIDDEN'; end if;
 update public.goals set title=p_data->>'title',definition=p_data->>'definition',unit=p_data->>'unit',target=(p_data->>'target')::numeric,current_value=(p_data->>'current_value')::numeric,due_at=nullif(p_data->>'due_at','')::timestamptz where id=g.id; return g.id;
 end if;
 if t is not null and not private.operator(t) then raise exception 'FORBIDDEN'; end if;
 insert into public.goals(team_id,owner_id,title,definition,unit,target,current_value,due_at) values(t,u,p_data->>'title',p_data->>'definition',p_data->>'unit',(p_data->>'target')::numeric,coalesce((p_data->>'current_value')::numeric,0),nullif(p_data->>'due_at','')::timestamptz) returning id into rid; return rid;
 end
$$;
create function public.save_availability(p_team uuid,p_start timestamptz,p_end timestamptz,p_kind text) returns uuid language plpgsql security definer set search_path = '' as $$
 declare rid uuid; begin
 if not private.member(p_team) then raise exception 'FORBIDDEN'; end if;
 insert into public.availability(team_id,user_id,starts_at,ends_at,kind) values(p_team,auth.uid(),p_start,p_end,p_kind) returning id into rid; return rid;
 end
$$;
create function public.save_play(p_data jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
 declare p public.playbook; rid uuid; t uuid:=nullif(p_data->>'team_id','')::uuid;
 begin
 if p_data->>'id' is not null then
 select * into p from public.playbook where id=(p_data->>'id')::uuid for update;
 if p.id is null then raise exception 'NOT_FOUND'; end if; t:=p.team_id;
 end if;
 if not private.operator(t) then raise exception 'FORBIDDEN'; end if;
 if p.id is null then
 insert into public.playbook(team_id,map_id,side,title) values(t,(p_data->>'map_id')::uuid,p_data->>'side',p_data->>'title') returning id into rid;
 else rid:=p.id; end if;
 update public.playbook set map_id=(p_data->>'map_id')::uuid,side=p_data->>'side',title=p_data->>'title',objective=coalesce(p_data->>'objective',''),positions=coalesce(p_data->>'positions',''),utilities=coalesce(p_data->>'utilities',''),roles=coalesce(p_data->>'roles',''),calls=coalesce(p_data->>'calls',''),plan_b=coalesce(p_data->>'plan_b',''),external_url=nullif(p_data->>'external_url',''),status=coalesce(p_data->>'status','testing'),updated_at=now() where id=rid;
 return rid;
 end
$$;
create function public.add_map(p_team uuid,p_name text) returns uuid language plpgsql security definer set search_path = '' as $$
 declare rid uuid; begin
 if not private.admin(p_team) then raise exception 'FORBIDDEN'; end if;
 insert into public.maps(name) values(trim(p_name)) on conflict(name) do update set name=excluded.name returning id into rid; return rid;
 end
$$;
