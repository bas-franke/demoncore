"""Broken fluted columns on weathered plinths (4 variants)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402

CATEGORY = "props"


def column_base(v, rng):
    K.plinth("plinth", v, rng, 1.45, 0.32)
    K.lathe_obj("base", v, rng, K.ATTIC_BASE, 24, (0, 0, 0.32), chips=1)
    return 0.66


def build():
    vs = sb.variants("col", 4, 4.0)
    # v0: tall, nearly whole, with capital
    rng = K.rng_for(11)
    v = vs[0]
    z = column_base(v, rng)
    for i, h in enumerate((1.05, 0.95, 1.0)):
        K.drum(f"drum{i}", v, rng, 0.4, h, (rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02), z),
               (rng.uniform(-1.2, 1.2), rng.uniform(-1.2, 1.2), rng.uniform(0, 360)), chips=1)
        z += h
    K.lathe_obj("capital", v, rng, K.CAPITAL, 24, (0, 0, z), chips=2)
    sb.stone_block("abacus", v, (1.3, 1.3, 0.24), K.M("Prop_Stone"), rng, loc=(0, 0, z + 0.27 + 0.12), chips=3)
    K.rubble(v, rng, (0.2, 0.3, 0), 1.6, 4)

    # v1: two drums, top one snapped; the fallen drum lies beside
    rng = K.rng_for(23)
    v = vs[1]
    z = column_base(v, rng)
    K.drum("drum0", v, rng, 0.4, 1.0, (0, 0, z), (0, 0, 40))
    K.drum("drum1", v, rng, 0.4, 0.85, (0.02, -0.01, z + 1.0), (1.5, -1, 100), broken_top=0.4)
    K.drum("fallen", v, rng, 0.4, 0.95, (1.55, 0.6, 0.38), (90, 0, 25), broken_top=0.3, chips=3)
    K.rubble(v, rng, (0.9, -0.4, 0), 1.5, 6)

    # v2: stump with the capital toppled in the grass
    rng = K.rng_for(37)
    v = vs[2]
    z = column_base(v, rng)
    K.drum("drum0", v, rng, 0.4, 0.75, (0, 0, z), (0, 0, 10), broken_top=0.45)
    K.lathe_obj("capital", v, rng, K.CAPITAL, 24, (-1.4, 0.75, 0.42), (100, 10, 30), chips=3)
    sb.stone_block("abacus", v, (1.25, 1.25, 0.24), K.M("Prop_Stone"), rng, loc=(-1.35, -0.6, 0.2),
                   rot=(-14, 6, 20), chips=3)
    K.rubble(v, rng, (0.3, 0.2, 0), 1.8, 7)

    # v3: split base, two drums toppled in a line
    rng = K.rng_for(41)
    v = vs[3]
    K.plinth("plinth", v, rng, 1.45, 0.32, chips=4)
    K.drum("drum0", v, rng, 0.4, 0.5, (0, 0, 0.32), (0, 0, 0), broken_top=0.35, cracks=2)
    K.drum("fallen0", v, rng, 0.4, 1.0, (0.35, -0.85, 0.37), (90, 0, -8), broken_bottom=0.3)
    K.drum("fallen1", v, rng, 0.4, 0.9, (0.6, -2.05, 0.36), (88, 0, 5), broken_top=0.3)
    K.rubble(v, rng, (-0.5, -0.9, 0), 1.4, 6)
    sb.tri_report("broken_column")
    return vs[0]
