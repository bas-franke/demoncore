"""Tall marsh reeds: long strap blades and bulrush stalks with dark cigar heads, for mud and puddle margins."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _foliage as F  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = F.CATEGORY


def build():
    rng = random.Random(51)
    g = F.Geo()
    reed = F.M("Foliage_ReedGreen", (0.3, 0.32, 0.16), 0.65)
    reed_dry = F.M("Foliage_ReedStraw", (0.52, 0.46, 0.3), 0.75)
    head = F.M("Foliage_BulrushHead", (0.2, 0.12, 0.07), 0.9)
    F.grass_clump(g, rng, [(reed, 2.0), (reed_dry, 1.0)], n=22, h=(0.75, 1.3), w=(0.022, 0.034), radius=0.16,
                  lean=(0.08, 0.4), droop_chance=0.2, segs=4)
    for i in range(5):
        a = rng.uniform(0, math.tau)
        d = Vector((math.cos(a), math.sin(a), 0))
        base = d * rng.uniform(0.0, 0.1)
        h = rng.uniform(1.1, 1.5)
        top = base + d * h * rng.uniform(0.04, 0.12) + Vector((0, 0, h))
        pts = [base.lerp(top, t / 4) for t in range(5)]
        g.tube(reed, pts, [0.007, 0.006, 0.005, 0.0045, 0.004], sides=3)
        tan = (top - base).normalized()
        hs = top - tan * 0.22
        g.tube(head, [hs, hs + tan * 0.02, hs + tan * 0.16, hs + tan * 0.19], [0.012, 0.022, 0.02, 0.0], sides=6)
        g.tube(reed, [top - tan * 0.03, top + tan * 0.08], [0.003, 0.0], sides=3)
    return g.build("Reeds")
