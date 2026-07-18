import { createSupabaseServerClient } from "../db/supabase-server";

export async function loginWithPassword(email: string, password: string) {
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return { ok: false as const, error: "invalid_credentials" as const };
  return { ok: true as const };
}
