-- Cleanup and authorization use the same metadata lock; resuming an old record
-- refreshes activity before any upstream part is sent.
alter table public.demos add column activity_at timestamptz not null default now();
create function public.touch_demo_upload(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
 declare d public.demos; begin
 select * into d from public.demos where id=p_id for update;
 if d.id is null or d.kind<>'file' or d.state<>'pending' or not private.scope_write(d.team_id,d.owner_id) then raise exception 'FORBIDDEN'; end if;
 update public.demos set activity_at=now() where id=p_id;
 update public.demo_transfers set updated_at=now() where demo_id=p_id;
 end
$$;
create function public.claim_stale_upload(p_id uuid,p_before timestamptz) returns boolean language plpgsql security definer set search_path='' as $$
 declare d public.demos; begin
 if auth.role()<>'service_role' then raise exception 'FORBIDDEN'; end if;
 select * into d from public.demos where id=p_id for update;
 if d.id is null or d.kind<>'file' or d.state='ready' or d.activity_at>=p_before or d.created_at>=p_before then return false; end if;
 update public.demos set state='failed',activity_at=now() where id=p_id;
 delete from public.demo_transfers where demo_id=p_id;
 return true;
 end
$$;
revoke all on function public.touch_demo_upload(uuid),public.claim_stale_upload(uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.touch_demo_upload(uuid) to authenticated;
grant execute on function public.claim_stale_upload(uuid,timestamptz) to service_role;
