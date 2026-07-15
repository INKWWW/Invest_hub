from __future__ import annotations

from collections.abc import Iterable

from .model import Chunk, FixtureCase, FixtureMessage


def build_chunks(
    case: FixtureCase,
    max_primary_messages: int,
    context_limit: int = 2,
) -> tuple[Chunk, ...]:
    if max_primary_messages < 1:
        raise ValueError("max_primary_messages must be positive")
    if context_limit < 0:
        raise ValueError("context_limit cannot be negative")

    messages = case.messages
    by_id = {message.message_id: message for message in messages}
    chunks: list[Chunk] = []
    for index, start in enumerate(range(0, len(messages), max_primary_messages)):
        primary = messages[start : start + max_primary_messages]
        primary_ids = tuple(message.message_id for message in primary)
        primary_id_set = set(primary_ids)
        context_ids: set[str] = set()

        for message in primary:
            if message.parent_id is not None and message.parent_id not in primary_id_set:
                context_ids.add(message.parent_id)
        for previous in messages[max(0, start - context_limit) : start]:
            context_ids.add(previous.message_id)

        context = tuple(
            message
            for message in messages
            if message.message_id in context_ids and message.message_id not in primary_id_set
        )
        chunks.append(
            _make_chunk(
                case,
                index=index,
                primary=primary,
                context=context,
                by_id=by_id,
            )
        )
    return tuple(chunks)


def split_chunk(chunk: Chunk) -> tuple[Chunk, Chunk]:
    if len(chunk.primary_message_ids) < 2:
        raise ValueError("chunk must contain at least two primary messages")
    midpoint = len(chunk.primary_message_ids) // 2
    left_ids = chunk.primary_message_ids[:midpoint]
    right_ids = chunk.primary_message_ids[midpoint:]
    left = _split_part(chunk, index=chunk.index * 2, primary_ids=left_ids)
    right = _split_part(chunk, index=chunk.index * 2 + 1, primary_ids=right_ids)
    return left, right


def _make_chunk(
    case: FixtureCase,
    *,
    index: int,
    primary: Iterable[FixtureMessage],
    context: Iterable[FixtureMessage],
    by_id: dict[str, FixtureMessage],
) -> Chunk:
    primary_tuple = tuple(primary)
    context_tuple = tuple(context)
    primary_ids = tuple(message.message_id for message in primary_tuple)
    context_ids = tuple(message.message_id for message in context_tuple)
    lines = tuple(
        _message_line("context", message)
        for message in context_tuple
    ) + tuple(_message_line("primary", message) for message in primary_tuple)
    prompt_text = _render_prompt(lines)
    if any(message.message_id not in by_id for message in primary_tuple + context_tuple):
        raise ValueError("chunk references unknown message")
    return Chunk(
        chunk_id=f"{case.case_id}-{index:04d}",
        case_id=case.case_id,
        index=index,
        primary_message_ids=primary_ids,
        context_message_ids=context_ids,
        prompt_text=prompt_text,
        input_chars=len(prompt_text),
        prompt_lines=lines,
    )


def _split_part(chunk: Chunk, *, index: int, primary_ids: tuple[str, ...]) -> Chunk:
    primary_id_set = set(primary_ids)
    lines = tuple(
        line
        for line in chunk.prompt_lines
        if line.split("\t", 2)[1] in primary_id_set
        or line.split("\t", 2)[0] == "context"
    )
    return Chunk(
        chunk_id=f"{chunk.chunk_id}-split-{index:04d}",
        case_id=chunk.case_id,
        index=index,
        primary_message_ids=primary_ids,
        context_message_ids=chunk.context_message_ids,
        prompt_text=_render_prompt(lines),
        input_chars=len(_render_prompt(lines)),
        prompt_lines=lines,
    )


def _message_line(scope: str, message: FixtureMessage) -> str:
    parent_id = message.parent_id or "-"
    content = message.content.replace("\t", " ").replace("\n", " ")
    return "\t".join(
        (
            scope,
            message.message_id,
            message.author_scope,
            message.published_at,
            parent_id,
            content,
        )
    )


def _render_prompt(lines: tuple[str, ...]) -> str:
    return (
        "请只根据以下消息生成结构化 JSON。不得推测未解析媒体内容。\n"
        + "\n".join(lines)
    )
