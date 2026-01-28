# Windows VPS Setup Guide (MT5 + Bridge)

## 1) Install Python 3
1. Download Python 3 from https://www.python.org/downloads/windows/
2. During installation, check **"Add Python to PATH"**.
3. Verify in PowerShell:
   ```
   python --version
   ```

## 2) Install bridge dependencies
From the repo root:
```
python -m pip install --upgrade pip
python -m pip install pyyaml
```

## 3) Install the Expert Advisor
1. Open MT5.
2. Go to **File → Open Data Folder**.
3. Copy `TradeExecutorEA.mq5` into `MQL5/Experts/`.
4. Restart MT5 or refresh the Navigator.

## 4) Enable Algo Trading and file access
1. In MT5, click **Tools → Options → Expert Advisors**.
2. Enable **Allow Algo Trading**.
3. (Optional) Enable **Allow DLL imports** only if your environment requires it (not used by this EA).

## 5) Configure the queue folder
The EA reads from `MQL5/Files/ea_queue/inbox` by default.

1. In MT5, open **File → Open Data Folder**.
2. Navigate to `MQL5/Files/` and create:
   - `ea_queue/inbox/`
   - `ea_queue/processed/`
   - `ea_queue/failed/`
3. Update `config.yaml` to point `queue_base_path` to the same `MQL5/Files/ea_queue` folder.
   Example:
   ```yaml
   dispatcher:
     queue_base_path: "C:/Users/<YOU>/AppData/Roaming/MetaQuotes/Terminal/<HASH>/MQL5/Files/ea_queue"
   ```

## 6) Attach EA to a chart
1. In MT5 Navigator, drag **TradeExecutorEA** onto any chart.
2. Ensure AutoTrading is enabled (green play button on the toolbar).

## 7) Run the bridge as a background task
### Option A: Manual start
```
python run_bridge.py
```

### Option B: Task Scheduler (recommended)
1. Open **Task Scheduler** → **Create Task**.
2. Trigger: **At startup**.
3. Action: **Start a program**.
   - Program: `python`
   - Arguments: `run_bridge.py`
   - Start in: the repo folder (e.g. `C:\MT5-Copier`)
4. Enable **Restart the task if it fails** in Settings.

## 8) Test with the simulator
```
python bridge/simulator.py
```
You should see:
- A trade open in MT5
- A trade close a few seconds later

Logs:
- Bridge: `bridge/logs/bridge.log`
- EA: `MQL5/Files/logs/TradeExecutorEA.log`
