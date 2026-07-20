export function parseUserInviteResponse(value: unknown): { code: string; expiresAt: string } | null {
  if (!value || typeof value !== "object") return null;
  const response = value as Record<string, unknown>;
  if (response.purpose !== "user" || typeof response.code !== "string" || !response.code) return null;
  if (typeof response.expires_at !== "string" || !response.expires_at) return null;
  return { code: response.code, expiresAt: response.expires_at };
}
