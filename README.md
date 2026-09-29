# MT5-Copier

A lightweight, self-hosted trade signal bridge for MetaTrader 5. Connects any external signal source to MT5 and executes trades automatically — no cloud dependency, no subscription fees.

---

## How It Works

```
Signal Source (JSONL / PU Prime emulator bridge / Custom Feed)
        ↓
  Python Bridge (run_bridge.py)
        ↓
  File Queue (MQL5/Files/ea_queue/inbox/)
        ↓
  TradeExecutorEA.mq5 (polls queue every 1s)
        ↓
  MT5 Trade Execution
```

The Python bridge reads trade events from a feed, maps symbols, deduplicates events using SQLite, and writes atomic JSON command files into MT5's local file system. The MQL5 Expert Advisor polls the inbox folder on a timer and executes OPEN/CLOSE orders directly on your broker account.

---

## Features

- **Zero external API dependency** — runs entirely on your local machine or Windows VPS
- **SQLite-backed deduplication** — prevents duplicate orders from being placed
- **Atomic file writes** — commands are written to `.tmp` then renamed, preventing partial reads by the EA
- **Retry logic** — both the bridge dispatcher and the EA retry failed operations
- **Symbol mapping** — remap symbol names between your signal source and your broker
- **CSV trade mapping** — persists source_id → MT5 ticket mapping across EA restarts
- **Pluggable feed system** — swap in any signal source by implementing the `TradeFeed` interface
- **Built-in simulator** — emits executable commands; use a demo account
- **Structured logging** — separate logs for the bridge and the EA

---

## Requirements

- Python 3.8+
- MetaTrader 5 (Windows)
- `pyyaml` (`pip install pyyaml`)

---

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/Mikeyaruto/MT5-Copier.git
cd MT5-Copier
```

### 2. Install dependencies

```bash
pip install pyyaml
```

### 3. Install the Expert Advisor

1. Open MT5 → **File → Open Data Folder**
2. Copy `TradeExecutorEA.mq5` into `MQL5/Experts/`
3. Restart MT5 or refresh the Navigator panel
4. Drag **TradeExecutorEA** onto any chart
5. Enable **AutoTrading** (green play button on toolbar)

### 4. Create queue folders

Inside MT5's `MQL5/Files/` directory, create:

```
ea_queue/
  inbox/
  processed/
  failed/
```

### 5. Configure

Edit `config.yaml`:

```yaml
bridge:
  dispatcher:
    queue_base_path: "C:/Users/<YOU>/AppData/Roaming/MetaQuotes/Terminal/<HASH>/MQL5/Files/ea_queue"

trading:
  symbol_map:
    XAUUSD: XAUUSD
    EURUSD: EURUSD
```

### 6. Run the bridge

```bash
python run_bridge.py
```

### 7. Test with the simulator

```bash
python bridge/simulator.py
```

On a configured MT5 demo account, the simulator emits a trade open and close. It is not a dry run.

---

## Feed Format (JSONL)

The companion [PU Prime emulator reader](https://github.com/Mikeyaruto/MT5-Copier-bridge) produces `C:/bridge/events.jsonl`. Set the same `jsonl_path` in `config.yaml` and start both Python processes on the Windows VPS. The feed cursor is saved only after a command enters MT5's local queue. Configure the EA on a demo account and explicitly enable execution. See [setup.md](setup.md).

Each line in your feed file is a JSON event:

```json
{"event": "OPEN", "source": "my_signal", "source_trade_id": "trade_001", "symbol": "XAUUSD", "side": "BUY", "lots": 0.1, "sl": 1900.0, "tp": 1950.0, "timestamp": "2025-01-01T10:00:00Z"}
{"event": "CLOSE", "source": "my_signal", "source_trade_id": "trade_001", "timestamp": "2025-01-01T10:30:00Z"}
```

---

## Custom Feed Integration

Implement the `TradeFeed` abstract class to plug in any signal source:

```python
from bridge.trade_feed import TradeFeed

class MyCustomFeed(TradeFeed):
    def poll(self) -> list:
        # Fetch events from Telegram, webhook, web platform, etc.
        return [...]
```

Then register it in `run_bridge.py` under `build_feed()`.

---

## Running on a VPS (Recommended)

Use Windows Task Scheduler to auto-start the bridge on boot:

1. Open **Task Scheduler** → **Create Task**
2. Trigger: **At startup**
3. Action: `python run_bridge.py` from the repo folder
4. Enable **Restart if task fails**

See [setup.md](setup.md) for the full VPS setup walkthrough.

---

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common MT5 error codes and fixes.

**Log locations:**
- Bridge: `bridge/logs/bridge.log`
- EA: `MQL5/Files/logs/TradeExecutorEA.log`

---

## Project Structure

```
MT5-Copier/
├── bridge/
│   ├── dispatcher.py          # Writes atomic JSON commands to MT5 queue
│   ├── jsonl_file_feed.py     # JSONL file feed with offset tracking
│   ├── trade_feed.py          # Abstract base class for feed plugins
│   ├── simulator.py           # Local test simulator
│   └── web_platform_feed_stub.py  # Stub for web platform integration
├── TradeExecutorEA.mq5        # MQL5 Expert Advisor
├── run_bridge.py              # Bridge entry point
├── config.yaml                # Configuration
├── setup.md                   # VPS setup guide
└── TROUBLESHOOTING.md         # Common errors and fixes
```

---

## Roadmap

- [ ] Telegram feed integration
- [ ] Webhook/HTTP feed support
- [ ] Web dashboard for monitoring trade status
- [ ] Multi-account support (fan-out to multiple MT5 terminals)
- [ ] Lot sizing modes (fixed, percentage risk, balance-proportional)

---

## License

MIT

---

## Contributing

PRs welcome. Open an issue first to discuss major changes.
