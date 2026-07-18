import json
import tempfile
import unittest
from pathlib import Path

from spike_02.fixtures import FixtureError, load_fixture


FIXTURE_PATH = Path("spikes/spike_02/fixtures/public_small.json")


def _write_fixture(directory: str, payload: dict) -> Path:
    path = Path(directory) / "fixture.json"
    path.write_text(json.dumps(payload), encoding="utf-8")
    return path


class FixtureTests(unittest.TestCase):
    def test_load_fixture_preserves_order_and_claim_sources(self):
        case = load_fixture(FIXTURE_PATH)
        self.assertEqual(case.scale, "small")
        self.assertEqual(
            [message.message_id for message in case.messages[:4]],
            ["public-001", "public-002", "public-003", "public-004"],
        )
        self.assertIn("public-001", case.claims[0].source_message_ids)

    def test_duplicate_message_ids_are_rejected(self):
        payload = {
            "case_id": "duplicate",
            "scale": "small",
            "messages": [
                {
                    "message_id": "same",
                    "author_id": "author",
                    "author_scope": "other",
                    "published_at": "2026-01-01T00:00:00Z",
                    "content": "one",
                    "kind": "text",
                    "parent_id": None,
                },
                {
                    "message_id": "same",
                    "author_id": "author",
                    "author_scope": "other",
                    "published_at": "2026-01-01T00:01:00Z",
                    "content": "two",
                    "kind": "text",
                    "parent_id": None,
                },
            ],
            "claims": [],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = _write_fixture(directory, payload)
            with self.assertRaisesRegex(FixtureError, "duplicate message_id"):
                load_fixture(path)

    def test_claim_source_must_reference_fixture_message(self):
        payload = {
            "case_id": "unknown-source",
            "scale": "small",
            "messages": [
                {
                    "message_id": "known",
                    "author_id": "author",
                    "author_scope": "other",
                    "published_at": "2026-01-01T00:00:00Z",
                    "content": "one",
                    "kind": "text",
                    "parent_id": None,
                }
            ],
            "claims": [
                {
                    "claim_id": "claim-001",
                    "category": "fact",
                    "required_terms": ["one"],
                    "source_message_ids": ["missing"],
                    "target_author_id": None,
                    "forbidden_terms": [],
                }
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = _write_fixture(directory, payload)
            with self.assertRaisesRegex(FixtureError, "unknown source_message_id"):
                load_fixture(path)


if __name__ == "__main__":
    unittest.main()
