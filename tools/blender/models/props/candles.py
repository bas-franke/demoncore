"""Clusters of melted votive candles with glowing flames (3 variants)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402

CATEGORY = "props"

def build():
    vs = sb.variants("cd", 3, 1.5)
    for i, v in enumerate(vs):
        rng = K.rng_for(900 + i)
        K.candles(v, rng, (4, 7, 10)[i], (0, 0, 0), (0.22, 0.3, 0.38)[i])
    sb.tri_report("candles")
    return vs[0]
