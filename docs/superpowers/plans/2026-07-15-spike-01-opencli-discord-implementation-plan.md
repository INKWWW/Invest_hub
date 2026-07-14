# Spike-01 OpenCLI Discord 增量采集 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 构建一个本地、一次性的 Spike harness，验证 OpenCLI Discord Web 采集能力、最小 Canonical Schema、checkpoint、幂等、恢复和失败隔离，并输出脱敏 Go/No-Go 证据。

**Architecture:** 真实网页轨通过 OpenCLI Boundary 取得原始页面结果，Fake Connector 负责公开 fixture 和故障注入；两条轨道在 Canonical Schema、Validator、本地 Evidence Store 和 Checkpoint Emulator 汇合。harness 不连接云端，不进入生产应用。

**Tech Stack:** Python 3.11+ 标准库（dataclasses、json、pathlib、subprocess、unittest）和已锁定版本的 OpenCLI 外部运行时。此选择只适用于 Spike harness，不固化产品技术栈。

## Global Constraints

- 不生成生产应用代码、应用框架、云端数据库、认证、LLM、X 或生产 Worker。
- 真实网页轨只使用用户本人已登录且有权限访问的专用 Chrome Profile，采集过程只读。
- Cookie、Token、密码、Chrome Profile、私有频道信息、真实正文和真实 fixture 不进入 Git 或云端。
- OpenCLI 任一硬性字段失败即不能判定 OpenCLI-first 通过。
- Playwright/CDP 仅可用于诊断，不能作为字段补齐方案或后备采集器。
- 原始结果、标准化结果和校验结果成功保存后才能推进 checkpoint。
- 公开 fixture 必须人工构造；确定性测试完整率为 100%，重复率为 0%。
- 真实网页轨必须验证至少 1000 条消息及已批准硬性字段；无法满足时写明未验证或不通过。

---

## 1. 文件结构

### 新增

- spikes/spike_01/__init__.py：包入口。
- spikes/spike_01/model.py：领域模型、来源配置、checkpoint 和运行报告。
- spikes/spike_01/preflight.py：OpenCLI 可执行文件和版本检查。
- spikes/spike_01/canonical.py：RawPage 到 Canonical Schema 的转换。
- spikes/spike_01/validator.py：字段、关系、顺序、重复和 checkpoint 安全性校验。
- spikes/spike_01/evidence.py：本地原始、标准化和校验结果存储。
- spikes/spike_01/checkpoint.py：本地 JSON checkpoint 存储。
- spikes/spike_01/connectors.py：Connector Protocol、Fake Connector、OpenCLI Connector。
- spikes/spike_01/runner.py：增量运行编排和命令行入口。
- spikes/spike_01/fixtures/basic_page.json：公开基础 fixture。
- spikes/spike_01/fixtures/recovery_pages.json：公开多页、关系、附件和恢复 fixture。
- spikes/spike_01/tests/test_preflight.py：前置检查测试。
- spikes/spike_01/tests/test_canonical.py：Canonical 映射测试。
- spikes/spike_01/tests/test_validator.py：字段和关系测试。
- spikes/spike_01/tests/test_checkpoint.py：证据存储和 checkpoint 测试。
- spikes/spike_01/tests/test_runner.py：Fake Connector、幂等、恢复和来源隔离测试。
- spikes/spike_01/tests/test_opencli_connector.py：OpenCLI 边界测试。
- spikes/spike_01/README.md：运行和安全说明。
- docs/spikes/2026-07-15-spike-01-decision-report.md：脱敏决策报告。

### 修改

- .gitignore：忽略 Spike 私有配置、证据和本地输出。

### 仓库外本地文件

- /private/tmp/invest-hub-spike-01-contract.json：OpenCLI 版本和实际命令契约。
- /private/tmp/invest-hub-spike-01-evidence/：真实网页原始输出和运行证据。

## 2. 稳定接口

将以下类型写入 spikes/spike_01/model.py：

~~~python
from dataclasses import dataclass
from typing import Any, Literal, Mapping

