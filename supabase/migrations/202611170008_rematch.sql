alter table public.scrim_posts add column visibility text not null default 'public' check(visibility in ('public','private'));
create function private.post_recipient(p uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.negotiations where post_id=p and (private.operator(home_team) or private.operator(away_team)))
$$;
revoke all on function private.post_recipient(uuid) from public,anon;
grant execute on function private.post_recipient(uuid) to authenticated;
drop policy posts_public on public.scrim_posts;
create policy posts_public on public.scrim_posts for select to anon,authenticated using(
 visibility='public' and state='open' and expires_at>now() or private.member(team_id)
);
create policy direct_post_recipient on public.scrim_posts for select to authenticated using(visibility='private' and private.post_recipient(id));
create function public.invite_rematch(p_scrim uuid,p_team uuid,p_start timestamptz,p_end timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
 declare s public.scrims; opponent uuid; p uuid; n uuid; begin
 select * into s from public.scrims where id=p_scrim;
 if s.id is null or p_team not in (s.home_team,s.away_team) or not private.operator(p_team) then raise exception 'FORBIDDEN'; end if;
 if p_start<=now() then raise exception 'INVALID_INPUT'; end if;
 opponent:=case when s.home_team=p_team then s.away_team else s.home_team end;
 perform private.lock_teams(p_team,opponent);
 if (select count(*) from public.scrim_posts where team_id=p_team and created_at>now()-interval '1 hour')>=10 then raise exception 'RATE_LIMIT'; end if;
 insert into public.scrim_posts(team_id,starts_at,ends_at,region,level,map_ids,format,expires_at,visibility)
 values(p_team,p_start,p_end,'Convite direto','Revanche',s.map_ids,s.format,p_start,'private') returning id into p;
 insert into public.negotiations(post_id,home_team,away_team) values(p,p_team,opponent) returning id into n;
 insert into public.proposal_versions(negotiation_id,version,sender_team,starts_at,ends_at,map_ids,format,expires_at)
 values(n,1,p_team,p_start,p_end,s.map_ids,s.format,least(p_start,now()+interval '24 hours'));
 perform private.notify(opponent,'rematch_invited',n); return n;
 end
$$;
revoke all on function public.invite_rematch(uuid,uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.invite_rematch(uuid,uuid,timestamptz,timestamptz) to authenticated;
