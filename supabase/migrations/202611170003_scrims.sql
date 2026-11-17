create table public.scrim_posts (
 id uuid primary key default gen_random_uuid(),
 team_id uuid not null references public.team_public(team_id),
 starts_at timestamptz not null,
 ends_at timestamptz not null check(ends_at>starts_at and ends_at<=starts_at+interval '12 hours'),
 region text not null check(length(region) between 2 and 80),
 level text not null check(length(level) between 2 and 40),
 map_ids uuid[] not null check(cardinality(map_ids) between 1 and 10),
 format integer not null check(format in (1,2)),
 state text not null default 'open' check(state in ('open','consumed','closed','moderated')),
 expires_at timestamptz not null,
 created_at timestamptz not null default now()
);
create index posts_search on public.scrim_posts(state,starts_at,level);
create index posts_maps on public.scrim_posts using gin(map_ids);
create table public.negotiations (
 id uuid primary key default gen_random_uuid(),
 post_id uuid not null references public.scrim_posts,
 home_team uuid not null references public.teams,
 away_team uuid not null references public.teams,
 state text not null default 'pending' check(state in ('pending','accepted','declined','withdrawn','expired')),
 current_version integer not null default 1,
 created_at timestamptz not null default now(),
 unique(post_id,away_team), check(home_team<>away_team)
);
create table public.proposal_versions (
 negotiation_id uuid not null references public.negotiations,
 version integer not null check(version>0),
 sender_team uuid not null references public.teams,
 starts_at timestamptz not null,
 ends_at timestamptz not null check(ends_at>starts_at and ends_at<=starts_at+interval '4 hours'),
 map_ids uuid[] not null,
 format integer not null check(format in (1,2)),
 expires_at timestamptz not null,
 created_at timestamptz not null default now(),
 primary key(negotiation_id,version), check(cardinality(map_ids)=format)
);
create table public.scrims (
 id uuid primary key default gen_random_uuid(),
 negotiation_id uuid not null unique references public.negotiations,
 home_team uuid not null references public.teams,
 away_team uuid not null references public.teams,
 accepted_version integer not null,
 starts_at timestamptz not null,
 ends_at timestamptz not null check(ends_at>starts_at),
 map_ids uuid[] not null,
 format integer not null,
 state text not null default 'confirmed' check(state in ('confirmed','completed','cancelled')),
 cancelled_by uuid references public.profiles,
 cancelled_at timestamptz,
 created_at timestamptz not null default now(),
 foreign key(negotiation_id,accepted_version) references public.proposal_versions(negotiation_id,version),
 check(home_team<>away_team), check(cardinality(map_ids)=format)
);
create index scrims_home_date on public.scrims(home_team,starts_at);
create index scrims_away_date on public.scrims(away_team,starts_at);
create table public.scrim_changes (
 scrim_id uuid not null references public.scrims,
 version integer not null,
 sender_team uuid not null references public.teams,
 starts_at timestamptz not null,
 ends_at timestamptz not null check(ends_at>starts_at and ends_at<=starts_at+interval '4 hours'),
 map_ids uuid[] not null,
 state text not null default 'pending' check(state in ('pending','accepted','declined','superseded')),
 created_at timestamptz not null default now(),
 primary key(scrim_id,version)
);
create unique index pending_change on public.scrim_changes(scrim_id) where state='pending';
create table public.team_blocks (
 id uuid primary key default gen_random_uuid(),
 team_id uuid not null references public.teams,
 title text not null check(length(title) between 2 and 120),
 starts_at timestamptz not null,
 ends_at timestamptz not null check(ends_at>starts_at),
 active boolean not null default true
);
create table public.reservations (
 id uuid primary key default gen_random_uuid(),
 team_id uuid not null references public.teams,
 scrim_id uuid references public.scrims,
 session_id uuid references public.training_sessions,
 block_id uuid references public.team_blocks,
 slot tstzrange not null,
 active boolean not null default true,
 check(num_nonnulls(scrim_id,session_id,block_id)=1),
 check(not isempty(slot) and not lower_inf(slot) and not upper_inf(slot) and lower_inc(slot) and not upper_inc(slot)),
 constraint reservations_no_overlap exclude using gist(team_id with =,slot with &&) where(active)
);
create unique index reservation_scrim_team on public.reservations(scrim_id,team_id) where scrim_id is not null;
create unique index reservation_session on public.reservations(session_id) where session_id is not null;
create unique index reservation_block on public.reservations(block_id) where block_id is not null;
create table public.room_instructions (
 scrim_id uuid primary key references public.scrims,
 address text not null default '' check(length(address)<=300),
 password text not null default '' check(length(password)<=200),
 instructions text not null default '' check(length(instructions)<=3000),
 updated_at timestamptz not null default now()
);
create table public.score_reports (
 scrim_id uuid not null references public.scrims,
 team_id uuid not null references public.teams,
 scores jsonb not null,
 reported_at timestamptz not null default now(),
 primary key(scrim_id,team_id)
);
create table public.shared_results (
 scrim_id uuid primary key references public.scrims,
 scores jsonb not null,
 agreed_at timestamptz not null default now()
);
create table public.post_reports (
 id uuid primary key default gen_random_uuid(),post_id uuid not null references public.scrim_posts,
 user_id uuid not null references public.profiles,reason text not null check(length(reason) between 5 and 500),
 state text not null default 'pending' check(state in ('pending','dismissed','removed')),
 created_at timestamptz not null default now(),unique(post_id,user_id)
);
create function private.participant(s uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.scrims where id=s and (private.member(home_team) or private.member(away_team)))
$$;
create function private.moderator() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.moderators where user_id=auth.uid())
$$;
create function private.lock_teams(a uuid,b uuid default null) returns void language plpgsql set search_path='' as $$
 declare t uuid; begin
 for t in select x from unnest(array[a,b]) x where x is not null order by x loop
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(t::text,0)); end loop;
 end
