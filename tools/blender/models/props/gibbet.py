"""Gibbet: crooked gallows post with a hanging iron cage and remains (2 variants)."""
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


def chain(parent, name, a, b, sag, n, link_r=0.06, wire=0.014):
    """Catenary-ish chain of interlocking oval links from a to b (merged into one mesh)."""
    a, b = Vector(a), Vector(b)
    bm = bmesh.new()
    pts = []
    for i in range(n + 1):
        t = i / n
        p = a.lerp(b, t)
        p.z -= sag * 4 * t * (1 - t)
        pts.append(p)
    for i in range(n):
        p, q = pts[i], pts[i + 1]
        c = (p + q) * 0.5
        d = (q - p).normalized()
        ring = []
        for k in range(9):
            ang = k / 8 * math.tau
            ring.append((math.cos(ang) * link_r * 1.5, math.sin(ang) * link_r * 0.8))
        side = d.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        side.normalize()
        if i % 2:
            side = d.cross(side).normalized()
        lp = [c + d * x + side * y for x, y in ring]
        lk = sb.bm_limb(lp, [wire] * len(lp), 4, 1, cap_end=False)
        sb.bm_merge(bm, lk)
    sb.bm_obj(name, parent, bm, K.M(IRON), sharp=50)

def cage(parent, rng, loc, rot, open_door=False):
    c = sb.empty("cage", parent, loc=loc, rot=rot)
    bm = bmesh.new()
    R = 0.38
    for z in (-0.62, 0.0, 0.58):
        ring = sb.bm_limb([(math.cos(t / 12 * math.tau) * R, math.sin(t / 12 * math.tau) * R, z) for t in range(13)],
                          [0.018] * 13, 4, 1, cap_end=False)
        sb.bm_merge(bm, ring)
    for k in range(10):
        if open_door and k in (0, 1):
            continue
        a = k / 10 * math.tau
        bar = sb.bm_limb([(math.cos(a) * R, math.sin(a) * R, -0.66), (math.cos(a) * R, math.sin(a) * R, 0.58),
                          (math.cos(a) * R * 0.45, math.sin(a) * R * 0.45, 0.8), (0, 0, 0.86)],
                         [0.016, 0.016, 0.014, 0.012], 4, 1)
        sb.bm_merge(bm, bar)
    floor = sb.bm_lathe([(0.0, -0.66), (R, -0.66), (R, -0.64), (0.0, -0.64)], 10)
    sb.bm_merge(bm, floor)
    hook = sb.bm_limb([(0, 0, 0.86), (0, 0, 0.96), (0.05, 0, 1.02), (0, 0, 1.06)], [0.02] * 4, 4, 1)
    sb.bm_merge(bm, hook)
    sb.bm_noise(bm, 0.004, 6, seed=rng.randrange(99))
    sb.bm_obj("cage_ns", c, bm, K.M(IRON), sharp=50)
    K.skull("skull_ns", c, rng, (0.08, 0.05, -0.64), (0, 20, 30))
    K.bone("bone0_ns", c, rng, (-0.2, -0.1, -0.6), (0.15, -0.2, -0.6), 0.025)
    K.bone("bone1_ns", c, rng, (-0.25, 0.15, -0.6), (-0.05, -0.25, -0.35), 0.025)
    return c


def build():
    vs = sb.variants("gb", 2, 4.0)
    for i, v in enumerate(vs):
        rng = K.rng_for(1900 + i)
        W = K.M("Prop_Wood")
        post = sb.bm_box((0.22, 0.22, 3.9), (1, 1, 8), z0=True)
        sb.bm_crack(post, rng, 2, 0.02, 0.008, axis=(0, 0, 1))
        sb.bm_bevel(post, 0.02)
        sb.bm_noise(post, 0.015, 2.5, seed=i)
        sb.bm_obj("post", v, post, W, (0, 0, -0.1), (0, 2.5 if i == 0 else -2, 0))
        beam = sb.bm_box((1.8, 0.2, 0.18), (6, 1, 1))
        sb.bm_bevel(beam, 0.02)
        sb.bm_noise(beam, 0.012, 2.5, seed=i + 5)
        sb.bm_obj("beam", v, beam, W, (0.75, 0, 3.66))
        br = sb.bm_box((0.12, 0.12, 0.85), (1, 1, 3))
        sb.bm_bevel(br, 0.015)
        sb.bm_obj("brace", v, br, W, (0.3, 0, 3.32), (0, 45, 0))
        for k, sx in enumerate((-1, 1)):
            sb.stone_block(f"wedge{k}", v, (0.3, 0.5, 0.25), K.M("Prop_Stone"), rng, loc=(sx * 0.25, 0.1, 0.1),
                           rot=(0, 0, rng.uniform(-20, 20)), chips=2, step=0.3)
        chain(v, "chain_ns", (1.45, 0, 3.58), (1.45, 0, 2.95), 0.0, 5, 0.045, 0.012)
        cage(v, rng, (1.45, 0, 2.05) if i == 0 else (1.5, 0.05, 2.1), (rng.uniform(-6, 6), rng.uniform(-6, 6), rng.uniform(0, 360)),
             open_door=(i == 1))
        K.bone_scatter(v, rng, (1.2, 0.3), 0.6, 3 + i)
    sb.tri_report("gibbet")
    return vs[0]
