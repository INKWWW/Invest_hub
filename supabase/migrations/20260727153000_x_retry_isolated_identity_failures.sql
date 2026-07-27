-- The first failure-isolation release deliberately stopped identity failures
-- from blocking other sources.  Requeue the failures recorded before the
-- Worker routing and protocol fixes once, so those existing sources get a
-- fresh verification attempt.  A failure after this migration remains
-- isolated in identity_failed and is not retried in a tight loop.
update public.x_source_activations
set stage = 'pending_identity',
    requested_at = timezone('utc', now()),
    last_error_code = null,
    completed_at = null
where stage = 'identity_failed';
