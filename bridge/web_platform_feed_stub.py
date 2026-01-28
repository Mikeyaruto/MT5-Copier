"""
Stub module for integrating a legitimate Vantage or PU Prime copy-trading feed.

IMPORTANT:
- Only use official or user-authorized data sources.
- Do not attempt to bypass authentication, 2FA, or platform security.
- Acceptable integrations include:
  - Official APIs or exports provided by the platform.
  - Email alerts (if the user explicitly enables trade notification emails).
  - Browser automation using the user's own credentials, if allowed by the platform TOS.

Replace this stub with a real TradeFeed implementation once you have a legitimate
and compliant source of trade events.
"""
from __future__ import annotations

from typing import Dict, List

from bridge.trade_feed import TradeFeed


class WebPlatformFeedStub(TradeFeed):
    def poll(self) -> List[Dict]:
        """Return an empty list until a real feed is implemented."""
        return []