RecordState = Literal[
    "accepted", "duplicate", "invalid", "unresolved_relation", "failed"
]


@dataclass(frozen=True)
class SourceConfig:
    source_container_id: str
    channel_url: str
    source_account_id: str
    max_messages: int = 1000


@dataclass(frozen=True)
class RawMessage:
    ordinal: int
    payload: Mapping[str, Any]


@dataclass(frozen=True)
class RawPage:
    page_id: str
    source_container_id: str
    cursor_before: str | None
    cursor_after: str | None
    messages: tuple[RawMessage, ...]
    raw_payload_ref: str


@dataclass(frozen=True)
class Attachment:
    name: str
    content_type: str | None
    url: str | None


@dataclass(frozen=True)
class QuoteReference:
    external_item_id: str
    content_text: str | None
    resolved: bool


@dataclass(frozen=True)
class CanonicalMessage:
    source_type: Literal["discord"]
    source_account_id: str
    source_container_id: str
    external_item_id: str
    author_id: str
    author_name: str
    published_at: str
    content_text: str
    content_type: str
    parent_item_id: str | None
    quoted_item: QuoteReference | None
    attachments: tuple[Attachment, ...]
    source_url: str | None
    raw_payload_ref: str
    collected_at: str


@dataclass(frozen=True)
class ValidationIssue:
    code: str
    item_id: str | None
    field: str | None
    detail: str


@dataclass(frozen=True)
class ValidationReport:
    state: RecordState
    issues: tuple[ValidationIssue, ...]
    accepted_ids: tuple[str, ...]
    duplicate_ids: tuple[str, ...]
    unresolved_ids: tuple[str, ...]
    checkpoint_safe: bool


@dataclass(frozen=True)
class Checkpoint:
    source_container_id: str
    cursor: str | None
    last_external_item_id: str | None


@dataclass(frozen=True)
class RunReport:
    run_id: str
    source_container_id: str
    pages_seen: int
    raw_messages_seen: int
    accepted_messages: int
    duplicate_messages: int
    invalid_messages: int
    unresolved_messages: int
    checkpoint_before: Checkpoint | None
    checkpoint_after: Checkpoint | None
    status: Literal["success", "partial", "failed", "unverified"]
    errors: tuple[str, ...]
~~~

将以下 Connector 接口写入 spikes/spike_01/connectors.py：

~~~python
from collections.abc import Iterator
from typing import Protocol

from .model import Checkpoint, RawPage, SourceConfig


class ConnectorError(RuntimeError):
    pass


class Connector(Protocol):
    def iter_pages(
        self,
        config: SourceConfig,
        checkpoint: Checkpoint | None,
    ) -> Iterator[RawPage]:
        raise NotImplementedError
~~~

必须提供以下函数：

~~~python
def normalize_page(
    page: RawPage,
    source_account_id: str,
) -> tuple[CanonicalMessage, ...]:
    raise NotImplementedError


def validate_page(
    messages: tuple[CanonicalMessage, ...],
    expected_container_id: str,
    known_external_ids: frozenset[str],
) -> ValidationReport:
    raise NotImplementedError


def run_incremental(
    connector: Connector,
    config: SourceConfig,
    evidence: LocalEvidenceStore,
    checkpoints: JsonCheckpointStore,
) -> RunReport:
    raise NotImplementedError
~~~

## 3. Task 1：建立 harness 和 OpenCLI 前置检查

**Files:**

- Create: spikes/spike_01/__init__.py
- Create: spikes/spike_01/preflight.py
- Create: spikes/spike_01/tests/test_preflight.py
- Create: spikes/spike_01/README.md
- Modify: .gitignore

**Interfaces:**

- Consumes: OPENCLI_BIN，默认值为 opencli。
- Produces: check_opencli(executable: str) -> PreflightResult。

- [ ] **Step 1: 写失败测试**

~~~python
import unittest
from unittest.mock import patch

from spike_01.preflight import PreflightError, check_opencli


