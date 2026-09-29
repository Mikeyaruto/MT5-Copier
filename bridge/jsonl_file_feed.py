from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Dict, List

from bridge.trade_feed import TradeFeed


class JsonlFileFeed(TradeFeed):
    def __init__(self, path: Path) -> None:
        self.path = path
        self.offset_path = path.with_suffix(".offset")
        self.offset = self._load_offset()
        self.pending_offset = None

    def _load_offset(self) -> int:
        if not self.offset_path.exists():
            return 0
        try:
            return int(self.offset_path.read_text(encoding="utf-8").strip())
        except ValueError as exc:
            raise ValueError("Invalid offset file; refusing to replay trades") from exc

    def _save_offset(self, offset: int) -> None:
        temp = self.offset_path.with_suffix(".offset.tmp")
        with temp.open("w", encoding="utf-8") as handle:
            handle.write(str(offset))
            handle.flush()
            os.fsync(handle.fileno())
        temp.replace(self.offset_path)

    def poll(self) -> List[Dict]:
        if not self.path.exists():
            return []
        if self.pending_offset is not None:
            raise RuntimeError("Previous event must be acknowledged first")
        with self.path.open("r", encoding="utf-8") as handle:
            if self.path.stat().st_size < self.offset:
                raise RuntimeError("Event file was truncated; refusing to reset offset")
            handle.seek(self.offset)
            line = handle.readline()
            if not line or not line.endswith("\n"):
                return []
            end = handle.tell()
        try:
            event = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"Invalid event at offset {self.offset}") from exc
        if not isinstance(event, dict):
            raise ValueError(f"Event at offset {self.offset} is not an object")
        self.pending_offset = end
        return [event]

    def ack(self) -> None:
        if self.pending_offset is None:
            raise RuntimeError("Nothing to acknowledge")
        self._save_offset(self.pending_offset)
        self.offset = self.pending_offset
        self.pending_offset = None

    def nack(self) -> None:
        """Retry the current event after a temporary queue write failure."""
        self.pending_offset = None
