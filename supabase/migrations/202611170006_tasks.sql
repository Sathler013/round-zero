create function public.save_task(p_session uuid,p_id uuid,p_label text,p_position integer,p_delete boolean) returns uuid language plpgsql security definer set search_path='' as $$
 declare s public.training_sessions; rid uuid; begin
 select * into s from public.training_sessions where id=p_session for update;
 if s.id is null or not private.scope_write(s.team_id,s.owner_id) then raise exception 'FORBIDDEN'; end if;
 if p_id is null then
 if (select count(*) from public.training_tasks where session_id=s.id)>=50 then raise exception 'RATE_LIMIT'; end if;
 insert into public.training_tasks(session_id,label,position) values(s.id,p_label,p_position) returning id into rid;
 elsif p_delete then delete from public.training_tasks where id=p_id and session_id=s.id returning id into rid;
 else update public.training_tasks set label=p_label,position=p_position where id=p_id and session_id=s.id returning id into rid;
 end if; if rid is null then raise exception 'NOT_FOUND'; end if; return rid;
 end
$$;
revoke all on function public.save_task(uuid,uuid,text,integer,boolean) from public,anon;
grant execute on function public.save_task(uuid,uuid,text,integer,boolean) to authenticated;
