"""Thorny bramble: arching barbed canes looping back into the ground, sparse dark leaves, black berries."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _foliage as F  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

CATEGORY = F.CATEGORY


def cane(g, rng, m_cane, m_thorn, m_leaf, m_berry, start, heading, length, height):
    d = Vector((math.cos(heading), math.sin(heading), 0.0))
    p0 = Vector(start)
    p3 = p0 + d * length + Vector((0, 0, -0.04))
    p1 = p0 + d * length * 0.25 + Vector((0, 0, height * 1.2))
    p2 = p0 + d * length * 0.75 + Vector((0, 0, height * 0.9))

    def cub(t):
        a = p0.lerp(p1, t)
        b = p1.lerp(p2, t)
        c = p2.lerp(p3, t)
        return a.lerp(b, t).lerp(b.lerp(c, t), t)

    N = 9
    pts = []
    for i in range(N + 1):
        t = i / N
        p = cub(t)
        p += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * 0.02 * math.sin(math.pi * t)
        pts.append(p)
    g.tube(m_cane, pts, [0.016 * (1 - 0.6 * i / N) for i in range(N + 1)], sides=4)
    # thorns: little hooked spikes along the cane
    for i in range(1, N):
        for k in range(2):
            t = (i + rng.random()) / N
            p = cub(t)
            tan = (cub(min(1, t + 0.01)) - p).normalized()
            out = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 1))).normalized()
            out = (out - tan * out.dot(tan)).normalized()
            r = 0.016 * (1 - 0.6 * t)
            b = p + out * r * 0.8
            tip = b + out * 0.035 - tan * 0.014
            s = tan * 0.007
            g.face((g.v(b - s), g.v(b + s), g.v(tip)), m_thorn)
    # leaves: trifoliate clusters
    for i in range(rng.randint(2, 4)):
        t = rng.uniform(0.2, 0.8)
        p = cub(t)
        for k in range(3):
            hd = heading + rng.uniform(-2.2, 2.2)
            F.leaf_shape(g, m_leaf, p + Vector((math.cos(hd), math.sin(hd), 0)) * 0.05 + Vector((0, 0, 0.01)),
                         rng.uniform(0.07, 0.1), rng.uniform(0.025, 0.035), hd, tilt=rng.uniform(-0.4, 0.4),
                         fold=0.35, curl=0.1, pitch=rng.uniform(-0.3, 0.2))
    # berry cluster
    if rng.random() < 0.7:
        p = cub(rng.uniform(0.35, 0.6)) + Vector((0, 0, -0.03))
        for k in range(rng.randint(2, 4)):
            c = p + Vector((rng.uniform(-0.025, 0.025), rng.uniform(-0.025, 0.025), rng.uniform(-0.02, 0.0)))
            g.lathe(m_berry, [(0.0, -0.014), (0.012, -0.009), (0.014, 0.0), (0.011, 0.009), (0.0, 0.013)], 5,
                    Matrix.Translation(c))


def build():
    rng = random.Random(9)
    g = F.Geo()
    canem = F.M("Foliage_BrambleCane", (0.2, 0.1, 0.09), 0.7)
    thorn = F.M("Foliage_BrambleThorn", (0.42, 0.33, 0.24), 0.6)
    leafm = F.M("Foliage_BrambleLeaf", (0.13, 0.15, 0.08), 0.6)
    berry = F.M("Foliage_BrambleBerry", (0.07, 0.03, 0.05), 0.25)
    n = 7
    for i in range(n):
        heading = i / n * math.tau + rng.uniform(-0.4, 0.4)
        start = Vector((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), 0.0))
        cane(g, rng, canem, thorn, leafm, berry, start, heading, rng.uniform(0.6, 1.0), rng.uniform(0.35, 0.55))
    return g.build("Bramble")
