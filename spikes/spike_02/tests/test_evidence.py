import json
import tempfile
import unittest
from pathlib import Path

from spike_02.evidence import EvidenceStore
from spike_02.model import Chunk, LLMRequest, ProviderResponse


class EvidenceTests(unittest.TestCase):
    def test_safe_request_record_contains_metadata_but_not_prompt_or_key(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = EvidenceStore(root)
            chunk = Chunk(
                chunk_id="case-0000",
                case_id="case",
                index=0,
                primary_message_ids=("public-001",),
                context_message_ids=(),
                prompt_text="secret fixture prompt",
                input_chars=21,
                prompt_lines=("primary\tpublic-001",),
            )
            request = LLMRequest("run-001", chunk, 1, "test-v1")
            response = ProviderResponse("success", "{}", 12, 3, 1, "stop", None)
            evidence.persist_request(request, response)
            payload = json.loads((root / "requests.jsonl").read_text().splitlines()[0])
            self.assertNotIn("prompt_text", payload)
            self.assertNotIn("api_key", payload)
            self.assertEqual(payload["chunk_id"], request.chunk.chunk_id)

    def test_raw_response_is_written_only_under_evidence_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = EvidenceStore(root)
            evidence.persist_raw_response("req-001", {"secret": "local-only"})
            self.assertEqual(
                json.loads((root / "raw_responses" / "req-001.json").read_text()),
                {"secret": "local-only"},
            )


if __name__ == "__main__":
    unittest.main()
