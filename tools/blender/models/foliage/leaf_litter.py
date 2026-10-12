"""Dead leaf litter: a drift of curled fallen leaves (rust, ochre, umber, blood) and a few twigs, lying flat."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _foliage as F  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = F.CATEGORY


def build():
    rng = random.Random(3)
    g = F.Geo()
    mats = [F.M("Foliage_LeafRust", (0.42, 0.18, 0.07), 0.85), F.M("Foliage_LeafOchre", (0.55, 0.38, 0.14), 0.85),
            F.M("Foliage_LeafUmber", (0.25, 0.16, 0.09), 0.9), F.M("Foliage_LeafBlood", (0.38, 0.08, 0.05), 0.85)]
    twig = F.M("Foliage_TwigBark", (0.16, 0.12, 0.09), 0.9)
    pts = F.scatter_disc(rng, 0.42, 26, 0.05)
    for i, p in enumerate(pts):
        r = p.length / 0.42
        z = 0.008 + 0.025 * (1 - r) * rng.random() + i * 0.0006
        m = mats[rng.choices(range(4), weights=(3, 2, 3, 1))[0]]
        F.leaf_shape(g, m, p + Vector((0, 0, z)), rng.uniform(0.07, 0.12), rng.uniform(0.028, 0.045),
                     rng.uniform(0, math.tau), tilt=rng.uniform(-0.35, 0.35), fold=rng.uniform(0.1, 0.5),
                     curl=rng.uniform(-0.05, 0.25), pitch=rng.uniform(-0.12, 0.15))
    for i in range(3):
        a = rng.uniform(0, math.tau)
        c = Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 0.012))
        d = Vector((math.cos(a), math.sin(a), 0.0)) * rng.uniform(0.12, 0.2)
        g.tube(twig, [c - d, c + Vector((0, 0, 0.008)), c + d], [0.007, 0.006, 0.004], sides=3)
        fork = c + d * 0.4
        e = Vector((math.cos(a + 0.6), math.sin(a + 0.6), 0.0)) * 0.08
        g.tube(twig, [fork, fork + e], [0.004, 0.002], sides=3)
    return g.build("LeafLitter")
