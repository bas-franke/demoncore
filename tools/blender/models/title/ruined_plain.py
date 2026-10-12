"""The ruined plain under the broken sky: an ash-dark battlefield of low dunes rising to jagged
ridges on the horizon, strewn with broken columns, toppled masonry and the great swords of fallen
angels driven into the earth. Hellfire fissures glow through the ground in the foreground.

Laid out in TITLE-SCENE coordinates (Blender (x, y, z) -> Godot (x, z, -y)): the camera sits near
Blender (0, -30, 7) looking along +Y; the colossus kneels at (26, 55); the pillar of light falls at
(-34, 260). The ground is a graded grid, denser near the camera.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _title_kit as K  # noqa: E402
import sb  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

CATEGORY = "title"

X0, X1 = -420.0, 420.0
Y0, Y1 = -90.0, 560.0
CLEAR = [((26.0, 55.0), 26.0), ((-34.0, 260.0), 34.0), ((0.0, -30.0), 14.0)]


def height(x, y):
    p = Vector((x * 0.018, y * 0.018, 0.3))
    h = noise.noise(p) * 2.2 + noise.noise(p * 2.7 + Vector((3.1, 1.7, 0.0))) * 0.8
    h += noise.noise(Vector((x * 0.07, y * 0.07, 5.0))) * 0.35
    dist = max(0.0, y)
    h *= 0.6 + dist / 160.0
    for (cx, cy), r in CLEAR:
        d = math.hypot(x - cx, y - cy)
        if d < r:
            h *= (d / r) ** 1.5
    # horizon ridges: jagged mountains past ~300 m, and walls closing the sides
    ridge = max(0.0, (y - 290.0) / 220.0)
    side = max(0.0, (abs(x) - 230.0) / 160.0)
    m = max(ridge, side * 0.8)
    if m > 0.0:
        q = Vector((x * 0.012, y * 0.012, 9.0))
        jag = 0.55 + 0.45 * noise.noise(q) + 0.35 * abs(noise.noise(q * 3.3 + Vector((1.0, 2.0, 0.0))))
        h += (m ** 1.4) * 95.0 * max(0.15, jag)
    return h


def ground():
    nx, ny = 110, 96
    xs = []
    for i in range(nx + 1):
        u = i / nx * 2.0 - 1.0
        xs.append(math.copysign(abs(u) ** 1.7, u) * X1)
    ys = [Y0 + (Y1 - Y0) * (j / ny) ** 1.6 for j in range(ny + 1)]
    bm = bmesh.new()
    rows = []
    for y in ys:
        rows.append([bm.verts.new((x, y, height(x, y))) for x in xs])
    for a, b in zip(rows[:-1], rows[1:]):
        for i in range(nx):
            bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    return sb.bm_obj("ground", None, bm, K.M("Title_AshRock"), sharp=0.0)


def fissure(name, parent, rng, start, heading, length, width):
    """Meandering glowing crack in the ground (a thin tube sunk into the surface)."""
    pts, radii = [], []
    x, y = start
    a = math.radians(heading)
    n = int(length / 1.5)
    for i in range(n + 1):
        t = i / n
        pts.append((x, y, height(x, y) - width * 0.3))
        radii.append(width * (0.15 + 0.55 * math.sin(math.pi * t)))
        a += rng.uniform(-0.5, 0.5)
        x += math.cos(a) * 1.5
        y += math.sin(a) * 1.5
    sb.ptube(name, parent, pts, radii, sides=4, material=K.M("Title_Ember"))
    # charred rim
    for i in range(0, len(pts), 3):
        p = pts[i]
        if rng.random() < 0.6:
            K.rock(f"{name}_rim{i}", parent, rng, (width * 3, width * 2, width * 1.2),
                   loc=(p[0] + rng.uniform(-1, 1) * width * 2, p[1] + rng.uniform(-1, 1) * width * 2, p[2]),
                   rot=(0, 0, rng.uniform(0, 360)), mat="Title_AshRock")


def place(x, y, sink=0.2):
    return (x, y, height(x, y) - sink)


def ruins(root, rng):
    # columns: standing broken shafts, scattered along a lost colonnade that leads to the colossus
    for i in range(9):
        x = -18.0 + i * 0.0 + rng.uniform(-2, 2) + (i % 2) * 36.0
        y = 6.0 + (i // 2) * 22.0 + rng.uniform(-3, 3)
        h = rng.uniform(3.0, 11.0)
        K.column(f"col{i}", root, rng, rng.uniform(0.8, 1.1), h, loc=place(x, y, 0.3),
                 rot=(rng.uniform(-6, 6), rng.uniform(-6, 6), rng.uniform(0, 360)), flutes=8,
                 broken_top=rng.uniform(0.6, 1.6))
        K.block(f"colbase{i}", root, rng, (2.8, 2.8, 0.9), loc=place(x, y, 0.1), chips=3)
    # toppled column drums lying in the dust
    for i in range(6):
        x = rng.uniform(-60, 60)
        y = rng.uniform(5, 110)
        if math.hypot(x - 26, y - 55) < 22 or abs(x) < 8 and y < 20:
            continue
        K.column(f"fall{i}", root, rng, 0.9, rng.uniform(2.5, 6.0), loc=place(x, y, -0.5),
                 rot=(90 + rng.uniform(-5, 5), 0, rng.uniform(0, 360)), flutes=8, broken_top=0.8)
    # a ruined wall with a gothic window, midground left
    w = sb.empty("wall", root, place(-46, 70, 0.5), (0, 0, 18))
    for i, (x, h) in enumerate(((-9, 14), (-5.5, 18), (5.5, 12), (9, 7))):
        K.block(f"wpier{i}", w, rng, (3.5, 2.6, h), loc=(x, 0, h * 0.5), chips=3, cracks=1)
    K.pointed_arch(w, rng, 0.0, 12.0, 8.0, 1.4, 2.4, tag="warch", pieces=3, drop=(4, 5))
    K.block("wsill", w, rng, (11.0, 2.8, 1.2), loc=(0, 0, 3.0), chips=3)
    K.block("wlow", w, rng, (11.0, 2.4, 3.0), loc=(0, 0, 1.5), chips=2)
    # field of great swords: blades of fallen angels driven into the ground
    for i in range(26):
        x = rng.uniform(-90, 90)
        y = rng.uniform(-6, 150)
        if math.hypot(x - 26, y - 55) < 20 or (abs(x) < 9 and y < 4):
            continue
        L = rng.uniform(4.0, 9.0)
        K.sword(f"sw{i}", root, rng, L, L * 0.09, place(x, y, L * rng.uniform(0.15, 0.4)),
                (rng.uniform(-22, 22), rng.uniform(-22, 22), rng.uniform(0, 360)), broken=rng.random() < 0.3)
    # gravestone slabs / fallen tablets
    for i in range(14):
        x = rng.uniform(-50, 50)
        y = rng.uniform(-8, 60)
        if abs(x) < 7 and y < 6:
            continue
        s = rng.uniform(0.8, 1.6)
        K.block(f"slab{i}", root, rng, (1.4 * s, 0.4 * s, 2.2 * s), loc=place(x, y, 0.4),
                rot=(rng.uniform(-25, 25), rng.uniform(-15, 15), rng.uniform(0, 360)), chips=3)
    # rubble & boulders
    for i in range(40):
        x = rng.uniform(-110, 110)
        y = rng.uniform(-20, 220)
        if abs(x) < 6 and y < -10:
            continue
        s = rng.uniform(0.6, 3.5) * (1.0 + max(0.0, y) / 120.0)
        K.rock(f"rock{i}", root, rng, (s * 1.4, s, s * 0.7), loc=place(x, y, s * 0.15),
               rot=(0, 0, rng.uniform(0, 360)), mat="Title_AshRock" if i % 3 else "Title_Marble")


def build():
    root = sb.root("RuinedPlain")
    rng = K.rng_for(31)
    g = ground()
    g.parent = root
    r = sb.empty("ruins", root)
    ruins(r, rng)
    sb.join_meshes(r, "ruins_mesh")
    f = sb.empty("fissures", root)
    for i, (sx, sy, hd, L, wd) in enumerate(((-14, -8, 60, 40, 0.35), (12, -2, 120, 34, 0.3),
                                             (-30, 20, 20, 50, 0.45), (6, 24, 75, 44, 0.4),
                                             (40, 10, 150, 30, 0.3), (-8, -16, 10, 22, 0.25))):
        fissure(f"fis{i}", f, rng, (sx, sy), hd, L, wd)
    sb.join_meshes(f, "fissures_mesh")
    sb.tri_count(root)
    return root
