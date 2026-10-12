"""Profane Haste: a tarnished hourglass whose sand is falling embers."""
import math
import random
import sb
import _ikit as k

ACCENT = (1.0, 0.48, 0.16)
VIEW = {"pitch": 10, "yaw": -18, "fill": 0.84}


def build():
    bronze = k.metal("I_Bronze", (0.38, 0.24, 0.1), 0.4)
    dark = k.metal("I_DarkBronze", (0.1, 0.07, 0.05), 0.5)
    glass = k.glass("I_Glass", (0.6, 0.55, 0.5), 0.18)
    sand = k.glow("I_EmberSand", (1.0, 0.36, 0.06), 1.5)
    hot = k.glow("I_EmberHot", (1.0, 0.65, 0.25), 1.8)
    root = sb.root("Hourglass")
    root.rotation_euler = (0, math.radians(10), 0)
    rnd = random.Random(6)

    # End caps.
    for z, nm in ((-0.95, "bot"), (0.95, "top")):
        sb.lathe(f"cap_{nm}", root, [(0.0, -0.07), (0.58, -0.07), (0.62, -0.02), (0.58, 0.07), (0.0, 0.07)], 6,
                 bronze, loc=(0, 0, z))
        sb.lathe(f"capb_{nm}", root, [(0.0, -0.05), (0.5, -0.05), (0.5, 0.05), (0.0, 0.05)], 6, dark,
                 loc=(0, 0, z + (0.1 if z > 0 else -0.1)))
        for i in range(6):
            a = 2 * math.pi * i / 6 + math.pi / 6
            sb.sphere(f"stud_{nm}{i}", root, 0.05, loc=(math.cos(a) * 0.6, math.sin(a) * 0.6, z), material=dark)
    # Twisted posts.
    for i in range(3):
        a = 2 * math.pi * i / 3 + math.pi / 2 + 0.35
        pts = []
        for j in range(9):
            t = j / 8
            r = 0.5 + 0.03 * math.sin(t * math.pi * 4)
            pts.append((math.cos(a) * r, math.sin(a) * r, -0.9 + 1.8 * t))
        sb.ptube(f"post{i}", root, pts, [0.04 + 0.015 * abs(math.sin(j * 1.3)) for j in range(9)], sides=6,
                 material=bronze)
    # Glass bulbs.
    prof = []
    for j in range(17):
        t = j / 16
        z = -0.86 + 1.72 * t
        r = 0.05 + 0.37 * abs(math.sin(math.pi * t)) ** 0.7 if abs(t - 0.5) > 0.02 else 0.05
        prof.append((r, z))
    prof[0] = (0.0, -0.86)
    prof[-1] = (0.0, 0.86)
    sb.lathe("glass", root, prof, 28, glass)
    # Top: remaining embers (a shallow cone); stream; bottom: the heap.
    sb.lathe("sand_top", root, [(0.0, 0.08), (0.12, 0.18), (0.3, 0.38), (0.0, 0.42)], 20, sand)
    sb.cylinder("stream", root, r1=0.018, r2=0.018, depth=0.66, loc=(0, 0, -0.62), material=hot, segments=8)
    sb.lathe("sand_bot", root, [(0.0, -0.84), (0.34, -0.82), (0.24, -0.66), (0.0, -0.52)], 20, sand)
    for i in range(16):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.05, 0.85)
        sb.sphere(f"spark{i}", root, rnd.uniform(0.012, 0.026),
                  loc=(math.cos(a) * r, -0.5 + rnd.uniform(-0.1, 0.1), rnd.uniform(-0.9, 1.1)), material=hot)
    return root
