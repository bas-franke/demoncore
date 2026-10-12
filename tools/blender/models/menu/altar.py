"""Gothic sacrificial altar for the select-screen ritual chamber: stepped platform, a marble block
carved with a blind arcade of pointed niches between colonnettes and buttressed corners, moulded
top slab, a torn crimson runner, a pile of skulls, candles, and a great iron candelabrum behind.
Front = Blender -Y (Godot -Z): demon_select.gd yaws it by PI so the front faces the camera.
Origin = floor centre."""
import math
import os
import random
import sys
sys.path.insert(0, os.path.dirname(__file__))
import sb  # noqa: E402
import _kit as kit  # noqa: E402

CATEGORY = "menu"


def runner(parent, m):
    """Torn cloth draped over the top slab and down the front."""
    rnd = random.Random(2)
    cols, rows = 6, 12
    w = 0.9
    verts, faces = [], []
    path = []
    for i in range(rows + 1):
        u = i / rows
        if u < 0.4:
            t = u / 0.4
            path.append((0.35 - 1.16 * t, 1.745))
        else:
            t = (u - 0.4) / 0.6
            path.append((-0.82 - 0.03 * t, 1.73 - 0.95 * t))
    for i, (y, z) in enumerate(path):
        for j in range(cols + 1):
            v = j / cols
            x = (v - 0.5) * w
            fold = math.sin(v * math.pi * 3) * 0.02 * (i / rows)
            zz = z
            if i == rows:
                zz += rnd.uniform(0.0, 0.25)  # torn hem
            verts.append((x, y - (fold if i > rows * 0.4 else 0), zz))
    for i in range(rows):
        for j in range(cols):
            a = i * (cols + 1) + j
            faces.append([a, a + 1, a + cols + 2, a + cols + 1])
    o = sb.mesh_from("runner", parent, verts, faces, m["cloth"], smooth=True)
    s = o.modifiers.new("Solid", "SOLIDIFY")
    s.thickness = 0.012
    return o


