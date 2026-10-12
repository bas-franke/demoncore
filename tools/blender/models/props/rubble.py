"""Rubble heaps: broken stones and masonry fragments (4 variants)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402

CATEGORY = "props"

def build():
    vs = sb.variants("rb", 4, 3.0)
    for i, v in enumerate(vs):
        rng = K.rng_for(500 + i)
        if i == 0:
            K.rubble(v, rng, (0, 0, 0), 0.9, 6, 0.15, 0.5, blocks=0.4)
        elif i == 1:
            sb.stone_block("block", v, (0.75, 0.45, 0.4), K.M("Prop_Stone"), rng, loc=(0.1, 0, 0.18),
                           rot=(4, -6, 25), chips=3, step=0.25)
            K.rubble(v, rng, (0, 0, 0), 0.9, 5, 0.12, 0.35, blocks=0.2)
        elif i == 2:
            K.rubble(v, rng, (0, 0, 0), 0.6, 4, 0.25, 0.55, blocks=0.0)
            K.rubble(v, rng, (0, 0, 0), 1.0, 4, 0.08, 0.18, blocks=0.0, tag="s")
        else:
            K.drum("drum", v, rng, 0.36, 0.5, (0, 0, 0.34), (90, 0, 30), broken_top=0.3, broken_bottom=0.2)
            K.rubble(v, rng, (0.3, 0.3, 0), 0.8, 4, 0.1, 0.3)
    sb.tri_report("rubble")
    return vs[0]
