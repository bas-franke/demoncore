"""Toadstool cluster: pale bone-white stalks with umber, rust and sickly-pale caps, dark gills beneath."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _foliage as F  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

CATEGORY = F.CATEGORY


def shroom(g, rng, m_stem, m_cap, m_gill, pos, h, cap_r, lean, conical=False):
    a = rng.uniform(0, math.tau)
    tilt = Matrix.Rotation(lean, 4, Vector((math.cos(a), math.sin(a), 0.0)))
    xf = Matrix.Translation(pos) @ tilt
    r = cap_r * 0.22
    g.lathe(m_stem, [(r * 1.3, -0.01), (r * 1.1, h * 0.15), (r * 0.9, h * 0.7), (r, h)], 6, xf)
    if conical:
        cap = [(cap_r, h - cap_r * 0.15), (cap_r * 0.85, h + cap_r * 0.35), (cap_r * 0.5, h + cap_r * 0.8),
               (0.0, h + cap_r * 1.05)]
    else:
        cap = [(cap_r, h - cap_r * 0.1), (cap_r * 0.95, h + cap_r * 0.18), (cap_r * 0.7, h + cap_r * 0.42),
               (cap_r * 0.35, h + cap_r * 0.52), (0.0, h + cap_r * 0.55)]
    ph = pos.x * 40.0

    def wob(an, i):
        return 1.0 + 0.06 * math.sin(an * 3 + ph)

    g.lathe(m_cap, cap, 9, xf, wob)
    # underside (gills): a shallow inverted cone
    g.lathe(m_gill, [(0.0, h - cap_r * 0.02), (cap_r * 0.98, h - cap_r * 0.1)], 9, xf, wob)


def build():
    rng = random.Random(21)
    g = F.Geo()
    stem = F.M("Foliage_ShroomStalk", (0.7, 0.66, 0.56), 0.6)
    capA = F.M("Foliage_ShroomCapUmber", (0.36, 0.22, 0.12), 0.45)
    capB = F.M("Foliage_ShroomCapRust", (0.5, 0.17, 0.07), 0.4)
    capC = F.M("Foliage_ShroomCapPale", (0.72, 0.68, 0.58), 0.5)
    gill = F.M("Foliage_ShroomGill", (0.22, 0.17, 0.13), 0.8)
    spots = F.scatter_disc(rng, 0.14, 6, 0.06)
    for i, p in enumerate(spots):
        big = 1.0 - p.length / 0.2
        h = rng.uniform(0.05, 0.11) * (0.6 + 0.8 * big)
        cr = h * rng.uniform(0.45, 0.65)
        cap = [capA, capA, capB, capC][i % 4]
        shroom(g, rng, stem, cap, gill, p, h, cr, rng.uniform(0.0, 0.35), conical=(i % 3 == 2))
    return g.build("Toadstools")
