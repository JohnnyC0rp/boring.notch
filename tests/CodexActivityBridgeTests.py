# SPDX-License-Identifier: GPL-3.0-only

import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location("activity_bridge", Path(__file__).resolve().parents[1] / "script/codex_activity_bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


def snapshot(status="active", flags=None, thread="one", owner="desktop", revision=1):
    runtime = {"type": status, "activeFlags": flags or []}
    return {"type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
            "sourceClientId": owner, "params": {"hostId": "local", "conversationId": thread,
            "change": {"type": "snapshot", "revision": revision,
            "conversationState": {"threadRuntimeStatus": runtime, "title": "must not survive",
                                  "turns": [{"text": "never retained"}]}}}}


def patch(value, base=1, revision=2, path=None, thread="one"):
    return {"type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
            "sourceClientId": "desktop", "params": {"hostId": "local", "conversationId": thread,
            "change": {"type": "patches", "baseRevision": base, "revision": revision,
            "patches": [{"op": "replace", "path": path or ["threadRuntimeStatus"], "value": value}]}}}


class ProjectionTests(unittest.TestCase):
    def setUp(self):
        self.state = bridge.ActivityProjection()
        self.state.connected = True

    def test_initial_state_is_unknown_until_snapshot(self):
        self.assertEqual(self.state.summary(100)["phase"], "offline")

    def test_authoritative_active_to_idle(self):
        self.state.consume(snapshot(), 100)
        self.assertEqual(self.state.summary(101)["phase"], "active")
        self.state.consume(patch({"type": "idle"}), 102)
        self.assertEqual(self.state.summary(102)["phase"], "idle")

    def test_waiting_tasks_remain_in_active_count(self):
        self.state.consume(snapshot(flags=["waitingOnApproval"]), 100)
        self.assertEqual(self.state.summary(100)["phase"], "waiting")
        self.assertEqual(self.state.summary(100)["activeCount"], 1)
        self.state.consume(snapshot(flags=["waitingOnUserInput"]), 101)
        self.assertEqual(self.state.summary(101)["phase"], "waiting")
        self.assertEqual(self.state.summary(101)["activeCount"], 1)

    def test_working_task_takes_precedence_over_waiting_task(self):
        self.state.consume(snapshot(flags=["waitingOnApproval"]), 100)
        self.state.consume(snapshot(thread="two"), 100)
        self.assertEqual(self.state.summary(100)["phase"], "active")
        self.assertEqual(self.state.summary(100)["activeCount"], 2)

    def test_error_and_not_loaded_are_static(self):
        self.state.consume(snapshot("systemError"), 100)
        self.assertEqual(self.state.summary(100)["phase"], "error")
        self.state.consume(snapshot("notLoaded"), 101)
        self.assertEqual(self.state.summary(101)["phase"], "idle")

    def test_gap_clears_activity_and_requests_snapshot(self):
        self.state.consume(snapshot(), 100)
        self.assertEqual(self.state.consume(patch({"type": "active"}, base=12), 101), "one")
        self.assertEqual(self.state.summary(101)["phase"], "offline")

    def test_owner_switch_requires_fresh_snapshot(self):
        self.state.consume(snapshot(owner="old"), 100)
        self.assertEqual(self.state.consume(patch({"type": "idle"}), 101), "one")
        self.assertEqual(self.state.summary(101)["phase"], "offline")

    def test_owner_disconnect_clears_activity(self):
        self.state.consume(snapshot(), 100)
        self.state.consume({"type": "broadcast", "method": "client-status-changed",
                            "params": {"clientId": "desktop", "status": "disconnected"}}, 101)
        self.assertEqual(self.state.summary(101)["phase"], "offline")

    def test_ipc_disconnect_and_stale_snapshot_clear_activity(self):
        self.state.consume(snapshot(), 100)
        self.assertEqual(self.state.summary(146)["phase"], "offline")
        self.state.disconnect()
        self.assertFalse(self.state.threads)
        self.assertEqual(self.state.summary(100)["phase"], "offline")

    def test_unknown_protocol_is_not_animated(self):
        value = snapshot()
        value["version"] = 12
        self.state.consume(value, 100)
        self.assertEqual(self.state.summary(100)["phase"], "offline")

    def test_remote_host_is_ignored(self):
        value = snapshot()
        value["params"]["hostId"] = "remote"
        self.state.consume(value, 100)
        self.assertFalse(self.state.threads)

    def test_projection_retains_no_content(self):
        self.state.consume(snapshot(), 100)
        self.assertNotIn("must not survive", repr(self.state.threads))
        self.assertNotIn("never retained", repr(self.state.threads))
        self.assertEqual(set(self.state.summary(100)), {"service", "version", "phase", "updatedAt", "activeCount"})

    def test_content_patches_are_discarded(self):
        self.state.consume(snapshot(), 100)
        self.state.consume(patch("secret message", path=["turnHistory", "items", 1]), 101)
        self.assertNotIn("secret", repr(self.state.threads))
        self.assertEqual(self.state.summary(101)["phase"], "active")

    def test_partial_status_fields_apply(self):
        self.state.consume(snapshot(), 100)
        self.state.consume(patch(["waitingOnUserInput"], path=["threadRuntimeStatus", "activeFlags"]), 101)
        self.assertEqual(self.state.summary(101)["phase"], "waiting")

    def test_unknown_nested_status_patch_refreshes(self):
        self.state.consume(snapshot(), 100)
        self.assertEqual(self.state.consume(patch("waitingOnApproval", path=["threadRuntimeStatus", "activeFlags", 0]), 101), "one")
        self.assertEqual(self.state.summary(101)["phase"], "offline")

    def test_unexpected_status_is_not_active(self):
        self.state.consume(snapshot("futureStatus"), 100)
        self.assertEqual(self.state.summary(100)["phase"], "offline")
        self.assertIsNone(bridge.clean_status({"type": "active", "activeFlags": [{}]}))

    def test_thread_id_discovery_uses_filename_only(self):
        self.assertIsNotNone(bridge.THREAD_ID.search("rollout-2026-09-07T17-00-00-00000000-0000-4000-8000-000000000001.jsonl"))
        self.assertIsNone(bridge.THREAD_ID.search("auth.json"))


if __name__ == "__main__":
    unittest.main()