def build():
    m = kit.mats()
    root = sb.root("Altar")
    # Stepped platform.
    sb.box("step1", root, size=(5.0, 2.8, 0.3), loc=(0, -0.2, 0.15), material=m["stone_dark"], bevel=0.04)
    sb.box("step2", root, size=(4.2, 2.2, 0.25), loc=(0, 0, 0.42), material=m["stone"], bevel=0.035)
    # Altar block + mouldings.
    sb.box("base_mould", root, size=(3.45, 1.5, 0.12), loc=(0, 0, 0.6), material=m["marble"], bevel=0.04)
    sb.box("block", root, size=(3.2, 1.3, 0.95), loc=(0, 0, 1.1), material=m["marble"], bevel=0.02)
    sb.box("top_under", root, size=(3.4, 1.42, 0.08), loc=(0, 0, 1.6), material=m["marble"], bevel=0.03)
    sb.box("top", root, size=(3.6, 1.66, 0.12), loc=(0, 0, 1.68), material=m["marble"], bevel=0.045)
    # Corner buttresses.
    for sx in (-1, 1):
        for sy in (-1, 1):
            sb.box(f"butt{sx}{sy}", root, size=(0.32, 0.32, 0.95), loc=(sx * 1.55, sy * 0.6, 1.1), material=m["stone"],
                   bevel=0.03, taper=(0.82, 0.82))
    # Blind arcade on the front: 4 pointed niches (dark backs), colonnettes between.
    nw = 0.6
    for k in range(4):
        x = (k - 1.5) * 0.7
        sb.box(f"niche{k}", root, size=(nw - 0.04, 0.02, 0.62), loc=(x, -0.655, 1.0), material=m["obsidian"], bevel=0)
        outer, inner = kit.pointed_arch(nw * 0.5, 1.22, 1.5, 0.06)
        kit.band(outer, inner, 0.06, f"arch{k}", root, m["stone"], loc=(x, -0.67, 0))
    for k in range(5):
        x = (k - 2) * 0.7
        sb.cylinder(f"col{k}", root, r1=0.045, depth=0.62, loc=(x, -0.69, 0.66), material=m["stone"], segments=8, bevel=0)
        sb.box(f"capital{k}", root, size=(0.12, 0.1, 0.06), loc=(x, -0.69, 1.3), material=m["stone"], bevel=0.015)
        sb.box(f"plinthc{k}", root, size=(0.12, 0.1, 0.06), loc=(x, -0.69, 0.69), material=m["stone"], bevel=0.015)
    runner(root, m)
    # Skull pile on the slab (either side of the runner), a few stacked.
    rnd = random.Random(5)
    spots = [(-1.3, -0.3, 0), (-0.95, -0.4, 0), (-1.12, -0.34, 1), (-0.7, 0.2, 0), (0.85, -0.35, 0), (1.2, -0.3, 0),
             (1.02, -0.3, 1), (1.4, 0.25, 0)]
    for k, (x, y, lvl) in enumerate(spots):
        kit.skull(f"skull{k}", root, m, loc=(x, y, 1.74 + lvl * 0.22), rot=(rnd.uniform(-10, 10), 0, rnd.uniform(-35, 35)),
                  s=rnd.uniform(1.5, 1.75))
    # Candles on the slab.
    for k, (x, y) in enumerate(((-1.6, 0.55), (-1.45, 0.62), (1.55, 0.58), (1.62, 0.42), (-0.3, 0.55), (0.35, 0.6))):
        kit.candle(f"candle{k}", root, m, loc=(x, y, 1.74), h=rnd.uniform(0.14, 0.36), r=rnd.uniform(0.035, 0.055), seed=k)
    # Great iron candelabrum behind.
    cy = 0.9
    sb.cylinder("cb_pole", root, r1=0.055, r2=0.04, depth=2.85, loc=(0, cy, 0.55), material=m["iron"], segments=8, bevel=0)
    for a in range(3):
        ang = a * 2 * math.pi / 3 + 0.5
        sb.ptube(f"cb_foot{a}", root, [(0, cy, 0.9), (math.cos(ang) * 0.35, cy + math.sin(ang) * 0.35, 0.62),
                                       (math.cos(ang) * 0.48, cy + math.sin(ang) * 0.48, 0.56)], [0.04, 0.03, 0.025],
                 sides=6, material=m["iron"])
    sb.ptube("cb_bar", root, [(-1.25, cy, 3.6), (-1.15, cy, 3.4), (0, cy, 3.35), (1.15, cy, 3.4), (1.25, cy, 3.6)],
             [0.025, 0.035, 0.04, 0.035, 0.025], sides=6, material=m["iron"])
    for k, s in enumerate((-1.0, -0.5, 0.0, 0.5, 1.0)):
        x = s * 1.15
        z = 3.43 + (0.3 if s == 0 else 0.0) + (0.1 if abs(s) == 1.0 else 0.0)
        if s == 0:
            sb.cylinder("cb_top", root, r1=0.03, depth=0.32, loc=(0, cy, 3.4), material=m["iron"], segments=6, bevel=0)
        sb.lathe(f"cb_cup{k}", root, [(0.0, 0.0), (0.03, 0.0), (0.075, 0.06), (0.07, 0.075), (0.0, 0.07)], segments=8,
                 material=m["iron"], loc=(x, cy, z - 0.03))
        kit.candle(f"cb_candle{k}", root, m, loc=(x, cy, z + 0.04), h=0.3 + 0.05 * (k % 2), r=0.045, seed=20 + k)
    for sx in (-1, 1):
        sb.ptube(f"cb_curl{sx}", root, [(0, cy, 2.9), (sx * 0.4, cy, 3.0), (sx * 0.7, cy, 3.22), (sx * 0.6, cy, 3.36)],
                 [0.02, 0.022, 0.02, 0.015], sides=5, material=m["iron"])
    sb.join_meshes(root, "altar")
    sb.tri_count(root)
    return root
