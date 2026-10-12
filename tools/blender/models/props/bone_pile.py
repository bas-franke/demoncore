"""Heaps of bones with skulls (3 variants)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402

CATEGORY = "props"

def ribcage(v, rng, loc, yaw):
    c = sb.empty("ribs", v, loc=loc, rot=(0, 0, yaw))
    K.bone("spine_ns", c, rng, (0, -0.3, 0.05), (0, 0.3, 0.07), 0.025)
    for i in range(5):
        y = -0.2 + i * 0.1
        for sx in (-1, 1):
            pts = [(0, y, 0.07), (sx * 0.12, y - 0.02, 0.16), (sx * 0.2, y - 0.05, 0.08), (sx * 0.17, y - 0.07, 0.0)]
            bm = sb.bm_limb(pts, [0.012, 0.012, 0.011, 0.008], 4, 2)
            sb.bm_obj(f"rib{i}{sx}_ns", c, bm, K.M("Prop_Bone"), sharp=70)


def build():
    vs = sb.variants("bp", 3, 3.0)
    for i, v in enumerate(vs):
        rng = K.rng_for(700 + i)
        K.bone_scatter(v, rng, (0, 0), 0.7, 6 + i * 2)
        for k in range(1 + i):
            a = rng.uniform(0, math.tau)
            d = rng.uniform(0.1, 0.5)
            K.skull(f"skull{k}_ns", v, rng, (math.cos(a) * d, math.sin(a) * d, 0.0),
                    (rng.uniform(-20, 20), rng.uniform(-25, 25), rng.uniform(0, 360)))
        if i != 1:
            ribcage(v, rng, (0.35, -0.2, 0), rng.uniform(0, 360))
    sb.tri_report("bone_pile")
    return vs[0]
