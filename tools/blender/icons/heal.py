"""Taste of Blood: two curved fangs, a fat drop of blood falling from one tip."""
import math
import sb
import _ikit as k

ACCENT = (0.9, 0.14, 0.1)
VIEW = {"pitch": 4, "yaw": -10, "fill": 0.86}


def build():
    ivory = sb.mat("I_Fang", (0.6, 0.54, 0.44), roughness=0.3)
    root_m = sb.mat("I_FangRoot", (0.25, 0.08, 0.07), roughness=0.5)
    blood = sb.mat("I_Blood", (0.32, 0.01, 0.02), roughness=0.08, emission=(0.7, 0.02, 0.03), strength=0.55)
    root = sb.root("Fangs")

    for s, (x, ln) in ((-1, (-0.35, 1.0)), (1, (0.35, 1.15))):
        pts, radii = [], []
        n = 8
        for j in range(n + 1):
            t = j / n
            pts.append((x + s * -0.18 * t * t, 0.0, 0.9 - t * ln * 1.4))
            radii.append(0.17 * (1 - t) ** 0.85 + 0.004)
        sb.ptube(f"fang{s}", root, pts, radii, sides=12, material=ivory)
        sb.sphere(f"gum{s}", root, 0.2, loc=(x, 0.02, 0.92), scale=(1.1, 0.9, 0.6), material=root_m)
        # Blood running down the fang.
        bp = [(p[0] - 0.02 * s, -0.12 + 0.12 * (j / n), p[2]) for j, p in enumerate(pts) if j > 2]
        sb.ptube(f"run{s}", root, bp, [0.02 + 0.01 * (j % 2) for j in range(len(bp))], sides=6, material=blood)
    # The drop, falling off the right fang.
    k.teardrop("drop", root, 0.27, 0.7, blood, loc=(0.17, -0.05, -1.55))
    sb.sphere("droplet", root, 0.06, loc=(-0.08, -0.05, -1.62), material=blood)
    sb.sphere("droplet2", root, 0.035, loc=(0.45, -0.05, -1.66), material=blood)
    return root
