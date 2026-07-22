from __future__ import annotations

import json
import unittest
from pathlib import Path

from invest_hub_worker.structured import (
    SchemaError,
    parse_structured_output,
    parse_v1_1_chunk_output,
    parse_v1_1_daily_output,
    validate_structured_output,
    validate_v1_1_chunk_output,
    validate_v1_1_daily_output,
)


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

    def test_v1_1_chunk_only_attributes_a_view_to_its_observed_author_and_message_evidence(self) -> None:
        output = parse_v1_1_chunk_output(json.dumps({
            "schema_version": "v1.1-chunk",
            "facts": [{
                "author_id": "author-1",
                "topic": "市场流动性",
                "viewpoint": "风险偏好正在修复",
                "reasoning": "成交量回升",
                "operation_tendency": "谨慎加仓",
                "methodology": ["分批验证"],
                "uncertainty": [],
                "source_message_ids": ["message-1"],
            }],
            "media_source_message_ids": ["media-1"],
            "warnings": ["存在未解析媒体"],
        }))

        validated = validate_v1_1_chunk_output(
            output,
            {
                "message-1": ("author-1", "Author One"),
                "media-1": ("author-2", "Author Two"),
            },
            {"media-1"},
        )

        self.assertEqual(validated["facts"][0]["author_id"], "author-1")
        invalid = {**output, "facts": [{**output["facts"][0], "author_id": "author-2"}]}
        with self.assertRaisesRegex(SchemaError, "author_id"):
            validate_v1_1_chunk_output(invalid, {
                "message-1": ("author-1", "Author One"),
                "media-1": ("author-2", "Author Two"),
            }, {"media-1"})

    def test_v1_1_daily_rejects_unknown_evidence_and_unconfigured_author_cards(self) -> None:
        output = parse_v1_1_daily_output(json.dumps({
            "schema_version": "v1.1",
            "natural_date": "2099-01-01",
            "as_of": "2099-01-01T08:00:00Z",
            "author_cards": [{
                "author_id": "author-1",
                "author_display": "Author One",
                "core_logic": {
                    "market_trend": "偏多",
                    "stock_judgments": [{
                        "subject": "ABC",
                        "judgment": "基本面改善",
                        "reasoning": "订单增长",
                        "source_message_ids": ["message-1"],
                    }],
                },
                "operation_tendency": {"market": "逢回调参与", "stocks": None},
                "methodology": ["分散验证"],
                "uncertainty": ["仅有单日讨论"],
                "source_message_ids": ["message-1"],
            }],
            "topic_discussions": [{
                "title": "市场流动性",
                "summary": "讨论认为流动性改善但节奏仍有分歧。",
                "viewpoints": [{
                    "author_id": "author-2",
                    "author_display": "Author Two",
                    "viewpoint": "仍需观察量能持续性",
                    "reasoning": None,
                    "operation_tendency": "等待确认",
                    "source_message_ids": ["message-2"],
                }],
                "uncertainty": ["未解析媒体可能包含补充信息"],
                "source_message_ids": ["message-2"],
            }],
            "warnings": ["存在未解析媒体"],
        }))
        message_catalog = {
            "message-1": ("author-1", "Author One"),
            "message-2": ("author-2", "Author Two"),
            "media-1": ("author-2", "Author Two"),
        }
        fact_units = [{
            "source_message_ids": ["message-1"],
        }, {
            "source_message_ids": ["message-2"],
        }]
        validated = validate_v1_1_daily_output(
            output,
            message_catalog,
            {"author-1": "Author One"},
            fact_units=fact_units,
            expected_natural_date="2099-01-01",
            expected_as_of="2099-01-01T08:00:00Z",
            unparsed_media_ids={"media-1"},
        )
        self.assertEqual(validated["schema_version"], "v1.1")

        invalid = {**output, "author_cards": [{**output["author_cards"][0], "author_id": "author-2", "author_display": "Author Two"}]}
        with self.assertRaisesRegex(SchemaError, "author_card"):
            validate_v1_1_daily_output(
                invalid,
                message_catalog,
                {"author-1": "Author One"},
                fact_units=fact_units,
                expected_natural_date="2099-01-01",
                expected_as_of="2099-01-01T08:00:00Z",
                unparsed_media_ids={"media-1"},
            )

    def test_v1_1_daily_rejects_known_same_day_evidence_outside_verified_fact_units(self) -> None:
        output = {
            "schema_version": "v1.1",
            "natural_date": "2099-01-01",
            "as_of": "2099-01-01T08:00:00Z",
            "author_cards": [{
                "author_id": "author-1",
                "author_display": "Author One",
                "core_logic": {"market_trend": None, "stock_judgments": []},
                "operation_tendency": {"market": None, "stocks": None},
                "methodology": [],
                "uncertainty": [],
                "source_message_ids": ["known-but-not-a-fact"],
            }],
            "topic_discussions": [],
            "warnings": [],
        }
        with self.assertRaisesRegex(SchemaError, "validated fact evidence"):
            validate_v1_1_daily_output(
                output,
                {
                    "fact-message": ("author-1", "Author One"),
                    "known-but-not-a-fact": ("author-1", "Author One"),
                },
                {"author-1": "Author One"},
                fact_units=[{"source_message_ids": ["fact-message"]}],
                expected_natural_date="2099-01-01",
                expected_as_of="2099-01-01T08:00:00Z",
                unparsed_media_ids=set(),
            )


if __name__ == "__main__":
    unittest.main()
