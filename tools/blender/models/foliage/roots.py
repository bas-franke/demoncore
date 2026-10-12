"""Exposed roots: gnarled bark roots arching out of the soil and diving back in, around a mossy rotted knot."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _foliage as F  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

CATEGORY = F.CATEGORY


def build():
    rng = random.Random(17)
    g = F.Geo()
    bark = F.M("Foliage_RootBark", (0.2, 0.15, 0.11), 0.9)
    dark = F.M("Foliage_RootBarkDark", (0.11, 0.085, 0.07), 0.95)
    moss = F.M("Foliage_RootMoss", (0.18, 0.22, 0.08), 1.0)
    # the knot (a rotted stump nub)
    g.lathe(dark, [(0.2, -0.05), (0.19, 0.04), (0.15, 0.1), (0.1, 0.13), (0.0, 0.12)], 7, Matrix.Identity(4),
            wobble=lambda a, i: 1.0 + 0.18 * math.sin(a * 3 + i) * math.cos(a * 2))
    g.lathe(moss, [(0.16, 0.08), (0.12, 0.125), (0.0, 0.135)], 7, Matrix.Translation((0.01, 0.0, 0.0)))
    n = 5
    for i in range(n):
        a = i / n * math.tau + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), 0.0))
        side = Vector((-d.y, d.x, 0.0))
        L = rng.uniform(0.7, 1.2)
        arcs = rng.randint(1, 2)
        pts = [d * 0.08 + Vector((0, 0, 0.07))]
        rad = [0.075]
        steps = 7
        for k in range(1, steps + 1):
            t = k / steps
            off = side * math.sin(t * 5.0 + i) * 0.08 * t
            h = 0.09 * abs(math.sin(math.pi * t * arcs)) * (1 - 0.4 * t) - 0.035 * t
            pts.append(d * (0.08 + L * t) + off + Vector((0, 0, h)))
            rad.append(0.07 * (1 - 0.75 * t) + 0.006)
        rad[-1] = 0.0
        g.tube(bark if i % 2 else dark, pts, rad, sides=5)
        # a thin side root
        k = rng.randint(2, 4)
        b = pts[k]
        sd = side * rng.choice((-1, 1))
        g.tube(bark, [b, b + sd * 0.15 + d * 0.1 + Vector((0, 0, 0.03)), b + sd * 0.3 + d * 0.2 + Vector((0, 0, -0.03))],
               [rad[k] * 0.5, rad[k] * 0.35, 0.0], sides=4)
    return g.build("Roots")
