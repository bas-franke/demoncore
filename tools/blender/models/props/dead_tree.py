"""Dead, twisted trees (3 variants)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"

def build():
    vs = sb.variants("dt", 3, 8.0)
    specs = [(5.2, 0.3, 3, "Prop_Bark", 0.1), (4.2, 0.26, 3, "Prop_BarkPale", 0.25), (6.0, 0.36, 3, "Prop_Bark", 0.06)]
    for i, v in enumerate(vs):
        rng = K.rng_for(1100 + i)
        h, r, depth, mat, lean = specs[i]
        K.tree(v, rng, h, r, depth, mat, "t", lean)
        if i == 1:
            # a snapped limb lying at the foot
            bm = sb.bm_limb([(0.8, 0.3, 0.1), (1.6, 0.5, 0.12), (2.3, 0.4, 0.08)], [0.1, 0.07, 0.04], 6, 2, rng, 0.1)
            sb.bm_obj("fallen", v, bm, K.M(mat), sharp=60)
    sb.tri_report("dead_tree")
    return vs[0]
