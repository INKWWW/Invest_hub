import { NextResponse } from "next/server";

import { getCurrentUser } from "../../../../lib/auth/current-user";
import { readXDay } from "../../../../lib/db/repositories/reader";

export async function GET(request: Request) {
  if (!await getCurrentUser()) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { searchParams } = new URL(request.url);
  const sourceKey = searchParams.get("source") ?? undefined;
  const date = searchParams.get("date") ?? undefined;
  if (date && !/^\d{4}-\d{2}-\d{2}$/.test(date)) return NextResponse.json({ error: "invalid_reader_query" }, { status: 422 });
  try {
    return NextResponse.json({ status: "ok", days: await readXDay({ sourceKey, date }) });
  } catch {
    return NextResponse.json({ error: "reader_unavailable" }, { status: 503 });
  }
}
