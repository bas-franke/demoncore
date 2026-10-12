"""Dominion: a black-iron crown of uneven spires, set with violet stones."""
import math
import random
import sb
import _ikit as k

ACCENT = (0.62, 0.38, 0.9)
VIEW = {"pitch": 18, "yaw": -8, "fill": 0.9, "exposure": 0.6, "key": 1.3}


def build():
    iron = k.metal("I_CrownIron", (0.12, 0.1, 0.11), 0.35)
    gold = k.metal("I_OldGold", (0.48, 0.34, 0.14), 0.3)
    gem = sb.mat("I_Amethyst", (0.3, 0.08, 0.45), roughness=0.1, emission=(0.6, 0.25, 1.0), strength=1.3)
    root = sb.root("Crown")
    rnd = random.Random(12)

    # Band (hollow) with gold rims.
    sb.lathe("band", root, [(0.78, 0.0), (0.8, 0.02), (0.8, 0.34), (0.74, 0.34), (0.72, 0.02), (0.74, 0.0)], 48,
             iron)
    sb.torus("rim_lo", root, 0.8, 0.035, loc=(0, 0, 0.02), material=gold, major_segments=48)
    sb.torus("rim_hi", root, 0.8, 0.03, loc=(0, 0, 0.33), material=gold, major_segments=48)
    # Spires: tallest at the front, alternating heights.
    n = 11
    for i in range(n):
        a = -math.pi / 2 + 2 * math.pi * i / n
        front = (1.0 + math.cos(a + math.pi / 2)) * 0.5  # 1 at front (-Y)
        h = (0.55 if i % 2 == 0 else 0.32) + 0.5 * front ** 2 + rnd.uniform(-0.04, 0.04)
        x, y = math.cos(a) * 0.77, math.sin(a) * 0.77
        sp = sb.lathe(f"spire{i}", root, [(0.0, 0.0), (0.1, 0.0), (0.07, h * 0.55), (0.0, h)], 4, iron,
                      loc=(x, y, 0.3), rot=(0, 0, math.degrees(a) + 45))
        # lean outward a touch
        sp.rotation_euler.rotate_axis("X", 0.0)
        if i % 2 == 0:
            sb.sphere(f"orb{i}", root, 0.05, loc=(x * 1.02, y * 1.02, 0.3 + h * 0.5), material=gold)
    # Stones around the band, the front one large.
    for i in range(8):
        a = -math.pi / 2 + 2 * math.pi * i / 8
        big = i == 0
        sb.sphere(f"gem{i}", root, 0.11 if big else 0.06,
                  loc=(math.cos(a) * 0.82, math.sin(a) * 0.82, 0.18), scale=(1, 0.6, 1.3 if big else 1),
                  material=gem)
        sb.torus(f"set{i}", root, 0.11 if big else 0.065, 0.018, loc=(math.cos(a) * 0.81, math.sin(a) * 0.81, 0.18),
                 rot=(90, 0, math.degrees(a) + 90), material=gold)
    return root
