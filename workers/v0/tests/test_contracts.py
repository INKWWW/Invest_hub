import unittest

from invest_hub_worker.contracts import ContractError, load_contract, validate_task_result


class ContractTests(unittest.TestCase):
    def test_valid_heartbeat_is_accepted(self):
        value = load_contract(
            "heartbeat",
            {
                "contract_version": "v0",
                "worker_id": "worker-001",
                "sent_at": "2026-07-18T12:00:00Z",
                "status": "idle",
                "capabilities": ["discord_sync"],
            },
        )
        self.assertEqual(value["worker_id"], "worker-001")

    def test_valid_task_claim_and_result_are_accepted(self):
        claim = load_contract(
            "task-claim",
            {
                "contract_version": "v0",
                "task_id": "task-001",
                "attempt": 1,
                "task_type": "discord_sync",
                "source_id": "source-001",
                "parameter_version": "v0-c100-c5",
                "lease_expires_at": "2026-07-18T12:10:00Z",
                "safe_checkpoint": "cursor-010",
            },
        )
        result = validate_task_result(
            {
                "contract_version": "v0",
                "task_id": claim["task_id"],
                "attempt": claim["attempt"],
                "status": "succeeded",
                "safe_checkpoint": "cursor-020",
                "raw_count": 10,
                "canonical_count": 9,
                "duplicate_count": 1,
                "unresolved_count": 0,
                "unparsed_media_count": 0,
                "structured_run_ids": ["structured-001"],
                "telemetry": {
                    "elapsed_ms": 1200,
                    "retry_count": 0,
                    "failure_class": None,
                },
            },
            previous_checkpoint="cursor-010",
            allowed_checkpoints={"cursor-010", "cursor-020"},
        )
        self.assertEqual(result["safe_checkpoint"], "cursor-020")

    def test_missing_task_id_is_rejected(self):
        with self.assertRaises(ContractError):
            load_contract(
                "task-claim",
                {
                    "contract_version": "v0",
                    "attempt": 1,
                    "task_type": "discord_sync",
                    "source_id": "source-001",
                    "parameter_version": "v0-c100-c5",
                    "lease_expires_at": "2026-07-18T12:10:00Z",
                    "safe_checkpoint": None,
                },
            )

    def test_unknown_failure_class_is_rejected(self):
        with self.assertRaises(ContractError):
            load_contract(
                "task-failure",
                {
                    "contract_version": "v0",
                    "task_id": "task-001",
                    "attempt": 1,
                    "status": "retryable_failed",
                    "failure_class": "invented_failure",
                    "safe_checkpoint": "cursor-010",
                    "retryable": True,
                },
            )

    def test_failure_stage_is_allowlisted_when_present(self):
        accepted = load_contract(
            "task-failure",
            {
                "contract_version": "v0",
                "task_id": "task-001",
                "attempt": 1,
                "status": "retryable_failed",
                "failure_class": "persistence_failure",
                "failure_stage": "remote_page_persist",
                "safe_checkpoint": None,
                "retryable": True,
            },
        )
        self.assertEqual(accepted["failure_stage"], "remote_page_persist")

        with self.assertRaises(ContractError):
            load_contract(
                "task-failure",
                {
                    "contract_version": "v0",
                    "task_id": "task-001",
                    "attempt": 1,
                    "status": "retryable_failed",
                    "failure_class": "persistence_failure",
                    "failure_stage": "raw_exception_text",
                    "safe_checkpoint": None,
                    "retryable": True,
                },
            )

    def test_checkpoint_outside_allowed_input_range_is_rejected(self):
        with self.assertRaises(ContractError):
            validate_task_result(
                {
                    "contract_version": "v0",
                    "task_id": "task-001",
                    "attempt": 1,
                    "status": "succeeded",
                    "safe_checkpoint": "cursor-999",
                    "raw_count": 1,
                    "canonical_count": 1,
                    "duplicate_count": 0,
                    "unresolved_count": 0,
                    "unparsed_media_count": 0,
                    "structured_run_ids": [],
                    "telemetry": {
                        "elapsed_ms": 10,
                        "retry_count": 0,
                        "failure_class": None,
                    },
                },
                previous_checkpoint="cursor-010",
                allowed_checkpoints={"cursor-010", "cursor-020"},
            )

    def test_full_prompt_or_response_cannot_enter_task_result(self):
        with self.assertRaises(ContractError):
            load_contract(
                "task-result",
                {
                    "contract_version": "v0",
                    "task_id": "task-001",
                    "attempt": 1,
                    "status": "succeeded",
                    "safe_checkpoint": None,
                    "raw_count": 0,
                    "canonical_count": 0,
                    "duplicate_count": 0,
                    "unresolved_count": 0,
                    "unparsed_media_count": 0,
                    "structured_run_ids": [],
                    "telemetry": {
                        "elapsed_ms": 10,
                        "retry_count": 0,
                        "failure_class": None,
                    },
                    "prompt": "private prompt",
                    "raw_response": "private response",
                },
            )


if __name__ == "__main__":
    unittest.main()
