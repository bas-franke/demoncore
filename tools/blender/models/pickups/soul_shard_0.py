"""Soul shard, tier 0 (see _shard.py)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _shard  # noqa: E402

CATEGORY = "pickups"


def build():
    return _shard.build_tier(0)
