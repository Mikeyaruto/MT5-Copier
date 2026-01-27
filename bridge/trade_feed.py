from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Dict, List


class TradeFeed(ABC):
    @abstractmethod
    def poll(self) -> List[Dict]:
        """Return a list of trade events since the last poll."""
        raise NotImplementedError
