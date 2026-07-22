"use client";

import { FormEvent, useEffect, useState } from "react";

type Coverage = {
  coverage_start_at: string;
  coverage_through_at: string;
};

const boundaryTimes = ["00:00", "08:00", "16:00", "20:50"] as const;

export function coverageBoundaryInstant(date: string, time: typeof boundaryTimes[number]): string {
  return `${date}T${time}:00+08:00`;
}

function shanghaiTime(value: string): string {
  return new Intl.DateTimeFormat("zh-CN", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Shanghai",
  }).format(new Date(value));
}

export function SourceCoverageForm({ sourceId }: { sourceId: string }) {
  const [coverage, setCoverage] = useState<Coverage | null | undefined>(undefined);
  const [date, setDate] = useState("");
  const [time, setTime] = useState<typeof boundaryTimes[number]>("00:00");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    void fetch(`/api/admin/sources/${encodeURIComponent(sourceId)}/coverage`)
      .then(async (response) => response.ok ? response.json() as Promise<{ coverage: Coverage | null }> : Promise.reject())
      .then((body) => { if (active) setCoverage(body.coverage); })
      .catch(() => { if (active) { setCoverage(null); setMessage("无法读取采集范围，请刷新后重试。"); } });
    return () => { active = false; };
  }, [sourceId]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const parsedDate = new Date(`${date}T00:00:00+08:00`);
    const validDate = /^\d{4}-\d{2}-\d{2}$/.test(date)
      && !Number.isNaN(parsedDate.getTime())
      && parsedDate.toLocaleDateString("en-CA", { timeZone: "Asia/Shanghai" }) === date;
    if (!validDate) {
      setMessage("请输入有效的首次采集日期，格式为 YYYY-MM-DD。");
      return;
    }
    setIsSubmitting(true);
    setMessage(null);
    try {
      const response = await fetch(`/api/admin/sources/${encodeURIComponent(sourceId)}/coverage`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ coverage_start_at: coverageBoundaryInstant(date, time) }),
      });
      const body = await response.json() as { coverage?: Coverage; error?: string };
      if (!response.ok || !body.coverage) {
        setMessage(body.error === "coverage_already_initialized" ? "采集范围已经初始化，请刷新页面。" : "初始化失败。请选择上海时间的有效边界后重试。");
        return;
      }
      setCoverage(body.coverage);
      setMessage("采集范围已初始化。");
    } catch {
      setMessage("初始化失败，请稍后重试。");
    } finally {
      setIsSubmitting(false);
    }
  }

  if (coverage) {
    return <section className="source-coverage-form" aria-label="采集范围">
      <h3>采集范围</h3>
      <p>已初始化。连续覆盖从 {shanghaiTime(coverage.coverage_start_at)} 开始。</p>
      <p>当前已确认至 {shanghaiTime(coverage.coverage_through_at)}。</p>
      {message ? <p role="status">{message}</p> : null}
    </section>;
  }

  return <form className="source-coverage-form" onSubmit={submit}>
    <h3>首次采集范围</h3>
    <p>请选择上海时间的已有边界。初始化后，连续覆盖从该时点开始，不能由页面改写。</p>
    <label>日期 <input aria-label="首次采集日期" type="text" inputMode="numeric" autoComplete="off" placeholder="YYYY-MM-DD" maxLength={10} pattern="\d{4}-\d{2}-\d{2}" value={date} onChange={(event) => setDate(event.target.value)} required /></label>
    <label>上海时间边界 <select value={time} onChange={(event) => setTime(event.target.value as typeof boundaryTimes[number])}>{boundaryTimes.map((value) => <option key={value} value={value}>{value}</option>)}</select></label>
    <button type="submit" disabled={isSubmitting || coverage === undefined}>{isSubmitting ? "正在初始化…" : "初始化采集范围"}</button>
    {coverage === undefined ? <p>正在读取采集范围…</p> : null}
    {message ? <p role="status">{message}</p> : null}
  </form>;
}
