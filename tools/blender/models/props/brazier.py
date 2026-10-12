"""Braziers: iron bowl on a tripod / on a stone baluster (2 variants). Fire + light are added in Godot
at the bowl (z ~ 1.05 -> props.gd BRAZIER_TOP)."""
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

def bowl(v, rng, z):
    prof = [(0.0, 0.0), (0.18, 0.0), (0.3, 0.06), (0.45, 0.18), (0.55, 0.3), (0.58, 0.33), (0.53, 0.34),
            (0.5, 0.3), (0.4, 0.18), (0.0, 0.14)]
    bm = sb.bm_lathe(prof, 16, cap_bottom=False, cap_top=False)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    for k in range(3):  # dents
        a = rng.uniform(0, math.tau)
        sb.bm_dent(bm, (math.cos(a) * 0.5, math.sin(a) * 0.5, 0.22), 0.15, 0.03)
    sb.bm_noise(bm, 0.008, 5.0, seed=rng.randrange(999))
    sb.bm_obj("bowl", v, bm, K.M(IRON), (0, 0, z), sharp=40)
    K.socket(v, "fire", (0, 0, z + 0.22))
    for k in range(8):  # rim spikes
        a = k / 8 * math.tau
        sp = sb.bm_lathe([(0.025, 0.0), (0.0, 0.16)], 4)
        sb.bm_obj(f"spike{k}_ns", v, sp, K.M(IRON), (math.cos(a) * 0.56, math.sin(a) * 0.56, z + 0.32),
                  (math.degrees(-math.sin(a)) * 0.35, math.degrees(math.cos(a)) * 0.35, 0), sharp=None)
    for k in range(7):  # embers heaped in the bowl
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, 0.3)
        s = rng.uniform(0.14, 0.24)
        K.rock(f"ember{k}_ns", v, rng, (s, s * 0.9, s * 0.7), (math.cos(a) * d, math.sin(a) * d, z + 0.15 + (0.3 - d) * 0.25),
               (0, 0, rng.uniform(0, 360)), "Prop_Ember", 1, 2)


def build():
    vs = sb.variants("bz", 2, 3.0)
    rng = K.rng_for(1600)
    v = vs[0]
    for k in range(3):
        a = k / 3 * math.tau
        pts = [(math.cos(a) * 0.18, math.sin(a) * 0.18, 1.0), (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.6),
               (math.cos(a) * 0.5, math.sin(a) * 0.5, 0.15), (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.03)]
        bm = sb.bm_limb(pts, [0.04, 0.035, 0.035, 0.05], 6, 2)
        sb.bm_obj(f"leg{k}", v, bm, K.M(IRON), sharp=50)
        ft = sb.bm_lathe([(0.07, 0.0), (0.06, 0.03), (0.0, 0.06)], 6)
        sb.bm_obj(f"foot{k}_ns", v, ft, K.M(IRON), (math.cos(a) * 0.63, math.sin(a) * 0.63, 0.0), sharp=None)
    ring = sb.bm_limb([(math.cos(t / 12 * math.tau) * 0.33, math.sin(t / 12 * math.tau) * 0.33, 0.55) for t in range(13)],
                      [0.02] * 13, 4, 1)
    sb.bm_obj("ring_ns", v, ring, K.M(IRON), sharp=50)
    bowl(v, rng, 0.98)

    rng = K.rng_for(1601)
    v = vs[1]
    sb.stone_block("base", v, (0.8, 0.8, 0.22), K.M("Prop_Stone"), rng, loc=(0, 0, 0.11), chips=2, step=0.3)
    K.lathe_obj("baluster", v, rng, [(0.3, 0.0), (0.3, 0.06), (0.2, 0.12), (0.16, 0.3), (0.2, 0.5), (0.24, 0.6),
                                      (0.14, 0.72), (0.18, 0.76), (0.3, 0.8)], 16, (0, 0, 0.22), chips=1)
    bowl(v, rng, 1.0)
    sb.tri_report("brazier")
    return vs[0]
