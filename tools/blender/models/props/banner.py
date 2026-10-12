"""Tattered war banners on iron poles (2 variants). Cloth material is tinted red or black in Godot."""
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

def cloth(v, rng, name, w, l, loc, notches=3, holes=1):
    bm = sb.bm_box((w, 0.03, l), (6, 1, 10))
    for vv in bm.verts:
        t = 0.5 - vv.co.z / l  # 0 top .. 1 bottom
        vv.co.y += 0.06 * math.sin(vv.co.x * 7.0 + t * 4.0) * t - 0.1 * t * t
        vv.co.x *= 1.0 - 0.12 * t
    for k in range(notches):  # torn V cuts in the hem
        x = -w * 0.5 + w * (k + 0.5) / notches + rng.uniform(-0.08, 0.08)
        depth = rng.uniform(0.25, 0.6)
        # carve a V into the hem
        lo =[vv for vv in bm.verts if vv.co.z < -l * 0.5 + depth * (1 - abs(vv.co.x - x) / 0.18) and abs(vv.co.x - x) < 0.18]
        bmesh.ops.delete(bm, geom=lo, context="VERTS")
    for k in range(holes):
        cx, cz = rng.uniform(-w * 0.3, w * 0.3), rng.uniform(-l * 0.2, l * 0.2)
        hole = [f for f in bm.faces if (f.calc_center_median() - Vector((cx, 0, cz))).length < 0.11]
        bmesh.ops.delete(bm, geom=hole, context="FACES")
    loose = [vv for vv in bm.verts if not vv.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    sb.bm_noise(bm, 0.01, 4.0, seed=rng.randrange(999))
    sb.bm_obj(name, v, bm, K.M("Prop_BannerCloth"), loc, sharp=0)


def build():
    vs = sb.variants("bn", 2, 3.0)
    for i, v in enumerate(vs):
        rng = K.rng_for(1700 + i)
        h = (3.7, 3.3)[i]
        sb.stone_block("base", v, (0.6, 0.6, 0.3), K.M("Prop_Stone"), rng, loc=(0, 0, 0.15), chips=2, step=0.3)
        K.lathe_obj("pole", v, rng, [(0.045, 0.0), (0.04, h), (0.0, h + 0.01)], 6, (0, 0, 0.3), (rng.uniform(-2, 2), 0, 0),
                    mat=IRON, chips=0, noise=0.003)
        K.lathe_obj("finial", v, rng, [(0.05, 0.0), (0.08, 0.06), (0.03, 0.14), (0.0, 0.32)], 6, (0, 0, h + 0.28),
                    mat="Prop_Gold", chips=0, noise=0.003)
        sb.stone_block("bar_ns", v, (1.25, 0.05, 0.05), K.M(IRON), rng, loc=(0, -0.03, h + 0.12), chips=0, step=0.4,
                       noise=0.002)
        sb.stone_block("trim_ns", v, (1.15, 0.035, 0.12), K.M("Prop_Gold"), rng, loc=(0, -0.07, h + 0.02), chips=0,
                       step=0.4, noise=0.002)
        l = (2.4, 1.9)[i]
        cloth(v, rng, "cloth", 1.05, l, (0, -0.08, h + 0.05 - l * 0.5), 3 + i, 1 + i)
        # sigil: a gold ring on the cloth face
        ring = sb.bm_limb([(math.cos(t / 10 * math.tau) * 0.16, 0, math.sin(t / 10 * math.tau) * 0.16) for t in range(11)],
                          [0.018] * 11, 4, 1)
        sb.bm_obj("sigil_ns", v, ring, K.M("Prop_Gold"), (0, -0.12, h - 0.55), sharp=50)
    sb.tri_report("banner")
    return vs[0]
