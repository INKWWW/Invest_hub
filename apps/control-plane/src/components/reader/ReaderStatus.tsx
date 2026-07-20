import type { ReaderStatus as Status } from "../../lib/db/repositories/reader";

const labels: Record<Status, string> = {
  processing: "Processing: newer evidence is still being collected or structured; the last safe summary remains available.",
  partial_failure: "Partial failure: the available summary may not cover every expected item.",
  retryable_failed: "Retryable failure: the last safe summary remains available while this source can be retried.",
  failed: "Failed: the last safe summary remains available; contact an administrator for recovery.",
  succeeded: "Succeeded: this is the current safe daily summary.",
};

export function readerStatusLabel(status: Status): string {
  return labels[status];
}

export function ReaderStatus({ status, evidenceExpired }: { status: Status; evidenceExpired: boolean }) {
  return <div className="reader-status" data-status={status}>
    <p role="status">{readerStatusLabel(status)}</p>
    {evidenceExpired ? <p>Some original-message evidence has expired. The retained summary remains available.</p> : null}
  </div>;
}
