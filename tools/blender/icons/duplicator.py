"""Legion: a throng of hooded silhouettes, backlit, eyes kindling in the dark."""
import math
import random
import sb
import _ikit as k

ACCENT = (1.0, 0.62, 0.28)
VIEW = {"pitch": 4, "yaw": 0, "fill": 0.9, "rim": 1.4, "key": 0.35, "backglow": 1.7, "exposure": 0.6}


def build():
    robe = sb.mat("I_Robe", (0.03, 0.025, 0.022), roughness=0.85)
    eye = k.glow("I_Eye", (1.0, 0.5, 0.15), 2.0)
    root = sb.root("Legion")
    rnd = random.Random(30)

    # (x, depth, scale) - front row large, rows behind smaller and higher.
    figures = [(0.0, -0.4, 1.0), (-0.62, -0.15, 0.85), (0.62, -0.15, 0.85),
               (-0.32, 0.3, 0.78), (0.32, 0.3, 0.78), (-1.0, 0.25, 0.7), (1.0, 0.25, 0.7),
               (0.0, 0.7, 0.72), (-0.7, 0.75, 0.62), (0.7, 0.75, 0.62), (-1.25, 0.8, 0.55), (1.25, 0.8, 0.55)]
    for i, (x, y, s) in enumerate(figures):
        z0 = -1.0 + (y + 0.4) * 0.35
        h = 1.6 * s
        sb.lathe(f"robe{i}", root, [(0.42 * s, 0), (0.36 * s, h * 0.35), (0.3 * s, h * 0.7), (0.24 * s, h * 0.82),
                                    (0.0, h * 0.86)], 14, robe, loc=(x, y, z0), jitter=0.06, seed=i)
        # Hood: a pointed cowl leaning forward.
        hood = sb.lathe(f"hood{i}", root, [(0.0, 0.0), (0.2 * s, 0.02 * s), (0.2 * s, 0.22 * s), (0.12 * s, 0.38 * s),
                                           (0.0, 0.48 * s)], 14, robe,
                        loc=(x, y + 0.02, z0 + h * 0.78), rot=(-12 + rnd.uniform(-6, 6), rnd.uniform(-8, 8), 0))
        # Shoulders.
        sb.sphere(f"sh{i}", root, 0.3 * s, loc=(x, y, z0 + h * 0.7), scale=(1.3, 0.8, 0.5), material=robe)
        for e in (-1, 1):
            sb.sphere(f"eye{i}{e}", root, 0.022 * s, loc=(x + 0.06 * s * e, y - 0.19 * s, z0 + h * 0.78 + 0.16 * s),
                      material=eye)
        del hood
    return root
