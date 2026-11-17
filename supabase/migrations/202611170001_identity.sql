create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 60),
  locale text not null default 'pt-BR' check (locale in ('pt-BR','en-US')),
  timezone text not null default 'America/Sao_Paulo',
  created_at timestamptz not null default now()
);
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,48}$'),
  name text not null check (char_length(name) between 2 and 60),
  timezone text not null default 'America/Sao_Paulo',
  created_at timestamptz not null default now()
);
create table public.team_public (
  team_id uuid primary key references public.teams on delete cascade,
  slug text not null unique,
  public_name text not null,
  region text not null default 'BR • São Paulo',
  level text not null default 'Intermediário'
);
create table public.team_members (
  team_id uuid not null references public.teams on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  access_role text not null check (access_role in ('owner','captain','coach','igl','player')),
  active boolean not null default true,
  joined_at timestamptz not null default now(),
  removed_at timestamptz,
  primary key (team_id,user_id)
);
create unique index one_active_owner on public.team_members(team_id) where access_role='owner' and active;
create index memberships_user on public.team_members(user_id,team_id) where active;
create table public.maps (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(name) between 2 and 40),
  active boolean not null default true
);
create table public.member_game_roles (
  team_id uuid not null,
  user_id uuid not null,
  map_id uuid not null references public.maps,
  side text not null check (side in ('TR','CT')),
  game_role text not null check (game_role in ('AWPer','Entry','Suporte','Lurker','IGL','Rifler')),
  primary key (team_id,user_id,map_id,side),
  foreign key (team_id,user_id) references public.team_members(team_id,user_id)
);
create table public.team_invites (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams on delete cascade,
  email text not null,
  token_hash bytea not null unique,
  access_role text not null check (access_role in ('captain','coach','igl','player')),
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked_at timestamptz,
  created_by uuid not null references public.profiles,
  created_at timestamptz not null default now()
);
create index invites_team on public.team_invites(team_id,created_at desc);
create table public.audit_events (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles,
  team_id uuid references public.teams,
  action text not null,
  resource_id uuid,
  created_at timestamptz not null default now()
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles on delete cascade,
  kind text not null,
  resource_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_inbox on public.notifications(user_id,created_at desc);
create table private.moderators (user_id uuid primary key references auth.users on delete cascade);

create function private.member(t uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.team_members where team_id=t and user_id=auth.uid() and active)
$$;
create function private.operator(t uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.team_members where team_id=t and user_id=auth.uid() and active and access_role in ('owner','captain','coach','igl'))
$$;
create function private.admin(t uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.team_members where team_id=t and user_id=auth.uid() and active and access_role in ('owner','captain'))
$$;
create function private.scope_read(t uuid,u uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select case when t is null then u=auth.uid() else private.member(t) end
$$;
create function private.scope_write(t uuid,u uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select case when t is null then u=auth.uid() else private.operator(t) end
$$;
create function private.require_user() returns uuid language plpgsql stable security definer set search_path = '' as $$
 begin if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if; return auth.uid(); end
$$;
create function private.valid_timezone(t text) returns boolean language sql stable set search_path = '' as $$
 select exists(select 1 from pg_catalog.pg_timezone_names where name=t)
$$;
create function private.audit(t uuid,a text,r uuid) returns void language sql security definer set search_path = '' as $$
 insert into public.audit_events(actor_id,team_id,action,resource_id) values(auth.uid(),t,a,r)
$$;
create function private.notify(t uuid,k text,r uuid) returns void language sql security definer set search_path = '' as $$
 insert into public.notifications(user_id,kind,resource_id) select user_id,k,r from public.team_members where team_id=t and active
$$;
create function private.profile_created() returns trigger language plpgsql security definer set search_path = '' as $$
 begin insert into public.profiles(id,display_name) values(new.id,coalesce(nullif(left(new.raw_user_meta_data->>'display_name',60),''),'Jogador')); return new; end
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function private.profile_created();

alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.team_public enable row level security;
alter table public.team_members enable row level security;
alter table public.maps enable row level security;
alter table public.member_game_roles enable row level security;
alter table public.team_invites enable row level security;
alter table public.audit_events enable row level security;
alter table public.notifications enable row level security;
create policy profile_read on public.profiles for select to authenticated using (
 id=auth.uid() or exists(select 1 from public.team_members m where m.user_id=id and m.active and private.member(m.team_id))
);
create policy teams_read on public.teams for select to authenticated using(private.member(id));
create policy directory_read on public.team_public for select to anon,authenticated using(true);
create policy members_read on public.team_members for select to authenticated using(active and private.member(team_id));
create policy maps_read on public.maps for select to anon,authenticated using(true);
create policy game_roles_read on public.member_game_roles for select to authenticated using(private.member(team_id));
-- Invite hashes and target emails have no Data API SELECT grant, including for members.
create policy audit_read on public.audit_events for select to authenticated using(private.admin(team_id));
create policy notifications_read on public.notifications for select to authenticated using(user_id=auth.uid());

grant select on public.profiles, public.teams, public.team_members, public.member_game_roles, public.audit_events, public.notifications to authenticated;
grant select on public.team_public, public.maps to anon,authenticated;
revoke all on public.team_invites from anon,authenticated;

create function public.update_profile(p_name text,p_locale text,p_timezone text) returns void language plpgsql security definer set search_path = '' as $$
 begin
 perform private.require_user();
 if p_locale not in ('pt-BR','en-US') or not private.valid_timezone(p_timezone) then raise exception 'INVALID_INPUT'; end if;
 update public.profiles set display_name=trim(p_name),locale=p_locale,timezone=p_timezone where id=auth.uid();
 end
$$;
create function public.create_team(p_name text,p_slug text,p_timezone text default 'America/Sao_Paulo') returns uuid language plpgsql security definer set search_path = '' as $$
 declare t uuid; u uuid:=private.require_user();
 begin
 if not private.valid_timezone(p_timezone) then raise exception 'INVALID_TIMEZONE'; end if;
 if (select count(*) from public.team_members where user_id=u and active and access_role='owner')>=5 then raise exception 'RATE_LIMIT'; end if;
 insert into public.teams(name,slug,timezone) values(trim(p_name),p_slug,p_timezone) returning id into t;
 insert into public.team_members(team_id,user_id,access_role) values(t,u,'owner');
 insert into public.team_public(team_id,slug,public_name) values(t,p_slug,trim(p_name));
 perform private.audit(t,'team_created',t); return t;
 end
$$;
create function public.manage_member(p_team uuid,p_user uuid,p_action text,p_role text default 'player') returns void language plpgsql security definer set search_path = '' as $$
 declare mine text; theirs text;
 begin
 perform private.require_user();
 perform 1 from public.teams where id=p_team for update;
 select access_role into mine from public.team_members where team_id=p_team and user_id=auth.uid() and active;
 select access_role into theirs from public.team_members where team_id=p_team and user_id=p_user and active;
 if theirs is null then raise exception 'NOT_FOUND'; end if;
 if p_action='leave' then
   if p_user<>auth.uid() or theirs='owner' then raise exception 'TRANSFER_OWNER_FIRST'; end if;
 elsif not private.admin(p_team) then raise exception 'FORBIDDEN';
 elsif theirs='owner' then raise exception 'TRANSFER_OWNER_FIRST';
 elsif mine='captain' and (theirs='captain' or p_role='captain') then raise exception 'FORBIDDEN';
 end if;
 if p_action in ('remove','leave') then
 update public.team_members set active=false,removed_at=now() where team_id=p_team and user_id=p_user;
 elsif p_action='role' then
 if p_role not in ('captain','coach','igl','player') then raise exception 'INVALID_ROLE'; end if;
 update public.team_members set access_role=p_role where team_id=p_team and user_id=p_user;
 elsif p_action='transfer' then
 if mine<>'owner' or p_user=auth.uid() then raise exception 'FORBIDDEN'; end if;
 update public.team_members set access_role='captain' where team_id=p_team and user_id=auth.uid();
 update public.team_members set access_role='owner' where team_id=p_team and user_id=p_user;
 else raise exception 'INVALID_ACTION'; end if;
 perform private.audit(p_team,'member_'||p_action,p_user);
 end
$$;
create function public.create_invite(p_team uuid,p_email text,p_role text default 'player') returns text language plpgsql security definer set search_path = '' as $$
 declare token text; rid uuid; mine text;
 begin
 perform private.require_user();
 perform 1 from public.teams where id=p_team for update;
 if not private.admin(p_team) then raise exception 'FORBIDDEN'; end if;
 select access_role into mine from public.team_members where team_id=p_team and user_id=auth.uid();
 if p_role not in ('captain','coach','igl','player') or (p_role='captain' and mine<>'owner') then raise exception 'FORBIDDEN'; end if;
 if p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(p_email)>254 then raise exception 'INVALID_EMAIL'; end if;
 if (select count(*) from public.team_invites where team_id=p_team and created_at>now()-interval '1 hour')>=20 then raise exception 'RATE_LIMIT'; end if;
 token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.team_invites(team_id,email,token_hash,access_role,expires_at,created_by)
 values(p_team,lower(trim(p_email)),extensions.digest(token,'sha256'),p_role,now()+interval '72 hours',auth.uid()) returning id into rid;
 perform private.audit(p_team,'invite_created',rid); return token;
 end
$$;
create function public.list_invites(p_team uuid) returns table(id uuid,email text,access_role text,expires_at timestamptz,used_at timestamptz,revoked_at timestamptz) language plpgsql security definer set search_path = '' as $$
 begin
 if not private.admin(p_team) then raise exception 'FORBIDDEN'; end if;
 return query select i.id,i.email,i.access_role,i.expires_at,i.used_at,i.revoked_at from public.team_invites i where i.team_id=p_team order by i.created_at desc limit 100;
 end
$$;
create function public.revoke_invite(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
 declare t uuid;
 begin
 select team_id into t from public.team_invites where id=p_id;
 if not private.admin(t) then raise exception 'FORBIDDEN'; end if;
 update public.team_invites set revoked_at=now() where id=p_id and used_at is null;
 perform private.audit(t,'invite_revoked',p_id);
 end
$$;
create function public.accept_invite(p_token text) returns uuid language plpgsql security definer set search_path = '' as $$
 declare i public.team_invites; e text; verified timestamptz; u uuid:=private.require_user();
 begin
 if length(p_token)<>64 then raise exception 'INVALID_INVITE'; end if;
 select * into i from public.team_invites where token_hash=extensions.digest(p_token,'sha256') for update;
 select lower(email),email_confirmed_at into e,verified from auth.users where id=u;
 if i.id is null or i.used_at is not null or i.revoked_at is not null or i.expires_at<=now() or e is distinct from i.email or verified is null then raise exception 'INVALID_INVITE'; end if;
 if exists(select 1 from public.team_members where team_id=i.team_id and user_id=u and active) then raise exception 'ALREADY_MEMBER'; end if;
 insert into public.team_members(team_id,user_id,access_role) values(i.team_id,u,i.access_role)
 on conflict(team_id,user_id) do update set active=true,removed_at=null,access_role=excluded.access_role,joined_at=now();
 update public.team_invites set used_at=now() where id=i.id;
 perform private.audit(i.team_id,'invite_accepted',i.id); return i.team_id;
 end
$$;
create function public.set_game_role(p_team uuid,p_user uuid,p_map uuid,p_side text,p_role text) returns void language plpgsql security definer set search_path = '' as $$
 begin
 if not private.operator(p_team) or not exists(select 1 from public.team_members where team_id=p_team and user_id=p_user and active) then raise exception 'FORBIDDEN'; end if;
 insert into public.member_game_roles values(p_team,p_user,p_map,p_side,p_role)
 on conflict(team_id,user_id,map_id,side) do update set game_role=excluded.game_role;
 end
$$;
create function public.mark_notifications_read() returns void language sql security definer set search_path = '' as $$
 update public.notifications set read_at=now() where user_id=auth.uid() and read_at is null
$$;
