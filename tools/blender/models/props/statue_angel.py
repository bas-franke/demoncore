"""Headless marble angels with broken wings on weathered pedestals (2 variants). Face -Y."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"
MARBLE = "Prop_Marble"


def pedestal(v, rng):
    S = K.M("Prop_Stone")
    sb.stone_block("ped0", v, (1.55, 1.55, 0.26), S, rng, loc=(0, 0, 0.13), chips=3, step=0.4)
    sb.stone_block("ped1", v, (1.15, 1.15, 0.8), S, rng, loc=(0, 0, 0.66), chips=2, cracks=1, step=0.3)
    sb.stone_block("ped2", v, (1.35, 1.35, 0.16), S, rng, loc=(0, 0, 1.14), chips=3, step=0.4)
    return 1.22


def body(v, rng, y0):
    prof = [(0.5, 0.0), (0.48, 0.08), (0.43, 0.45), (0.37, 0.9), (0.31, 1.25), (0.29, 1.42), (0.32, 1.6),
            (0.36, 1.8), (0.35, 1.9), (0.24, 2.0), (0.11, 2.05), (0.09, 2.14)]
    ph = rng.uniform(0, 6)

    def folds(a, t):
        k = max(0.0, 1.0 - t * 1.6)
        return 1.0 + 0.075 * math.sin(9 * a + 2.0 * math.sin(3 * a + ph)) * k

    import bmesh  # noqa: F401
    bm = sb.bm_lathe(prof, 28, wobble=folds)
    sb.bm_xform(bm, scale=(1.0, 0.72, 1.0))
    caps = sb.bm_cut(bm, (0, 0, 2.08), Vector((0.3, 0.2, 1)).normalized())
    sb.bm_roughen(bm, caps, rng, 0.025, 0.3)
    sb.bm_chip(bm, rng, 2, 0.12, rough=0.01)
    sb.bm_crack(bm, rng, 1, 0.012, 0.008)
    sb.bm_noise(bm, 0.008, 3.0, seed=rng.randrange(999))
    sb.bm_obj("robe", v, bm, K.M(MARBLE), (0, 0, y0), sharp=50)
    for sx in (-1, 1):
        sh = sb.bm_lathe([(0.0, -0.13), (0.12, -0.09), (0.16, 0.0), (0.12, 0.09), (0.0, 0.12)], 10)
        sb.bm_obj(f"shoulder{sx}", v, sh, K.M(MARBLE), (sx * 0.27, 0.0, y0 + 1.86), (0, sx * 70, 0),
                  (1.0, 0.9, 1.0), sharp=0)


def arm(v, rng, name, pts, r=0.07, broken=False):
    radii = [r, r * 0.9, r * 0.75] + [r * 0.7] * (len(pts) - 3)
    bm = sb.bm_limb(pts, radii[:len(pts)], 8, 2)
    if broken:
        a, b = Vector(pts[-2]), Vector(pts[-1])
        d = (b - a).normalized()
        caps = sb.bm_cut(bm, b - d * 0.05, (d + Vector((0.3, 0.2, 0.1))).normalized())
        sb.bm_roughen(bm, caps, rng, 0.015, 0.3)
    sb.bm_noise(bm, 0.005, 5.0, seed=rng.randrange(999))
    sb.bm_obj(name, v, bm, K.M(MARBLE), sharp=50)


def feather(name, parent, rng, length, width, rot, curve=0.12, broken=0.0, loc=(0, 0, 0)):
    bm = sb.bm_box((width, 0.04, length), (1, 1, 4), z0=True)
    for vv in bm.verts:
        t = vv.co.z / length
        vv.co.x *= max(0.15, 1.0 - t ** 3 * 0.85) * (0.55 + 0.45 * min(1.0, t * 4))
        vv.co.y += curve * t * t * length
    if broken > 0.0:
        caps = sb.bm_cut(bm, (0, 0, length * broken), Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.3, 0.3), 1)).normalized())
        sb.bm_roughen(bm, caps, rng, 0.012, 0.25)
    sb.bm_noise(bm, 0.006, 4.0, seed=rng.randrange(999))
    return sb.bm_obj(name, parent, bm, K.M(MARBLE), loc, rot, sharp=45)


def wing(v, rng, side, y0, broken, tag):
    """Raised wing: a leading-edge 'arm' with feathers hanging from it, fanning from down to out-up."""
    root = sb.empty(f"{tag}wing", v, loc=(side * 0.12, 0.2, y0 + 1.7), rot=(-12, 0, side * 32))
    n = 9
    smax = 0.5 if broken else 1.0
    edge = []
    for i in range(6):
        s = i / 5 * smax
        edge.append((side * (0.05 + 0.95 * s), 0.0, 0.05 + 0.75 * math.sin(s * math.pi * 0.55)))
    bm = sb.bm_limb(edge, [0.09, 0.08, 0.07, 0.06, 0.05, 0.04], 6, 1)
    if broken:
        caps = sb.bm_cut(bm, Vector(edge[-1]) - Vector((side * 0.04, 0, 0)), Vector((side, 0.2, 0.3)).normalized())
        sb.bm_roughen(bm, caps, rng, 0.02, 0.3)
    sb.bm_obj(f"{tag}edge", root, bm, K.M(MARBLE), sharp=50)
    for i in range(n):
        s = (i + 0.5) / n
        if broken and s > 0.55:
            continue
        e = Vector((side * (0.05 + 0.95 * s), 0.0, 0.05 + 0.75 * math.sin(s * math.pi * 0.55)))
        theta = 180 - s * 125  # from hanging down to pointing out and up
        ln = 0.55 + 0.95 * s
        br = rng.uniform(0.45, 0.8) if (broken and s > 0.35) else 0.0
        feather(f"{tag}f{i}", root, rng, ln, 0.26, (0, side * theta, 0), 0.08, br, (e.x, 0.03, e.z))
        if i % 2 == 0:
            feather(f"{tag}c{i}_ns", root, rng, ln * 0.45, 0.3, (0, side * (theta - 8), 0), 0.04, 0.0,
                    (e.x, -0.035, e.z))
    if broken:
        for i in range(2):
            feather(f"{tag}frag{i}_ns", v, rng, rng.uniform(0.6, 0.9), 0.24,
                    (90 + rng.uniform(-8, 8), 0, rng.uniform(0, 360)), 0.05, 0.0,
                    (side * rng.uniform(1.0, 1.6), rng.uniform(0.3, 1.1), 0.05))

def build():
    vs = sb.variants("an", 2, 4.0)
    # v0: one arm lowered holding the robe, the other broken mid-gesture; right wing snapped
    rng = K.rng_for(61)
    v = vs[0]
    y0 = pedestal(v, rng)
    body(v, rng, y0)
    arm(v, rng, "armL", [(-0.3, 0, y0 + 1.86), (-0.42, -0.06, y0 + 1.5), (-0.34, -0.2, y0 + 1.22), (-0.26, -0.26, y0 + 1.12)])
    arm(v, rng, "armR", [(0.3, 0, y0 + 1.86), (0.44, -0.14, y0 + 1.58), (0.4, -0.42, y0 + 1.62)], broken=True)
    wing(v, rng, -1, y0, False, "L")
    wing(v, rng, 1, y0, True, "R")
    K.rubble(v, rng, (0.2, -0.3, 0), 1.6, 4, 0.12, 0.28, mat="Prop_Marble")

    # v1: hands joined in prayer, both wings broken
    rng = K.rng_for(62)
    v = vs[1]
    y0 = pedestal(v, rng)
    body(v, rng, y0)
    for sx in (-1, 1):
        arm(v, rng, f"arm{sx}", [(sx * 0.3, 0, y0 + 1.86), (sx * 0.34, -0.12, y0 + 1.5), (sx * 0.12, -0.32, y0 + 1.62),
                                 (sx * 0.02, -0.36, y0 + 1.72)])
    wing(v, rng, -1, y0, True, "L")
    wing(v, rng, 1, y0, True, "R")
    K.rubble(v, rng, (0.0, 0.5, 0), 1.7, 5, 0.12, 0.3, mat="Prop_Marble")
    sb.tri_report("statue_angel")
    return vs[0]
