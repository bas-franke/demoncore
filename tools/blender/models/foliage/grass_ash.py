"""Ash-choked grass: grey, wiry, half-dead blades, many snapped and lying over."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import random  # noqa: E402
import _foliage as F  # noqa: E402

CATEGORY = F.CATEGORY


def build():
    rng = random.Random(37)
    g = F.Geo()
    ash = F.M("Foliage_GrassAsh", (0.43, 0.42, 0.4), 0.95)
    char = F.M("Foliage_GrassCharred", (0.2, 0.19, 0.18), 0.95)
    F.grass_clump(g, rng, [(ash, 2.5), (char, 1.0)], n=20, h=(0.24, 0.46), w=(0.018, 0.03),
                  radius=0.18, lean=(0.35, 0.9), droop_chance=0.5, seeds=2, seed_mat=char, seed_h=1.1)
    return g.build("GrassAsh")
