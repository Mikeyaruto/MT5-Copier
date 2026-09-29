import json
import tempfile
import unittest
from pathlib import Path

from bridge.dispatcher import Dispatcher
from bridge.jsonl_file_feed import JsonlFileFeed


class QueueTests(unittest.TestCase):
    def test_dispatch_ack_and_crash_replay(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = root / "events.jsonl"
            event = {"event_id": "puprime:1:0", "event": "OPEN", "source": "puprime",
                     "source_trade_id": "uuid-1", "symbol": "XAUUSD", "side": "BUY", "lots": 0.1}
            path.write_text(json.dumps(event) + "\n" + json.dumps(event) + "\n")
            feed = JsonlFileFeed(path)
            config = {"bridge": {"dispatcher": {"queue_base_path": str(root / "queue"),
                       "inbox_subdir": "inbox", "processed_subdir": "processed",
                       "failed_subdir": "failed", "max_write_retries": 1,
                       "retry_backoff_seconds": 0}, "state_db_path": str(root / "state.db")},
                      "trading": {"symbol_map": {"XAUUSD": "XAUUSD.demo"}}}
            dispatcher = Dispatcher(config)
            self.assertEqual(feed.poll(), [event])
            self.assertFalse(path.with_suffix(".offset").exists())
            self.assertTrue(dispatcher.dispatch(event))
            # Re-reading before ack models a crash after a successful queue write.
            replay = JsonlFileFeed(path)
            self.assertEqual(replay.poll(), [event])
            self.assertTrue(dispatcher.dispatch(event))
            replay.ack()
            self.assertEqual(replay.poll(), [event])
            self.assertTrue(dispatcher.dispatch(event))
            replay.ack()
            self.assertEqual(replay.poll(), [])
            queued = list((root / "queue" / "inbox").glob("*.json"))
            self.assertEqual(len(queued), 1)
            self.assertEqual(json.loads(queued[0].read_text())["symbol"], "XAUUSD.demo")

    def test_incomplete_line_does_not_advance_cursor(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "events.jsonl"
            path.write_text('{"event":"OPEN"')
            feed = JsonlFileFeed(path)
            self.assertEqual(feed.poll(), [])
            self.assertFalse(path.with_suffix(".offset").exists())


if __name__ == "__main__":
    unittest.main()
