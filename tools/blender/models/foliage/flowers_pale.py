"""Pale wildflowers: ashen-white and grey-lilac star flowers with dusky eyes on thin stems over a rosette."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _foliage as F  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

CATEGORY = F.CATEGORY


def flower(g, rng, m_stem, m_petal, m_eye, base, h, petals=5, size=0.035):
    a = rng.uniform(0, math.tau)
    d = Vector((math.cos(a), math.sin(a), 0.0))
    top = base + d * h * rng.uniform(0.08, 0.25) + Vector((0, 0, h))
    mid = base + Vector((0, 0, h * 0.6))
    pts = [F.bezier(base, mid, top, t / 3) for t in range(4)]
    sd = Vector((-d.y, d.x, 0))
    g.ribbon(m_stem, pts, [0.005, 0.004, 0.0035, 0.003], [sd] * 4)
    # petals: a flat star facing up (tipped toward the lean)
    n = (Vector((0, 0, 1)) + d * 0.35).normalized()
    u = sd
    v = n.cross(u).normalized()
    c = top + n * 0.004
    for k in range(petals):
        ang = k / petals * math.tau + rng.uniform(-0.15, 0.15)
        dirp = u * math.cos(ang) + v * math.sin(ang)
        s2 = n.cross(dirp).normalized()
        p1 = c + dirp * size * 0.55 + n * size * 0.12
        p2 = c + dirp * size + n * size * 0.05
        g.ribbon(m_petal, [c, p1, p2], [size * 0.12, size * 0.32, 0.0], [s2] * 3)
    rot = n.to_track_quat("Z", "Y").to_matrix().to_4x4()
    g.lathe(m_eye, [(0.0, -0.003), (size * 0.22, 0.0), (size * 0.15, 0.006), (0.0, 0.008)], 5,
            Matrix.Translation(c) @ rot)


def build():
    rng = random.Random(31)
    g = F.Geo()
    stem = F.M("Foliage_FlowerStem", (0.2, 0.24, 0.12), 0.7)
    petal = F.M("Foliage_PetalPale", (0.85, 0.82, 0.76), 0.6)
    petal2 = F.M("Foliage_PetalAshLilac", (0.68, 0.64, 0.72), 0.6)
    eye = F.M("Foliage_FlowerEyeDusk", (0.35, 0.25, 0.1), 0.6)
    leaf = F.M("Foliage_FlowerLeaf", (0.17, 0.22, 0.09), 0.7)
    for i in range(7):
        a = i / 7 * math.tau
        F.leaf_shape(g, leaf, Vector((math.cos(a) * 0.07, math.sin(a) * 0.07, 0.03)), 0.12, 0.025, a,
                     fold=0.4, curl=0.15, pitch=0.35)
    for i, p in enumerate(F.scatter_disc(rng, 0.13, 7, 0.04)):
        flower(g, rng, stem, petal if i % 3 else petal2, eye, p, rng.uniform(0.2, 0.36), size=rng.uniform(0.03, 0.042))
    return g.build("FlowersPale")
