#!/usr/bin/env python3
import json
import time
from datetime import datetime, timezone
from pathlib import Path
import uuid

EVENTS_PATH = Path("bridge/events.jsonl")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def emit(event: dict) -> None:
    EVENTS_PATH.parent.mkdir(parents=True, exist_ok=True)
    with EVENTS_PATH.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event) + "\n")


def run() -> None:
    source_trade_id = str(uuid.uuid4())
    open_event = {
        "event": "OPEN",
        "source": "vantage",
        "source_trade_id": source_trade_id,
        "symbol": "XAUUSD",
        "side": "BUY",
        "lots": 0.10,
        "sl": None,
        "tp": None,
        "timestamp": now_iso(),
    }
    emit(open_event)
    time.sleep(2)
    close_event = {
        "event": "CLOSE",
        "source": "vantage",
        "source_trade_id": source_trade_id,
        "symbol": "XAUUSD",
        "side": "BUY",
        "lots": 0.10,
        "sl": None,
        "tp": None,
        "timestamp": now_iso(),
    }
    emit(close_event)


if __name__ == "__main__":
    run()
