#!/usr/bin/env python3
import logging
import signal
import sys
import time
from pathlib import Path

import yaml

from bridge.dispatcher import Dispatcher
from bridge.jsonl_file_feed import JsonlFileFeed
from bridge.trade_feed import TradeFeed


def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as file:
        return yaml.safe_load(file)


def build_feed(config: dict) -> TradeFeed:
    feed_config = config["bridge"]["feed"]
    feed_type = feed_config["type"]
    if feed_type == "jsonl_file_feed":
        return JsonlFileFeed(Path(feed_config["jsonl_path"]))
    raise ValueError(f"Unsupported feed type: {feed_type}")


def setup_logging(log_path: Path) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[logging.FileHandler(log_path, encoding="utf-8"), logging.StreamHandler(sys.stdout)],
    )


def main() -> int:
    config = load_config("config.yaml")
    log_path = Path(config["bridge"]["log_path"])
    setup_logging(log_path)

    dispatcher = Dispatcher(config)
    feed = build_feed(config)

    running = True

    def handle_signal(signum, frame):  # noqa: ARG001
        nonlocal running
        logging.info("Received signal %s. Shutting down.", signum)
        running = False

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    poll_interval = float(config["bridge"]["poll_interval_seconds"])
    logging.info("Bridge started. Poll interval: %s seconds", poll_interval)

    while running:
        events = feed.poll()
        for event in events:
            dispatcher.dispatch(event)
        time.sleep(poll_interval)

    logging.info("Bridge stopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
