"""Toppled pillars: drums strewn in a line from a standing stump (3 variants)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402

CATEGORY = "props"


def line(v, rng, n, x0=-1.2):
    x = x0
    for i in range(n):
        ln = rng.uniform(0.8, 1.15)
        yaw = rng.uniform(-10, 10)
        K.drum(f"lay{i}", v, rng, 0.42, ln, (x, rng.uniform(-0.15, 0.15), 0.4), (0, 90, yaw),
               broken_top=0.25 if i == n - 1 else 0.0, broken_bottom=0.2 if i == 0 else 0.0, chips=2, flutes=6)
        x += ln + rng.uniform(0.08, 0.35)
    return x


def build():
    vs = sb.variants("fp", 3, 7.0)
    rng = K.rng_for(101)
    v = vs[0]
    K.plinth("plinth", v, rng, 1.4, 0.3, (-2.3, 0, 0))
    K.drum("stump", v, rng, 0.4, 0.75, (-2.3, 0, 0.3), (0, 0, 0), broken_top=0.4)
    x = line(v, rng, 3)
    K.lathe_obj("capital", v, rng, K.CAPITAL, 20, (x + 0.15, 0.1, 0.62), (0, 80, 15), chips=3)
    K.rubble(v, rng, (-0.2, 0.7, 0), 2.0, 3)

    rng = K.rng_for(202)
    v = vs[1]
    x = line(v, rng, 2, -1.0)
    sb.stone_block("abacus", v, (1.2, 1.2, 0.24), K.M("Prop_Stone"), rng, loc=(x + 0.5, -0.2, 0.2),
                   rot=(8, -10, 25), chips=3)
    K.rubble(v, rng, (0.0, -0.6, 0), 1.8, 7)

    rng = K.rng_for(303)
    v = vs[2]
    K.plinth("plinth", v, rng, 1.35, 0.3, (-2.4, 0.2, 0), chips=4)
    line(v, rng, 4, -1.5)
    K.rubble(v, rng, (0.5, 0.6, 0), 2.2, 6)
    sb.tri_report("fallen_pillar")
    return vs[0]
