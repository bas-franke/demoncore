"""Colossal fallen angel statue (~34 m): a robed angel kneeling on one knee, head bowed, both
hands on the pommel of a great sword driven into the earth. The left wing has snapped off and lies
shattered on the ground behind; the right wing still rises, broken at the tip. Its halo lies broken
in two at its knee. A crack through the chest still leaks a thread of holy gold.

Modeled at human scale (2 m) in bmesh, then scaled by S into real meters. Faces -Y.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _title_kit as K  # noqa: E402
import sb  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "title"
S = 16.0

ROOT = None
RNG = None


def put(name, bm, mat="Title_Marble", sharp=40.0, noise=0.006):
    if noise:
        sb.bm_noise(bm, noise, 6.0, seed=RNG.randrange(9999))
    sb.bm_xform(bm, scale=(S, S, S))
    return sb.bm_obj(name, ROOT, bm, K.M(mat), sharp=sharp)


def limb(name, pts, radii, sides=10, samples=3, mat="Title_Marble", sx=1.0, gnarl=0.0):
    bm = sb.bm_limb(pts, radii, sides=sides, samples=samples, rng=RNG, gnarl=gnarl)
    if sx != 1.0:
        c = Vector(pts[0])
        for v in bm.verts:
            v.co.x = c.x + (v.co.x - c.x) * sx
    return put(name, bm, mat)


def ellipsoid(name, center, size, mat="Title_Marble", seg=16, rings=10, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=0.5)
    sb.bm_xform(bm, loc=center, rot=rot, scale=size)
    return bm


def robe():
    """Draped robe from the waist to the ground, flared and folded, swept back behind the kneel."""
    def wob(a, t):
        return 1.0 + 0.07 * math.sin(a * 9.0 + t * 2.0) * t + 0.04 * math.sin(a * 5.0 + 1.0)
    prof = [(0.62, 0.0), (0.6, 0.06), (0.52, 0.2), (0.42, 0.38), (0.32, 0.56), (0.24, 0.7), (0.2, 0.8),
            (0.0, 0.84)]
    bm = sb.bm_lathe(prof, 28, wobble=wob)
    for v in bm.verts:
        # oval footprint, pushed back (the kneeling leg trails behind)
        v.co.x *= 0.95
        if v.co.y > 0:
            v.co.y *= 1.6
        else:
            v.co.y *= 0.85
    sb.bm_xform(bm, loc=(0, 0.12, 0))
    return bm


def wing_feathers(prefix, arm_pts, count, length0, length1, down, out, spread, mat="Title_Marble"):
    """Stone feathers hanging from a wing arm (polyline): pointing along `down`, fanning toward
    `out` by up to `spread` degrees at the tip."""
    down = Vector(down).normalized()
    out = Vector(out).normalized()
    pts = [Vector(p) for p in arm_pts]
    total = sum((b - a).length for a, b in zip(pts[:-1], pts[1:]))
    for i in range(count):
        t = (i + 0.5) / count
        # point along the polyline
        d = t * total
        p = pts[0]
        for a, b in zip(pts[:-1], pts[1:]):
            seg = (b - a).length
            if d <= seg:
                p = a + (b - a) * (d / seg)
                break
            d -= seg
        L = length0 + (length1 - length0) * t
        L *= RNG.uniform(0.85, 1.1)
        # feather direction: down and outward, fanning toward the tip
        phi = math.radians(spread * t + RNG.uniform(-4, 4))
        dirv = (down * math.cos(phi) + out * math.sin(phi)).normalized()
        bm = bmesh.new()
        steps = 4
        rows = []
        w = 0.07 + 0.03 * t
        th = 0.018
        for k in range(steps + 1):
            u = k / steps
            ww = w * (1.0 - u ** 1.8) + 0.004
            rows.append([bm.verts.new((-ww, -th, u)), bm.verts.new((ww, -th, u)),
                         bm.verts.new((ww, th, u)), bm.verts.new((-ww, th, u))])
        for a, b in zip(rows[:-1], rows[1:]):
            for k in range(4):
                bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
        bm.faces.new(list(reversed(rows[0])))
        bm.faces.new(rows[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        # feather lies in the wing plane (XZ-ish), rotated about Y by `ang` from +Z
        sb.bm_xform(bm, scale=(1.0, 1.0, L))
        q = Vector((0, 0, 1)).rotation_difference(dirv)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=q.to_matrix())
        sb.bm_xform(bm, loc=tuple(p))
        if RNG.random() < 0.18:  # broken feather
            sb.bm_cut(bm, tuple(p + dirv * L * RNG.uniform(0.35, 0.7)), tuple(dirv))
        put(f"{prefix}{i}", bm, mat, sharp=50, noise=0.004)


def build():
    global ROOT, RNG
    ROOT = sb.root("FallenAngel")
    RNG = K.rng_for(13)

    # ---- robe and legs
    put("robe", robe(), noise=0.01)
    # right leg: thigh forward (knee up), shin down, foot planted - under thin cloth
    limb("rthigh", [(0.15, 0.02, 0.62), (0.17, -0.22, 0.62), (0.18, -0.42, 0.6)], [0.13, 0.12, 0.1], sides=10)
    limb("rshin", [(0.18, -0.44, 0.6), (0.19, -0.47, 0.32), (0.19, -0.47, 0.08)], [0.1, 0.075, 0.06], sides=10)
    put("rfoot", ellipsoid("rfoot", (0.19, -0.56, 0.04), (0.11, 0.26, 0.09)))
    # hanging cloth over the raised knee
    bm = sb.bm_lathe([(0.0, 0.0), (0.2, 0.05), (0.19, 0.25), (0.16, 0.45), (0.12, 0.58), (0.0, 0.62)], 14,
                     wobble=lambda a, t: 1.0 + 0.08 * math.sin(a * 7.0))
    sb.bm_xform(bm, loc=(0.19, -0.42, 0.0), scale=(1.0, 0.8, 1.0))
    put("kneecloth", bm, noise=0.008)

    # ---- torso: leaning slightly forward, broad chest
    limb("torso", [(0, 0.06, 0.72), (0, 0.04, 0.9), (0, -0.02, 1.08), (0, -0.05, 1.18)],
         [0.17, 0.16, 0.2, 0.19], sides=14, sx=1.35)
    # breastplate ridge + belt
    bm = sb.bm_lathe([(0.19, 0.0), (0.2, 0.04), (0.19, 0.08)], 18)
    sb.bm_xform(bm, loc=(0, 0.05, 0.74), scale=(1.3, 1.0, 1.0))
    put("belt", bm, "Title_MarbleDark")
    # shoulders / pauldrons
    for sx in (-1, 1):
        put(f"pauldron{sx}", ellipsoid("p", (sx * 0.27, -0.03, 1.17), (0.2, 0.22, 0.15), rot=(0, sx * 20, 0)))
    # chest crack leaking gold
    sb.ptube("crack_glow", ROOT, [(x * S, y * S, z * S) for x, y, z in
                                  [(-0.05, -0.215, 1.15), (0.0, -0.225, 1.05), (-0.03, -0.222, 0.97),
                                   (0.02, -0.21, 0.88)]],
             [0.008 * S, 0.012 * S, 0.01 * S, 0.004 * S], sides=4, material=K.M("Title_HolyCrack"))

    # ---- neck and bowed head with a hood-like veil
    limb("neck", [(0, -0.06, 1.2), (0, -0.12, 1.3)], [0.065, 0.06], sides=8)
    head = ellipsoid("head", (0, -0.17, 1.36), (0.2, 0.23, 0.25), rot=(-30, 0, 0))
    sb.bm_dent(head, (0, -0.28, 1.33), 0.07, 0.015)
    # missing chunk of the skull (broken statue)
    sb.bm_cut(head, (0.08, -0.12, 1.45), Vector((0.7, 0.1, 0.7)).normalized())
    put("head", head)
    veil = sb.bm_lathe([(0.0, 0.155), (0.08, 0.145), (0.125, 0.1), (0.14, 0.02), (0.15, -0.08), (0.19, -0.2),
                        (0.23, -0.27)], 18,
                       cap_bottom=False, wobble=lambda a, t: 1.0 + 0.06 * math.sin(a * 8.0) * t)
    sb.bm_cut(veil, (0, -0.07, 0.0), Vector((0, -1, 0.35)).normalized(), fill=False)  # open face
    sb.bm_xform(veil, rot=(-32, 0, 0), loc=(0, -0.12, 1.36))
    put("veil", veil, noise=0.006)
    # long hair strands falling over the shoulders under the veil
    for i, sx in enumerate((-1, 1)):
        limb(f"hair{i}", [(sx * 0.13, -0.16, 1.3), (sx * 0.17, -0.2, 1.15), (sx * 0.19, -0.18, 1.0)],
             [0.05, 0.045, 0.02], sides=6)

    # ---- arms reaching down to the sword pommel
    hands = (0.0, -0.52, 0.94)
    for sx in (-1, 1):
        sh = (sx * 0.28, -0.04, 1.14)
        el = (sx * 0.33, -0.26, 0.96)
        wr = (sx * 0.08, -0.5, 0.96)
        limb(f"uarm{sx}", [sh, el], [0.085, 0.07], sides=10)
        limb(f"farm{sx}", [el, wr], [0.07, 0.05], sides=10)
        # sleeve flare
        limb(f"sleeve{sx}", [(sx * 0.31, -0.18, 1.01), (sx * 0.34, -0.3, 0.86), (sx * 0.32, -0.32, 0.78)],
             [0.1, 0.12, 0.05], sides=10)
        put(f"hand{sx}", ellipsoid("h", (sx * 0.055, -0.53, 0.955), (0.09, 0.11, 0.1)))

    # ---- the great sword, point buried in the ground in front
    sw = sb.empty("sword_root", ROOT, (0, -0.56 * S, -0.35 * S), (0, 0, 0))
    K.sword("sword", sw, RNG, 1.45 * S, 0.12 * S, (0, 0, 0), (0, 0, 0), mat_blade="Title_MarbleDark",
            mat_hilt="Title_Gold")

    # ---- right wing (raised, broken tip)
    rw = [(0.12, 0.16, 1.12), (0.45, 0.32, 1.45), (0.85, 0.42, 1.85), (1.18, 0.48, 2.05)]
    limb("rwing_arm", rw, [0.1, 0.085, 0.06, 0.035], sides=8, samples=2)
    wing_feathers("rwf", rw, 16, 0.55, 1.15, (0, 0.2, -1), (1, 0, 0), 55.0)
    # a second, shorter covert row
    wing_feathers("rwc", rw[:3], 9, 0.35, 0.55, (0, -0.1, -1), (1, 0, 0), 35.0)
    # ---- left wing: stump at the shoulder, the rest lies shattered on the ground behind-left
    limb("lwing_stump", [(-0.12, 0.16, 1.12), (-0.32, 0.3, 1.28)], [0.1, 0.08], sides=8)
    cut = sb.bm_rock(RNG, (0.14, 0.14, 0.12), cuts=3)
    sb.bm_xform(cut, loc=(-0.33, 0.31, 1.24))
    put("lwing_break", cut, "Title_Marble")
    lw = [(-0.6, 0.9, 0.12), (-1.0, 1.15, 0.2), (-1.45, 1.3, 0.16), (-1.8, 1.45, 0.08)]
    limb("lwing_arm", lw, [0.09, 0.075, 0.055, 0.03], sides=8, samples=2)
    # fallen feathers lie flat-ish: droop ~ -70 (rotated toward the ground plane)
    wing_feathers("lwf", lw, 13, 0.5, 1.0, (0.1, 1, -0.06), (-1, 0, 0), 50.0)

    # ---- broken halo at the knee, two arcs leaning on the ground
    for i, (a0, a1, loc, rot) in enumerate(((10, 150, (0.62, -0.55, 0.0), (0, -12, 35)),
                                            (190, 300, (0.95, -0.15, 0.0), (75, 0, -20)))):
        bm = sb.bm_box((1.0, 0.04, 1.0), (10, 1, 1))
        sb.bm_arc(bm, (0, 0, 0.33), 0.33, 0.39, a0, a1)
        sb.bm_xform(bm, rot=rot, loc=loc)
        put(f"halo{i}", bm, "Title_Gold", noise=0.003)

    # ---- rubble mound around the base, and fallen fragments
    for i in range(16):
        a = RNG.uniform(0, math.tau)
        d = RNG.uniform(0.55, 1.4)
        s = RNG.uniform(0.06, 0.2)
        bm = sb.bm_rock(RNG, (s * 1.4, s, s * 0.7), cuts=4)
        sb.bm_xform(bm, loc=(math.cos(a) * d, math.sin(a) * d * 0.8 + 0.2, -0.02), rot=(0, 0, RNG.uniform(0, 360)))
        put(f"rubble{i}", bm, "Title_Marble" if i % 3 else "Title_StoneRock", noise=0.0)
    # the snapped-off chunk of the skull lies beside the sword
    bm = sb.bm_rock(RNG, (0.12, 0.1, 0.07), cuts=3)
    sb.bm_xform(bm, loc=(-0.38, -0.7, 0.0))
    put("skullchunk", bm, noise=0.0)

    sb.join_meshes(ROOT, "statue")
    sb.tri_count(ROOT)
    return ROOT
