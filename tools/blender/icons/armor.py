"""Obsidian Hide: a kite-shaped plate of overlapping volcanic-glass scales."""
import math
import random
import sb
import _ikit as k

ACCENT = (0.62, 0.55, 0.95)
VIEW = {"pitch": 8, "yaw": -6, "fill": 0.84, "key": 1.6, "exposure": 0.6}


def build():
    obsidian = sb.mat("I_Obsidian", (0.02, 0.018, 0.025), roughness=0.08, metallic=0.2)
    obsidian2 = sb.mat("I_Obsidian2", (0.09, 0.07, 0.11), roughness=0.18, metallic=0.2)
    frame = k.metal("I_PlateIron", (0.14, 0.12, 0.12), 0.4)
    seam = k.glow("I_Seam", (0.7, 0.35, 1.0), 0.9)
    root = sb.root("ScalePlate")
    rnd = random.Random(21)

    # Kite-shaped backing plate.
    kite = [(0.0, -1.2), (0.62, -0.2), (0.7, 0.55), (0.45, 0.95), (0.0, 1.05), (-0.45, 0.95), (-0.7, 0.55),
            (-0.62, -0.2)]
    sb.extrude_outline("plate", root, kite, 0.08, frame, loc=(0, 0.06, 0), rot=(90, 0, 0), bevel=0.03)
    # Scales: rows of pointed ovals, each overlapping the one below, slightly tilted out.
    scale_ol = []
    for i in range(14):
        a = 2 * math.pi * i / 14
        x = math.sin(a) * 0.15
        y = -math.cos(a) * 0.2
        if y < 0:
            x *= 1.0 - (-y / 0.2) * 0.5
            y *= 1.25
        scale_ol.append((x, y))
    rows = [(0.85, 4), (0.6, 5), (0.35, 5), (0.1, 5), (-0.15, 4), (-0.4, 3), (-0.65, 2)]
    for ri, (z, n) in enumerate(rows):
        for i in range(n):
            x = (i - (n - 1) / 2) * 0.26 + (0.0 if ri % 2 else 0.0)
            # Clip to the kite silhouette.
            mat = obsidian if (i + ri) % 3 else obsidian2
            sb.extrude_outline(f"s{ri}_{i}", root, scale_ol, 0.04, mat,
                               loc=(x, -0.02 - 0.03 * ri, z), rot=(90 - 14 + rnd.uniform(-3, 3), rnd.uniform(-4, 4), 0),
                               bevel=0.015)
    # Glowing seam down the middle and a boss at the top.
    sb.ptube("seam", root, [(0, -0.3, 1.0), (0, -0.33, -0.2), (0, -0.25, -0.95)], [0.012, 0.012, 0.006], sides=5,
             material=seam)
    sb.sphere("boss", root, 0.11, loc=(0, -0.08, 1.0), scale=(1, 0.6, 1), material=frame)
    return root
