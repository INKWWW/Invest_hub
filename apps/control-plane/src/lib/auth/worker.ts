import { createHash } from "node:crypto";

import { findWorkerBySecretHash } from "../db/repositories/workers";

export async function authenticateWorker(request: Request) {
  const header = request.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return null;
  const secret = header.slice("Bearer ".length).trim();
  if (!secret) return null;
  const secretHash = createHash("sha256").update(secret, "utf8").digest("hex");
  const worker = await findWorkerBySecretHash(secretHash);
  if (!worker || worker.status === "revoked") return null;
  return worker;
}