class PreflightTests(unittest.TestCase):
    @patch("spike_01.preflight.subprocess.run")
    def test_missing_executable_is_reported(self, run):
        run.side_effect = FileNotFoundError("opencli not found")
        with self.assertRaisesRegex(PreflightError, "executable not found"):
            check_opencli("opencli")

    @patch("spike_01.preflight.subprocess.run")
    def test_version_is_returned(self, run):
        run.return_value.stdout = "opencli 1.2.3\n"
        run.return_value.stderr = ""
        run.return_value.returncode = 0
        result = check_opencli("opencli")
        self.assertEqual(result.version, "opencli 1.2.3")


if __name__ == "__main__":
    unittest.main()
~~~

- [ ] **Step 2: 运行失败测试**

~~~bash
PYTHONPATH=spikes python3 -m unittest spikes.spike_01.tests.test_preflight -v
~~~

预期：FAIL，因为 preflight.py 尚未存在。

- [ ] **Step 3: 实现前置检查**

~~~python
import subprocess
from dataclasses import dataclass


class PreflightError(RuntimeError):
    pass


@dataclass(frozen=True)
class PreflightResult:
    executable: str
    version: str


def check_opencli(executable: str) -> PreflightResult:
    try:
        completed = subprocess.run(
            [executable, "--version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except FileNotFoundError as exc:
        raise PreflightError("executable not found") from exc
    except subprocess.TimeoutExpired as exc:
        raise PreflightError("version check timed out") from exc
    if completed.returncode != 0:
        detail = completed.stderr.strip() or "unknown version error"
        raise PreflightError(f"version check failed: {detail}")
    version = completed.stdout.strip()
    if not version:
        raise PreflightError("version output is empty")
    return PreflightResult(executable, version)
~~~

- [ ] **Step 4: 写运行说明和忽略规则**

在 .gitignore 追加：

~~~gitignore
/spikes/spike_01/private/
/spikes/spike_01/evidence/
/docs/spikes/*-real.md
~~~

README 必须写明真实证据目录、只读边界、禁止提交敏感信息，以及 OpenCLI 缺失时只记录环境前置条件失败。

- [ ] **Step 5: 运行测试并提交**

运行前置检查测试，预期 PASS，然后提交：

~~~bash
git add .gitignore spikes/spike_01
git commit -m "spike: add OpenCLI preflight harness"
~~~

## 4. Task 2：实现 Canonical Schema 和 Validator

**Files:**

- Create: spikes/spike_01/model.py
- Create: spikes/spike_01/canonical.py
- Create: spikes/spike_01/validator.py
- Create: spikes/spike_01/fixtures/basic_page.json
- Create: spikes/spike_01/tests/test_canonical.py
- Create: spikes/spike_01/tests/test_validator.py

**Interfaces:**

- Consumes: Task 1 的包结构和公开 RawPage fixture。
- Produces: normalize_page、validate_page、CanonicalMessage 和 ValidationReport。

- [ ] **Step 1: 写公开基础 fixture 和失败测试**

basic_page.json 使用以下结构，所有内容必须人工构造：

~~~json
{
  "page_id": "page-001",
  "source_container_id": "channel-public-001",
  "cursor_before": null,
  "cursor_after": "cursor-001",
  "raw_payload_ref": "fixture://basic_page.json",
  "messages": [
    {
      "id": "message-001",
      "author": {"id": "author-001", "name": "Analyst A"},
      "channel_id": "channel-public-001",
      "published_at": "2026-01-01T08:00:00Z",
      "content": "人工构造的公开测试消息，ticker ABC。",
      "content_type": "text",
      "reply_to": null,
      "quote": null,
      "attachments": [],
      "source_url": "https://discord.example/messages/message-001"
    }
  ]
}
~~~

测试必须覆盖身份、作者、频道、时间、正文、source_url、附件、回复、引用和 raw_payload_ref。

- [ ] **Step 2: 运行失败测试**

~~~bash
PYTHONPATH=spikes python3 -m unittest \
  spikes.spike_01.tests.test_canonical \
  spikes.spike_01.tests.test_validator -v
~~~

预期：FAIL，因为 model.py、canonical.py 和 validator.py 尚未实现。

- [ ] **Step 3: 实现模型和映射**

将本计划第 2 节的类型定义写入 model.py。canonical.py 的 normalize_page 必须：

- 从 author.id 和 author.name 读取作者；
- 从 channel_id 读取频道；
- 保留 Discord 原始时间、正文、内容类型和 source_url；
- 将 reply_to 映射为 parent_item_id；
- 将 quote 映射为 QuoteReference；
- 将附件映射为 Attachment；
- 记录 raw_payload_ref 和 collected_at；
- 缺少硬性字段时抛出可定位的转换错误，不使用推测值。

- [ ] **Step 4: 实现 Validator**

validate_page 必须：

- 缺少消息 ID、作者 ID、频道 ID或发布时间时返回 invalid 且 checkpoint_safe 为 False；
- 频道 ID冲突、当前页重复 ID返回 invalid；
- 已知 ID返回 duplicate，不新增 Canonical 记录；
- 回复/引用目标未知时返回 unresolved_relation，保留外部 ID且 checkpoint_safe 为 True；
- 正常记录返回 accepted 且 checkpoint_safe 为 True；
- 每个异常都生成 ValidationIssue。

- [ ] **Step 5: 运行测试并提交**

运行 Task 2 的 unittest 命令，预期所有测试 PASS，然后提交：

~~~bash
git add spikes/spike_01
git commit -m "spike: add Discord canonical schema contract"
~~~

## 5. Task 3：实现本地 Evidence Store 和 Checkpoint Emulator

**Files:**

- Create: spikes/spike_01/evidence.py
- Create: spikes/spike_01/checkpoint.py
- Create: spikes/spike_01/tests/test_checkpoint.py

**Interfaces:**

- Consumes: RawPage、CanonicalMessage 和 ValidationReport。
- Produces: LocalEvidenceStore 和 JsonCheckpointStore。

- [ ] **Step 1: 写失败测试**

使用 tempfile.TemporaryDirectory() 覆盖：

- 初始 checkpoint 为空；
- checkpoint 写入后可读取；
- 未调用 commit 时旧 checkpoint 不变；
- 原始页、Canonical 结果和 ValidationReport 可读取；
- external_item_id 可查询；
- checkpoint JSON 包含 source_container_id、cursor 和 last_external_item_id。

- [ ] **Step 2: 运行失败测试**

~~~bash
PYTHONPATH=spikes python3 -m unittest spikes.spike_01.tests.test_checkpoint -v
~~~

预期：FAIL，因为 evidence.py 和 checkpoint.py 尚未存在。

- [ ] **Step 3: 实现 LocalEvidenceStore**

必须提供：

~~~python
class LocalEvidenceStore:
    def __init__(self, root: Path) -> None: pass
    def persist_raw(self, page: RawPage) -> None: raise NotImplementedError
    def persist_canonical(
        self, messages: tuple[CanonicalMessage, ...]
    ) -> None: raise NotImplementedError
    def persist_validation(self, report: ValidationReport) -> None: raise NotImplementedError
    def has_message(self, external_item_id: str) -> bool: raise NotImplementedError
    def message_count(self) -> int: raise NotImplementedError
~~~

root 下建立 raw、canonical、validation、metrics 四个目录；原始页面使用 JSON，Canonical 和验证结果使用 JSONL；写入后 flush 和 fsync；不记录 Cookie、Token 或真实凭据。

- [ ] **Step 4: 实现 JsonCheckpointStore**

必须提供：

~~~python
class JsonCheckpointStore:
    def __init__(self, root: Path) -> None: pass
    def load(self, source_container_id: str) -> Checkpoint | None: raise NotImplementedError
    def commit(self, checkpoint: Checkpoint) -> None: raise NotImplementedError
~~~

commit 先写临时 JSON，再原子替换目标文件；写入失败不得改变旧 checkpoint。

- [ ] **Step 5: 运行测试并提交**

运行 Task 3 的 unittest 命令，预期 PASS，然后提交：

~~~bash
git add spikes/spike_01
git commit -m "spike: add local evidence and checkpoint emulator"
~~~

## 6. Task 4：实现 Fake Connector、Runner 和确定性恢复

**Files:**

- Create: spikes/spike_01/connectors.py
- Create: spikes/spike_01/runner.py
- Create: spikes/spike_01/fixtures/recovery_pages.json
- Create: spikes/spike_01/tests/test_runner.py

**Interfaces:**

- Consumes: Task 2 的转换/校验接口和 Task 3 的本地存储接口。
- Produces: FakeConnector 和 run_incremental(connector, config, evidence, checkpoints) -> RunReport。

- [ ] **Step 1: 写三页 recovery fixture**

recovery_pages.json 必须包含：

- 三页连续 cursor；
- 至少 12 条人工构造消息；
- 一条回复；
- 一条引用；
- 一个包含文件名、类型和链接的附件；
- 一个当前 fixture 不包含的引用目标；
- 每条消息唯一 ID和一致频道 ID。

- [ ] **Step 2: 写失败测试**

覆盖：

- 二次运行不新增 Canonical 消息；
- 二次运行将已存在 ID记录为 duplicate；
- 第二页失败时只提交第一页 checkpoint；
- 失败后再次运行从旧 checkpoint 继续；
- 同一运行内重复 ID不推进 checkpoint；
- 缺少作者 ID时原始页保留且 checkpoint 不推进；
- channel-a 失败不影响 channel-b；
- 删除 checkpoint 对应原始消息时不伪造上下文。

- [ ] **Step 3: 运行失败测试**

~~~bash
PYTHONPATH=spikes python3 -m unittest spikes.spike_01.tests.test_runner -v
~~~

预期：FAIL，因为 FakeConnector 和 Runner 尚未实现。

- [ ] **Step 4: 实现 FakeConnector**

必须提供：

~~~python
class FakeConnector:
    def __init__(
        self,
        pages: tuple[RawPage, ...],
        *,
        fail_after_page: int | None = None,
    ) -> None: pass

    @classmethod
    def from_fixture(
        cls,
        path: Path,
        *,
        source_container_id: str,
        fail_after_page: int | None = None,
    ) -> "FakeConnector": raise NotImplementedError

    def iter_pages(
        self,
        config: SourceConfig,
        checkpoint: Checkpoint | None,
    ) -> Iterator[RawPage]: raise NotImplementedError
~~~

iter_pages 从 checkpoint 之后的页开始；达到 fail_after_page 时抛出 ConnectorError；Fake Connector 不推进 checkpoint。

- [ ] **Step 5: 实现 Runner**

run_incremental 的每页顺序必须是：

1. 读取 checkpoint；
2. 从 Connector 取得一页；
3. 保存原始页；
4. 转换 Canonical 消息；
5. 保存 Canonical 消息；
6. 校验并保存 ValidationReport；
7. 仅在 checkpoint_safe 为 True 时提交下一 checkpoint；
8. ConnectorError 或持久化异常返回 partial/failed，并保留旧 checkpoint；
9. 通过 external_item_id 记录 duplicate，不重复追加；
10. 返回完整 RunReport。

- [ ] **Step 6: 运行全套确定性测试**

~~~bash
PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_01/tests -v
~~~

预期：全部 PASS；fixture 完整率 100%，重复率 0%，恢复后的最终 Canonical ID 集合与一次性成功运行一致。

- [ ] **Step 7: 提交独立变更**

~~~bash
git add spikes/spike_01
git commit -m "spike: add deterministic Discord incremental runner"
~~~

## 7. Task 5：接入 OpenCLI Boundary 和真实网页轨

**Files:**

- Modify: spikes/spike_01/connectors.py
- Modify: spikes/spike_01/runner.py
- Create: spikes/spike_01/tests/test_opencli_connector.py
- Modify: spikes/spike_01/README.md

**Interfaces:**

- Consumes: OpenCLI 版本检查、RawPage contract 和 Runner。
- Produces: OpenCLIInvoker、SubprocessOpenCLIInvoker、OpenCLIConnector 和真实网页运行命令。

- [ ] **Step 1: 捕获 OpenCLI 外部契约**

~~~bash
export OPENCLI_BIN='opencli'
"$OPENCLI_BIN" --version > /private/tmp/invest-hub-spike-01-opencli-version.txt
"$OPENCLI_BIN" --help > /private/tmp/invest-hub-spike-01-opencli-help.txt
~~~

将实际版本、Discord 读取命令、分页参数、profile 参数、JSON 输出方式和退出码规则记录到 /private/tmp/invest-hub-spike-01-contract.json。契约文件不得包含频道 URL、Profile 路径、Cookie、Token 或消息正文。

如果可执行文件缺失或没有机器可解析输出，完成 Task 1–4，并在报告中标记真实网页轨未验证；不发明命令参数，不切换到 Playwright/CDP。

- [ ] **Step 2: 写 OpenCLI 边界失败测试**

覆盖：

- JSON stdout 可以转换为 RawPage；
- 非零退出码产生 ConnectorError；
- 非 JSON 输出产生 ConnectorError；
- stderr 不进入 Canonical 内容；
- contract 中的 channel_url、profile_path 和 cursor 被替换；
- cursor 为空时不发送字符串 None；
- 实际版本与契约版本不同则停止。

- [ ] **Step 3: 实现命令边界**

在 connectors.py 增加：

~~~python
class OpenCLIInvoker(Protocol):
    def fetch_page(
        self,
        *,
        channel_url: str,
        profile_path: Path,
        cursor: str | None,
    ) -> Mapping[str, Any]: raise NotImplementedError


class OpenCLIConnector:
    def __init__(
        self,
        invoker: OpenCLIInvoker,
        *,
        source_account_id: str,
    ) -> None: pass

    def iter_pages(
        self,
        config: SourceConfig,
        checkpoint: Checkpoint | None,
    ) -> Iterator[RawPage]: raise NotImplementedError
~~~

SubprocessOpenCLIInvoker 从私有 contract 文件读取 executable、version、args template 和 output mode，校验版本后执行；不自动升级或降级。

- [ ] **Step 4: 增加真实运行入口**

runner.py 必须支持：

~~~text
python3 -m spike_01.runner real
  --channel-url 本地频道 URL
  --profile-path 本地专用 Profile 路径
  --source-account-id 脱敏标识
  --opencli-bin 可执行文件
  --contract-path 本地 contract 路径
  --evidence-dir 本地证据目录
  --max-messages 1000
~~~

真实运行命令：

~~~bash
export DISCORD_CHANNEL_URL='用户本地频道 URL'
export CHROME_PROFILE_PATH='用户本地专用 Profile 路径'
export SPIKE_EVIDENCE_DIR='/private/tmp/invest-hub-spike-01-evidence'
PYTHONPATH=spikes python3 -m spike_01.runner real \
  --channel-url "$DISCORD_CHANNEL_URL" \
  --profile-path "$CHROME_PROFILE_PATH" \
  --source-account-id local-test-account \
  --opencli-bin opencli \
  --contract-path /private/tmp/invest-hub-spike-01-contract.json \
  --evidence-dir "$SPIKE_EVIDENCE_DIR" \
  --max-messages 1000
~~~

命令只能读取 Discord，不发送消息、不修改频道内容、不访问其他网站。

- [ ] **Step 5: 执行真实网页两轮**

第一轮必须记录：

- 是否访问指定频道；
- 消息数量，目标至少 1000；
- 消息 ID、作者 ID、频道 ID、时间、正文；
- 回复、引用和附件元数据；
- 分页或虚拟滚动连续性；
- OpenCLI 版本；
- 原始、Canonical、ValidationReport 和指标文件。

第二轮使用同一频道、Profile、contract 和新 run ID，验证已采集 ID不重复、checkpoint 从第一轮末尾开始、无明显漏采。

失败必须分为环境前置条件、OpenCLI 能力缺口、harness 映射错误或页面采集不完整。

- [ ] **Step 6: 运行 OpenCLI 单元测试并提交**

~~~bash
PYTHONPATH=spikes python3 -m unittest \
  spikes.spike_01.tests.test_opencli_connector -v
git add spikes/spike_01
git commit -m "spike: add OpenCLI Discord boundary"
~~~

## 8. Task 6：生成脱敏决策报告并完成验收

**Files:**

- Create: docs/spikes/2026-07-15-spike-01-decision-report.md
- Modify: spikes/spike_01/README.md

**Interfaces:**

- Consumes: 确定性测试结果、真实网页证据和错误分类。
- Produces: 脱敏 Go/No-Go 报告。

- [ ] **Step 1: 运行完整测试**

~~~bash
PYTHONPATH=spikes python3 -m unittest discover -s spikes/spike_01/tests -v
~~~

记录测试总数、通过数、fixture 消息数、完整率、重复率、恢复结果、checkpoint 提交/越界次数、多频道隔离和故障分类。

- [ ] **Step 2: 检查敏感文件**

~~~bash
find /private/tmp/invest-hub-spike-01-evidence -maxdepth 3 -type f -print
git status --short
~~~

若仓库目录出现真实正文、Cookie、Token、Profile 文件或私有链接，立即停止报告生成并隔离清理，不得提交。

- [ ] **Step 3: 写脱敏报告**

报告必须包含执行环境、真实网页结果、确定性轨结果、失败分类、未验证项、OpenCLI-first Go/No-Go、进入 V0/V1 的建议和需用户确认的后续决策。只能引用计数、状态和脱敏标识，不引用真实正文、频道 URL、Profile 路径或完整附件链接。

- [ ] **Step 4: 对照 Spike-01 spec 验收**

逐项核对双轨证据、1000 条真实采集、硬性字段、回复/引用/附件、幂等、fixture 100% 完整率、fixture 0% 重复率、checkpoint 后置推进、单频道失败隔离、未使用 Playwright/CDP 补齐和真实数据未入 Git。

缺少证据的项目写为未验证或不通过，不写整体通过。

- [ ] **Step 5: 提交报告**

~~~bash
git add docs/spikes/2026-07-15-spike-01-decision-report.md spikes/spike_01/README.md
git commit -m "docs: record Spike-01 Discord collection decision"
~~~

## 9. 完成条件

本计划完成后应存在公开 fixture harness、真实网页运行入口、字段/关系验证结果、checkpoint/幂等/恢复测试结果、脱敏决策报告和明确的 OpenCLI-first Go/No-Go。

本计划不批准 V0 或 V1 实现；决策报告审阅完成后，才开始下一子项目 spec。

## 10. Plan 自检

- Spec 覆盖：Task 1 覆盖前置条件和安全边界；Task 2 覆盖 Canonical Schema 与字段；Task 3 覆盖原始证据和 checkpoint；Task 4 覆盖 fixture、幂等、恢复和失败隔离；Task 5 覆盖 OpenCLI 真实网页轨；Task 6 覆盖脱敏报告和最终验收。
- 范围检查：没有加入 LLM、X、云端数据库、认证、生产 Worker、后备采集器或 UI。
- 接口一致性：Runner 使用 Connector、LocalEvidenceStore、JsonCheckpointStore、normalize_page 和 validate_page，后续任务不改名前序接口。
- 数据安全检查：真实证据位于 /private/tmp，仓库只接收公开 fixture 和脱敏报告。
- 验收检查：1000 条真实网页采集、硬性字段、二次运行、checkpoint、恢复、失败隔离和未验证分类均有任务。
- 占位符检查：步骤不依赖未填充的后续空白；OpenCLI 实际参数通过前置契约捕获，不凭空假设。
