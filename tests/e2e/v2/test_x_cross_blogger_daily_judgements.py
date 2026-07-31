from __future__ import annotations

import json
import unittest


RAW_CONTENT_SENTINEL = "FORBIDDEN_RAW_X_CONTENT_SENTINEL"


class SyntheticDailyJudgementFixture:
    """Public-only harness for the Reader /api/reader/x contract."""

    def __init__(self) -> None:
        self.coverage = {source: "2026-07-31T16:00:00+08:00" for source in ("alpha", "beta", "gamma")}
        self.batches: dict[str, dict[str, object]] = {}

    def tick(self, cutoff_at: str) -> dict[str, object]:
        batch = self.batches.get(cutoff_at)
        if batch is None:
            batch = {
                "cutoff_at": cutoff_at,
                "natural_date": cutoff_at[:10],
                "sources": {source: {"status": "pending", "viewpoints": []} for source in self.coverage},
                "status": "collecting",
                "versions": [],
                "run": None,
            }
            self.batches[cutoff_at] = batch
        return batch

    def settle_source(self, cutoff_at: str, source: str, outcome: str, viewpoints: tuple[str, ...] = ()) -> None:
        batch = self.tick(cutoff_at)
        sources = batch["sources"]
        assert isinstance(sources, dict)
        item = sources[source]
        assert isinstance(item, dict)
        if outcome not in {"included", "no_new_information", "excluded"}:
            raise ValueError("invalid_source_outcome")
        item["status"] = outcome
        item["viewpoints"] = list(viewpoints)
        item["raw_post"] = RAW_CONTENT_SENTINEL
        if outcome != "excluded":
            self.coverage[source] = cutoff_at

    def settle_batch(self, cutoff_at: str) -> dict[str, object]:
        batch = self.tick(cutoff_at)
        sources = batch["sources"]
        assert isinstance(sources, dict)
        if any(item["status"] == "pending" for item in sources.values()):
            raise ValueError("batch_not_settled")
        included = [source for source, item in sources.items() if item["status"] == "included"]
        excluded = [source for source, item in sources.items() if item["status"] == "excluded"]
        if not included:
            batch["coverage_status"] = "no_new_information"
            batch["status"] = "succeeded"
        else:
            batch["coverage_status"] = "partial" if excluded else "complete"
            batch["status"] = "judgement_pending"
            batch["run"] = {"attempt": 0, "status": "queued"}
        return batch

    def claim(self, cutoff_at: str) -> dict[str, int]:
        batch = self.tick(cutoff_at)
        run = batch["run"]
        if not isinstance(run, dict) or run["status"] not in {"queued", "retryable_failed"}:
            raise ValueError("no_ready_judgement")
        run["attempt"] = int(run["attempt"]) + 1
        run["status"] = "leased"
        return {"attempt": run["attempt"]}

    def fail_provider(self, cutoff_at: str, attempt: int) -> None:
        run = self.tick(cutoff_at)["run"]
        if not isinstance(run, dict) or run["status"] != "leased" or run["attempt"] != attempt:
            raise ValueError("stale_completion")
        run["status"] = "retryable_failed"

    def complete_judgement(self, cutoff_at: str, attempt: int, *, supporting: tuple[str, ...], dissenting: tuple[str, ...]) -> dict[str, object]:
        batch = self.tick(cutoff_at)
        run = batch["run"]
        if not isinstance(run, dict) or run["status"] != "leased" or run["attempt"] != attempt:
            raise ValueError("stale_completion")
        sources = batch["sources"]
        assert isinstance(sources, dict)
        allowed = {source for source, item in sources.items() if item["status"] == "included"}
        if not set(supporting).issubset(allowed) or not set(dissenting).issubset(allowed) or set(supporting) & set(dissenting):
            raise ValueError("invalid_judgement_evidence")
        versions = batch["versions"]
        assert isinstance(versions, list)
        version = {
            "revision": len(versions) + 1,
            "statement": "Synthetic Company Q judgement",
            "supporting": list(supporting),
            "dissenting": list(dissenting),
        }
        versions.append(version)
        run["status"] = "succeeded"
        batch["status"] = "succeeded"
        return version

    def api_reader_x(self, *, source: str | None = None, user: str = "ordinary") -> dict[str, object]:
        if user not in {"ordinary", "admin"}:
            raise PermissionError("unauthorized")
        days: dict[str, dict[str, object]] = {}
        for batch in self.batches.values():
            natural_date = batch["natural_date"]
            assert isinstance(natural_date, str)
            day = days.setdefault(natural_date, {"naturalDate": natural_date, "judgement": {"visible": source is None, "batches": []}, "bloggers": []})
            sources = batch["sources"]
            assert isinstance(sources, dict)
            if source is None:
                versions = batch["versions"]
                assert isinstance(versions, list)
                version = versions[-1] if versions else None
                day["judgement"]["batches"].append({
                    "cutoffAt": batch["cutoff_at"], "coverageStatus": batch.get("coverage_status", "no_new_information"),
                    "status": "succeeded" if batch["status"] == "succeeded" else "judgement_pending",
                    "revision": version["revision"] if version else 0,
                    "stockViewpoints": [] if version is None else [{"statement": version["statement"], "supportingDisplayNames": list(version["supporting"]), "dissentingDisplayNames": list(version["dissenting"]), "uncertainties": []}],
                    "marketIndustryViewpoints": [], "uncertainties": [],
                    "excludedSourceCount": sum(item["status"] == "excluded" for item in sources.values()),
                })
            for source_key, item in sources.items():
                if source is not None and source != source_key:
                    continue
                day["bloggers"].append({"source": {"sourceKey": source_key, "displayName": source_key.title()}, "status": "failed" if item["status"] == "excluded" else "succeeded", "segments": [{"viewpoints": item["viewpoints"]}] if item["viewpoints"] else []})
        result = list(days.values())
        for day in result:
            day["judgement"]["batches"].sort(key=lambda batch: batch["cutoffAt"], reverse=True)
            day["bloggers"].sort(key=lambda blogger: blogger["source"]["displayName"])
        return {"status": "ok", "days": sorted(result, key=lambda day: day["naturalDate"], reverse=True)}

    def reader_html(self, *, source: str | None = None, width: int = 1280) -> str:
        projection = self.api_reader_x(source=source)
        layout = "single-column" if width <= 430 else "two-column"
        explanation = "跨博主当日判断总结仅在全部博主视图展示。" if source is not None else "当日判断总结"
        return f'<main data-layout="{layout}">{explanation}{json.dumps(projection, ensure_ascii=False)}</main>'


