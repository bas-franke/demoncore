"""Broken clustered pier (~4 m, shattered top) with fallen drums and rubble strewn toward +X."""
import math
import os
import random
import sys
sys.path.insert(0, os.path.dirname(__file__))
import sb  # noqa: E402
import _kit as kit  # noqa: E402
import _pillar  # noqa: E402

CATEGORY = "menu"


def drum(name, parent, m, loc, rot, seed):
    g = sb.empty(name, parent, loc=loc, rot=rot)
    sb.lathe("d", g, [(0.0, -0.45), (0.47, -0.45), (0.48, 0.45), (0.0, 0.45)], segments=14, material=m["stone"],
             jitter=0.03, seed=seed)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        sb.cylinder(f"c{k}", g, r1=0.14, depth=0.9, loc=(math.cos(a) * 0.5, math.sin(a) * 0.5, -0.45),
                    material=m["stone"], segments=8, bevel=0)
    return g


def build():
    m = kit.mats()
    root = sb.root("PillarBroken")
    _pillar.pier(root, m, 4.0, seed=5, broken=True)
    drum("drum0", root, m, (1.5, 0.4, 0.5), (90, 0, 20), 1)
    drum("drum1", root, m, (2.4, -0.7, 0.5), (90, 0, -50), 2)
    g = drum("drum2", root, m, (1.3, -1.1, 0.0), (8, 4, 0), 3)
    g.location.z = 0.45
    rnd = random.Random(6)
    for k in range(9):
        a = rnd.uniform(-1.2, 1.2)
        r = rnd.uniform(0.9, 2.8)
        s = rnd.uniform(0.12, 0.35)
        sb.box(f"rubble{k}", root, size=(s, s * 0.8, s * 0.6), loc=(math.cos(a) * r, math.sin(a) * r, s * 0.25),
               rot=(rnd.uniform(-25, 25), rnd.uniform(-25, 25), rnd.uniform(0, 90)), material=m["stone"], bevel=0.02)
    sb.join_meshes(root, "pillar")
    sb.tri_count(root)
    return root
