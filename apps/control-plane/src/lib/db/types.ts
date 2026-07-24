export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type AppRole = "admin" | "user";
export type WorkerStatus = "enrolled" | "online" | "offline" | "revoked";
export type TaskStatus =
  | "queued"
  | "leased"
  | "running"
  | "retryable_failed"
  | "succeeded"
  | "failed"
  | "cancelled";
export type TaskAttemptStatus =
  | "leased"
  | "running"
  | "succeeded"
  | "retryable_failed"
  | "failed";

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          role: AppRole;
          display_name: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id: string;
          role?: AppRole;
          display_name?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["profiles"]["Insert"]>;
        Relationships: [];
      };
      invites: {
        Row: {
          id: string;
          code_hash: string;
          role: AppRole;
          purpose: "user" | "worker";
          created_by: string | null;
          expires_at: string;
          consumed_at: string | null;
          consumed_by: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          code_hash: string;
          role?: AppRole;
          purpose?: "user" | "worker";
          created_by?: string | null;
          expires_at: string;
          consumed_at?: string | null;
          consumed_by?: string | null;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["invites"]["Insert"]>;
        Relationships: [];
      };
      workers: {
        Row: {
          id: string;
          name: string;
          device_secret_hash: string;
          status: WorkerStatus;
          last_heartbeat_at: string | null;
          enrolled_at: string;
          revoked_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          name: string;
          device_secret_hash: string;
          status?: WorkerStatus;
          last_heartbeat_at?: string | null;
          enrolled_at?: string;
          revoked_at?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["workers"]["Insert"]>;
        Relationships: [];
      };
      sources: {
        Row: {
          id: string;
          source_key: string;
          source_type: "discord" | "x";
          display_name: string;
          parameter_version: string;
          enabled: boolean;
          authorized_worker_id: string | null;
          author_rules_version: number;
          created_by: string | null;
          archived_at: string | null;
          archived_by: string | null;
          archive_reason: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          source_key: string;
          source_type: "discord" | "x";
          display_name: string;
          parameter_version: string;
          enabled?: boolean;
          authorized_worker_id?: string | null;
          author_rules_version?: number;
          created_by?: string | null;
          archived_at?: string | null;
          archived_by?: string | null;
          archive_reason?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["sources"]["Insert"]>;
        Relationships: [];
      };
      sync_tasks: {
        Row: {
          id: string;
          task_type: "discord_sync" | "x_sync";
          source_id: string;
          status: TaskStatus;
          parameter_version: string;
          requested_by: string | null;
          queued_at: string;
          lease_owner: string | null;
          lease_expires_at: string | null;
          last_checkpoint: string | null;
          rule_snapshot: Json;
          collection_scope: Json;
          capture_range: Json | null;
          author_profile_snapshot: Json;
          x_source_snapshot: Json | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          task_type: "discord_sync" | "x_sync";
          source_id: string;
          status?: TaskStatus;
          parameter_version: string;
          requested_by?: string | null;
          queued_at?: string;
          lease_owner?: string | null;
          lease_expires_at?: string | null;
          last_checkpoint?: string | null;
          rule_snapshot?: Json;
          collection_scope?: Json;
          capture_range?: Json | null;
          author_profile_snapshot?: Json;
          x_source_snapshot?: Json | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["sync_tasks"]["Insert"]>;
        Relationships: [];
      };
      task_attempts: {
        Row: {
          id: string;
          task_id: string;
          attempt: number;
          worker_id: string;
          status: TaskAttemptStatus;
          lease_expires_at: string;
          result: Json | null;
          failure: Json | null;
          started_at: string | null;
          completed_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          task_id: string;
          attempt: number;
          worker_id: string;
          status: TaskAttemptStatus;
          lease_expires_at: string;
          result?: Json | null;
          failure?: Json | null;
          started_at?: string | null;
          completed_at?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["task_attempts"]["Insert"]>;
        Relationships: [];
      };
      checkpoints: {
        Row: {
          source_id: string;
          safe_checkpoint: string | null;
          version: number;
          updated_by_task_id: string | null;
          updated_at: string;
        };
        Insert: {
          source_id: string;
          safe_checkpoint?: string | null;
          version?: number;
          updated_by_task_id?: string | null;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["checkpoints"]["Insert"]>;
        Relationships: [];
      };
      scheduled_sync_windows: {
        Row: {
          id: string;
          source_id: string;
          window_key: string;
          worker_id: string;
          task_id: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          source_id: string;
          window_key: string;
          worker_id: string;
          task_id: string;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["scheduled_sync_windows"]["Insert"]>;
        Relationships: [];
      };
      source_collection_coverage: {
        Row: {
          source_id: string;
          coverage_start_at: string;
          coverage_through_at: string;
          last_completed_task_id: string | null;
          initialized_by: string | null;
          initialized_at: string;
          updated_at: string;
        };
        Insert: {
          source_id: string;
          coverage_start_at: string;
          coverage_through_at: string;
          last_completed_task_id?: string | null;
          initialized_by?: string | null;
          initialized_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["source_collection_coverage"]["Insert"]>;
        Relationships: [];
      };
      sync_task_capture_progress: {
        Row: {
          task_id: string;
          source_id: string;
          capture_range: Json;
          resume_cursor: string | null;
          page_count: number;
          oldest_verified_at: string | null;
          newest_verified_at: string | null;
          boundary_verified_at: string | null;
          boundary_kind: "oldest_at_or_before_start" | "history_exhausted" | null;
          range_complete: boolean;
          last_error: Json | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          task_id: string;
          source_id: string;
          capture_range: Json;
          resume_cursor?: string | null;
          page_count?: number;
          oldest_verified_at?: string | null;
          newest_verified_at?: string | null;
          boundary_verified_at?: string | null;
          boundary_kind?: "oldest_at_or_before_start" | "history_exhausted" | null;
          range_complete?: boolean;
          last_error?: Json | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["sync_task_capture_progress"]["Insert"]>;
        Relationships: [];
      };
      sync_task_capture_segments: {
        Row: {
          id: string;
          task_id: string;
          attempt: number;
          idempotency_key: string;
          request_cursor: string | null;
          next_cursor: string | null;
          oldest_occurred_at: string | null;
          newest_occurred_at: string | null;
          response_matched: boolean;
          response_fresh: boolean;
          created_at: string;
        };
        Insert: {
          id?: string;
          task_id: string;
          attempt: number;
          idempotency_key: string;
          request_cursor?: string | null;
          next_cursor?: string | null;
          oldest_occurred_at?: string | null;
          newest_occurred_at?: string | null;
          response_matched: boolean;
          response_fresh: boolean;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["sync_task_capture_segments"]["Insert"]>;
        Relationships: [];
      };
      source_author_profiles: {
        Row: {
          id: string;
          source_id: string;
          requested_author: string;
          resolution_status: "pending" | "resolved" | "ambiguous";
          author_id: string | null;
          author_display: string;
          author_handle: string | null;
          enabled: boolean;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          source_id: string;
          requested_author: string;
          resolution_status?: "pending" | "resolved" | "ambiguous";
          author_id?: string | null;
          author_display: string;
          author_handle?: string | null;
          enabled?: boolean;
          created_by?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["source_author_profiles"]["Insert"]>;
        Relationships: [];
      };
      raw_messages: {
        Row: {
          id: string;
          source_id: string;
          external_message_id: string;
          occurred_at: string | null;
          local_raw_ref: string;
          payload_hash: string;
          retention_expires_at: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          source_id: string;
          external_message_id: string;
          occurred_at?: string | null;
          local_raw_ref: string;
          payload_hash: string;
          retention_expires_at: string;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["raw_messages"]["Insert"]>;
        Relationships: [];
      };
      canonical_messages: {
        Row: {
          id: string;
          source_id: string;
          external_message_id: string;
          occurred_at: string | null;
          author_display: string | null;
          content: string;
          has_unparsed_media: boolean;
          metadata: Json;
          created_at: string;
        };
        Insert: {
          id?: string;
          source_id: string;
          external_message_id: string;
          occurred_at?: string | null;
          author_display?: string | null;
          content: string;
          has_unparsed_media?: boolean;
          metadata?: Json;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["canonical_messages"]["Insert"]>;
        Relationships: [];
      };
      structured_runs: {
        Row: {
          id: string;
          task_id: string;
          attempt: number;
          chunk_key: string;
          provider: "mock" | "codex_cli";
          parameter_version: string;
          input_message_ids: Json;
          output: Json;
          created_at: string;
        };
        Insert: {
          id?: string;
          task_id: string;
          attempt?: number;
          chunk_key?: string;
          provider: "mock" | "codex_cli";
          parameter_version: string;
          input_message_ids?: Json;
          output: Json;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["structured_runs"]["Insert"]>;
        Relationships: [];
      };
      evidence_refs: {
        Row: {
          id: string;
          structured_run_id: string;
          canonical_message_id: string;
          evidence_kind: "message" | "unparsed_media" | "local_raw_ref";
          local_raw_ref: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          structured_run_id: string;
          canonical_message_id: string;
          evidence_kind: "message" | "unparsed_media" | "local_raw_ref";
          local_raw_ref?: string | null;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["evidence_refs"]["Insert"]>;
        Relationships: [];
      };
      task_events: {
        Row: {
          id: string;
          task_id: string;
          attempt: number;
          event_type: string;
          occurred_at: string;
          details: Json;
          created_at: string;
        };
        Insert: {
          id?: string;
          task_id: string;
          attempt: number;
          event_type: string;
          occurred_at?: string;
          details?: Json;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["task_events"]["Insert"]>;
        Relationships: [];
      };
      source_author_rules: {
        Row: {
          id: string;
          author_id: string;
          scope: "global" | "source";
          source_id: string | null;
          policy: "target" | "exclude";
          enabled: boolean;
          version: number;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          author_id: string;
          scope: "global" | "source";
          source_id?: string | null;
          policy: "target" | "exclude";
          enabled?: boolean;
          version: number;
          created_by?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["source_author_rules"]["Insert"]>;
        Relationships: [];
      };
      summary_batches: {
        Row: {
          id: string;
          task_id: string;
          source_id: string;
          natural_date: string;
          input_message_ids: Json;
          structured_run_ids: Json;
          output: Json;
          coverage: Json;
          created_at: string;
        };
        Insert: {
          id?: string;
          task_id: string;
          source_id: string;
          natural_date: string;
          input_message_ids: Json;
          structured_run_ids: Json;
          output: Json;
          coverage: Json;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["summary_batches"]["Insert"]>;
        Relationships: [];
      };
      daily_summaries: {
        Row: {
          id: string;
          source_id: string;
          natural_date: string;
          version: number;
          is_current: boolean;
          batch_ids: Json;
          output: Json;
          coverage: Json;
          created_at: string;
        };
        Insert: {
          id?: string;
          source_id: string;
          natural_date: string;
          version: number;
          is_current?: boolean;
          batch_ids: Json;
          output: Json;
          coverage: Json;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["daily_summaries"]["Insert"]>;
        Relationships: [];
      };
      x_source_profiles: {
        Row: {
          source_id: string;
          requested_handle: string;
          account_id: string | null;
          display_name: string;
          resolution_status: "pending" | "resolved" | "ambiguous";
          enabled: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          source_id: string;
          requested_handle: string;
          account_id?: string | null;
          display_name: string;
          resolution_status?: "pending" | "resolved" | "ambiguous";
          enabled?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["x_source_profiles"]["Insert"]>;
        Relationships: [];
      };
      x_post_contexts: {
        Row: {
          canonical_message_id: string;
          post_type: "original" | "quote" | "reply" | "repost";
          post_url: string;
          quoted_post_id: string | null;
          reply_to_post_id: string | null;
          reposted_post_id: string | null;
          context_status: "complete" | "unavailable" | "deleted" | "unresolved";
          attachments: Json;
          created_at: string;
        };
        Insert: {
          canonical_message_id: string;
          post_type: "original" | "quote" | "reply" | "repost";
          post_url: string;
          quoted_post_id?: string | null;
          reply_to_post_id?: string | null;
          reposted_post_id?: string | null;
          context_status: "complete" | "unavailable" | "deleted" | "unresolved";
          attachments?: Json;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["x_post_contexts"]["Insert"]>;
        Relationships: [];
      };
      x_post_analyses: {
        Row: {
          canonical_message_id: string;
          analysis_version: number;
          blogger_viewpoint: string | null;
          arguments: Json;
          quoted_post_viewpoint: string | null;
          uncertainties: Json;
          evidence_refs: Json;
          created_at: string;
        };
        Insert: {
          canonical_message_id: string;
          analysis_version: number;
          blogger_viewpoint?: string | null;
          arguments: Json;
          quoted_post_viewpoint?: string | null;
          uncertainties: Json;
          evidence_refs: Json;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["x_post_analyses"]["Insert"]>;
        Relationships: [];
      };
      x_daily_viewpoint_segments: {
        Row: {
          id: string;
          source_id: string;
          natural_date: string;
          range_task_id: string;
          segment_version: number;
          occurred_from_at: string;
          occurred_through_at: string;
          window_viewpoints: Json;
          post_analysis_refs: Json;
          evidence_refs: Json;
          created_at: string;
        };
        Insert: {
          id?: string;
          source_id: string;
          natural_date: string;
          range_task_id: string;
          segment_version: number;
          occurred_from_at: string;
          occurred_through_at: string;
          window_viewpoints: Json;
          post_analysis_refs: Json;
          evidence_refs: Json;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["x_daily_viewpoint_segments"]["Insert"]>;
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
    Functions: {
      consume_invite: {
        Args: { p_code_hash: string; p_purpose?: string; p_user_id: string; p_now: string };
        Returns: Json | null;
      };
      claim_next_task: {
        Args: { p_worker_id: string; p_now: string };
        Returns: Json | null;
      };
      renew_task_lease: {
        Args: { p_task_id: string; p_attempt: number; p_worker_id: string; p_now: string };
        Returns: Json;
      };
      accept_task_result: {
        Args: { p_task_id: string; p_attempt: number; p_result: Json; p_context: Json };
        Returns: Json;
      };
      persist_worker_execution: {
        Args: { p_task_id: string; p_attempt: number; p_worker_id: string; p_payload: Json };
        Returns: Json;
      };
      persist_windowed_capture_page: {
        Args: { p_task_id: string; p_attempt: number; p_worker_id: string; p_payload: Json };
        Returns: Json;
      };
      replace_source_author_rules: {
        Args: {
          p_source_id: string;
          p_global_target_author_ids: string[];
          p_source_target_author_ids: string[];
          p_source_excluded_author_ids: string[];
          p_actor_id: string;
        };
        Returns: Json;
      };
      create_discord_sync_task: {
        Args: { p_source_id: string; p_parameter_version: string; p_requested_by: string; p_scope: Json };
        Returns: Json;
      };
      initialize_discord_collection_coverage: {
        Args: { p_source_id: string; p_actor_id: string; p_boundary: string };
        Returns: Json;
      };
      create_windowed_discord_sync_task: {
        Args: {
          p_source_id: string;
          p_parameter_version: string;
          p_requested_by: string | null;
          p_trigger: string;
          p_end_at: string;
          p_scheduled_window_key: string | null;
        };
        Returns: Json;
      };
      create_windowed_x_sync_task: {
        Args: {
          p_source_id: string;
          p_parameter_version: string;
          p_requested_by: string | null;
          p_trigger: string;
          p_end_at: string;
          p_scheduled_window_key: string | null;
        };
        Returns: Json;
      };
      create_bounded_x_history_task: {
        Args: { p_source_id: string; p_parameter_version: string; p_requested_by: string; p_start_at: string; p_end_at: string };
        Returns: Json;
      };
      resolve_x_source_identity: {
        Args: { p_source_id: string; p_worker_id: string; p_parameter_version: string; p_account_id: string };
        Returns: Json;
      };
      create_x_source: {
        Args: { p_source_key: string; p_display_name: string; p_requested_handle: string; p_parameter_version: string; p_actor_id: string };
        Returns: Json;
      };
      initialize_x_collection_coverage: {
        Args: { p_source_id: string; p_actor_id: string; p_boundary: string };
        Returns: Json;
      };
      remove_x_source: {
        Args: { p_source_id: string; p_actor_id: string; p_confirmation_name: string };
        Returns: Json;
      };
      record_windowed_capture_segment: {
        Args: { p_task_id: string; p_attempt: number; p_worker_id: string; p_segment: Json };
        Returns: Json;
      };
      complete_windowed_capture_range: {
        Args: { p_task_id: string; p_attempt: number; p_worker_id: string; p_payload: Json };
        Returns: Json;
      };
      complete_bounded_x_history_range: {
        Args: { p_task_id: string; p_attempt: number; p_worker_id: string; p_payload: Json };
        Returns: Json;
      };
      enqueue_scheduled_discord_tasks: {
        Args: { p_worker_id: string; p_window_key: string };
        Returns: Json;
      };
      enqueue_due_discord_tasks: {
        Args: { p_worker_id: string; p_now: string };
        Returns: Json;
      };
      enqueue_due_x_tasks: {
        Args: { p_worker_id: string; p_now: string };
        Returns: Json;
      };
      get_window_daily_fact_context: {
        Args: { p_task_id: string; p_attempt: number; p_worker_id: string };
        Returns: Json;
      };
      resolve_windowed_author_profiles: {
        Args: { p_task_id: string; p_attempt: number; p_worker_id: string };
        Returns: Json;
      };
      record_task_failure: {
        Args: { p_task_id: string; p_attempt: number; p_failure: Json; p_context: Json };
        Returns: Json;
      };
      is_admin: {
        Args: Record<string, never>;
        Returns: boolean;
      };
    };
  };
}

export type TableName = keyof Database["public"]["Tables"];
export type TableRow<T extends TableName> = Database["public"]["Tables"][T]["Row"];