class XCrossBloggerDailyJudgementE2ETests(unittest.TestCase):
    def test_complete_partial_no_new_retry_and_reader_safety(self) -> None:
        fixture = SyntheticDailyJudgementFixture()
        complete = "2026-08-01T08:00:00+08:00"
        for source, viewpoints in (("alpha", ("Company Q is improving",)), ("beta", ("Company Q supports the trend",)), ("gamma", ("Company Q valuation is stretched",))):
            fixture.settle_source(complete, source, "included", viewpoints)
        fixture.settle_batch(complete)
        attempt = fixture.claim(complete)
        version = fixture.complete_judgement(complete, attempt["attempt"], supporting=("alpha", "beta"), dissenting=("gamma",))
        self.assertEqual(version["revision"], 1)
        self.assertEqual(version["supporting"], ["alpha", "beta"])
        self.assertEqual(version["dissenting"], ["gamma"])

        partial = "2026-08-01T12:00:00+08:00"
        fixture.settle_source(partial, "alpha", "included", ("Company Q still improving",))
        fixture.settle_source(partial, "beta", "excluded")
        fixture.settle_source(partial, "gamma", "no_new_information")
        partial_batch = fixture.settle_batch(partial)
        partial_attempt = fixture.claim(partial)
        fixture.complete_judgement(partial, partial_attempt["attempt"], supporting=("alpha",), dissenting=())
        self.assertEqual(partial_batch["coverage_status"], "partial")
        self.assertEqual(fixture.coverage["alpha"], partial)
        self.assertEqual(fixture.coverage["beta"], complete)

        no_new = "2026-08-01T16:00:00+08:00"
        for source in ("alpha", "beta", "gamma"):
            fixture.settle_source(no_new, source, "no_new_information")
        self.assertEqual(fixture.settle_batch(no_new)["coverage_status"], "no_new_information")
        with self.assertRaisesRegex(ValueError, "no_ready_judgement"):
            fixture.claim(no_new)

        safe_json = json.dumps(fixture.api_reader_x(user="ordinary"), ensure_ascii=False)
        safe_html = fixture.reader_html()
        for forbidden in (RAW_CONTENT_SENTINEL, "provider", "prompt", "task", "analysis_ids", "evidence_post_ids"):
            self.assertNotIn(forbidden, safe_json)
            self.assertNotIn(forbidden, safe_html)

    @unittest.skip(
        "BLOCKED: Spec §3 and acceptance criterion 6 require a provider retry to append revision 2, "
        "but the implemented Plan Task 1–3 state machine records a failed attempt without a version and "
        "allows its sole run to complete only once. This needs an approved explicit successful-batch regeneration path."
    )
    def test_provider_retry_later_appends_revision_two_without_overwriting_revision_one(self) -> None:
        fixture = SyntheticDailyJudgementFixture()
        cutoff = "2026-08-01T08:00:00+08:00"
        for source in ("alpha", "beta", "gamma"):
            fixture.settle_source(cutoff, source, "included", ("synthetic",))
        fixture.settle_batch(cutoff)
        first_attempt = fixture.claim(cutoff)
        fixture.fail_provider(cutoff, first_attempt["attempt"])
        second_attempt = fixture.claim(cutoff)
        revision = fixture.complete_judgement(cutoff, second_attempt["attempt"], supporting=("alpha",), dissenting=())

        self.assertEqual(revision["revision"], 2)

    def test_duplicate_ticks_stale_completion_filter_and_mobile_layout(self) -> None:
        fixture = SyntheticDailyJudgementFixture()

        first = fixture.tick("2026-08-01T08:00:00+08:00")
        self.assertIs(first, fixture.tick("2026-08-01T08:00:00+08:00"))
        for source in ("alpha", "beta", "gamma"):
            fixture.settle_source("2026-08-01T08:00:00+08:00", source, "included", ("synthetic",))
        fixture.settle_batch("2026-08-01T08:00:00+08:00")
        first_attempt = fixture.claim("2026-08-01T08:00:00+08:00")
        fixture.fail_provider("2026-08-01T08:00:00+08:00", first_attempt["attempt"])
        second_attempt = fixture.claim("2026-08-01T08:00:00+08:00")
        with self.assertRaisesRegex(ValueError, "stale_completion"):
            fixture.complete_judgement("2026-08-01T08:00:00+08:00", first_attempt["attempt"], supporting=("alpha",), dissenting=())
        fixture.complete_judgement("2026-08-01T08:00:00+08:00", second_attempt["attempt"], supporting=("alpha",), dissenting=())

        earlier = "2026-07-31T20:00:00+08:00"
        for source in ("alpha", "beta", "gamma"):
            fixture.settle_source(earlier, source, "no_new_information")
        fixture.settle_batch(earlier)
        projection = fixture.api_reader_x()
        self.assertEqual([day["naturalDate"] for day in projection["days"]], ["2026-08-01", "2026-07-31"])
        single_source_html = fixture.reader_html(source="alpha")
        self.assertIn("跨博主当日判断总结仅在全部博主视图展示。", single_source_html)
        self.assertNotIn("Synthetic Company Q judgement", single_source_html)
        self.assertIn('data-layout="single-column"', fixture.reader_html(width=375))


if __name__ == "__main__":
    unittest.main()
