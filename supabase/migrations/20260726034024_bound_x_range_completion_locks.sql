-- Range completion is the only operation that advances a source waterline.
-- A stale request must fail quickly rather than consume the Worker deadline
-- while waiting for another completion transaction to release its row locks.
alter function public.complete_windowed_capture_range(uuid, integer, uuid, jsonb)
  set lock_timeout = '5s';
