from __future__ import annotations

import json
import logging
import sqlite3
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Optional


@dataclass
class QueuePaths:
    base_path: Path
    inbox: Path
    processed: Path
    failed: Path


class Dispatcher:
    def __init__(self, config: Dict) -> None:
        dispatcher_config = config["bridge"]["dispatcher"]
        base_path = Path(dispatcher_config["queue_base_path"])
        self.queue_paths = QueuePaths(
            base_path=base_path,
            inbox=base_path / dispatcher_config["inbox_subdir"],
            processed=base_path / dispatcher_config["processed_subdir"],
            failed=base_path / dispatcher_config["failed_subdir"],
        )
        self.queue_paths.inbox.mkdir(parents=True, exist_ok=True)
        self.queue_paths.processed.mkdir(parents=True, exist_ok=True)
        self.queue_paths.failed.mkdir(parents=True, exist_ok=True)

        self.max_write_retries = int(dispatcher_config["max_write_retries"])
        self.retry_backoff_seconds = float(dispatcher_config["retry_backoff_seconds"])

        trading_config = config["trading"]
        self.symbol_map = trading_config.get("symbol_map", {})

        state_db_path = Path(config["bridge"]["state_db_path"])
        state_db_path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(state_db_path)
        self._init_db()

    def _init_db(self) -> None:
        with self.db:
            self.db.execute(
                """
                CREATE TABLE IF NOT EXISTS processed_events (
                    event_id TEXT PRIMARY KEY,
                    processed_at TEXT
                )
                """
            )

    def _event_id(self, event: Dict) -> str:
        return f"{event.get('source')}:{event.get('source_trade_id')}:{event.get('event')}"

    def _is_processed(self, event_id: str) -> bool:
        cursor = self.db.execute(
            "SELECT 1 FROM processed_events WHERE event_id = ?", (event_id,)
        )
        return cursor.fetchone() is not None

    def _mark_processed(self, event_id: str) -> None:
        with self.db:
            self.db.execute(
                "INSERT OR IGNORE INTO processed_events (event_id, processed_at) VALUES (?, datetime('now'))",
                (event_id,),
            )

    def _map_symbol(self, symbol: Optional[str]) -> Optional[str]:
        if symbol is None:
            return None
        return self.symbol_map.get(symbol, symbol)

    def dispatch(self, event: Dict) -> None:
        event_id = self._event_id(event)
        if self._is_processed(event_id):
            logging.info("Duplicate event ignored: %s", event_id)
            return

        command = {
            "command_id": str(uuid.uuid4()),
            "event": event.get("event"),
            "source": event.get("source"),
            "source_trade_id": event.get("source_trade_id"),
            "symbol": self._map_symbol(event.get("symbol")),
            "side": event.get("side"),
            "lots": event.get("lots"),
            "sl": event.get("sl"),
            "tp": event.get("tp"),
            "timestamp": event.get("timestamp"),
        }

        payload = json.dumps(command, ensure_ascii=False)
        for attempt in range(1, self.max_write_retries + 1):
            try:
                filename = f"{int(time.time() * 1000)}_{uuid.uuid4().hex}.json"
                tmp_path = self.queue_paths.inbox / f"{filename}.tmp"
                final_path = self.queue_paths.inbox / filename
                tmp_path.write_text(payload, encoding="utf-8")
                tmp_path.replace(final_path)
                self._mark_processed(event_id)
                logging.info("Dispatched command %s to %s", command["command_id"], final_path)
                return
            except OSError as exc:
                logging.warning("Failed to write command (attempt %s/%s): %s", attempt, self.max_write_retries, exc)
                time.sleep(self.retry_backoff_seconds)

        logging.error("Failed to dispatch event after retries: %s", event_id)
