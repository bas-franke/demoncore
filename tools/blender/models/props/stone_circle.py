"""Landmark: ring of weathered menhirs around an obsidian altar (2 variants). The glowing sigil
decal + hell light are added in Godot at the origin; candle sockets sit at some stones."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import bmesh  # noqa: E402
import _props_kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"

def menhir(v, rng, name, h, loc, yaw, lean=0.0, fallen=False):
    w, t = rng.uniform(0.9, 1.15), rng.uniform(0.6, 0.8)
    bm = sb.bm_box((w, t, h), (3, 2, max(3, int(h / 0.45))), z0=True)
    for vv in bm.verts:
        k = vv.co.z / h
        vv.co.x *= 1.0 - 0.3 * k * k
        vv.co.y *= 1.0 - 0.25 * k
    sb.bm_cut(bm, (rng.uniform(-0.2, 0.2), 0, h * 0.92), Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.3, 0.3), 1)).normalized())
    sb.bm_chip(bm, rng, 3, 0.18, rough=0.03)
    sb.bm_crack(bm, rng, 1, 0.03, 0.012)
    sb.bm_bevel(bm, 0.04)
    sb.bm_noise(bm, 0.08, 1.1, seed=rng.randrange(999))
    if fallen:
        return sb.bm_obj(name, v, bm, K.M("Prop_StoneDark"), (loc[0], loc[1], t * 0.4), (90, 0, yaw))
    return sb.bm_obj(name, v, bm, K.M("Prop_StoneDark"), (loc[0], loc[1], -0.15), (lean, 0, yaw))


def build():
    vs = sb.variants("sc", 2, 13.0)
    for vi, v in enumerate(vs):
        rng = K.rng_for(2200 + vi)
        n = (8, 9)[vi]
        R = 4.4
        for i in range(n):
            ang = i / n * math.tau + rng.uniform(-0.1, 0.1)
            p = (math.cos(ang) * R, math.sin(ang) * R)
            roll = rng.random()
            if roll < 0.15 + 0.1 * vi:
                menhir(v, rng, f"m{i}", rng.uniform(2.0, 2.6), p, math.degrees(ang) + rng.uniform(-30, 30), fallen=True)
            else:
                menhir(v, rng, f"m{i}", rng.uniform(2.2, 3.3), p, math.degrees(ang) + 90,
                       rng.uniform(-9, 9) if roll < 0.5 else 0.0)
            if rng.random() < 0.35:
                K.socket(v, f"candles{i}", (p[0] * 0.84, p[1] * 0.84, 0.0))

        sb.stone_block("altar", v, (1.15, 0.8, 0.5), K.M("Prop_ObsidianAltar"), rng, loc=(0, 0, 0.25), chips=2,
                       step=0.3)
        sb.box("altar_rune_ns", v, size=(0.7, 0.06, 0.02), loc=(0, 0, 0.505), material=K.M("Prop_HellRune"), bevel=0.0)
        K.bone_scatter(v, rng, (1.2, -1.0), 0.6, 4)
        K.skull("skull_ns", v, rng, (-1.0, 1.2, 0), (0, 0, rng.uniform(0, 360)))
        K.socket(v, "sigil", (0, 0, 0.03))
        K.socket(v, "light", (0, 0, 1.3))
    sb.tri_report("stone_circle")
    return vs[0]
