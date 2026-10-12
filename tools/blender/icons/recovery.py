"""Blood Pact: a tarnished golden chalice brimming with blood, spilling over its lip."""
import math
import sb
import _ikit as k

ACCENT = (0.85, 0.12, 0.1)
VIEW = {"pitch": 16, "yaw": -10, "fill": 0.84}


def build():
    gold = k.metal("I_ChaliceGold", (0.52, 0.36, 0.15), 0.3)
    dark = k.metal("I_DarkGold", (0.18, 0.11, 0.05), 0.45)
    blood = sb.mat("I_Blood", (0.25, 0.01, 0.02), roughness=0.12, emission=(0.6, 0.02, 0.03), strength=0.5)
    gem = sb.mat("I_Ruby", (0.4, 0.02, 0.04), roughness=0.1, emission=(1.0, 0.1, 0.1), strength=1.2)
    root = sb.root("Chalice")

    sb.lathe("chalice", root, [
        (0.0, 0.0), (0.5, 0.0), (0.52, 0.05), (0.4, 0.12), (0.2, 0.2), (0.1, 0.35), (0.09, 0.55),
        (0.16, 0.62), (0.16, 0.7), (0.09, 0.78), (0.1, 0.9), (0.3, 0.98), (0.5, 1.12), (0.62, 1.35),
        (0.66, 1.62), (0.6, 1.62), (0.56, 1.38), (0.0, 1.2)], 40, gold)
    sb.torus("knot", root, 0.17, 0.05, loc=(0, 0, 0.66), material=dark)
    sb.torus("lipband", root, 0.645, 0.03, loc=(0, 0, 1.5), material=dark, major_segments=48)
    sb.torus("footband", root, 0.47, 0.03, loc=(0, 0, 0.07), material=dark, major_segments=48)
    sb.cylinder("surface", root, r1=0.6, depth=0.02, loc=(0, 0, 1.55), material=blood, segments=40)
    # Rubies around the bowl.
    for i in range(5):
        a = -math.pi / 2 + (i - 2) * 0.5
        sb.sphere(f"ruby{i}", root, 0.06, loc=(math.cos(a) * 0.6, math.sin(a) * 0.6, 1.27), scale=(1, 0.6, 1.2),
                  material=gem)
    # Overflow: rivulets down the bowl, pooling at the base.
    for i, (a, ln) in enumerate(((-1.75, 0.95), (-1.3, 0.55), (-2.1, 0.35))):
        pts = []
        for j in range(7):
            t = j / 6
            z = 1.62 - t * ln
            r = 0.68 - 0.25 * max(0.0, (1.35 - z)) * 1.2 if z > 1.0 else 0.4
            pts.append((math.cos(a) * r * 1.02, math.sin(a) * r * 1.02, z))
        sb.ptube(f"drip{i}", root, pts, [0.03, 0.028, 0.03, 0.026, 0.028, 0.03, 0.04], sides=6, material=blood)
        sb.sphere(f"drop{i}", root, 0.045, loc=pts[-1], scale=(1, 1, 1.3), material=blood)
    sb.cylinder("pool", root, r1=0.75, depth=0.01, loc=(-0.1, -0.15, 0.0), scale=(1.0, 0.7, 1.0), material=blood,
                segments=32)
    return root
