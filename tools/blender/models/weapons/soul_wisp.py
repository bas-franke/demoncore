"""Wailing Souls: a spectral howling death-mask with a torn, streaming shroud.
Faces -Y (Godot -Z = along the orbit). The 'Spirit' materials are re-tinted per soul and drawn
as additive glow in Godot; the mask is pale bone lit from within (dark eye/mouth holes)."""
import math
import os
import random
import sb
from mathutils import Vector

CATEGORY = "weapons"


def build():
    mask = sb.mat("Soul_BoneMask", (0.82, 0.76, 0.7), roughness=0.5, emission=(0.9, 0.55, 0.6), strength=0.35)
    hole = sb.mat("Soul_Void", (0.01, 0.0, 0.01), roughness=1.0)
    eyes = sb.mat("Soul_SpiritEyes", (1.0, 0.8, 0.85), roughness=0.5, emission=(1.0, 0.85, 0.9), strength=8.0)
    shroud = sb.mat("Soul_SpiritShroud", (0.8, 0.15, 0.3), roughness=0.5, emission=(0.8, 0.15, 0.3), strength=2.0)
    root = sb.root("SoulWisp")
    if os.environ.get("SB_LIFT"):
        root.location = (0, 0, 0.4)

    # Mask: a shallow elongated shell (front half of a stretched sphere), facing -Y.
    bm_r = 0.16
    o = sb.sphere("mask", root, radius=bm_r, loc=(0, 0, 0), scale=(0.78, 0.55, 1.12), material=mask,
                  segments=14, rings=10)
    # Long howling mouth, hollow eye sockets, a cracked brow.
    sb.sphere("mouth", root, radius=0.05, loc=(0, -0.075, -0.075), scale=(0.62, 0.4, 1.5), material=hole,
              segments=8, rings=6)
    for s in (-1, 1):
        sb.sphere(f"socket{s}", root, radius=0.04, loc=(0.052 * s, -0.072, 0.045), rot=(0, -25 * s, 0),
                  scale=(1.0, 0.45, 0.72), material=hole, segments=8, rings=6)
        sb.sphere(f"eye{s}", root, radius=0.014, loc=(0.05 * s, -0.088, 0.04), material=eyes, segments=6, rings=4)
        # Sunken cheeks: ridges running down to the jaw.
        sb.ptube(f"cheek{s}", root, [(0.085 * s, -0.04, 0.03), (0.08 * s, -0.06, -0.05), (0.05 * s, -0.07, -0.15)],
                 [0.012, 0.016, 0.006], sides=5, material=mask)
    sb.ptube("brow", root, [(-0.1, -0.05, 0.09), (-0.03, -0.085, 0.085), (0.03, -0.085, 0.085), (0.1, -0.05, 0.09)],
             [0.008, 0.016, 0.016, 0.008], sides=5, material=mask)
    sb.ptube("crack", root, [(0.02, -0.088, 0.17), (0.035, -0.09, 0.12), (0.02, -0.092, 0.095)],
             [0.004, 0.006, 0.003], sides=4, material=hole)

    # Hood-shroud behind the mask, tearing into three streaming tails (+Y = trailing).
    rnd = random.Random(4)
    hood_prof = [(0.0, 0.0)]
    sb.sphere("hood", root, radius=0.15, loc=(0, 0.1, 0.03), scale=(1.0, 0.9, 1.15), material=shroud,
              segments=12, rings=8)
    for k, (x, z, ln) in enumerate(((-0.09, -0.02, 0.55), (0.0, 0.08, 0.7), (0.1, -0.05, 0.5), (0.02, -0.12, 0.42))):
        pts, rad = [], []
        for j in range(6):
            u = j / 5
            pts.append((x * (1 + u) + math.sin(u * 5 + k) * 0.04, 0.12 + u * ln, z + math.sin(u * 4 + k * 2) * 0.05 - u * 0.05))
            rad.append(0.075 * (1 - u) + 0.008)
        sb.ptube(f"tail{k}", root, pts, rad, sides=6, material=shroud)
    sb.join_meshes(root, "soul_wisp")
    sb.tri_count(root)
    return root
