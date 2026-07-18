import type { User } from "@supabase/supabase-js";

import { createSupabaseServerClient } from "../db/supabase-server";
import type { AppRole } from "../db/types";

export type CurrentUser = {
  id: string;
  email: string | null;
  role: AppRole;
};

export async function getCurrentUser(): Promise<CurrentUser | null> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return null;

  const profile = await profileForUser(supabase, data.user);
  if (!profile) return null;
  return { id: data.user.id, email: data.user.email ?? null, role: profile.role };
}

async function profileForUser(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>,
  user: User,
) {
  const { data, error } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();
  if (error) return null;
  return data;
}
