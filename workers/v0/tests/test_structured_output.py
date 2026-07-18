from __future__ import annotations

import json
import unittest
from pathlib import Path

from invest_hub_worker.structured import SchemaError, parse_structured_output, validate_structured_output


FIXTURES = Path(__file__).parent / "fixtures"


class StructuredOutputTests(unittest.TestCase):
    def load(self, name: str) -> dict[str, object]:
        return json.loads((FIXTURES / name).read_text(encoding="utf-8"))

    def test_valid_media_linkage_cites_every_unparsed_message(self) -> None:
        output = parse_structured_output(json.dumps(self.load("structured_valid.json")))
        validated = validate_structured_output(output, {"message-1", "media-1"}, {"media-1"})
        self.assertEqual(validated["media_source_message_ids"], ["media-1"])

    def test_missing_media_source_is_rejected(self) -> None:
        output = parse_structured_output(json.dumps(self.load("structured_media_linkage_invalid.json")))
        with self.assertRaises(SchemaError):
            validate_structured_output(output, {"message-1", "media-1"}, {"media-1"})

    def test_unknown_or_non_media_source_is_rejected(self) -> None:
        output = parse_structured_output(json.dumps({
            "topics": [],
            "media_unparsed": True,
            "media_source_message_ids": ["message-1"],
            "warnings": [],
        }))
        with self.assertRaises(SchemaError):
            validate_structured_output(output, {"message-1", "media-1"}, {"media-1"})

        output = parse_structured_output(json.dumps({
            "topics": [],
            "media_unparsed": True,
            "media_source_message_ids": ["unknown"],
            "warnings": [],
        }))
        with self.assertRaises(SchemaError):
            validate_structured_output(output, {"message-1", "media-1"}, {"media-1"})

    def test_invalid_json_and_missing_required_fields_have_stable_codes(self) -> None:
        with self.assertRaisesRegex(SchemaError, "invalid_json"):
            parse_structured_output("not-json")
        with self.assertRaisesRegex(SchemaError, "missing_field"):
            parse_structured_output(json.dumps({"topics": []}))


if __name__ == "__main__":
    unittest.main()
