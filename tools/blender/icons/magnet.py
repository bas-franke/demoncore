"""Soul Hunger: a ringed, many-toothed maw opening into darkness, drinking in pale souls."""
import math
import random
import sb
import _ikit as k

ACCENT = (0.55, 0.75, 0.95)
VIEW = {"pitch": 6, "yaw": -12, "fill": 0.9}


def build():
    flesh = sb.mat("I_MawFlesh", (0.12, 0.04, 0.045), roughness=0.5)
    gum = sb.mat("I_Gum", (0.35, 0.08, 0.1), roughness=0.35)
    tooth = sb.mat("I_Tooth", (0.62, 0.56, 0.45), roughness=0.4)
    void = sb.mat("I_Void", (0.0, 0.0, 0.0), roughness=1.0)
    soul = k.glow("I_Soul", (0.6, 0.85, 1.0), 1.3)
    soul_d = k.glow("I_SoulDim", (0.3, 0.5, 0.8), 0.9)
    root = sb.root("Maw")
    rnd = random.Random(14)

    # The maw faces the camera (-Y): fleshy lip ring, inner gum ring, a dark throat.
    lip = sb.torus("lip", root, 0.62, 0.17, loc=(0, 0, 0), rot=(90, 0, 0), material=flesh, major_segments=48,
                   minor_segments=14)
    sb.displace(lip, 0.08, 0.25)
    for i in range(12):
        a = 2 * math.pi * i / 12 + 0.1
        sb.sphere(f"lobe{i}", root, 0.2, loc=(math.cos(a) * 0.68, -0.05, math.sin(a) * 0.68),
                  rot=(0, -math.degrees(a), 0), scale=(1.0, 0.9, 1.5 + 0.3 * (i % 2)), material=flesh)
    sb.torus("gum", root, 0.48, 0.1, loc=(0, 0.1, 0), rot=(90, 0, 0), material=gum, major_segments=40)
    sb.sphere("throat", root, 0.5, loc=(0, 0.35, 0), scale=(1, 0.6, 1), material=void)
    for s in (-1, 1):
        sb.sphere(f"lipfold{s}", root, 0.2, loc=(0.6 * s, 0.1, 0.1), scale=(0.7, 0.7, 1.2), material=flesh)
    # Two rings of teeth pointing inward.
    for ring, (r, n, ln, y) in enumerate(((0.52, 18, 0.2, -0.02), (0.38, 14, 0.15, 0.15))):
        for i in range(n):
            a = 2 * math.pi * i / n + ring * 0.2
            base = (math.cos(a) * r, y, math.sin(a) * r)
            d = (-math.cos(a), 0.35, -math.sin(a))
            k.spike(f"t{ring}_{i}", root, base, d, ln * rnd.uniform(0.8, 1.2), 0.04, tooth, segments=5)
    # Souls spiralling in from outside.
    for i in range(6):
        a0 = 2 * math.pi * i / 6 + 0.3
        pts = []
        for j in range(10):
            t = j / 9
            r = 1.25 - t * 1.0
            a = a0 + t * 1.6
            pts.append((math.cos(a) * r, -0.5 * (1 - t) + 0.25 * t, math.sin(a) * r))
        sb.ptube(f"soul{i}", root, pts, [0.012 + 0.05 * math.sin(t * math.pi) for t in (j / 9 for j in range(10))],
                 sides=6, material=soul if i % 2 else soul_d)
        sb.sphere(f"head{i}", root, 0.06, loc=pts[1], material=soul)
    return root
