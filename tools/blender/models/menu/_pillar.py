"""Shared clustered gothic pier builder for pillar_full.py / pillar_broken.py (not built itself)."""
import math
import random
import sb


def pier(parent, m, height, seed=0, broken=False):
    """Square stepped base, a weathered core shaft with four attached colonnettes, and (if not
    broken) a moulded capital + abacus at the top. Base at z=0. Returns the shaft top height."""
    rnd = random.Random(seed)
    sb.box("base", parent, size=(1.6, 1.6, 0.45), loc=(0, 0, 0.225), material=m["stone_dark"], bevel=0.04)
    sb.box("base2", parent, size=(1.35, 1.35, 0.2), loc=(0, 0, 0.55), material=m["stone"], bevel=0.035, taper=(0.92, 0.92))
    sb.lathe("torus_mould", parent, [(0.0, 0.65), (0.6, 0.65), (0.66, 0.72), (0.6, 0.8), (0.52, 0.82), (0.0, 0.82)],
             segments=16, material=m["stone"])
    top = height
    core = [(0.0, 0.8), (0.48, 0.8)]
    z = 0.8
    while z < top - 0.6:
        z = min(z + 0.9, top - 0.6)
        core.append((0.48, z))  # drum joints
        core.append((0.465, z + 0.015))
        core.append((0.48, z + 0.03))
    core += [(0.48, top), (0.0, top)]
    sh = sb.lathe("core", parent, core, segments=14, material=m["stone"], jitter=0.025, seed=seed)
    if broken:
        # Shatter the top: knock the upper rings down unevenly.
        for v in sh.data.vertices:
            if v.co.z > top - 0.75:
                k = (v.co.z - (top - 0.75)) / 0.75
                v.co.z -= k * rnd.uniform(0.0, 0.7)
                v.co.x *= 1.0 - 0.15 * k * rnd.random()
                v.co.y *= 1.0 - 0.15 * k * rnd.random()
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        c, s = math.cos(a) * 0.5, math.sin(a) * 0.5
        h = top - 0.8 - (rnd.uniform(0.3, 1.1) if broken else 0.0)
        sb.cylinder(f"colonnette{k}", parent, r1=0.14, depth=h, loc=(c, s, 0.8), material=m["stone"], segments=8,
                    bevel=0)
        sb.cylinder(f"col_base{k}", parent, r1=0.18, r2=0.15, depth=0.12, loc=(c, s, 0.78), material=m["stone"],
                    segments=8, bevel=0)
        if not broken:
            sb.cylinder(f"col_cap{k}", parent, r1=0.15, r2=0.2, depth=0.2, loc=(c, s, top - 0.82), material=m["stone"],
                        segments=8, bevel=0)
    if not broken:
        sb.lathe("capital", parent, [(0.0, top - 0.8), (0.5, top - 0.8), (0.72, top - 0.55), (0.78, top - 0.5),
                                     (0.0, top - 0.5)], segments=16, material=m["stone"])
        sb.box("abacus", parent, size=(1.55, 1.55, 0.5), loc=(0, 0, top - 0.25), material=m["stone_dark"], bevel=0.04)
    return top
