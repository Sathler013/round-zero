create table private.mutation_receipts (
 user_id uuid not null references auth.users on delete cascade,
 request_key uuid not null,
 fingerprint bytea not null,
 response jsonb,
 created_at timestamptz not null default now(),
 primary key(user_id,request_key)
);
-- Dispatch only: validation/state invariants remain in their domain RPCs.
create function public.execute_command(p_key uuid,p_command text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare u uuid:=private.require_user(); fp bytea:=extensions.digest(p_command||p_data::text,'sha256'); receipt private.mutation_receipts; result jsonb;
 begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text||p_key::text,2));
 select * into receipt from private.mutation_receipts where user_id=u and request_key=p_key;
 if found then
 if receipt.fingerprint<>fp then raise exception 'IDEMPOTENCY_CONFLICT'; end if;
 if p_command='invite.create' then raise exception 'INVITE_ALREADY_ISSUED'; end if;
 return receipt.response;
 end if;
 case p_command
 when 'profile.save' then perform public.update_profile(p_data->>'display_name',p_data->>'locale',p_data->>'timezone');
 when 'team.create' then result:=to_jsonb(public.create_team(p_data->>'name',p_data->>'slug',p_data->>'timezone'));
 when 'member.manage' then perform public.manage_member((p_data->>'team_id')::uuid,(p_data->>'user_id')::uuid,p_data->>'action',coalesce(p_data->>'role','player'));
 when 'invite.create' then result:=to_jsonb(public.create_invite((p_data->>'team_id')::uuid,p_data->>'email',p_data->>'role'));
 when 'invite.revoke' then perform public.revoke_invite((p_data->>'id')::uuid);
 when 'invite.accept' then result:=to_jsonb(public.accept_invite(p_data->>'token'));
 when 'role.save' then perform public.set_game_role((p_data->>'team_id')::uuid,(p_data->>'user_id')::uuid,(p_data->>'map_id')::uuid,p_data->>'side',p_data->>'game_role');
 when 'training.save' then result:=to_jsonb(public.manage_training(p_data->>'action',p_data));
 when 'training.week' then result:=to_jsonb(public.duplicate_week((p_data->>'team_id')::uuid,(p_data->>'from')::timestamptz,(p_data->>'to')::timestamptz));
 when 'training.result' then perform public.record_training((p_data->>'session_id')::uuid,(p_data->>'attempts')::int,(p_data->>'hits')::int,(p_data->>'actual_minutes')::int,p_data->>'difficulty',p_data->>'notes');
 when 'task.save' then result:=to_jsonb(public.save_task((p_data->>'session_id')::uuid,(p_data->>'id')::uuid,p_data->>'label',(p_data->>'position')::int,(p_data->>'delete')::boolean));
 when 'task.toggle' then perform public.toggle_task((p_data->>'id')::uuid,(p_data->>'done')::boolean);
 when 'attendance.save' then perform public.respond_attendance((p_data->>'session_id')::uuid,p_data->>'response');
 when 'goal.save' then result:=to_jsonb(public.save_goal(p_data));
 when 'availability.save' then result:=to_jsonb(public.save_availability((p_data->>'team_id')::uuid,(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,p_data->>'kind'));
 when 'play.save' then result:=to_jsonb(public.save_play(p_data));
 when 'map.create' then result:=to_jsonb(public.add_map((p_data->>'team_id')::uuid,p_data->>'name'));
 when 'post.create' then result:=to_jsonb(public.publish_scrim(p_data));
 when 'post.close' then perform public.close_scrim_post((p_data->>'id')::uuid);
 when 'proposal.save' then result:=to_jsonb(public.propose_scrim(p_data));
 when 'proposal.accept' then result:=to_jsonb(public.accept_proposal((p_data->>'id')::uuid,(p_data->>'version')::int,(p_data->>'team_id')::uuid));
 when 'proposal.resolve' then perform public.resolve_proposal((p_data->>'id')::uuid,(p_data->>'version')::int,(p_data->>'team_id')::uuid,p_data->>'action');
 when 'scrim.reschedule' then result:=to_jsonb(public.propose_reschedule((p_data->>'id')::uuid,(p_data->>'team_id')::uuid,(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,array(select value::uuid from jsonb_array_elements_text(p_data->'map_ids'))));
 when 'scrim.resolve' then perform public.resolve_reschedule((p_data->>'id')::uuid,(p_data->>'version')::int,(p_data->>'team_id')::uuid,(p_data->>'accept')::boolean);
 when 'scrim.rematch' then result:=to_jsonb(public.invite_rematch((p_data->>'id')::uuid,(p_data->>'team_id')::uuid,(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz));
 when 'scrim.cancel' then perform public.cancel_scrim((p_data->>'id')::uuid,(p_data->>'team_id')::uuid);
 when 'room.save' then perform public.save_room((p_data->>'id')::uuid,(p_data->>'team_id')::uuid,p_data->>'address',p_data->>'password',p_data->>'instructions');
 when 'score.save' then result:=to_jsonb(public.report_score((p_data->>'id')::uuid,(p_data->>'team_id')::uuid,p_data->'scores'));
 when 'block.save' then result:=to_jsonb(public.manage_block((p_data->>'team_id')::uuid,(p_data->>'id')::uuid,p_data->>'title',(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,(p_data->>'active')::boolean));
 when 'post.report' then perform public.report_post((p_data->>'id')::uuid,p_data->>'reason');
 when 'post.moderate' then perform public.moderate_post((p_data->>'id')::uuid,(p_data->>'remove')::boolean);
 when 'demo.create' then result:=to_jsonb(public.create_demo(p_data));
 when 'demo.retry' then perform public.retry_demo((p_data->>'id')::uuid);
 when 'demo.fail' then perform public.fail_demo((p_data->>'id')::uuid);
 when 'review.save' then result:=to_jsonb(public.save_review(p_data));
 when 'review.task' then result:=to_jsonb(public.review_to_training((p_data->>'id')::uuid,(p_data->>'starts_at')::timestamptz,(p_data->>'expected_minutes')::int));
 when 'notifications.read' then perform public.mark_notifications_read();
 else raise exception 'INVALID_COMMAND';
 end case;
 insert into private.mutation_receipts(user_id,request_key,fingerprint,response) values(u,p_key,fp,case when p_command='invite.create' then null else result end);
 return result;
 end
$$;
revoke all on function public.execute_command(uuid,text,jsonb) from public,anon;
grant execute on function public.execute_command(uuid,text,jsonb) to authenticated;
