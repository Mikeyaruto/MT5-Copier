from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Dict, List

from bridge.trade_feed import TradeFeed


class JsonlFileFeed(TradeFeed):
    def __init__(self, path: Path) -> None:
        self.path = path
        self.offset_path = path.with_suffix(".offset")
        self.offset = self._load_offset()

    def _load_offset(self) -> int:
        if not self.offset_path.exists():
            return 0
        try:
            return int(self.offset_path.read_text(encoding="utf-8").strip())
        except ValueError:
            logging.warning("Invalid offset file. Resetting to 0.")
            return 0

    def _save_offset(self, offset: int) -> None:
        self.offset_path.write_text(str(offset), encoding="utf-8")

    def poll(self) -> List[Dict]:
        if not self.path.exists():
            return []

        events: List[Dict] = []
        with self.path.open("r", encoding="utf-8") as handle:
            handle.seek(self.offset)
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    logging.warning("Invalid JSONL line: %s", line)
            self.offset = handle.tell()

        self._save_offset(self.offset)
        return events
