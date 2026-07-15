import json
import unittest
from http.client import RemoteDisconnected
from urllib.error import HTTPError

from spike_02.model import Chunk, LLMRequest
from spike_02.providers import GLMProvider, MockOutcome, MockProvider


VALID_JSON = '{"topics":[],"media_unparsed":false,"warnings":[]}'


def request_for(chunk_id="case-0000"):
    chunk = Chunk(
        chunk_id=chunk_id,
        case_id="case",
        index=0,
        primary_message_ids=("public-001",),
        context_message_ids=(),
        prompt_text="prompt",
        input_chars=6,
        prompt_lines=("primary\tpublic-001",),
    )
    return LLMRequest("run-001", chunk, attempt=1, prompt_version="test-v1")


class FakeResponse:
    def __init__(self, payload, *, status=200):
        self.payload = json.dumps(payload).encode("utf-8")
        self.status = status

    def read(self):
        return self.payload

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False


class ProviderTests(unittest.TestCase):
    def test_mock_returns_scripted_json_and_counts_calls(self):
        provider = MockProvider({"case-0000": [MockOutcome.success(VALID_JSON)]})
        response = provider.complete(request_for("case-0000"))
        self.assertEqual(response.status, "success")
        self.assertEqual(provider.call_count, 1)
        self.assertEqual(provider.calls_for("case-0000"), 1)

    def test_mock_can_inject_timeout_then_success(self):
        provider = MockProvider(
            {
                "case-0000": [
                    MockOutcome.failure("timeout"),
                    MockOutcome.success(VALID_JSON),
                ]
            }
        )
        self.assertEqual(provider.complete(request_for("case-0000")).status, "timeout")
        self.assertEqual(provider.complete(request_for("case-0000")).status, "success")

    def test_glm_maps_http_429_to_rate_limited_without_leaking_key(self):
        def raising_429_opener(request, timeout):
            raise HTTPError(request.full_url, 429, "rate limited", {}, None)

        provider = GLMProvider(
            endpoint="https://glm.example.test",
            api_key="secret",
            model="glm-test",
            opener=raising_429_opener,
        )
        response = provider.complete(request_for())
        self.assertEqual(response.status, "rate_limited")
        self.assertNotIn("secret", str(response))

    def test_glm_reads_openai_compatible_json_response(self):
        seen = {}

        def opener(request, timeout):
            seen["timeout"] = timeout
            seen["body"] = json.loads(request.data.decode("utf-8"))
            return FakeResponse(
                {
                    "choices": [
                        {
                            "message": {"content": VALID_JSON},
                            "finish_reason": "stop",
                        }
                    ],
                    "usage": {"prompt_tokens": 10, "completion_tokens": 4},
                }
            )

        response = GLMProvider(
            endpoint="https://glm.example.test",
            api_key="secret",
            model="glm-test",
            opener=opener,
            timeout_seconds=7,
        ).complete(request_for())
        self.assertEqual(response.status, "success")
        self.assertEqual(response.input_tokens, 10)
        self.assertEqual(response.output_tokens, 4)
        self.assertEqual(seen["timeout"], 7)
        self.assertEqual(seen["body"]["model"], "glm-test")

    def test_glm_maps_network_disconnect_to_provider_unavailable(self):
        def opener(request, timeout):
            raise RemoteDisconnected("closed")

        response = GLMProvider(
            endpoint="https://glm.example.test",
            api_key="secret",
            model="glm-test",
            opener=opener,
        ).complete(request_for())
        self.assertEqual(response.status, "provider_unavailable")


if __name__ == "__main__":
    unittest.main()
