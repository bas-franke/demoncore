"""Gravestones (5 variants): rounded, gothic-pointed, cross, broken slab, obelisk. Face -Y."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import bmesh  # noqa: E402
import _props_kit as K  # noqa: E402

CATEGORY = "props"


def headstone(name, v, rng, w, h, t, shape, loc=(0, 0, 0), rot=(0, 0, 0), chips=2, cut=None, shift=None):
    """Upright slab (base z=0) whose top follows `shape(u)` (u = |2x/w| in 0..1, returns 0..1)."""
    bm = sb.bm_box((w, t, h), (6, 1, 5), z0=True)
    sh = h * 0.72
    for vv in bm.verts:
        u = min(1.0, abs(vv.co.x) * 2 / w)
        top = sh + (h - sh) * shape(u)
        vv.co.z = vv.co.z / h * top
    if cut is not None:
        caps = sb.bm_cut(bm, cut[0], cut[1])
        sb.bm_roughen(bm, caps, rng, 0.01, 0.3)
    if shift is not None:
        sb.bm_xform(bm, loc=shift)
    sb.bm_chip(bm, rng, chips, 0.08, rough=0.01)
    sb.bm_crack(bm, rng, 1, depth=0.01, width=0.006)
    sb.bm_bevel(bm, 0.012)
    sb.bm_noise(bm, 0.008, 4.0, seed=rng.randrange(999))
    return sb.bm_obj(name, v, bm, K.M("Prop_Stone"), loc, rot)


def round_top(u):
    return math.sqrt(max(0.0, 1 - u * u))


def pointed_top(u):
    # equilateral gothic arch, normalised
    x = u * 0.5
    return math.sqrt(max(0.0, 1 - (x + 0.5) ** 2)) / 0.866


def ledger(v, rng, y):
    sb.stone_block("ledger_ns", v, (0.7, 1.4, 0.1), K.M("Prop_Stone"), rng, loc=(0, y, 0.03),
                   rot=(rng.uniform(-2, 2), rng.uniform(-2, 2), rng.uniform(-5, 5)), chips=2, step=0.25)


def build():
    vs = sb.variants("gs", 5, 2.5)
    # v0 rounded, tilted, with ledger slab
    rng = K.rng_for(1)
    v = vs[0]
    headstone("stone", v, rng, 0.62, 0.95, 0.14, round_top, (0, 0, -0.08), (-6, 4, 0))
    sb.stone_block("foot_ns", v, (0.78, 0.3, 0.12), K.M("Prop_Stone"), rng, loc=(0, 0, 0.03), chips=1, step=0.25)
    ledger(v, rng, -0.85)

    # v1 gothic pointed
    rng = K.rng_for(2)
    v = vs[1]
    headstone("stone", v, rng, 0.58, 1.15, 0.16, pointed_top, (0, 0, -0.06), (3, -5, 2), chips=3)
    sb.stone_block("foot_ns", v, (0.76, 0.34, 0.14), K.M("Prop_Stone"), rng, loc=(0, 0, 0.04), chips=2, step=0.25)

    # v2 cross on a stepped base
    rng = K.rng_for(3)
    v = vs[2]
    sb.stone_block("base", v, (0.5, 0.38, 0.2), K.M("Prop_Stone"), rng, loc=(0, 0, 0.1), chips=2, step=0.2)
    sb.stone_block("base2_ns", v, (0.36, 0.26, 0.14), K.M("Prop_Stone"), rng, loc=(0, 0, 0.26), chips=1, step=0.2)
    cross = sb.bm_box((0.13, 0.12, 1.15), (1, 1, 6), z0=True)
    arm = sb.bm_box((0.6, 0.12, 0.13), (4, 1, 1))
    sb.bm_xform(arm, loc=(0, 0, 0.82))
    sb.bm_merge(cross, arm)
    sb.bm_chip(cross, rng, 2, 0.05)
    sb.bm_bevel(cross, 0.01)
    sb.bm_noise(cross, 0.006, 5.0, seed=5)
    sb.bm_obj("cross", v, cross, K.M("Prop_Stone"), (0, 0, 0.3), (5, -4, 0))

    # v3 broken slab, its top lying in front
    rng = K.rng_for(4)
    v = vs[3]
    headstone("stone", v, rng, 0.66, 1.0, 0.15, round_top, (0, 0, -0.05), (-3, 0, 0), chips=1,
              cut=((0.1, 0, 0.5), (0.35, 0.05, 1.0)))
    headstone("top_ns", v, rng, 0.66, 1.0, 0.15, round_top, (0.15, -0.55, 0.075), (-88, 0, 18), chips=1,
              cut=((0.1, 0, 0.55), (-0.35, -0.05, -1.0)), shift=(0, 0, -0.55))
    K.rubble(v, rng, (0.0, -0.4, 0), 0.5, 3, 0.06, 0.14)

    # v4 obelisk
    rng = K.rng_for(5)
    v = vs[4]
    sb.stone_block("base", v, (0.55, 0.55, 0.26), K.M("Prop_Stone"), rng, loc=(0, 0, 0.13), chips=2, step=0.2)
    sb.stone_block("die", v, (0.4, 0.4, 0.3), K.M("Prop_Stone"), rng, loc=(0, 0, 0.41), chips=1, step=0.2)
    sh = sb.bm_box((0.28, 0.28, 1.4), (1, 1, 6), z0=True)
    for vv in sh.verts:
        k = 1.0 - 0.35 * vv.co.z / 1.4
        vv.co.x *= k
        vv.co.y *= k
    tip = sb.bm_lathe([(0.13, 0.0), (0.0, 0.22)], 4, cap_bottom=True)
    sb.bm_xform(tip, loc=(0, 0, 1.4), rot=(0, 0, 45))
    sb.bm_merge(sh, tip)
    sb.bm_chip(sh, rng, 1, 0.06)
    sb.bm_bevel(sh, 0.008)
    sb.bm_noise(sh, 0.006, 4.0, seed=9)
    sb.bm_obj("shaft", v, sh, K.M("Prop_Stone"), (0, 0, 0.56), (2, -3, 0))
    sb.tri_report("gravestone")
    return vs[0]
