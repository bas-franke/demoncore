"""Dry golden grass tussock: straw-gold blades, some broken over, ripe seed stalks."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import random  # noqa: E402
import _foliage as F  # noqa: E402

CATEGORY = F.CATEGORY


def build():
    rng = random.Random(11)
    g = F.Geo()
    gold = F.M("Foliage_GrassGold", (0.56, 0.45, 0.22), 0.8)
    straw = F.M("Foliage_GrassStraw", (0.66, 0.58, 0.38), 0.85)
    F.grass_clump(g, rng, [(gold, 2.0), (straw, 1.0)], n=24, h=(0.35, 0.62), w=(0.026, 0.042),
                  radius=0.17, lean=(0.3, 0.8), droop_chance=0.25, seeds=4, seed_mat=straw)
    return g.build("GrassDry")
