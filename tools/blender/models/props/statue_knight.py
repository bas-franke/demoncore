"""Kneeling knight in verdigris bronze, hands on a planted sword (2 variants). Face -Y."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"
BR = "Prop_Bronze"


def limb(v, rng, name, pts, radii, sides=8, broken=False):
    bm = sb.bm_limb(pts, radii, sides, 2)
    if broken:
        a, b = Vector(pts[-2]), Vector(pts[-1])
        d = (b - a).normalized()
        caps = sb.bm_cut(bm, b - d * 0.06, (d + Vector((0.3, -0.2, 0.2))).normalized())
        sb.bm_roughen(bm, caps, rng, 0.015, 0.3)
    sb.bm_noise(bm, 0.004, 6.0, seed=rng.randrange(999))
    return sb.bm_obj(name, v, bm, K.M(BR), sharp=50)


def lathe(v, rng, name, prof, segs, loc, rot=(0, 0, 0), scale=(1, 1, 1), sharp=40, wob=None):
    bm = sb.bm_lathe(prof, segs, wobble=wob)
    sb.bm_xform(bm, scale=scale)
    sb.bm_noise(bm, 0.004, 6.0, seed=rng.randrange(999))
    return sb.bm_obj(name, v, bm, K.M(BR), loc, rot, sharp=sharp)


def knight(v, rng, y0, head=True, broken_arm=False):
    # legs: left knee raised, right knee on the plinth
    limb(v, rng, "thighL", [(-0.15, 0.05, y0 + 0.5), (-0.16, -0.18, y0 + 0.52), (-0.17, -0.4, y0 + 0.5)], [0.12, 0.11, 0.1])
    limb(v, rng, "shinL", [(-0.17, -0.42, y0 + 0.5), (-0.17, -0.44, y0 + 0.28), (-0.17, -0.42, y0 + 0.07)], [0.1, 0.085, 0.07])
    sb.stone_block("footL", v, (0.13, 0.28, 0.1), K.M(BR), rng, loc=(-0.17, -0.5, y0 + 0.05), chips=0, step=0.2,
                   noise=0.004)
    limb(v, rng, "thighR", [(0.15, 0.05, y0 + 0.5), (0.16, -0.06, y0 + 0.3), (0.16, -0.12, y0 + 0.09)], [0.12, 0.11, 0.1])
    limb(v, rng, "shinR", [(0.16, -0.12, y0 + 0.08), (0.16, 0.15, y0 + 0.08), (0.16, 0.4, y0 + 0.09)], [0.09, 0.08, 0.065])
    sb.stone_block("footR", v, (0.12, 0.12, 0.24), K.M(BR), rng, loc=(0.16, 0.47, y0 + 0.12), rot=(-30, 0, 0),
                   chips=0, step=0.2, noise=0.004)
    # faulds (armoured skirt) and torso
    lathe(v, rng, "faulds", [(0.31, 0.0), (0.29, 0.1), (0.27, 0.2), (0.24, 0.32), (0.2, 0.36)], 16,
          (0, 0.03, y0 + 0.36), scale=(1, 0.8, 1), sharp=30,
          wob=lambda a, t: 1.0 + 0.04 * math.sin(a * 8))
    lathe(v, rng, "torso", [(0.2, 0.0), (0.25, 0.15), (0.3, 0.33), (0.31, 0.45), (0.25, 0.55), (0.1, 0.6)], 16,
          (0, 0.02, y0 + 0.68), (-8, 0, 0), (1, 0.72, 1))
    # tabard over the chest
    tb = sb.bm_box((0.36, 0.03, 0.75), (2, 1, 5))
    for vv in tb.verts:
        vv.co.y -= 0.06 * (0.5 - vv.co.z / 0.75) ** 2
        vv.co.x *= 1.0 + 0.4 * max(0.0, -vv.co.z / 0.75)
    sb.bm_noise(tb, 0.006, 5.0, seed=4)
    sb.bm_obj("tabard_ns", v, tb, K.M(BR), (0, -0.23, y0 + 0.62), (-8, 0, 0))
    # cape falling behind
    cp = sb.bm_box((0.66, 0.035, 1.25), (5, 1, 7))
    for vv in cp.verts:
        t = 0.5 - vv.co.z / 1.25  # 0 top .. 1 bottom
        vv.co.y += 0.32 * t * t + 0.03 * math.sin(vv.co.x * 14.0)
        vv.co.x *= 1.0 + 0.35 * t
    sb.bm_noise(cp, 0.008, 4.0, seed=8)
    sb.bm_obj("cape", v, cp, K.M(BR), (0, 0.24, y0 + 0.68), (6, 0, 0))
    for sx in (-1, 1):
        lathe(v, rng, f"pauldron{sx}", [(0.17, 0.0), (0.16, 0.05), (0.12, 0.11), (0.0, 0.14)], 12,
              (sx * 0.3, 0.02, y0 + 1.1), (0, sx * 35, 0), (1, 1.05, 1), sharp=0)
        lathe(v, rng, f"pauldron{sx}b_ns", [(0.15, 0.0), (0.14, 0.04), (0.0, 0.07)], 12,
              (sx * 0.33, 0.02, y0 + 1.02), (0, sx * 45, 0), sharp=0)
    # arms to the sword pommel
    for sx in (-1, 1):
        broken = broken_arm and sx < 0
        if broken:
            limb(v, rng, f"arm{sx}", [(sx * 0.31, 0.0, y0 + 1.05), (sx * 0.33, -0.12, y0 + 0.86), (sx * 0.28, -0.22, y0 + 0.78)],
                 [0.075, 0.07, 0.065], broken=True)
            continue
        limb(v, rng, f"arm{sx}", [(sx * 0.31, 0.0, y0 + 1.05), (sx * 0.31, -0.14, y0 + 0.84), (sx * 0.2, -0.32, y0 + 0.88),
                                  (sx * 0.06, -0.44, y0 + 0.96)], [0.075, 0.07, 0.06, 0.055])
    gl = sb.bm_rock(rng, (0.2, 0.13, 0.11), cuts=2, subdiv=1, noise=0.03, flat_bottom=False)
    sb.bm_obj("gauntlets", v, gl, K.M(BR), (0, -0.45, y0 + 0.9), sharp=45)
    if head:
        lathe(v, rng, "helm", [(0.0, -0.02), (0.125, 0.0), (0.135, 0.14), (0.13, 0.25), (0.11, 0.3), (0.0, 0.31)], 12,
              (0, -0.02, y0 + 1.17), (14, 0, 0), sharp=30)
        sb.box("visor_ns", v, size=(0.2, 0.03, 0.025), loc=(0, -0.155, y0 + 1.37), rot=(14, 0, 0),
               material=K.M("Prop_Void"), bevel=0.0)
        sb.stone_block("crest_ns", v, (0.03, 0.22, 0.06), K.M(BR), rng, loc=(0, 0.0, y0 + 1.49), rot=(14, 0, 0),
                       chips=0, step=0.2, noise=0.003)
    else:
        nb = sb.bm_column(0.08, 0.12, 8, 1)
        caps = sb.bm_cut(nb, (0, 0, 0.09), Vector((0.4, 0.3, 1)).normalized())
        sb.bm_roughen(nb, caps, rng, 0.02, 0.3)
        sb.bm_obj("neck", v, nb, K.M(BR), (0, 0.0, y0 + 1.22))
    # the planted sword
    bl = sb.bm_box((0.1, 0.022, 0.86), (1, 1, 5), z0=True)
    for vv in bl.verts:
        t = vv.co.z / 0.86
        vv.co.x *= min(1.0, t * 4.0 + 0.05)
        vv.co.y *= 1.0 if abs(vv.co.x) < 0.01 else 0.5
    sb.bm_obj("blade", v, bl, K.M(BR), (0, -0.47, y0 - 0.06), sharp=30)
    sb.stone_block("guard", v, (0.44, 0.06, 0.06), K.M(BR), rng, loc=(0, -0.47, y0 + 0.82), chips=0, step=0.2,
                   noise=0.003)
    lathe(v, rng, "grip", [(0.025, 0.0), (0.028, 0.16), (0.045, 0.17), (0.05, 0.21), (0.0, 0.25)], 8,
          (0, -0.47, y0 + 0.85))


def build():
    vs = sb.variants("kn", 2, 4.0)
    rng = K.rng_for(71)
    v = vs[0]
    S = K.M("Prop_Stone")
    sb.stone_block("ped0", v, (1.3, 1.4, 0.62), S, rng, loc=(0, 0, 0.31), chips=3, cracks=1, step=0.3)
    sb.stone_block("ped1", v, (1.42, 1.52, 0.14), S, rng, loc=(0, 0, 0.69), chips=3, step=0.4)
    knight(v, rng, 0.76)

    rng = K.rng_for(72)
    v = vs[1]
    sb.stone_block("ped0", v, (1.6, 1.6, 0.3), S, rng, loc=(0, 0, 0.15), chips=4, step=0.4)
    sb.stone_block("ped1", v, (1.25, 1.35, 0.4), S, rng, loc=(0, 0, 0.5), chips=2, cracks=1, step=0.3)
    knight(v, rng, 0.7, head=False, broken_arm=True)
    K.rubble(v, rng, (-0.6, -0.9, 0), 0.8, 4, 0.08, 0.25)
    sb.tri_report("statue_knight")
    return vs[0]
