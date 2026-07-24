-- V2 Workers use the database UUID for an X source at every local boundary.
-- The retained V1.1 persistence base function still verifies a logical
-- source_key, so translate only inside the X-specific database wrapper.

create or replace function public.persist_windowed_capture_page(
  p_task_id uuid, p_attempt integer, p_worker_id uuid, p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source_id uuid;
  v_source_type text;
  v_source_key text;
  v_context record;
  v_ack jsonb;
  v_canonical_id uuid;
begin
  select source.id, source.source_type, source.source_key into v_source_id, v_source_type, v_source_key
  from public.sync_tasks task join public.sources source on source.id = task.source_id
  where task.id = p_task_id;
  if not found then raise exception 'lease_mismatch' using errcode = '40001'; end if;
  if v_source_type <> 'x' then
    return public.persist_windowed_capture_page_base(p_task_id, p_attempt, p_worker_id, p_payload);
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or (p_payload - 'contract_version' - 'task_id' - 'attempt' - 'source_id' - 'raw_messages' - 'canonical_messages' - 'structured_runs' - 'capture_segment' - 'x_post_contexts') <> '{}'::jsonb
     or p_payload->>'source_id' <> v_source_id::text
     or jsonb_typeof(coalesce(p_payload->'x_post_contexts', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_x_windowed_page_persistence' using errcode = '22023';
  end if;
  v_ack := public.persist_windowed_capture_page_base(
    p_task_id,
    p_attempt,
    p_worker_id,
    (p_payload - 'x_post_contexts') || jsonb_build_object('source_id', v_source_key)
  );
  for v_context in
    select * from jsonb_to_recordset(coalesce(p_payload->'x_post_contexts', '[]'::jsonb)) as context(
      external_message_id text, post_type text, post_url text, quoted_post_id text,
      reply_to_post_id text, reposted_post_id text, context_status text, attachments jsonb
    )
  loop
    select id into v_canonical_id from public.canonical_messages
    where source_id = v_source_id and external_message_id = v_context.external_message_id;
    if v_canonical_id is null then raise exception 'x_context_without_canonical_post' using errcode = '22023'; end if;
    if exists (
      select 1 from public.x_post_contexts existing
      where existing.canonical_message_id = v_canonical_id
        and (existing.post_type, existing.post_url, existing.quoted_post_id, existing.reply_to_post_id,
          existing.reposted_post_id, existing.context_status, existing.attachments)
          is distinct from
          (v_context.post_type, v_context.post_url, v_context.quoted_post_id, v_context.reply_to_post_id,
            v_context.reposted_post_id, v_context.context_status, v_context.attachments)
    ) then
      raise exception 'conflicting_x_post_context' using errcode = '23505';
    end if;
    insert into public.x_post_contexts (
      canonical_message_id, post_type, post_url, quoted_post_id, reply_to_post_id,
      reposted_post_id, context_status, attachments
    ) values (
      v_canonical_id, v_context.post_type, v_context.post_url, v_context.quoted_post_id,
      v_context.reply_to_post_id, v_context.reposted_post_id, v_context.context_status,
      coalesce(v_context.attachments, '[]'::jsonb)
    ) on conflict (canonical_message_id) do nothing;
  end loop;
  return v_ack;
end;
$$;

revoke all on function public.persist_windowed_capture_page(uuid, integer, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.persist_windowed_capture_page(uuid, integer, uuid, jsonb) to service_role;
