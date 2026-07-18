type EvidenceSummaryProps = {
  rawCount: number;
  canonicalCount: number;
  duplicateCount: number;
  unresolvedCount: number;
  unparsedMediaCount: number;
  evidenceRefs: string[];
};

export function EvidenceSummary(props: EvidenceSummaryProps) {
  return (
    <section>
      <h2>Evidence</h2>
      <dl>
        <dt>Raw</dt><dd>{props.rawCount}</dd>
        <dt>Canonical</dt><dd>{props.canonicalCount}</dd>
        <dt>Duplicates</dt><dd>{props.duplicateCount}</dd>
        <dt>Unresolved</dt><dd>{props.unresolvedCount}</dd>
        <dt>Unparsed media</dt><dd>{props.unparsedMediaCount}</dd>
      </dl>
      {props.evidenceRefs.length > 0 ? (
        <ul aria-label="Evidence references">
          {props.evidenceRefs.map((ref) => <li key={ref}>{ref}</li>)}
        </ul>
      ) : <p>No evidence references.</p>}
    </section>
  );
}