$$;
create function private.valid_maps(ids uuid[]) returns boolean language sql stable set search_path='' as $$
 select cardinality(ids)>0 and cardinality(ids)=(select count(distinct m.id) from public.maps m where m.id=any(ids) and active)
$$;
create function private.reserve_session() returns trigger language plpgsql security definer set search_path='' as $$
 begin
 if new.team_id is not null then
 perform private.lock_teams(new.team_id);
 if new.blocks_time and new.status not in ('cancelled','archived') then
 insert into public.reservations(team_id,session_id,slot,active) values(new.team_id,new.id,tstzrange(new.starts_at,new.ends_at,'[)'),true)
 on conflict(session_id) where session_id is not null do update set slot=excluded.slot,active=true;
 else update public.reservations set active=false where session_id=new.id; end if;
 end if; return new;
 end
$$;
create trigger reserve_training after insert or update on public.training_sessions for each row execute function private.reserve_session();

alter table public.scrim_posts enable row level security;
alter table public.negotiations enable row level security;
alter table public.proposal_versions enable row level security;
alter table public.scrims enable row level security;
alter table public.scrim_changes enable row level security;
alter table public.team_blocks enable row level security;
alter table public.reservations enable row level security;
alter table public.room_instructions enable row level security;
alter table public.score_reports enable row level security;
alter table public.shared_results enable row level security;
alter table public.post_reports enable row level security;
create policy posts_public on public.scrim_posts for select to anon,authenticated using(state='open' and expires_at>now() or private.member(team_id));
create policy negotiations_read on public.negotiations for select to authenticated using(private.operator(home_team) or private.operator(away_team));
create policy versions_read on public.proposal_versions for select to authenticated using(exists(select 1 from public.negotiations n where n.id=negotiation_id and (private.operator(n.home_team) or private.operator(n.away_team))));
create policy scrims_read on public.scrims for select to authenticated using(private.member(home_team) or private.member(away_team));
create policy changes_read on public.scrim_changes for select to authenticated using(private.participant(scrim_id));
create policy blocks_read on public.team_blocks for select to authenticated using(private.member(team_id));
create policy reservations_read on public.reservations for select to authenticated using(private.member(team_id));
create policy room_read on public.room_instructions for select to authenticated using(private.participant(scrim_id));
create policy scores_read on public.score_reports for select to authenticated using(private.member(team_id) and private.participant(scrim_id));
create policy shared_scores_read on public.shared_results for select to authenticated using(private.participant(scrim_id));
create policy reports_read on public.post_reports for select to authenticated using(private.moderator());
grant select on public.scrim_posts to anon,authenticated;
grant select on public.negotiations,public.proposal_versions,public.scrims,public.scrim_changes,public.team_blocks,public.reservations,public.room_instructions,public.score_reports,public.shared_results,public.post_reports to authenticated;

