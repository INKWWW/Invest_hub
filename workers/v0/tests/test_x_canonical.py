from __future__ import annotations

import unittest

from invest_hub_worker.canonical import CanonicalValidationError, Canonicalizer
from invest_hub_worker.connectors.base import RawPage


def x_page(post: dict[str, object]) -> RawPage:
    return RawPage(page_id="page", source_id="x-source", cursor_before=None, cursor_after=None, messages=(post,), raw_payload_ref="local://x/page", source_type="x")


class XCanonicalTests(unittest.TestCase):
    def test_x_quote_relation_is_preserved_without_merging_context_content(self) -> None:
        message = Canonicalizer().map(x_page({
            "id": "post-1", "author": {"id": "author-1", "name": "Author"}, "text": "comment", "created_at": "2026-07-23T00:00:00Z",
            "url": "https://x.com/author/status/1", "post_type": "quote", "quoted_post_id": "quoted-1", "context_status": "complete", "attachments": [],
        }))[0]
        self.assertEqual(message.metadata["x"]["post_type"], "quote")
        self.assertEqual(message.metadata["x"]["quoted_post_id"], "quoted-1")
        self.assertEqual(message.content, "comment")

    def test_x_repost_cannot_fabricate_an_author_comment(self) -> None:
        with self.assertRaises(CanonicalValidationError):
            Canonicalizer().map(x_page({
                "id": "post-1", "author": {"id": "author-1"}, "text": "fabricated", "created_at": "2026-07-23T00:00:00Z",
                "url": "https://x.com/author/status/1", "post_type": "repost", "reposted_post_id": "other-1", "context_status": "complete", "attachments": [],
            }))

    def test_x_requires_a_timezone_aware_time_and_safe_post_link(self) -> None:
        for bad in ("2026-07-23T00:00:00", "", None):
            with self.assertRaises(CanonicalValidationError):
                Canonicalizer().map(x_page({
                    "id": "post-1", "author": {"id": "author-1"}, "text": "", "created_at": bad,
                    "url": "https://x.com/author/status/1", "post_type": "original", "context_status": "complete", "attachments": [],
                }))
