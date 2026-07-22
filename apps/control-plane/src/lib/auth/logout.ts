import { createSupabaseServerClient } from "../db/supabase-server";

export async function signOutCurrentUser() {
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signOut();
  if (error) return { ok: false as const, error: "sign_out_failed" as const };
  return { ok: true as const };
}
