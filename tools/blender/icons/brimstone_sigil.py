"""Brimstone Sigil: a weathered rune stone, its carved sigil welling with sulphur fire."""
import math
import random
import sb
import _ikit as k

ACCENT = (1.0, 0.36, 0.08)
VIEW = {"pitch": 8, "yaw": -16, "fill": 0.84}


def build():
    stone = sb.mat("I_Stone", (0.16, 0.14, 0.13), roughness=0.9)
    moss = sb.mat("I_Soot", (0.05, 0.04, 0.035), roughness=1.0)
    rune = k.glow("I_Rune", (1.0, 0.3, 0.04), 1.4)
    core = k.glow("I_RuneCore", (1.0, 0.6, 0.25), 1.6)
    root = sb.root("RuneStone")
    rnd = random.Random(5)
    sb.stone_block("slab", root, (1.0, 0.42, 1.5), stone, rnd, loc=(0, 0, 0), chips=4, chip_depth=0.22,
                   cracks=2, noise=0.03, step=0.12, taper=(0.82, 0.85))
    sb.sphere("soot", root, 0.5, loc=(0, 0.1, 0.62), scale=(1.0, 0.5, 0.35), material=moss)
    # Sigil on the front face (y ~ -0.21): circle, inverted triangle, a cross-stroke and ticks.
    fy = -0.225
    cz = 0.05
    n = 28
    ring = [(math.cos(2 * math.pi * i / n) * 0.3, fy, cz + math.sin(2 * math.pi * i / n) * 0.3) for i in range(n + 1)]
    sb.ptube("ring", root, ring, [0.022] * (n + 1), sides=5, material=rune)
    tri = [(0.0, fy, cz - 0.42), (0.36, fy, cz + 0.24), (-0.36, fy, cz + 0.24), (0.0, fy, cz - 0.42)]
    sb.ptube("tri", root, tri, [0.026] * 4, sides=5, material=rune)
    sb.ptube("bar", root, [(0, fy, cz + 0.5), (0, fy, cz - 0.55)], [0.024, 0.02], sides=5, material=rune)
    sb.ptube("hook", root, [(-0.18, fy, cz - 0.55), (0, fy, cz - 0.55), (0.12, fy, cz - 0.46)], [0.02] * 3,
             sides=5, material=rune)
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.3
        p0 = (math.cos(a) * 0.34, fy, cz + math.sin(a) * 0.34)
        p1 = (math.cos(a) * 0.43, fy, cz + math.sin(a) * 0.43)
        sb.ptube(f"tick{i}", root, [p0, p1], [0.016, 0.012], sides=4, material=rune)
    sb.sphere("eye", root, 0.06, loc=(0, fy - 0.01, cz + 0.02), material=core)
    # Smouldering cinders around the foot.
    for i in range(9):
        sb.sphere(f"cinder{i}", root, rnd.uniform(0.015, 0.03),
                  loc=(rnd.uniform(-0.6, 0.6), rnd.uniform(-0.4, 0.1), rnd.uniform(-0.6, 0.9)), material=rune)
    return root
