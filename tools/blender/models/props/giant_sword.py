"""Landmark: a colossal sword driven into cracked earth, holy runes in the fuller. Socket: light."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import bmesh  # noqa: E402
import _props_kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"

def blade(v, rng, s):
    L, W, T = 7.6, 1.15, 0.26
    bm = sb.bm_box((W, T, L), (4, 1, 14), z0=True)
    for vv in bm.verts:
        u = abs(vv.co.x) / (W * 0.5)
        vv.co.y *= max(0.25, 1.0 - u * 0.75)        # diamond section, sharp edges
        t = vv.co.z / L
        if t < 0.18:                                  # the buried point tapers
            vv.co.x *= 0.35 + 0.65 * t / 0.18
    for k in range(5):                                # nicks along both edges
        side = rng.choice((-1, 1))
        z = rng.uniform(1.0, L - 0.6)
        n = Vector((side, 0, rng.uniform(-0.6, 0.6))).normalized()
        caps = sb.bm_cut(bm, (side * (W * 0.5 - rng.uniform(0.05, 0.18)), 0, z), n)
        sb.bm_roughen(bm, caps, rng, 0.015, 0.3)
    sb.bm_crack(bm, rng, 2, 0.02, 0.01, axis=(0.3, 0, 1))
    sb.bm_noise(bm, 0.012, 1.5, seed=3)
    sb.bm_obj("blade", s, bm, K.M("Prop_Steel"), (0, 0, -1.6), sharp=30)
    for k in range(5):                                # fuller with rune inlays
        z = 0.6 + k * 1.05
        sb.box(f"rune{k}_ns", s, size=(0.12, T * 1.06, 0.42), loc=(0, 0, z), material=K.M("Prop_HolyRune"), bevel=0.0)
    sb.box("fuller_ns", s, size=(0.22, T * 1.02, 5.6), loc=(0, 0, 2.9), material=K.M("Prop_SteelDark"), bevel=0.0)


def build():
    v = sb.variants("gs", 1)[0]
    rng = K.rng_for(2100)
    s = sb.empty("sword", v, loc=(0, 0, 0), rot=(9, 14, 8))
    blade(v, rng, s)
    # crossguard: swept down at the tips
    g = sb.bm_box((3.6, 0.5, 0.36), (12, 1, 1))
    for vv in g.verts:
        u = vv.co.x / 1.8
        vv.co.z -= 0.35 * u * u
        vv.co.y *= 1.0 - 0.4 * abs(u)
        vv.co.z *= 1.0
    sb.bm_bevel(g, 0.04)
    sb.bm_noise(g, 0.015, 2.0, seed=7)
    sb.bm_obj("guard", s, g, K.M("Prop_SteelDark"), (0, 0, 6.15), sharp=30)
    for sx in (-1, 1):
        K.lathe_obj(f"guardtip{sx}", s, rng, [(0.0, 0.0), (0.2, 0.05), (0.24, 0.2), (0.0, 0.42)], 8,
                    (sx * 1.85, 0, 5.75), (0, sx * 30, 0), mat="Prop_Gold", chips=0, noise=0.01)
    K.lathe_obj("grip", s, rng, [(0.19, 0.0), (0.17, 0.3)] + [(0.17 + 0.03 * (k % 2), 0.3 + k * 0.12) for k in range(1, 12)]
                + [(0.2, 1.75), (0.0, 1.8)], 10, (0, 0, 6.3), mat="Prop_SteelDark", chips=0, noise=0.006)
    K.lathe_obj("pommel", s, rng, [(0.0, 0.0), (0.3, 0.08), (0.42, 0.3), (0.36, 0.55), (0.12, 0.7), (0.0, 0.72)], 12,
                (0, 0, 8.05), mat="Prop_Gold", chips=1, noise=0.01)
    # cracked, heaved earth around the impact
    for i in range(10):
        a = i / 10 * math.tau + rng.uniform(-0.2, 0.2)
        d = rng.uniform(1.0, 2.2)
        sz = (rng.uniform(0.8, 1.4), rng.uniform(0.6, 1.0), 0.32)
        sb.stone_block(f"heave{i}", v, sz, K.M("Prop_StoneDark"), rng, loc=(math.cos(a) * d, math.sin(a) * d, 0.08),
                       rot=(math.degrees(math.sin(a)) * -0.4, math.degrees(math.cos(a)) * 0.4 + rng.uniform(5, 18) * 0,
                            math.degrees(a)), chips=2, step=0.5)
    K.rubble(v, rng, (0, 0, 0), 3.2, 10, 0.15, 0.5)
    K.socket(v, "light", (0.6, -0.6, 2.0))
    sb.tri_report("giant_sword")
    return v
