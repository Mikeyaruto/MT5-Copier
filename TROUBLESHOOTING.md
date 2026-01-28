# Troubleshooting MT5 Trade Execution

## Common MT5 Errors

### 1) TRADE_RETCODE_REJECT / Invalid volume
- **Cause:** Broker's minimum or step size not met.
- **Fix:** Adjust `lots` or update `symbol_map` and lot sizing on the bridge side.

### 2) TRADE_RETCODE_INVALID_PRICE
- **Cause:** Price moved beyond allowed deviation or symbol not available.
- **Fix:** Increase `MaxSlippage` or ensure the symbol is visible in Market Watch.

### 3) TRADE_RETCODE_MARKET_CLOSED
- **Cause:** Market is closed or the symbol is in a trading break.
- **Fix:** Wait for the market to reopen or choose a symbol with active trading.

### 4) No trades placed (EA logs show invalid fields)
- **Cause:** Missing `symbol`, `side`, or `lots` in the incoming command.
- **Fix:** Check the JSONL feed or bridge logs for malformed events.

### 5) CLOSE ignored (no mapping)
- **Cause:** The mapping file does not include the source trade ID (EA restarted or trade never opened).
- **Fix:** Ensure OPEN events are received before CLOSE, and check `TradeExecutorEA/mapping.csv` in `MQL5/Files/`.

### 6) Queue files stuck in inbox
- **Cause:** EA not attached to a chart or AutoTrading disabled.
- **Fix:** Attach EA to a chart and enable AutoTrading.

## Log Locations
- **EA Log:** `MQL5/Files/logs/TradeExecutorEA.log`
- **Bridge Log:** `bridge/logs/bridge.log`
