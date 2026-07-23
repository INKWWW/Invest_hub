from __future__ import annotations

import unittest

from fixtures import V2FixtureControl, instant, text


class XRecoveryAndPermissionsTests(unittest.TestCase):
    def test_failed_middle_window_does_not_block_another_source_or_move_its_waterline(self) -> None:
        control = V2FixtureControl()
        control.configure("x-a", "2026-07-23T00:00:00+08:00"); control.configure("x-b", "2026-07-23T00:00:00+08:00")
        a, b = control.schedule("x-a", "2026-07-23T16:00:00+08:00"), control.schedule("x-b", "2026-07-23T16:00:00+08:00")
        control.complete(b[0]["id"], post_ids=(), viewpoints=(), natural_date="2026-07-23")
        self.assertEqual(text(control.sources["x-a"]), "2026-07-22T16:00:00Z")
        self.assertEqual(text(control.sources["x-b"]), "2026-07-23T00:00:00Z")
        with self.assertRaises(ValueError): control.complete(a[1]["id"], post_ids=(), viewpoints=(), natural_date="2026-07-23")
