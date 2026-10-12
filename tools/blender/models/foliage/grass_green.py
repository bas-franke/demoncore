"""Dark green meadow tussock: dense, darker blades with a few olive ones and seed stalks."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import random  # noqa: E402
import _foliage as F  # noqa: E402

CATEGORY = F.CATEGORY


def build():
    rng = random.Random(23)
    g = F.Geo()
    dark = F.M("Foliage_GrassDark", (0.16, 0.22, 0.09), 0.75)
    olive = F.M("Foliage_GrassOlive", (0.27, 0.3, 0.13), 0.8)
    F.grass_clump(g, rng, [(dark, 3.0), (olive, 1.0)], n=28, h=(0.28, 0.5), w=(0.028, 0.045),
                  radius=0.18, lean=(0.25, 0.75), droop_chance=0.15, seeds=2, seed_mat=olive, seed_h=1.2)
    return g.build("GrassGreen")
