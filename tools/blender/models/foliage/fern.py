"""Fern: arching fronds of paired, tapering pinnae around a dark crown; two greens + a browning frond."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _foliage as F  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = F.CATEGORY


def frond(g, rng, m_rachis, m_leaf, heading, length, rise, pairs=9):
    d = Vector((math.cos(heading), math.sin(heading), 0.0))
    side = Vector((-d.y, d.x, 0.0))
    base = d * 0.03
    tip = base + d * length * 0.92 + Vector((0, 0, rise * 0.35))
    mid = base + d * length * 0.45 + Vector((0, 0, rise))
    pts = [F.bezier(base, mid, tip, t / 6) for t in range(7)]
    g.ribbon(m_rachis, pts, [0.008, 0.007, 0.006, 0.005, 0.004, 0.003, 0.0], [side] * 7)
    for i in range(pairs):
        t = 0.18 + 0.8 * i / pairs
        p = F.bezier(base, mid, tip, t)
        tan = (F.bezier(base, mid, tip, min(1.0, t + 0.02)) - p).normalized()
        L = length * 0.26 * math.sin(math.pi * min(1.0, 0.15 + t * 0.95)) * rng.uniform(0.85, 1.1)
        for s in (-1, 1):
            out = (side * s * 0.85 + tan * 0.5).normalized()
            out.z -= 0.25 + 0.3 * t  # pinnae droop
            out.normalize()
            q0 = p
            q2 = p + out * L
            q1 = p + out * L * 0.5 + Vector((0, 0, L * 0.12))
            w = L * 0.22
            # pinna lies roughly flat: its width runs along the rachis
            pts2 = [q0, F.bezier(q0, q1, q2, 0.35), F.bezier(q0, q1, q2, 0.7), q2]
            g.ribbon(m_leaf, pts2, [w * 0.5, w, w * 0.6, 0.0], [tan] * 4)


def build():
    rng = random.Random(5)
    g = F.Geo()
    leaf = F.M("Foliage_FernLeaf", (0.17, 0.23, 0.09), 0.7)
    leaf2 = F.M("Foliage_FernLeafOlive", (0.26, 0.29, 0.12), 0.75)
    brown = F.M("Foliage_FernDead", (0.36, 0.24, 0.12), 0.85)
    rachis = F.M("Foliage_FernStem", (0.12, 0.11, 0.06), 0.8)
    n = 8
    for i in range(n):
        heading = i / n * math.tau + rng.uniform(-0.25, 0.25)
        length = rng.uniform(0.55, 0.8)
        m = leaf if i % 3 else leaf2
        if i == 5:
            m = brown
            length *= 0.85
        frond(g, rng, rachis, m, heading, length, rise=rng.uniform(0.3, 0.45) * (0.6 if m is brown else 1.0))
    # unfurling fiddleheads at the crown
    for i in range(2):
        a = rng.uniform(0, math.tau)
        c, s = math.cos(a), math.sin(a)
        pts = [Vector((c * 0.02, s * 0.02, 0.0)), Vector((c * 0.03, s * 0.03, 0.12)), Vector((c * 0.06, s * 0.06, 0.19)),
               Vector((c * 0.09, s * 0.09, 0.17)), Vector((c * 0.07, s * 0.07, 0.14))]
        g.tube(rachis, pts, [0.008, 0.007, 0.007, 0.006, 0.0], sides=4)
    return g.build("Fern")
