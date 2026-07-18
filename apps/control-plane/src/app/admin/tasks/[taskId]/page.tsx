import { notFound } from "next/navigation";

import { EvidenceSummary } from "../../../../components/admin/EvidenceSummary";
import { RetryTaskButton } from "../../../../components/admin/RetryTaskButton";
import { StatusBadge } from "../../../../components/admin/StatusBadge";
import { TaskTimeline } from "../../../../components/admin/TaskTimeline";
import { buildTaskViewModel, canRetryTask } from "../../../../lib/admin/view-model";
import { getTaskDetail } from "../../../../lib/db/repositories/tasks";

export default async function AdminTaskDetailPage({ params }: { params: Promise<{ taskId: string }> }) {
  const { taskId } = await params;
  const detail = await getTaskDetail(taskId);
  if (!detail) notFound();
  const latestAttempt = detail.attempts[0];
  const view = buildTaskViewModel({
    ...detail.task,
    attempt: latestAttempt?.attempt,
    result: latestAttempt?.result,
    failure: latestAttempt?.failure,
  });
  const evidenceRefs = detail.evidenceRefs.map((ref) => `${ref.id} (${ref.evidence_kind})`);
  return (
    <>
      <section>
        <h1>Task {view.id}</h1>
        <p><StatusBadge status={view.status} /> {canRetryTask({ status: view.taskStatus }) ? <RetryTaskButton taskId={view.id} /> : null}</p>
        <dl>
          <dt>Task type</dt><dd>{view.taskType}</dd>
          <dt>Source</dt><dd>{view.sourceId}</dd>
          <dt>Attempt</dt><dd>{view.attempt ?? "—"}</dd>
          <dt>Lease owner</dt><dd>{view.leaseOwner ?? "—"}</dd>
          <dt>Lease expiry</dt><dd>{view.leaseExpiresAt ?? "—"}</dd>
          <dt>Failure class</dt><dd>{view.failureClass ?? "—"}</dd>
          <dt>Safe checkpoint</dt><dd>{view.checkpoint ?? "—"}</dd>
        </dl>
      </section>
      <EvidenceSummary
        rawCount={view.rawCount}
        canonicalCount={view.canonicalCount}
        duplicateCount={view.duplicateCount}
        unresolvedCount={view.unresolvedCount}
        unparsedMediaCount={view.unparsedMediaCount}
        evidenceRefs={evidenceRefs.length > 0 ? evidenceRefs : view.evidenceRefs}
      />
      <section>
        <h2>Provider and schema</h2>
        <dl>
          <dt>Provider</dt><dd>{view.provider ?? "—"}</dd>
          <dt>Model reported</dt><dd>{view.modelReported ?? "—"}</dd>
          <dt>Prompt version</dt><dd>{view.promptVersion ?? "—"}</dd>
          <dt>P50</dt><dd>{view.p50Ms ?? "—"} ms</dd>
          <dt>P95</dt><dd>{view.p95Ms ?? "—"} ms</dd>
          <dt>Schema status</dt><dd>{view.schemaStatus ?? "—"}</dd>
        </dl>
        {detail.structuredRuns.length > 0 ? (
          <ul aria-label="Structured run summaries">
            {detail.structuredRuns.map((run) => <li key={run.id}>{run.id} · {run.provider} · {run.parameter_version} · {run.created_at}</li>)}
          </ul>
        ) : <p>No structured runs recorded.</p>}
      </section>
      <section>
        <h2>Chunk ranges</h2>
        {view.chunkRanges.length > 0 ? (
          <ul>{view.chunkRanges.map((chunk) => <li key={chunk.chunkId}>{chunk.chunkId}: {chunk.startId ?? "—"} → {chunk.endId ?? "—"} ({chunk.messageIds.length} messages)</li>)}</ul>
        ) : <p>No chunk range telemetry recorded.</p>}
      </section>
      <section>
        <h2>Timeline</h2>
        <TaskTimeline events={detail.events} />
      </section>
    </>
  );
}

