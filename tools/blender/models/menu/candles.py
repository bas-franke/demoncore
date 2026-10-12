"""Candle cluster: seven pillar candles of different heights standing in a pool of old wax,
~0.8 m across. Flames are emissive meshes (bloom). Origin = floor centre."""
import math
import os
import random
import sys
sys.path.insert(0, os.path.dirname(__file__))
import sb  # noqa: E402
import _kit as kit  # noqa: E402

CATEGORY = "menu"


def build():
    m = kit.mats()
    root = sb.root("CandleCluster")
    rnd = random.Random(12)
    sb.lathe("pool", root, [(0.0, 0.0), (0.42, 0.0), (0.38, 0.012), (0.2, 0.02), (0.0, 0.022)], segments=14,
             material=m["wax"], jitter=0.12, seed=3)
    spots = [(0, 0, 0.45, 0.065), (0.2, 0.08, 0.3, 0.055), (-0.17, 0.12, 0.36, 0.06), (-0.12, -0.18, 0.22, 0.05),
             (0.16, -0.16, 0.16, 0.045), (0.3, -0.02, 0.12, 0.04), (-0.3, -0.04, 0.26, 0.045)]
    for k, (x, y, h, r) in enumerate(spots):
        kit.candle(f"c{k}", root, m, loc=(x, y, 0.01), h=h * rnd.uniform(0.9, 1.1), r=r, seed=k + 3,
                   lit=(k != 5))
    sb.join_meshes(root, "candles")
    sb.tri_count(root)
    return root