create function public.publish_scrim(p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
 declare t uuid:=(p_data->>'team_id')::uuid; rid uuid; ids uuid[];
 begin
 if not private.operator(t) then raise exception 'FORBIDDEN'; end if;
 perform private.lock_teams(t);
 if (select count(*) from public.scrim_posts where team_id=t and created_at>now()-interval '1 hour')>=10 then raise exception 'RATE_LIMIT'; end if;
 select array_agg(value::uuid) into ids from jsonb_array_elements_text(p_data->'map_ids');
 if not private.valid_maps(ids) or (p_data->>'starts_at')::timestamptz<=now() then raise exception 'INVALID_INPUT'; end if;
 insert into public.scrim_posts(team_id,starts_at,ends_at,region,level,map_ids,format,expires_at)
 values(t,(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,p_data->>'region',p_data->>'level',ids,(p_data->>'format')::int,(p_data->>'ends_at')::timestamptz) returning id into rid; return rid;
 end
$$;
create function public.close_scrim_post(p_post uuid) returns void language plpgsql security definer set search_path='' as $$
 declare p public.scrim_posts; begin
 select * into p from public.scrim_posts where id=p_post for update;
 if p.id is null or not private.operator(p.team_id) then raise exception 'FORBIDDEN'; end if;
 if p.state<>'open' then raise exception 'INVALID_TRANSITION'; end if;
 update public.scrim_posts set state='closed' where id=p_post;
 end
$$;
create function public.propose_scrim(p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
 declare p public.scrim_posts; n public.negotiations; last_version public.proposal_versions; t uuid:=(p_data->>'team_id')::uuid; rid uuid; v int; st timestamptz:=(p_data->>'starts_at')::timestamptz; en timestamptz:=(p_data->>'ends_at')::timestamptz; ids uuid[];
 begin
 if not private.operator(t) then raise exception 'FORBIDDEN'; end if;
 select * into p from public.scrim_posts where id=(p_data->>'post_id')::uuid for update;
 if p.id is null or p.state<>'open' or p.expires_at<=now() or st<=now() or st<p.starts_at or en>p.ends_at then raise exception 'POST_UNAVAILABLE'; end if;
 select array_agg(value::uuid) into ids from jsonb_array_elements_text(p_data->'map_ids');
 if not private.valid_maps(ids) or not ids<@p.map_ids or cardinality(ids)<>p.format then raise exception 'INVALID_MAPS'; end if;
 if p_data->>'negotiation_id' is null then
 if t=p.team_id then raise exception 'OWN_TEAM'; end if;
 perform private.lock_teams(t);
 if (select count(*) from public.negotiations where away_team=t and created_at>now()-interval '1 hour')>=20 then raise exception 'RATE_LIMIT'; end if;
 insert into public.negotiations(post_id,home_team,away_team) values(p.id,p.team_id,t) returning id into rid; v:=1;
 else
 select * into n from public.negotiations where id=(p_data->>'negotiation_id')::uuid for update;
 if n.id is null or n.post_id<>p.id or n.state<>'pending' or t not in (n.home_team,n.away_team) then raise exception 'FORBIDDEN'; end if;
 if n.current_version<>(p_data->>'version')::int then raise exception 'STALE_VERSION'; end if;
 select * into last_version from public.proposal_versions where negotiation_id=n.id and version=n.current_version;
 if last_version.sender_team=t then raise exception 'WAIT_OTHER_TEAM'; end if;
 if n.current_version>=30 then raise exception 'RATE_LIMIT'; end if;
 rid:=n.id; v:=n.current_version+1;
 update public.negotiations set current_version=v where id=rid;
 end if;
 insert into public.proposal_versions(negotiation_id,version,sender_team,starts_at,ends_at,map_ids,format,expires_at)
 values(rid,v,t,st,en,ids,p.format,least(st,now()+interval '24 hours'));
 if t=p.team_id then perform private.notify(n.away_team,'counterproposal',rid); else perform private.notify(p.team_id,case when v=1 then 'proposal' else 'counterproposal' end,rid); end if;
 return rid;
 end
$$;
create function public.accept_proposal(p_negotiation uuid,p_version integer,p_team uuid) returns uuid language plpgsql security definer set search_path='' as $$
 declare n public.negotiations; v public.proposal_versions; p public.scrim_posts; rid uuid; post_uuid uuid;
 begin
 if not private.operator(p_team) then raise exception 'FORBIDDEN'; end if;
 select post_id into post_uuid from public.negotiations where id=p_negotiation;
 select * into p from public.scrim_posts where id=post_uuid for update;
 select * into n from public.negotiations where id=p_negotiation for update;
 if n.id is null or p_team not in (n.home_team,n.away_team) then raise exception 'FORBIDDEN'; end if;
 if n.current_version<>p_version then raise exception 'STALE_VERSION'; end if;
 select * into v from public.proposal_versions where negotiation_id=n.id and version=p_version;
 if v.sender_team=p_team then raise exception 'WAIT_OTHER_TEAM'; end if;
 if n.state='accepted' then select id into rid from public.scrims where negotiation_id=n.id; return rid; end if;
 if n.state<>'pending' or p.state<>'open' or p.expires_at<=now() or v.expires_at<=now() or v.starts_at<=now() then raise exception 'PROPOSAL_EXPIRED'; end if;
 perform private.lock_teams(n.home_team,n.away_team);
 insert into public.scrims(negotiation_id,home_team,away_team,accepted_version,starts_at,ends_at,map_ids,format)
 values(n.id,n.home_team,n.away_team,p_version,v.starts_at,v.ends_at,v.map_ids,v.format) returning id into rid;
 insert into public.reservations(team_id,scrim_id,slot) select t,rid,tstzrange(v.starts_at,v.ends_at,'[)') from unnest(array[n.home_team,n.away_team]) t order by t;
 update public.negotiations set state='accepted' where id=n.id;
 update public.scrim_posts set state='consumed' where id=p.id;
 insert into public.room_instructions(scrim_id) values(rid);
 perform private.notify(n.home_team,'confirmed',rid); perform private.notify(n.away_team,'confirmed',rid);
 perform private.audit(p_team,'scrim_confirmed',rid); return rid;
 exception when exclusion_violation then raise exception 'SCHEDULE_CONFLICT';
 end
$$;
create function public.resolve_proposal(p_negotiation uuid,p_version integer,p_team uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$
 declare n public.negotiations; v public.proposal_versions;
 begin
 select * into n from public.negotiations where id=p_negotiation for update;
 if n.id is null or p_team not in (n.home_team,n.away_team) or not private.operator(p_team) then raise exception 'FORBIDDEN'; end if;
 if n.current_version<>p_version then raise exception 'STALE_VERSION'; end if;
 select * into v from public.proposal_versions where negotiation_id=n.id and version=p_version;
 if n.state<>'pending' then raise exception 'INVALID_TRANSITION'; end if;
 if p_action='decline' and v.sender_team<>p_team then update public.negotiations set state='declined' where id=n.id;
 elsif p_action='withdraw' and v.sender_team=p_team then update public.negotiations set state='withdrawn' where id=n.id;
 elsif p_action='expire' and v.expires_at<=now() then update public.negotiations set state='expired' where id=n.id;
 else raise exception 'INVALID_TRANSITION'; end if;
 perform private.notify(n.home_team,p_action,n.id); perform private.notify(n.away_team,p_action,n.id);
 end
$$;
create function public.propose_reschedule(p_scrim uuid,p_team uuid,p_start timestamptz,p_end timestamptz,p_maps uuid[]) returns integer language plpgsql security definer set search_path='' as $$
 declare s public.scrims; v int;
 begin
 select * into s from public.scrims where id=p_scrim for update;
 if s.id is null or p_team not in (s.home_team,s.away_team) or not private.operator(p_team) then raise exception 'FORBIDDEN'; end if;
 if s.state<>'confirmed' or p_start<=now() or not private.valid_maps(p_maps) or cardinality(p_maps)<>s.format then raise exception 'INVALID_TRANSITION'; end if;
 select coalesce(max(version),0)+1 into v from public.scrim_changes where scrim_id=s.id;
 if v>30 then raise exception 'RATE_LIMIT'; end if;
 update public.scrim_changes set state='superseded' where scrim_id=s.id and state='pending';
 insert into public.scrim_changes(scrim_id,version,sender_team,starts_at,ends_at,map_ids) values(s.id,v,p_team,p_start,p_end,p_maps);
 perform private.notify(s.home_team,'reschedule_requested',s.id); perform private.notify(s.away_team,'reschedule_requested',s.id); return v;
 end
$$;
create function public.resolve_reschedule(p_scrim uuid,p_version integer,p_team uuid,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$
 declare s public.scrims; c public.scrim_changes;
 begin
 select * into s from public.scrims where id=p_scrim for update;
 if s.id is null or p_team not in (s.home_team,s.away_team) or not private.operator(p_team) then raise exception 'FORBIDDEN'; end if;
 select * into c from public.scrim_changes where scrim_id=s.id and version=p_version;
 if c.scrim_id is null or c.sender_team=p_team then raise exception 'FORBIDDEN'; end if;
 if c.state='accepted' and p_accept then return; end if;
 if s.state<>'confirmed' or c.state<>'pending' or c.starts_at<=now() then raise exception 'STALE_VERSION'; end if;
 if p_accept then
 perform private.lock_teams(s.home_team,s.away_team);
 update public.reservations set slot=tstzrange(c.starts_at,c.ends_at,'[)') where scrim_id=s.id and active;
 update public.scrims set starts_at=c.starts_at,ends_at=c.ends_at,map_ids=c.map_ids where id=s.id;
 end if;
 update public.scrim_changes set state=case when p_accept then 'accepted' else 'declined' end where scrim_id=s.id and version=c.version;
 perform private.notify(s.home_team,case when p_accept then 'rescheduled' else 'reschedule_declined' end,s.id);
 perform private.notify(s.away_team,case when p_accept then 'rescheduled' else 'reschedule_declined' end,s.id);
 perform private.audit(p_team,case when p_accept then 'scrim_rescheduled' else 'reschedule_declined' end,s.id);
 exception when exclusion_violation then raise exception 'SCHEDULE_CONFLICT';
 end
$$;
create function public.cancel_scrim(p_scrim uuid,p_team uuid) returns void language plpgsql security definer set search_path='' as $$
 declare s public.scrims; begin
 select * into s from public.scrims where id=p_scrim for update;
 if s.id is null or p_team not in (s.home_team,s.away_team) or not private.operator(p_team) then raise exception 'FORBIDDEN'; end if;
 if s.state='cancelled' then return; end if;
 if s.state<>'confirmed' then raise exception 'INVALID_TRANSITION'; end if;
 perform private.lock_teams(s.home_team,s.away_team);
 update public.scrims set state='cancelled',cancelled_by=auth.uid(),cancelled_at=now() where id=s.id;
 update public.reservations set active=false where scrim_id=s.id;
 update public.scrim_changes set state='superseded' where scrim_id=s.id and state='pending';
 perform private.notify(s.home_team,'cancelled',s.id); perform private.notify(s.away_team,'cancelled',s.id);
 perform private.audit(p_team,'scrim_cancelled',s.id);
 end
$$;
create function public.save_room(p_scrim uuid,p_team uuid,p_address text,p_password text,p_instructions text) returns void language plpgsql security definer set search_path='' as $$
 declare s public.scrims; begin
 select * into s from public.scrims where id=p_scrim;
 if s.id is null or p_team not in (s.home_team,s.away_team) or not private.operator(p_team) or s.state<>'confirmed' then raise exception 'FORBIDDEN'; end if;
 update public.room_instructions set address=p_address,password=p_password,instructions=p_instructions,updated_at=now() where scrim_id=s.id;
 end
$$;
create function public.report_score(p_scrim uuid,p_team uuid,p_scores jsonb) returns boolean language plpgsql security definer set search_path='' as $$
 declare s public.scrims; other jsonb; canonical jsonb; begin
 select * into s from public.scrims where id=p_scrim for update;
 if s.id is null or p_team not in (s.home_team,s.away_team) or not private.operator(p_team) then raise exception 'FORBIDDEN'; end if;
 if s.state='cancelled' or s.starts_at>now() then raise exception 'NOT_PLAYED'; end if;
 if jsonb_typeof(p_scores)<>'array' or jsonb_array_length(p_scores)<>s.format then raise exception 'INVALID_SCORE'; end if;
 if exists(select 1 from jsonb_array_elements(p_scores) e where not (e->>'map_id')::uuid=any(s.map_ids) or (e->>'home')::int not between 0 and 100 or (e->>'away')::int not between 0 and 100 or e->>'home' is null or e->>'away' is null) or (select count(distinct e->>'map_id') from jsonb_array_elements(p_scores) e)<>s.format then raise exception 'INVALID_SCORE'; end if;
 select jsonb_agg(jsonb_build_object('map_id',e->>'map_id','home',(e->>'home')::int,'away',(e->>'away')::int) order by e->>'map_id') into canonical from jsonb_array_elements(p_scores) e;
 if s.state='completed' then raise exception 'RESULT_ALREADY_AGREED'; end if;
 insert into public.score_reports values(s.id,p_team,canonical,now()) on conflict(scrim_id,team_id) do update set scores=excluded.scores,reported_at=now();
 select scores into other from public.score_reports where scrim_id=s.id and team_id<>p_team;
 if other=canonical then
 insert into public.shared_results values(s.id,canonical,now());
 update public.scrims set state='completed' where id=s.id;
 perform private.notify(s.home_team,'result_agreed',s.id); perform private.notify(s.away_team,'result_agreed',s.id); return true;
 end if; return false;
 end
$$;
create function public.manage_block(p_team uuid,p_id uuid,p_title text,p_start timestamptz,p_end timestamptz,p_active boolean) returns uuid language plpgsql security definer set search_path='' as $$
 declare rid uuid; begin
 if not private.operator(p_team) then raise exception 'FORBIDDEN'; end if;
 perform private.lock_teams(p_team);
 if p_id is null then insert into public.team_blocks(team_id,title,starts_at,ends_at,active) values(p_team,p_title,p_start,p_end,p_active) returning id into rid;
 else update public.team_blocks set title=p_title,starts_at=p_start,ends_at=p_end,active=p_active where id=p_id and team_id=p_team returning id into rid; end if;
 if rid is null then raise exception 'NOT_FOUND'; end if;
 insert into public.reservations(team_id,block_id,slot,active) values(p_team,rid,tstzrange(p_start,p_end,'[)'),p_active)
 on conflict(block_id) where block_id is not null do update set slot=excluded.slot,active=excluded.active; return rid;
 exception when exclusion_violation then raise exception 'SCHEDULE_CONFLICT';
 end
$$;
create function public.report_post(p_post uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
 declare u uuid:=private.require_user(); begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text,1));
 if (select count(*) from public.post_reports where user_id=u and created_at>now()-interval '1 day')>=10 then raise exception 'RATE_LIMIT'; end if;
 insert into public.post_reports(post_id,user_id,reason) values(p_post,u,p_reason);
 end
$$;
create function public.moderate_post(p_report uuid,p_remove boolean) returns void language plpgsql security definer set search_path='' as $$
 declare p uuid; begin
 if not private.moderator() then raise exception 'FORBIDDEN'; end if;
 update public.post_reports set state=case when p_remove then 'removed' else 'dismissed' end where id=p_report returning post_id into p;
 if p_remove then update public.scrim_posts set state='moderated' where id=p; end if;
 perform private.audit(null,'post_moderated',p);
 end
$$;
