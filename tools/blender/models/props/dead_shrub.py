"""Dry thorny shrubs (3 variants)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"

def build():
    vs = sb.variants("ds", 3, 2.0)
    for i, v in enumerate(vs):
        rng = K.rng_for(1300 + i)
        ends = []
        for k in range(5 + i):
            d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(1.0, 2.2))).normalized()
            K.branch(v, rng, (0, 0, -0.02), d, rng.uniform(0.45, 0.85), 0.03, 1, ends, f"b{k}",
                     "Prop_BarkPale" if i == 1 else "Prop_Bark", 3, 0.0, (1, 2), (25, 45))
    sb.tri_report("dead_shrub")
    return vs[0]
