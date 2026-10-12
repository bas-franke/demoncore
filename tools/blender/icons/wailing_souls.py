"""Wailing Souls: a pale cracked funeral mask, mouth open in an endless wail, souls streaming off it."""
import math
import random
import sb
import _ikit as k

ACCENT = (0.85, 0.25, 0.75)
VIEW = {"pitch": 4, "yaw": -14, "fill": 0.88}


def build():
    porcelain = sb.mat("I_Porcelain", (0.4, 0.37, 0.33), roughness=0.45)
    void = sb.mat("I_Void", (0.0, 0.0, 0.0), roughness=1.0)
    crack = sb.mat("I_Crack", (0.05, 0.02, 0.04), roughness=1.0)
    tear = k.glow("I_Tear", (0.9, 0.3, 0.8), 1.6)
    soul = k.glow("I_Soul", (0.75, 0.25, 0.7), 0.75)
    soul_d = k.glow("I_SoulDeep", (0.5, 0.06, 0.4), 0.7)
    root = sb.root("Mask")
    rnd = random.Random(9)

    k.shell("mask", root, 0.5, (0.78, 0.5, 1.0), 0.02, 0.04, porcelain)
    # Sorrowful eye holes (slanting down at the outer corners) and the long screaming mouth.
    for s in (-1, 1):
        sb.sphere(f"eye{s}", root, 0.12, loc=(0.17 * s, -0.42, 0.12), rot=(0, 26 * s, 0), scale=(1.25, 0.5, 0.55),
                  material=void)
        sb.sphere(f"glint{s}", root, 0.03, loc=(0.17 * s, -0.43, 0.1), material=tear)
        sb.box(f"brow{s}", root, (0.26, 0.08, 0.05), loc=(0.17 * s, -0.43, 0.27), rot=(0, -22 * s, 0),
               material=porcelain, bevel=0.02, subdiv=1)
        # A glowing tear track down each cheek.
        sb.ptube(f"tear{s}", root, [(0.2 * s, -0.43, 0.04), (0.22 * s, -0.42, -0.12), (0.2 * s, -0.36, -0.32)],
                 [0.016, 0.014, 0.006], sides=5, material=tear)
    sb.sphere("mouth", root, 0.12, loc=(0, -0.43, -0.3), scale=(0.75, 0.5, 1.45), material=void)
    sb.sphere("nose", root, 0.06, loc=(0, -0.49, -0.04), scale=(0.7, 0.8, 1.5), material=porcelain)
    # Hairline cracks.
    for c in range(4):
        x0 = rnd.uniform(-0.25, 0.25)
        pts = [(x0, -0.36, 0.48)]
        for j in range(3):
            px, py, pz = pts[-1]
            pts.append((px + rnd.uniform(-0.08, 0.08), -0.42 if pz > 0.0 else -0.44, pz - 0.14))
        sb.ptube(f"crack{c}", root, pts, [0.008, 0.01, 0.007, 0.003], sides=4, material=crack)
    # Souls: translucent ghost streams torn off the mask, all swept up and to the right as if by a gale.
    soul_a = k.ghost("I_SoulGhost", (0.85, 0.35, 0.8), 1.1, 0.55)
    soul_b = k.ghost("I_SoulGhostDeep", (0.6, 0.1, 0.5), 0.9, 0.5)
    for i in range(5):
        z0 = 0.35 - i * 0.22
        pts = []
        for j in range(9):
            t = j / 8
            pts.append((0.3 + t * 0.95 - 0.1 * i * t, 0.25 + 0.1 * t, z0 + t * (0.55 + 0.1 * i) + 0.08 * math.sin(t * 7 + i)))
        sb.ptube(f"soul{i}", root, pts, [0.13 * (1 - j / 9) ** 1.2 + 0.006 for j in range(9)], sides=8,
                 material=soul_a if i % 2 == 0 else soul_b)
    for i in range(3):
        sb.ptube(f"souL{i}", root, [(-0.3, 0.25, 0.3 - i * 0.3), (-0.55, 0.3, 0.45 - i * 0.25),
                                    (-0.8, 0.35, 0.75 - i * 0.2)], [0.08, 0.05, 0.01], sides=8, material=soul_b)
    return root
