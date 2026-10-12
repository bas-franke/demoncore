"""Landmark: the toppled head of a colossal angel statue lying on its cheek, broken golden halo,
a fallen stone wing and marble debris."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import bmesh  # noqa: E402
import _props_kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"
MB = "Prop_Marble"


def head(parent, rng):
    """Head modelled upright (face -Y, crown +Z, radius ~1.1 m), centred at the origin."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=28, radius=1.0)
    for v in bm.verts:
        v.co.x *= 0.95
        v.co.y *= 1.12
        v.co.z *= 1.28
        if v.co.y < -0.4:                       # flatten the face plane
            v.co.y = -0.4 + (v.co.y + 0.4) * 0.78
        if v.co.z < -0.5:                       # narrower jaw / chin
            k = 1.0 - 0.28 * min(1.0, (-v.co.z - 0.5) / 0.75)
            v.co.x *= k
    bm.normal_update()

    def g(x, z, cx, cz, rx, rz):
        return math.exp(-(((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2))

    for v in bm.verts:
        x, y, z = v.co
        if y > -0.3:
            continue
        front = min(1.0, (-0.3 - y) / 0.4)
        d = 0.0
        for sx in (-1, 1):
            d -= 0.2 * g(x, z, sx * 0.36, 0.1, 0.2, 0.13)      # eye sockets
            d += 0.09 * g(x, z, sx * 0.36, 0.34, 0.26, 0.08)    # brow ridge
            d += 0.06 * g(x, z, sx * 0.55, -0.15, 0.2, 0.18)    # cheekbones
            d += 0.05 * g(x, z, sx * 0.36, 0.05, 0.12, 0.07)    # closed eyelids
        if abs(x) < 0.2 and -0.42 < z < 0.3:                    # nose: ridge growing towards the tip
            t = (0.3 - z) / 0.72
            d += 0.34 * t ** 1.3 * max(0.0, 1.0 - (abs(x) / (0.08 + 0.12 * t)) ** 2)
        d += 0.07 * g(x, z, 0, -0.58, 0.2, 0.05)                # upper lip
        d += 0.08 * g(x, z, 0, -0.7, 0.17, 0.05)                # lower lip
        d -= 0.05 * g(x, z, 0, -0.64, 0.2, 0.018)               # mouth line
        d += 0.08 * g(x, z, 0, -0.98, 0.22, 0.12)               # chin
        v.co.y -= d * front
    # broken neck + a chunk sheared off the back of the skull
    caps = sb.bm_cut(bm, (0, 0.1, -1.05), Vector((0.15, 0.25, -1)).normalized())
    caps += sb.bm_cut(bm, (0.55, 0.75, 0.75), Vector((0.6, 0.7, 0.5)).normalized())
    sb.bm_roughen(bm, [f for f in caps if f.is_valid], rng, 0.08, 0.3)
    sb.bm_crack(bm, rng, 1, 0.03, 0.015)
    sb.bm_noise(bm, 0.02, 1.2, seed=11)
    sb.bm_obj("skull", parent, bm, K.M(MB), sharp=70)    # carved hair: heavy locks sweeping back over the crown
    for k in range(9):
        phi = math.radians(-70 + k * 17.5)
        pts = []
        for i in range(6):
            th = math.radians(18 + i * 26)
            r = 1.06
            p = Vector((math.sin(th) * math.sin(phi) * 0.95 * r, math.sin(th) * math.cos(phi) * 1.12 * r + 0.05,
                        math.cos(th) * 1.28 * r))
            pts.append(p)
        bm = sb.bm_limb(pts, [0.14, 0.2, 0.22, 0.2, 0.17, 0.1], 7, 1, rng, 0.08)
        sb.bm_cut(bm, (0.55, 0.75, 0.75), Vector((0.6, 0.7, 0.5)).normalized())
        sb.bm_noise(bm, 0.02, 2.0, seed=k)
        sb.bm_obj(f"lock{k}", parent, bm, K.M(MB), sharp=60)
    neck = sb.bm_column(0.62, 0.9, 14, 2)
    caps = sb.bm_cut(neck, (0, 0, 0.25), Vector((0.2, -0.3, -1)).normalized())
    sb.bm_roughen(neck, caps, rng, 0.08, 0.35)
    sb.bm_noise(neck, 0.02, 1.5, seed=5)
    sb.bm_obj("neck", parent, neck, K.M(MB), (0, 0.15, -1.85))


def arc(parent, name, r, a0, a1, n, tube, mat, loc=(0, 0, 0), rot=(0, 0, 0)):
    pts = [(math.cos(math.radians(a0 + (a1 - a0) * i / n)) * r, math.sin(math.radians(a0 + (a1 - a0) * i / n)) * r, 0)
           for i in range(n + 1)]
    bm = sb.bm_limb(pts, [tube] * (n + 1), 8, 1)
    sb.bm_noise(bm, 0.01, 3, seed=n)
    return sb.bm_obj(name, parent, bm, K.M(mat), loc, rot, sharp=50)


def build():
    v = sb.variants("fc", 1)[0]
    rng = K.rng_for(2300)
    h = sb.empty("head", v, loc=(0, 0, 1.05), rot=(6, 78, 18))
    h.scale = (1.55, 1.55, 1.55)
    head(h, rng)
    # broken halo: one arc leaning on the skull, one half sunk in the earth
    arc(v, "halo_a", 2.4, 15, 160, 16, 0.16, "Prop_Gold", (-0.4, 1.9, 0.3), (62, 0, 8))
    arc(v, "halo_b", 2.4, 185, 285, 11, 0.16, "Prop_Gold", (-1.4, -1.4, 0.12), (4, -3, -35))
    # fallen wing: long marble feathers fanned on the ground
    w = sb.empty("wing", v, loc=(2.1, 1.4, 0.0), rot=(0, 0, rng.uniform(-15, 15)))
    for i in range(6):
        L = 5.0 - i * 0.55
        bm = sb.bm_box((L, 0.72, 0.24), (5, 1, 1))
        for vv in bm.verts:
            t = (vv.co.x + L * 0.5) / L
            vv.co.y *= max(0.2, 1.0 - t ** 3 * 0.8)
            vv.co.z += 0.1 * math.sin(t * math.pi)
        if i in (1, 4):
            caps = sb.bm_cut(bm, (L * rng.uniform(0.1, 0.3), 0, 0), Vector((1, rng.uniform(-0.4, 0.4), 0.2)).normalized())
            sb.bm_roughen(bm, caps, rng, 0.03, 0.3)
        sb.bm_bevel(bm, 0.03)
        sb.bm_noise(bm, 0.02, 1.6, seed=i)
        ang = -10 - i * 17
        a = math.radians(ang)
        sb.bm_obj(f"feather{i}", w, bm, K.M(MB), (math.cos(a) * L * 0.5, math.sin(a) * L * 0.5, 0.1 + i * 0.03),
                  (rng.uniform(-3, 3), 0, ang))
    K.rubble(v, rng, (0.4, -0.6, 0), 3.6, 12, 0.2, 0.7, MB, blocks=0.3)
    K.socket(v, "light", (0.0, -1.6, 2.2))
    sb.tri_report("fallen_colossus")
    return v
