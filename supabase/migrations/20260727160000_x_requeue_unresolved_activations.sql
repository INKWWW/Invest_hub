-- One-time recovery for X activations created before the identity gate was
-- enforced.  Their old task/activation state may look complete while the
-- profile is still unresolved.  Re-enter identity verification once; a new
-- failure remains isolated by the identity-failure RPC.
update public.x_source_activations activation
set stage = 'pending_identity',
    requested_at = timezone('utc', now()),
    last_error_code = null,
    completed_at = null
from public.x_source_profiles profile
where profile.source_id = activation.source_id
  and profile.resolution_status <> 'resolved'
  and activation.stage in ('pending_initialization', 'collecting', 'completed', 'retryable_failed');
