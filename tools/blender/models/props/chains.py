"""Heavy chains slung between two stone posts (2 variants)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import bmesh  # noqa: E402
import _props_kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"
IRON = "Prop_Iron"


def chain(parent, name, a, b, sag, n, link_r=0.06, wire=0.014):
    """Catenary-ish chain of interlocking oval links from a to b (merged into one mesh)."""
    a, b = Vector(a), Vector(b)
    bm = bmesh.new()
    pts = []
    for i in range(n + 1):
        t = i / n
        p = a.lerp(b, t)
        p.z -= sag * 4 * t * (1 - t)
        pts.append(p)
    for i in range(n):
        p, q = pts[i], pts[i + 1]
        c = (p + q) * 0.5
        d = (q - p).normalized()
        ring = []
        for k in range(9):
            ang = k / 8 * math.tau
            ring.append((math.cos(ang) * link_r * 1.5, math.sin(ang) * link_r * 0.8))
        side = d.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        side.normalize()
        if i % 2:
            side = d.cross(side).normalized()
        lp = [c + d * x + side * y for x, y in ring]
        lk = sb.bm_limb(lp, [wire] * len(lp), 4, 1, cap_end=False)
        sb.bm_merge(bm, lk)
    sb.bm_obj(name, parent, bm, K.M(IRON), sharp=50)

def build():
    vs = sb.variants("ch", 2, 5.0)
    for i, v in enumerate(vs):
        rng = K.rng_for(1800 + i)
        span = (2.6, 2.2)[i]
        ph = (1.25, 1.05)[i]
        for sx in (-1, 1):
            h = ph if not (i == 1 and sx > 0) else 0.7
            sb.stone_block(f"post{sx}", v, (0.34, 0.34, h), K.M("Prop_Stone"), rng, loc=(sx * span * 0.5, 0, h * 0.5),
                           chips=2, step=0.3)
            sb.stone_block(f"cap{sx}", v, (0.44, 0.44, 0.12), K.M("Prop_Stone"), rng,
                           loc=(sx * span * 0.5, 0, h + 0.06), chips=1, step=0.4)
            K.lathe_obj(f"ring{sx}_ns", v, rng, [(0.0, 0.0), (0.05, 0.02), (0.05, 0.06), (0.0, 0.08)], 6,
                        (sx * (span * 0.5 - 0.17), 0, h - 0.12), (0, 90, 0), mat=IRON, chips=0, noise=0.0)
        if i == 0:
            chain(v, "chain_ns", (-span * 0.5 + 0.2, 0, ph - 0.12), (span * 0.5 - 0.2, 0, ph - 0.12), 0.5, 16)
        else:
            chain(v, "chain_ns", (-span * 0.5 + 0.2, 0, ph - 0.12), (0.4, -0.3, 0.05), 0.25, 12)
            chain(v, "chain2_ns", (0.4, -0.3, 0.05), (1.1, 0.5, 0.05), 0.0, 6)
            K.rubble(v, rng, (span * 0.5, 0.4, 0), 0.6, 4, 0.1, 0.3)
    sb.tri_report("chains")
    return vs[0]
