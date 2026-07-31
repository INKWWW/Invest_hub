import { createHash, createHmac, randomInt } from "node:crypto";

const UPPERCASE = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const LOWERCASE = "abcdefghijklmnopqrstuvwxyz";
const DIGITS = "0123456789";
const ALPHANUMERIC = `${UPPERCASE}${LOWERCASE}${DIGITS}`;

function requiredInvitePepper(): string {
  const pepper = process.env.INVITE_CODE_PEPPER;
  if (!pepper) throw new Error("missing required server environment variable: INVITE_CODE_PEPPER");
  return pepper;
}

function randomCharacter(alphabet: string): string {
  return alphabet[randomInt(alphabet.length)];
}

function shuffle(values: string[]): string[] {
  for (let index = values.length - 1; index > 0; index -= 1) {
    const swapIndex = randomInt(index + 1);
    [values[index], values[swapIndex]] = [values[swapIndex], values[index]];
  }
  return values;
}

export type UserInviteCode = { code: string; mask: string };

export function isValidUserInviteCode(code: string): boolean {
  return code.length === 8
    && /^[A-Za-z0-9]{8}$/.test(code)
    && /[A-Z]/.test(code)
    && /[a-z]/.test(code)
    && /[0-9]/.test(code);
}

export function generateUserInviteCode(): UserInviteCode {
  const characters = [
    randomCharacter(UPPERCASE),
    randomCharacter(LOWERCASE),
    randomCharacter(DIGITS),
    ...Array.from({ length: 5 }, () => randomCharacter(ALPHANUMERIC)),
  ];
  const code = shuffle(characters).join("");
  return { code, mask: `${code.slice(0, 2)}••••${code.slice(-2)}` };
}

export function hashUserInviteCode(code: string): string {
  return createHmac("sha256", requiredInvitePepper()).update(code, "utf8").digest("hex");
}

export function hashLegacyInviteCode(code: string): string {
  return createHash("sha256").update(code, "utf8").digest("hex");
}

export function hashRedemptionSource(source: string): string {
  return createHmac("sha256", requiredInvitePepper()).update(`invite-redemption:${source}`, "utf8").digest("hex");
}
