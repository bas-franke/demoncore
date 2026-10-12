"""Brimstone Sigil rune stones: three jagged obsidian monoliths, each carved with a burning
rune on its inward (-Y) face. Separate child meshes 'stone0..2' so the sigil can pick variants.
Base at z=0, ~0.55-0.75 m tall."""
import math
import os
import random
import sb

CATEGORY = "weapons"

RUNES = [
    [[(0, 0.0), (0, 0.32)], [(-0.07, 0.24), (0.07, 0.1)], [(-0.07, 0.08), (0.07, 0.08)]],
    [[(-0.06, 0.0), (0, 0.32), (0.06, 0.0)], [(-0.05, 0.16), (0.05, 0.16)]],
    [[(0, 0.0), (0, 0.32)], [(0, 0.32), (0.07, 0.24)], [(0, 0.2), (-0.07, 0.12)], [(0, 0.12), (0.07, 0.05)]],
]


def build():
    obs = sb.mat("Rune_ObsidianStone", (0.045, 0.04, 0.045), roughness=0.35)
    glow = sb.mat("Rune_FireGlow", (1.0, 0.4, 0.1), roughness=0.4, emission=(1.0, 0.32, 0.06), strength=7.0)
    root = sb.root("RuneStones")
    rnd = random.Random(9)
    for i in range(3):
        g = sb.empty(f"stone{i}", root, loc=(0 if not os.environ.get("SB_LIFT") else (i - 1) * 0.6, 0, 0))
        h = 0.55 + 0.1 * i
        w = 0.24 + 0.02 * i
        d = 0.15
        # Jagged monolith: a lathe-free hand-built prism with a broken, slanted crown.
        top_l = h * rnd.uniform(0.82, 0.95)
        top_r = h * rnd.uniform(0.95, 1.08)
        outline = [(-w * 0.5, 0), (w * 0.5, 0), (w * 0.44, top_r * 0.55), (w * 0.38, top_r),
                   (w * 0.05, h * 1.05 + 0.04), (-w * 0.2, top_l + 0.02), (-w * 0.42, top_l), (-w * 0.47, h * 0.5)]
        # extrude_outline works in XY, extruded along Z -> rotate so outline stands in XZ, depth along Y
        o = sb.extrude_outline("monolith", g, outline, d, obs, rot=(90, 0, 0), bevel=0.0)
        bv = o.modifiers.new("Bevel", "BEVEL")
        bv.width = 0.018
        bv.segments = 1
        # taper: narrower at the top
        for v in o.data.vertices:
            k = 1.0 - 0.25 * (v.co.y / (h + 0.05))
            v.co.x *= k
            v.co.z *= k
        # Carved rune strokes standing proud of the -Y face (glowing).
        for stroke in RUNES[i]:
            pts = [(x, -d * 0.5 * (1.0 - 0.25 * ((0.1 + z) / (h + 0.05))) - 0.004, 0.12 + z) for x, z in stroke]
            sb.ptube(f"rune{len(pts)}", g, pts, [0.012] * len(pts), sides=4, material=glow, smooth=False)
        # Glowing fracture at the foot.
        sb.box("foot_glow", g, size=(w * 0.9, d * 0.7, 0.03), loc=(0, 0, 0.015), material=glow, bevel=0)
        sb.join_meshes(g, f"stone{i}_mesh")
    sb.tri_count(root)
    return root
