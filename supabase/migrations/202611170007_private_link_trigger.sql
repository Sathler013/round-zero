-- Regression: avoid accessing a field absent from a different trigger record type.
create or replace function private.validate_private_links() returns trigger language plpgsql security definer set search_path='' as $$
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
 elsif tg_table_name='training_sessions' then
 if new.source_review_id is not null then
 select team_id,owner_id into st,su from public.reviews where id=new.source_review_id;
 if not found or st is distinct from new.team_id or (st is null and su<>new.owner_id) then raise exception 'SCOPE_MISMATCH'; end if;
 end if;
 end if;
 return new;
 end
$$;
