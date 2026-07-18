import unittest

from spike_02.schema import SchemaError, parse_structured_output, validate_structured_output


def valid_json(source_message_id="public-001"):
    return (
        '{"topics":[{"title":"ABC","summary":"收入增速稳健",'
        f'"source_message_ids":["{source_message_id}"],'
        '"author_scope":"target","author_id":"target-user",'
        '"tickers":["ABC"],"operation_tendency":null,"uncertainty":null}],'
        '"media_unparsed":false,"media_source_message_ids":[],"warnings":[]}'
    )


class SchemaTests(unittest.TestCase):
    def test_schema_rejects_unknown_source_message_id(self):
        with self.assertRaisesRegex(SchemaError, "source_message_ids"):
            validate_structured_output(
                parse_structured_output(valid_json("missing")),
                {"public-001"},
                {"target-user"},
                set(),
            )

    def test_schema_requires_media_source_message_ids(self):
        text = valid_json().replace('"media_source_message_ids":[],', "")
        with self.assertRaisesRegex(SchemaError, "media_source_message_ids"):
            parse_structured_output(text)

    def test_schema_requires_all_unparsed_media_sources(self):
        output = parse_structured_output(
            valid_json().replace(
                '"media_unparsed":false,"media_source_message_ids":[]',
                '"media_unparsed":true,"media_source_message_ids":["public-008"]',
            )
        )
        with self.assertRaisesRegex(SchemaError, "media_source_message_ids"):
            validate_structured_output(
                output,
                {"public-001", "public-008"},
                {"target-user"},
                {"public-008", "public-009"},
            )

    def test_schema_rejects_non_media_source_id(self):
        output = parse_structured_output(
            valid_json().replace(
                '"media_source_message_ids":[]',
                '"media_source_message_ids":["public-001"]',
            )
        )
        with self.assertRaisesRegex(SchemaError, "media_source_message_ids"):
            validate_structured_output(
                output,
                {"public-001"},
                {"target-user"},
                {"public-008"},
            )

    def test_schema_accepts_complete_media_source_ids(self):
        output = parse_structured_output(
            valid_json().replace(
                '"media_unparsed":false,"media_source_message_ids":[]',
                '"media_unparsed":true,"media_source_message_ids":["public-008"]',
            )
        )
        validate_structured_output(
            output,
            {"public-001", "public-008"},
            {"target-user"},
            {"public-008"},
        )

    def test_program_repair_only_removes_json_fence(self):
        output = parse_structured_output(
            '```json\n{"topics":[],"media_unparsed":false,"media_source_message_ids":[],"warnings":[]}\n```'
        )
        self.assertEqual(output.topics, ())

    def test_schema_rejects_missing_required_top_level_fields(self):
        with self.assertRaisesRegex(SchemaError, "missing_field"):
            parse_structured_output('{"messages":[]}')

    def test_target_topic_requires_known_target_author(self):
        text = valid_json().replace('"target-user"', '"other-user"')
        output = parse_structured_output(text)
        with self.assertRaisesRegex(SchemaError, "author_id"):
            validate_structured_output(output, {"public-001"}, {"target-user"}, set())

    def test_invalid_json_has_stable_error_code(self):
        with self.assertRaises(SchemaError) as context:
            parse_structured_output("not json")
        self.assertEqual(context.exception.code, "invalid_json")


if __name__ == "__main__":
    unittest.main()
