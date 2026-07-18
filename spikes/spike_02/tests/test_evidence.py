import json
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from spike_02.evidence import EvidenceStore
from spike_02.model import Chunk, LLMRequest, ProviderResponse


class EvidenceTests(unittest.TestCase):
    def test_concurrent_request_persistence_serializes_file_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = EvidenceStore(root)
            original_append = evidence._append_jsonl
            state_lock = threading.Lock()
            active = 0
            max_active = 0

            def slow_append(target, payload):
                nonlocal active, max_active
                with state_lock:
                    active += 1
                    max_active = max(max_active, active)
                try:
                    time.sleep(0.01)
                    original_append(target, payload)
                finally:
                    with state_lock:
                        active -= 1

            evidence._append_jsonl = slow_append

            def persist(index):
                chunk = Chunk(
                    chunk_id=f"case-{index:04d}",
                    case_id="case",
                    index=index,
                    primary_message_ids=(f"public-{index:04d}",),
                    context_message_ids=(),
                    prompt_text="secret prompt",
                    input_chars=13,
                    prompt_lines=(f"primary\tpublic-{index:04d}",),
                )
                evidence.persist_request(
                    LLMRequest("run-001", chunk, 1, "test-v1"),
                    ProviderResponse(
                        "success",
                        "{}",
                        10,
                        None,
                        None,
                        "stop",
                        None,
                        diagnostic="secret diagnostic",
                    ),
                )

            with ThreadPoolExecutor(max_workers=4) as executor:
                list(executor.map(persist, range(40)))

            lines = [
                json.loads(line)
                for line in (root / "requests.jsonl").read_text().splitlines()
            ]
            self.assertEqual(max_active, 1)
            self.assertEqual(len(lines), 40)
            self.assertEqual(
                {row["chunk_id"] for row in lines},
                {f"case-{index:04d}" for index in range(40)},
            )
            self.assertTrue(all("prompt_text" not in row for row in lines))
            self.assertTrue(all("secret diagnostic" not in row for row in lines))

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

    def test_request_record_contains_exit_code_and_not_diagnostic_text(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = EvidenceStore(root)
            chunk = Chunk(
                chunk_id="case-0000",
                case_id="case",
                index=0,
                primary_message_ids=("public-001",),
                context_message_ids=(),
                prompt_text="prompt",
                input_chars=6,
                prompt_lines=("primary\tpublic-001",),
            )
            request = LLMRequest("run-001", chunk, 1, "test-v1")
            response = ProviderResponse(
                status="provider_failed",
                content=None,
                latency_ms=10,
                input_tokens=None,
                output_tokens=None,
                finish_reason=None,
                error_code="provider_failed",
                process_exit_code=7,
                diagnostic="stderr text",
            )
            evidence.persist_request(request, response)
            payload = json.loads((root / "requests.jsonl").read_text().splitlines()[0])
            self.assertEqual(payload["process_exit_code"], 7)
            self.assertTrue(payload["stderr_present"])
            self.assertNotIn("stderr text", payload)


if __name__ == "__main__":
    unittest.main()
