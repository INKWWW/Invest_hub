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
          source_type: "discord";
          display_name: string;
          parameter_version: string;
          enabled: boolean;
          authorized_worker_id: string | null;
          author_rules_version: number;
          created_by: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          source_key: string;
          source_type: "discord";
          display_name: string;
          parameter_version: string;
          enabled?: boolean;
          authorized_worker_id?: string | null;
          author_rules_version?: number;
          created_by?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["sources"]["Insert"]>;
        Relationships: [];
      };
      sync_tasks: {
        Row: {
          id: string;
          task_type: "discord_sync";
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
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          task_type: "discord_sync";
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
      enqueue_scheduled_discord_tasks: {
        Args: { p_worker_id: string; p_window_key: string };
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
