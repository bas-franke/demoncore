"""Wrought-iron cemetery fence on a stone curb with capped posts (3 variants). Runs along X."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import bmesh  # noqa: E402
import _props_kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"
IRON = "Prop_Iron"

def bar_bm(h, lean=0.0, bend=0.0, finial=True):
    bm = sb.bm_box((0.028, 0.028, h), (1, 1, 2 if bend else 1), z0=True)
    if bend:
        for vv in bm.verts:
            t = vv.co.z / h
            vv.co.y += bend * t * t
    if finial:
        sp = sb.bm_lathe([(0.0, 0.0), (0.035, 0.03), (0.02, 0.06), (0.03, 0.09), (0.0, 0.17)], 4)
        sb.bm_xform(sp, loc=(0, bend, h), rot=(0, 0, 45))
        sb.bm_merge(bm, sp)
    sb.bm_xform(bm, rot=(0, lean, 0))
    return bm


def section(v, rng, cx, w, tag, missing=0.1, sag=0.0):
    bm = bmesh.new()
    nb = 6
    for b in range(nb):
        if rng.random() < missing:
            continue
        x = cx - w * 0.5 + (b + 0.5) * w / nb
        h = 1.35 if rng.random() > 0.12 else rng.uniform(0.5, 1.0)
        bb = bar_bm(h, rng.uniform(-3, 3), rng.uniform(-0.06, 0.06) if rng.random() < 0.25 else 0.0, h > 1.2)
        sb.bm_xform(bb, loc=(x, 0, 0.34))
        sb.bm_merge(bm, bb)
    for z in (0.62, 1.42):
        rail = sb.bm_box((w - 0.08, 0.03, 0.035), (4, 1, 1))
        for vv in rail.verts:
            vv.co.z -= sag * (1 - (2 * vv.co.x / w) ** 2)
        sb.bm_xform(rail, loc=(cx, 0, z))
        sb.bm_merge(bm, rail)
    # scrollwork ring in the middle
    ring2 = sb.bm_limb([(math.cos(t / 10 * math.tau) * 0.13, math.sin(t / 10 * math.tau) * 0.13, 0) for t in range(11)],
                       [0.012] * 11, 4, 1)
    sb.bm_xform(ring2, loc=(cx, 0, 1.08), rot=(90, 0, 0))
    sb.bm_merge(bm, ring2)
    sb.bm_noise(bm, 0.004, 6.0, seed=rng.randrange(999))
    sb.bm_obj(tag + "_ns", v, bm, K.M(IRON), sharp=40)


def fence(v, rng, n, w=1.3, gap=None):
    x0 = -n * w * 0.5
    K.wall(v, rng, x0 - 0.15, -x0 + 0.15, lambda x: 0.34, 0.38, 0.34, 0.0, tag="curb", step=0.6)
    for i in range(n + 1):
        x = x0 + i * w
        if gap is not None and i == gap:
            K.rubble(v, rng, (x, 0.4, 0), 0.5, 3, 0.12, 0.3)
            continue
        sb.stone_block(f"post{i}", v, (0.3, 0.3, 1.45), K.M("Prop_Stone"), rng, loc=(x, 0, 0.34 + 0.72), chips=1,
                       step=0.35)
        cap = sb.bm_box((0.4, 0.4, 0.12), (1, 1, 1))
        sb.bm_bevel(cap, 0.02)
        pyr = sb.bm_lathe([(0.2, 0.0), (0.0, 0.2)], 4)
        sb.bm_xform(pyr, loc=(0, 0, 0.06), rot=(0, 0, 45))
        sb.bm_merge(cap, pyr)
        sb.bm_noise(cap, 0.008, 3, seed=i)
        sb.bm_obj(f"cap{i}", v, cap, K.M("Prop_Stone"), (x, 0, 1.86), (rng.uniform(-3, 3), rng.uniform(-3, 3), rng.uniform(-5, 5)))
    for s in range(n):
        if gap is not None and s in (gap - 1, gap):
            continue
        section(v, rng, x0 + (s + 0.5) * w, w - 0.3, f"sec{s}", 0.1, rng.uniform(0, 0.06))


def build():
    vs = sb.variants("fe", 3, 9.0)
    rng = K.rng_for(1500)
    fence(vs[0], rng, 4)
    rng = K.rng_for(1501)
    fence(vs[1], rng, 5, gap=3)
    # fallen section lying in the grass
    rng2 = K.rng_for(1502)
    sec = sb.empty("fallen", vs[1], loc=(1.95, -0.7, 0.05), rot=(-84, 0, 6))
    section(sec, rng2, 0, 1.0, "fsec", 0.2)
    rng = K.rng_for(1503)
    fence(vs[2], rng, 3)
    sb.tri_report("iron_fence")
    return vs[0]
