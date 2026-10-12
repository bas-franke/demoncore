"""A lone skull with a bone or two (3 variants)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402

CATEGORY = "props"

def build():
    vs = sb.variants("sk", 3, 1.5)
    for i, v in enumerate(vs):
        rng = K.rng_for(800 + i)
        K.skull("skull_ns", v, rng, (0, 0, 0), (rng.uniform(-15, 15), rng.uniform(-30, 30), rng.uniform(0, 360)),
                1.0 + 0.1 * i)
        K.bone_scatter(v, rng, (0.15, 0.1), 0.35, i + 1)
    sb.tri_report("skull")
    return vs[0]
