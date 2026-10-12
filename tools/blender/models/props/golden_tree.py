"""Erdtree-gold leafed trees with fallen leaves (2 variants)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"

def build():
    vs = sb.variants("gt", 2, 9.0)
    for i, v in enumerate(vs):
        rng = K.rng_for(1200 + i)
        ends = K.tree(v, rng, 6.2 + i * 0.6, 0.36, 3, "Prop_BarkPale" if i else "Prop_Bark", "t", 0.08, kids=(2, 3))
        rng.shuffle(ends)
        picked = []
        for e in sorted(ends, key=lambda p: -p.z):
            if all((e - p).length > 1.1 for p in picked):
                picked.append(e)
        for k, e in enumerate(picked[:11]):
            s = rng.uniform(1.2, 1.7)
            bm = sb.bm_rock(rng, (s * 1.15, s * 1.05, s * 0.7), cuts=0, subdiv=2, noise=0.22, flat_bottom=False)
            sb.bm_xform(bm, loc=(e.x, e.y, e.z - s * 0.45), rot=(0, 0, rng.uniform(0, 360)))
            sb.bm_obj(f"leaf{k}", v, bm, K.M("Prop_Leaf" if rng.random() < 0.6 else "Prop_LeafDark"), sharp=0)
        import bmesh
        bm = bmesh.new()
        for k in range(46):
            a = rng.uniform(0, math.tau)
            d = math.sqrt(rng.random()) * 3.2
            cx, cy = math.cos(a) * d, math.sin(a) * d
            yaw = rng.uniform(0, math.tau)
            ca, sa = math.cos(yaw), math.sin(yaw)
            q = []
            for lx, ly in ((-0.09, -0.05), (0.09, -0.05), (0.09, 0.05), (-0.09, 0.05)):
                q.append(bm.verts.new((cx + lx * ca - ly * sa, cy + lx * sa + ly * ca, 0.012 + k * 0.0002)))
            bm.faces.new(q)
        sb.bm_obj("fallen_leaves_ns", v, bm, K.M("Prop_LeafFallen"), sharp=None)
    sb.tri_report("golden_tree")
    return vs[0]
