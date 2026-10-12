"""Bronze tripod brazier: clawed legs, a braced ring, a deep banded bowl with a spiked rim and
a bed of glowing coals (top of the coals ~ z 1.27; demon_select.gd adds flames/embers/light)."""
import math
import os
import random
import sys
sys.path.insert(0, os.path.dirname(__file__))
import sb  # noqa: E402
import _kit as kit  # noqa: E402

CATEGORY = "menu"


def build():
    m = kit.mats()
    root = sb.root("Brazier")
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        c, s = math.cos(a), math.sin(a)
        pts = [(c * 0.18, s * 0.18, 1.0), (c * 0.3, s * 0.3, 0.7), (c * 0.38, s * 0.38, 0.3), (c * 0.46, s * 0.46, 0.08),
               (c * 0.52, s * 0.52, 0.02)]
        sb.ptube(f"leg{k}", root, pts, [0.045, 0.04, 0.035, 0.04, 0.03], sides=6, material=m["bronze"])
        # Claw foot: three toes.
        for t in (-0.35, 0.0, 0.35):
            ta = a + t
            sb.ptube(f"toe{k}{t}", root, [(c * 0.5, s * 0.5, 0.04), (c * 0.5 + math.cos(ta) * 0.1, s * 0.5 + math.sin(ta) * 0.1, 0.03),
                                         (c * 0.5 + math.cos(ta) * 0.15, s * 0.5 + math.sin(ta) * 0.15, 0.0)],
                     [0.025, 0.018, 0.006], sides=5, material=m["bronze"])
        # Decorative scroll on each leg.
        sb.ptube(f"scroll{k}", root, [(c * 0.31, s * 0.31, 0.66), (c * 0.42, s * 0.42, 0.75), (c * 0.4, s * 0.4, 0.88),
                                      (c * 0.32, s * 0.32, 0.85)], [0.02, 0.022, 0.018, 0.012], sides=5, material=m["bronze"])
    sb.torus("brace", root, major=0.33, minor=0.025, loc=(0, 0, 0.55), material=m["bronze"], major_segments=24,
             minor_segments=6)
    # Stem + bowl.
    sb.lathe("stem", root, [(0.0, 0.9), (0.08, 0.9), (0.06, 0.96), (0.1, 1.0), (0.0, 1.0)], segments=12,
             material=m["bronze"])
    bowl = [(0.0, 0.98), (0.14, 0.98), (0.3, 1.04), (0.42, 1.13), (0.48, 1.24), (0.53, 1.29), (0.5, 1.31),
            (0.45, 1.27), (0.38, 1.18), (0.0, 1.14)]
    sb.lathe("bowl", root, bowl, segments=20, material=m["bronze"])
    sb.torus("band", root, major=0.43, minor=0.018, loc=(0, 0, 1.15), material=m["iron"], major_segments=24,
             minor_segments=5)
    for k in range(10):
        a = 2 * math.pi * k / 10
        sb.cylinder(f"spike{k}", root, r1=0.025, r2=0.0, depth=0.14, loc=(math.cos(a) * 0.52, math.sin(a) * 0.52, 1.29),
                    rot=(math.degrees(math.sin(a)) * -0.3, math.degrees(math.cos(a)) * 0.3, 0), material=m["iron"],
                    segments=4, bevel=0, smooth=False)
    # Coal bed: glowing core with dark charred lumps.
    sb.lathe("coals", root, [(0.0, 1.2), (0.44, 1.2), (0.42, 1.25), (0.25, 1.29), (0.0, 1.3)], segments=14,
             material=m["coal"], jitter=0.05, seed=2)
    rnd = random.Random(4)
    for k in range(9):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.05, 0.36)
        sb.sphere(f"lump{k}", root, radius=rnd.uniform(0.05, 0.08), loc=(math.cos(a) * r, math.sin(a) * r, 1.28),
                  scale=(1, 0.8, 0.6), material=m["obsidian"], segments=6, rings=4)
    sb.join_meshes(root, "brazier")
    sb.tri_count(root)
    return root
