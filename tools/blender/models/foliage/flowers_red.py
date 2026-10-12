"""Blood-red lilies: spider-lily-like umbels of recurved narrow petals and long stamens on bare stems."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _foliage as F  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = F.CATEGORY


def lily(g, rng, m_stem, m_petal, m_stamen, base, h):
    a = rng.uniform(0, math.tau)
    d = Vector((math.cos(a), math.sin(a), 0.0))
    top = base + d * h * rng.uniform(0.05, 0.15) + Vector((0, 0, h))
    pts = [base.lerp(top, t / 3) for t in range(4)]
    sd = Vector((-d.y, d.x, 0))
    g.ribbon(m_stem, pts, [0.006, 0.005, 0.0045, 0.004], [sd] * 4)
    n_fl = rng.randint(3, 5)  # florets in an umbel, each a whorl of recurved petals
    for f in range(n_fl):
        fa = f / n_fl * math.tau + rng.uniform(-0.3, 0.3)
        fd = Vector((math.cos(fa), math.sin(fa), 0.45)).normalized()
        c = top + fd * 0.025
        side = Vector((-fd.y, fd.x, 0)).normalized()
        upv = fd.cross(side).normalized()
        for k in range(5):
            ang = k / 5 * math.tau
            out = (side * math.cos(ang) + upv * math.sin(ang)) * 0.8 + fd * 0.6
            out.normalize()
            p1 = c + out * 0.04
            p2 = c + out * 0.068 - fd * 0.02 + Vector((0, 0, -0.012))  # recurved tip
            s2 = out.cross(fd).normalized()
            g.ribbon(m_petal, [c, p1, p2], [0.005, 0.009, 0.0], [s2] * 3)
        for k in range(3):
            ang = k / 3 * math.tau + 0.5
            out = ((side * math.cos(ang) + upv * math.sin(ang)) * 0.4 + fd).normalized()
            e = c + out * 0.085 + Vector((0, 0, 0.015))
            g.ribbon(m_stamen, [c, c.lerp(e, 0.6) + Vector((0, 0, 0.01)), e], [0.0015, 0.0015, 0.004],
                     [out.cross(Vector((0, 0, 1))).normalized()] * 3)


def build():
    rng = random.Random(41)
    g = F.Geo()
    stem = F.M("Foliage_LilyStem", (0.18, 0.2, 0.1), 0.7)
    petal = F.M("Foliage_PetalBlood", (0.55, 0.04, 0.03), 0.45)
    stamen = F.M("Foliage_LilyStamen", (0.62, 0.12, 0.06), 0.5)
    for i, p in enumerate(F.scatter_disc(rng, 0.14, 5, 0.06)):
        lily(g, rng, stem, petal, stamen, p, rng.uniform(0.3, 0.45))
    # strap leaves at the foot
    for i in range(5):
        F.blade(g, stem, rng, Vector((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), 0)), rng.uniform(0.12, 0.2),
                0.012, rng.uniform(0.5, 0.9), rng.uniform(0, math.tau), segs=3, droop=0.04)
    return g.build("FlowersRed")
