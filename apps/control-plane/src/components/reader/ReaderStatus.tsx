import type { ReaderStatus as Status } from "../../lib/db/repositories/reader";

const labels: Record<Status, string> = {
  processing: "处理中：最新内容仍在整理，已生成的摘要保持可读。",
  partial_failure: "覆盖不完整：当前摘要可能未包含该时段的全部内容。",
  retryable_failed: "可重试失败：保留上次可用摘要，管理员可在稍后重试。",
  failed: "更新失败：保留上次可用摘要，请联系管理员处理。",
  no_new_messages: "已核实：截至当前时间没有新增消息。",
  succeeded: "已更新：这是当前可用的日度摘要。",
};

export function readerStatusLabel(status: Status): string {
  return labels[status];
}

export function ReaderStatus({ status }: { status: Status }) {
  return <div className="reader-status" data-status={status}><p role="status">{readerStatusLabel(status)}</p></div>;
}
