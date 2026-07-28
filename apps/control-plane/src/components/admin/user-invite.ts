export type UserInviteListItem = {
  codeMask: string | null;
  validityHours: number | null;
  createdAt: string;
  expiresAt: string;
  consumedAt: string | null;
};

export function isValidInviteHours(value: number): boolean {
  return Number.isInteger(value) && value >= 1 && value <= 168;
}

export function parseUserInviteResponse(value: unknown): { code: string; expiresAt: string } | null {
  if (!value || typeof value !== "object") return null;
  const response = value as Record<string, unknown>;
  if (response.purpose !== "user" || typeof response.code !== "string" || !/^[A-Za-z0-9]{8}$/.test(response.code)) return null;
  if (typeof response.expires_at !== "string" || !response.expires_at) return null;
  return { code: response.code, expiresAt: response.expires_at };
}

export function parseUserInviteListResponse(value: unknown): UserInviteListItem[] | null {
  if (!value || typeof value !== "object") return null;
  const response = value as Record<string, unknown>;
  if (!Array.isArray(response.invites)) return null;
  const parsed: UserInviteListItem[] = [];
  for (const item of response.invites) {
    if (!item || typeof item !== "object") return null;
    const row = item as Record<string, unknown>;
    const codeMask = row.code_mask;
    const validityHours = row.validity_hours;
    if (codeMask !== null && (typeof codeMask !== "string" || !/^[A-Za-z0-9]{2}••••[A-Za-z0-9]{2}$/.test(codeMask))) return null;
    if (validityHours !== null && (typeof validityHours !== "number" || !isValidInviteHours(validityHours))) return null;
    if (typeof row.created_at !== "string" || typeof row.expires_at !== "string") return null;
    if (row.consumed_at !== null && typeof row.consumed_at !== "string") return null;
    parsed.push({
      codeMask,
      validityHours,
      createdAt: row.created_at,
      expiresAt: row.expires_at,
      consumedAt: row.consumed_at,
    });
  }
  return parsed;
}
