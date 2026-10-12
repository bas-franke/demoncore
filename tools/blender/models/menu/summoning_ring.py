"""Summoning-circle stone floor ring around the sigil (inner radius 2.12, outer 2.85): a raised
inner kerb with a faintly glowing groove, an annulus of worn, slightly uneven curved flagstones,
and four carved cardinal rune-blocks. Origin = floor centre; top of the flags at ~z 0.06."""
import math
import os
import random
import sys
sys.path.insert(0, os.path.dirname(__file__))
import sb  # noqa: E402
import _kit as kit  # noqa: E402

CATEGORY = "menu"
R0, R1 = 2.12, 2.85


def sector(name, parent, mat, r0, r1, a0, a1, z0, z1, steps=3, tilt=(0.0, 0.0)):
    verts, faces = [], []
    for i in range(steps + 1):
        a = a0 + (a1 - a0) * i / steps
        c, s = math.cos(a), math.sin(a)
        for r in (r0, r1):
            for z in (z0, z1):
                zz = z + (tilt[0] * (r - (r0 + r1) / 2) + tilt[1] * (i / steps - 0.5)) * (1 if z == z1 else 0)
                verts.append((c * r, s * r, zz))
    # per step 4 verts: (r0,z0)=0 (r0,z1)=1 (r1,z0)=2 (r1,z1)=3
    for i in range(steps):
        a, b = i * 4, (i + 1) * 4
        faces.append([a + 1, a + 3, b + 3, b + 1])  # top
        faces.append([a + 0, b + 0, b + 2, a + 2])  # bottom
        faces.append([a + 2, b + 2, b + 3, a + 3])  # outer
        faces.append([a + 0, a + 1, b + 1, b + 0])  # inner
    e = steps * 4
    faces.append([0, 2, 3, 1])
    faces.append([e + 0, e + 1, e + 3, e + 2])
    o = sb.mesh_from(name, parent, verts, faces, mat)
    bv = o.modifiers.new("Bevel", "BEVEL")
    bv.width = 0.015
    bv.segments = 1
    return o


def build():
    m = kit.mats()
    root = sb.root("SummoningRing")
    rnd = random.Random(21)
    n = 18
    for k in range(n):
        a0 = 2 * math.pi * k / n + 0.006
        a1 = 2 * math.pi * (k + 1) / n - 0.006
        mat = m["stone"] if rnd.random() > 0.3 else m["stone_dark"]
        sector(f"flag{k}", root, mat, R0 + 0.16, R1, a0, a1, -0.1, 0.05 + rnd.uniform(-0.012, 0.012),
               tilt=(rnd.uniform(-0.02, 0.02), rnd.uniform(-0.015, 0.015)))
    # Inner kerb: raised marble ring with a glowing groove cut along its top.
    for k in range(24):
        a0 = 2 * math.pi * k / 24 + 0.004
        a1 = 2 * math.pi * (k + 1) / 24 - 0.004
        sector(f"kerb{k}", root, m["marble"], R0, R0 + 0.06, a0, a1, -0.05, 0.09, steps=2)
        sector(f"kerb_o{k}", root, m["marble"], R0 + 0.1, R0 + 0.16, a0, a1, -0.05, 0.09, steps=2)
    sb.lathe("groove", root, [(R0 + 0.06, 0.05), (R0 + 0.1, 0.05), (R0 + 0.1, 0.06), (R0 + 0.06, 0.06)], segments=72,
             material=m["rune"], smooth=False, caps=False)
    sb.lathe("groove_floor", root, [(R0 + 0.06, 0.0), (R0 + 0.1, 0.0), (R0 + 0.1, 0.05), (R0 + 0.06, 0.05)],
             segments=36, material=m["obsidian"], smooth=False, caps=False)
    # Cardinal rune blocks on the outer flags.
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        g = sb.empty(f"cardinal{k}", root, loc=(math.cos(a) * 2.55, math.sin(a) * 2.55, 0.05), rot=(0, 0, math.degrees(a) + 90))
        sb.box("block", g, size=(0.34, 0.22, 0.16), loc=(0, 0, 0.08), material=m["stone"], bevel=0.03, taper=(0.85, 0.85))
        sb.ptube("glyph_a", g, [(-0.08, -0.03, 0.165), (0.0, 0.05, 0.165), (0.08, -0.03, 0.165)], [0.012] * 3, sides=4,
                 material=m["rune"], smooth=False)
        sb.ptube("glyph_b", g, [(0.0, 0.05, 0.165), (0.0, -0.07, 0.165)], [0.012] * 2, sides=4, material=m["rune"],
                 smooth=False)
    sb.join_meshes(root, "ring")
    sb.tri_count(root)
    return root
