"""Penitent Statue: a weathered marble angel, hooded and veiled, both hands pressed over its face.
Light weeps from beneath its fingers, runs down the chest and bleeds through a fissure that splits
its robe from hem to waist. Deep carved drapery, moss in the upturned folds, grime creeping up
from the hem. Carved stone wings raised behind it: the left one whole, the right snapped at the
elbow (the break glows; the lost tip lies on the plinth). A broken stone halo with a gilt inlay.
It still stands on a fragment of its square plinth, one corner cracked away.

Joints (every piece that falls in the death crumble is its own joint):
  base (plinth) > chunk_plinth, body > robe_L, robe_R, torso > chunk_shoulder, head, halo,
  wing_L > wing_L_hand, wing_R (broken)
Anims: idle / walk (loops: grinding stillness, a rocking shuffle), windup (crouch, stone groans),
attack (the leap; Godot adds the arc - impact lands on the LAST frame), land (impact hold +
grinding recovery, played by penitent_statue.gd on play_land), hit (chip and jolt),
death (crumbles: robe halves split, head, wings, halo and chunks fall)."""
import importlib.util
import math
import os
import random

import bmesh
import bpy
from mathutils import Vector, Matrix, noise as _noise

import sb
import sbanim as S

_spec = importlib.util.spec_from_file_location("_angel", os.path.join(os.path.dirname(__file__), "_angel.py"))
A = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(A)

CATEGORY = "enemies"

# material slot indices (every bmesh part carries all slots; unused ones are stripped at the end)
ST, GR, MO, CR, TE, GI, PL = range(7)
MATS = []

ROBE_H = 0.64          # robe height above the plinth
PLINTH_H = 0.15


# ----------------------------------------------------------------------------- helpers

def mk(name, parent, bm, loc=(0, 0, 0), rot=(0, 0, 0), sharp=42.0):
    o = sb.bm_obj(name, parent, bm, None, loc, rot, sharp=sharp)
    for m in MATS:
        o.data.materials.append(m)
    return o


def nz(p, scale=1.0, seed=0.0):
    return _noise.noise(Vector(p) * scale + Vector((seed * 3.1, seed * 7.7, seed * 1.3)))


def paint(bm, idx, pred):
    bm.normal_update()
    for f in bm.faces:
        if pred(f.calc_center_median(), f.normal):
            f.material_index = idx


def moss(bm, up=0.45, th=0.05, scale=7.0, seed=0.0, up_vec=(0, 0, 1)):
    u = Vector(up_vec).normalized()
    paint(bm, MO, lambda c, n: n.dot(u) > up and nz(c, scale, seed) > th)


def crack(name, parent, pts, r=0.006, mat=None):
    return sb.ptube(name, parent, pts, [r * (1.0 - 0.5 * i / max(1, len(pts) - 1)) for i in range(len(pts))],
                    sides=3, material=mat or MATS[CR], smooth=False)


def interp(profile, z):
    """Radius of a (r, z) profile at height z (linear)."""
    if z <= profile[0][1]:
        return profile[0][0]
    for (r0, z0), (r1, z1) in zip(profile[:-1], profile[1:]):
        if z <= z1:
            return r0 + (r1 - r0) * (z - z0) / max(z1 - z0, 1e-6)
    return profile[-1][0]


def lathe_fn(R, zs, segs, cap_top=True, cap_bottom=True, ysc=1.0):
    """Surface of revolution with radius R(a, z) (a = angle from +X). Optional top pole."""
    bm = bmesh.new()
    rows = []
    for z in zs:
        if z is None:
            continue
        row = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            r = R(a, z)
            row.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r * ysc, z)))
        rows.append(row)
    for lo, hi in zip(rows[:-1], rows[1:]):
        for j in range(segs):
            bm.faces.new((lo[j], lo[(j + 1) % segs], hi[(j + 1) % segs], hi[j]))
    if cap_bottom:
        bm.faces.new(list(reversed(rows[0])))
    if cap_top:
        bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def plate_bm(outline, thick, y=0.0, idx=ST):
    """Solid plate from an (x, z) outline (simple polygon), thickness along Y."""
    bm = bmesh.new()
    fr = [bm.verts.new((x, y - thick * 0.5, z)) for x, z in outline]
    bk = [bm.verts.new((x, y + thick * 0.5, z)) for x, z in outline]
    n = len(outline)
    bm.faces.new(fr)
    bm.faces.new(list(reversed(bk)))
    for k in range(n):
        k1 = (k + 1) % n
        bm.faces.new((fr[k1], fr[k], bk[k], bk[k1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.material_index = idx
    return bm


def feathers_outline(top, feathers, hw, notch=0.06, back=0.07):
    """Carved feather tier outline in (x, z): the `top` edge (inner -> outer), then each feather
    (base, tip) listed outer -> inner as a rounded lobe, with a deep notch between neighbours."""
    out = [Vector(p) for p in top]
    n = len(feathers)
    for k, (b, t) in enumerate(feathers):
        b, t = Vector(b), Vector(t)
        d = (t - b).normalized()
        p = Vector((-d.y, d.x))
        ref = Vector(feathers[k - 1][1]) if k > 0 else out[-1]
        if p.dot(ref - t) < 0:
            p = -p
        w = hw[k] if isinstance(hw, (list, tuple)) else hw
        out += [t - d * back + p * w, t - d * 0.014 + p * w * 0.5, t - d * 0.014 - p * w * 0.5,
                t - d * back - p * w]
        if k + 1 < n:
            b2, t2 = Vector(feathers[k + 1][0]), Vector(feathers[k + 1][1])
            dm = (d + (t2 - b2).normalized()).normalized()
            out.append((t + t2) * 0.5 - dm * (back + notch))
    return [tuple(v) for v in out]


WS = 1.18   # wing scale


def wing_parts(s, rng, broken=False):
    """Carved stone wing for side s (+1 = +X): returns (root_bm, hand_bm or None, hand_loc)."""
    def X(pts):
        return [(p[0] * s * WS, p[1] * WS) for p in pts]
    root = bmesh.new()
    # coverts (thick top tier of short rounded feathers)
    cf = []
    for k in range(7):
        x = 0.52 - 0.08 * k
        cf.append(((x, 0.04), (x + 0.015, -0.13 - 0.04 * x + rng.uniform(-0.01, 0.01))))
    cov = feathers_outline([(0.0, 0.03), (0.28, 0.085), (0.55, 0.065)], cf, 0.034, notch=0.02, back=0.05)
    sb.bm_merge(root, plate_bm(X(cov), 0.05, y=-0.018))
    # secondaries (long, hanging)
    sf = []
    for k in range(6):
        x = 0.5 - 0.092 * k
        sf.append(((x - 0.01, 0.0), (x + 0.03, -0.4 - 0.07 * x + rng.uniform(-0.015, 0.015))))
    sec = feathers_outline([(-0.02, -0.02), (0.53, 0.0)], sf, 0.04, notch=0.05, back=0.08)
    sb.bm_merge(root, plate_bm(X(sec), 0.034, y=0.004))
    # arm (leading edge bone)
    arm = sb.bm_limb([(0, 0, 0.02), (s * 0.26 * WS, 0, 0.085 * WS), (s * 0.5 * WS, 0, 0.05 * WS)],
                     [0.045, 0.038, 0.032], sides=6, samples=1)
    sb.bm_merge(root, arm)
    hand = None
    hloc = (s * 0.5 * WS, 0.0, 0.05 * WS)
    if not broken:
        hand = bmesh.new()
        pf = []
        for k in range(6):
            ang = math.radians(-4 - 15.0 * k)
            dv = Vector((math.cos(ang), math.sin(ang)))
            ln = 0.5 - 0.03 * k
            pf.append((tuple(dv * 0.12), tuple(dv * ln)))
        pri = feathers_outline([(-0.06, 0.0), (0.24, 0.02)], pf, 0.042, notch=0.05, back=0.09)
        pri.append((-0.07, -0.26))
        sb.bm_merge(hand, plate_bm(X(pri), 0.03, y=0.008))
        sb.bm_merge(hand, sb.bm_limb([(0, 0, 0), (s * 0.2 * WS, 0, 0.012 * WS), (s * 0.36 * WS, 0, -0.01 * WS)],
                                     [0.032, 0.025, 0.013], sides=6, samples=1))
        sb.bm_noise(hand, 0.005, 9.0, seed=rng.randrange(999))
        moss(hand, 0.6, 0.3, 8.0, 3.0, up_vec=(0, 0.8, 0.6))
    else:
        # snapped past the elbow: jagged break, light bleeding out of it
        caps = sb.bm_cut(root, (s * 0.4 * WS, 0, 0), Vector((s * 1.0, 0.0, 0.45)).normalized())
        caps = [f for f in caps if f.is_valid]
        sb.bm_roughen(root, caps, rng, 0.02)
        root.normal_update()
        for f in root.faces:
            if f.calc_center_median().x * s > 0.3 * WS and f.normal.x * s > 0.55:
                f.material_index = CR
    sb.bm_noise(root, 0.005, 9.0, seed=rng.randrange(999))
    sb.bm_chip(root, rng, 1, 0.05)
    moss(root, 0.6, 0.22, 8.0, 1.0 + s, up_vec=(0, 0.8, 0.6))
    return root, hand, hloc

# ----------------------------------------------------------------------------- build

def build():
    rng = random.Random(11)
    MATS.clear()
    MATS.extend([
        sb.mat("Statue_WeatheredMarble", (0.62, 0.6, 0.55), roughness=0.9),
        sb.mat("Statue_GrimeStone", (0.33, 0.32, 0.29), roughness=0.96),
        sb.mat("Statue_Moss", (0.19, 0.26, 0.1), roughness=1.0),
        sb.mat("Statue_CrackLight", (1.0, 0.86, 0.55), roughness=0.5, emission=(1.0, 0.76, 0.38), strength=6.0),
        sb.mat("Statue_TearLight", (1.0, 0.97, 0.9), roughness=0.3, emission=(1.0, 0.94, 0.78), strength=8.0),
        sb.mat("Statue_HaloGiltGold", (0.62, 0.46, 0.2), roughness=0.45, metallic=1.0),
        sb.mat("Statue_PlinthStone", (0.42, 0.4, 0.37), roughness=0.95),
    ])
    root = sb.root("PenitentStatue")

    # ------------------------------------------------------------ plinth fragment (base)
    base = sb.empty("base", root)
    W, D = 0.64, 0.6
    corner_n = Vector((1.0, -1.0, 0.12)).normalized()      # front-right corner cracked off
    corner_c = Vector((W * 0.5 - 0.13, -D * 0.5 + 0.13, 0.0))

    def plinth_bm():
        bm = sb.bm_box((W, D, PLINTH_H), (7, 7, 1))
        bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, PLINTH_H * 0.5))
        return bm
    pb = plinth_bm()
    sb.bm_cut(pb, corner_c, corner_n)
    sb.bm_chip(pb, rng, 2, 0.08, rough=0.012)
    sb.bm_cut(pb, (-W * 0.5 + 0.1, D * 0.5, PLINTH_H), Vector((-0.6, 0.5, 0.6)).normalized())  # back-left bite
    sb.bm_crack(pb, rng, 1, depth=0.02, axis=(1, 0.3, 0))
    sb.bm_bevel(pb, 0.012)
    sb.bm_noise(pb, 0.006, 6.0, seed=4)
    for f in pb.faces:
        f.material_index = PL
    moss(pb, 0.6, 0.12, 6.0, 2.0)
    paint(pb, MO, lambda c, n: n.z < 0.3 and c.z < 0.05 and nz(c, 5.0, 9.0) > 0.0)  # moss creeping up the foot
    mk("plinth", base, pb)
    # carved inscription band on the front (dark grooves)
    for i in range(5):
        x = -0.22 + i * 0.075
        sb.box(f"glyph{i}", base, size=(0.035, 0.01, 0.05), loc=(x, -D * 0.5 - 0.002, 0.075),
               rot=(0, rng.uniform(-20, 20), 0), material=MATS[GR], bevel=0.0)
    # the broken-off corner (its own joint; slides off in the death)
    chunk_plinth = sb.empty("chunk_plinth", base, loc=(W * 0.5 - 0.07, -D * 0.5 + 0.07, 0.0))
    cb = plinth_bm()
    sb.bm_cut(cb, corner_c + corner_n * 0.008, -corner_n)
    sb.bm_bevel(cb, 0.01)
    sb.bm_noise(cb, 0.005, 6.0, seed=5)
    for f in cb.faces:
        f.material_index = PL
    moss(cb, 0.6, 0.0, 6.0, 2.0)
    bmesh.ops.translate(cb, verts=cb.verts, vec=(-(W * 0.5 - 0.07), D * 0.5 - 0.07, 0))
    mk("plinth_corner", chunk_plinth, cb)
    # glowing fracture along the corner break, on the top face
    crack("crack_plinth", base, [(corner_c.x - 0.13 + 0.01, corner_c.y - 0.13, PLINTH_H + 0.003),
                                 (corner_c.x - 0.03, corner_c.y - 0.04, PLINTH_H + 0.003),
                                 (corner_c.x + 0.05, corner_c.y + 0.03, PLINTH_H + 0.003),
                                 (corner_c.x + 0.13, corner_c.y + 0.13, PLINTH_H + 0.003)], 0.006)
    # bare stone feet on the plinth, toes chipped
    for s in (-1, 1):
        ft = sb.bm_limb([(s * 0.07, -0.17, PLINTH_H + 0.03), (s * 0.08, -0.25, PLINTH_H + 0.022),
                         (s * 0.085, -0.285, PLINTH_H + 0.016)], [0.04, 0.034, 0.022], sides=6, samples=1)
        sb.bm_noise(ft, 0.004, 12.0, seed=s + 3)
        for f in ft.faces:
            f.material_index = GR
        mk(f"foot_{s}", base, ft)
    # the snapped-off wing tip of the right wing, lying on the plinth
    tip = bmesh.new()
    pf = []
    for k in range(4):
        dv = Vector((math.cos(math.radians(-6 - 16 * k)), math.sin(math.radians(-6 - 16 * k))))
        pf.append((tuple(dv * 0.1), tuple(dv * (0.36 - 0.03 * k))))
    sb.bm_merge(tip, plate_bm(feathers_outline([(-0.04, 0.0), (0.2, 0.01)], pf, 0.04, 0.05, 0.08)
                              + [(-0.05, -0.18)], 0.03))
    sb.bm_cut(tip, (0.0, 0, 0), Vector((-1, 0, 0.3)).normalized())
    sb.bm_noise(tip, 0.005, 9.0, seed=7)
    moss(tip, 0.5, 0.1, 9.0, 5.0, up_vec=(0, -1, 0))
    sb.bm_xform(tip, scale=(0.62, 0.62, 0.62))
    mk("fallen_tip", base, tip, loc=(0.19, 0.03, PLINTH_H + 0.012), rot=(-90, 0, 115))

    # ------------------------------------------------------------ robe (two halves split by a lit fissure)
    body = sb.empty("body", base, loc=(0, 0, PLINTH_H))
    prof = [(0.262, 0.0), (0.258, 0.03), (0.245, 0.12), (0.226, 0.25), (0.205, 0.38), (0.185, 0.5),
            (0.17, 0.58), (0.16, ROBE_H)]

    def robe_r(a, z):
        t = z / ROBE_H
        r0 = interp(prof, z)
        ph = a * 7 + 0.9 * math.sin(a * 3 + 1.3) + 1.3 * t
        c = math.cos(ph)
        fold = math.copysign(abs(c) ** 0.55, c)
        depth = 0.2 * (1 - t) ** 1.2 + 0.035
        return r0 * (1 + depth * fold * 0.5) * (1.0 + 0.04 * nz((math.cos(a), math.sin(a), z * 3), 2.0, 1.0))

    YS = 0.86
    zs = [0.0, 0.035, 0.1, 0.18, 0.27, 0.36, 0.45, 0.54, 0.6, ROBE_H]
    rb = lathe_fn(robe_r, zs, 30, cap_top=True, ysc=YS)
    # a chunk missing from the hem at the back-left
    caps = sb.bm_cut(rb, (-0.2, 0.17, 0.06), Vector((-0.8, 0.7, -0.7)).normalized())
    sb.bm_roughen(rb, [f for f in caps if f.is_valid], rng, 0.01)
    sb.bm_noise(rb, 0.006, 7.0, seed=1)
    paint(rb, GR, lambda c, n: c.z < 0.1 + 0.08 * nz(c, 6.0, 2.0))
    moss(rb, 0.3, 0.12, 6.0, 3.0)
    # split plane for the death crumble: the fissure drifts diagonally down the front
    split_n = Vector((1.0, 0.0, 0.1)).normalized()
    split_c = Vector((0.04, 0.0, 0.1))
    robe_L = sb.empty("robe_L", body, loc=(-0.24, 0, 0))
    robe_R = sb.empty("robe_R", body, loc=(0.24, 0, 0))
    rl = rb.copy()
    for f in sb.bm_cut(rl, split_c, split_n):   # the split faces: light inside the stone
        f.material_index = CR
    bmesh.ops.translate(rl, verts=rl.verts, vec=(0.24, 0, 0))
    mk("robe_half_L", robe_L, rl)
    for f in sb.bm_cut(rb, split_c - split_n * 0.004, -split_n):
        f.material_index = CR
    bmesh.ops.translate(rb, verts=rb.verts, vec=(-0.24, 0, 0))
    mk("robe_half_R", robe_R, rb)

    def robe_pt(x, z, front=True, off=0.008):
        """Point on the robe surface at (x, z) on the front (-Y) or back (+Y)."""
        lo, hi = (-math.pi * 0.5 - 0.9, -math.pi * 0.5 + 0.9) if front else (math.pi * 0.5 + 0.9, math.pi * 0.5 - 0.9)
        for _ in range(30):
            mid = (lo + hi) * 0.5
            if math.cos(mid) * robe_r(mid, z) < x:
                lo = mid
            else:
                hi = mid
        a = (lo + hi) * 0.5
        r = robe_r(a, z) + off
        return (math.cos(a) * r, math.sin(a) * r * YS, z)

    def seam_x(z):
        return split_c.x - split_n.z / split_n.x * (z - split_c.z)
    for nm, front in (("fissure_front", True), ("fissure_back", False)):
        pts = []
        for i, z in enumerate((0.015, 0.09, 0.17, 0.25, 0.33, 0.41, 0.49, 0.56)):
            pts.append(robe_pt(seam_x(z) + (0.012 if i % 2 else -0.012), z, front))
        crack(nm, body, pts, 0.0075)
    # branching hairline cracks with inner light
    for i, (x0, z0, dx, dz) in enumerate(((-0.12, 0.05, 0.03, 0.08), (0.14, 0.3, -0.02, 0.08),
                                          (0.0, 0.3, -0.06, 0.05))):
        pts = []
        x, z = x0, z0
        for k in range(4):
            pts.append(robe_pt(x, z, True, 0.006))
            x += dx + rng.uniform(-0.02, 0.02)
            z += dz
        crack(f"crack_robe{i}", body, pts, 0.005)

    # ------------------------------------------------------------ torso: chest + carved mantle
    torso = sb.empty("torso", body, loc=(0, 0.02, ROBE_H - 0.04), rot=(18, 0, 0))
    tprof = [(0.16, 0.0), (0.185, 0.07), (0.225, 0.16), (0.25, 0.23), (0.225, 0.29), (0.15, 0.345),
             (0.085, 0.38)]

    def mantle_r(a, z):
        r0 = interp(tprof, z)
        ph = a * 9 + 0.7 * math.sin(a * 2 + 0.4)
        c = math.cos(ph)
        d = 0.09 * max(0.0, 1.0 - abs(z - 0.18) / 0.2)
        return r0 * (1 + d * math.copysign(abs(c) ** 0.6, c))
    tb = lathe_fn(mantle_r, [z for _r, z in tprof], 20, cap_top=True, ysc=0.74)
    sb.bm_noise(tb, 0.005, 7.0, seed=6)
    moss(tb, 0.5, 0.1, 7.0, 4.0, up_vec=(0, 0.3, 1))
    mk("chest", torso, tb)
    # tears of light running down the chest from the chin
    for s in (-1, 1):
        pts = []
        for i, z in enumerate((0.31, 0.25, 0.19, 0.13, 0.07)):
            x = s * (0.03 + 0.008 * i + (0.006 if i % 2 else 0.0))
            r = mantle_r(math.atan2(-1, x / 0.74), z)
            pts.append((x, -math.sqrt(max(r * r * 0.74 * 0.74 - x * x * 0.55, 0.001)) - 0.004, z))
        crack(f"tear_chest_{s}", torso, pts, 0.0055, MATS[TE])
    crack("crack_chest", torso, [(0.17, -0.12, 0.2), (0.12, -0.15, 0.15), (0.13, -0.165, 0.08)], 0.005)
    # shoulder chunk (its own joint: knocked loose on hits, falls in the death)
    chunk_sh = sb.empty("chunk_shoulder", torso, loc=(-0.15, 0.02, 0.27))
    cs = sb.bm_rock(random.Random(2), (0.17, 0.15, 0.09), cuts=4, subdiv=1, noise=0.06)
    bmesh.ops.translate(cs, verts=cs.verts, vec=(0, 0, -0.03))
    moss(cs, 0.45, -0.15, 8.0, 6.0)
    mk("shoulder_chunk", chunk_sh, cs, rot=(0, -20, 0))
    crack("crack_shoulder", torso, [(-0.08, -0.06, 0.32), (-0.13, -0.03, 0.29), (-0.2, 0.0, 0.26)], 0.005)

    # ------------------------------------------------------------ head: hood, hidden face, hands
    head = sb.empty("head", torso, loc=(0, -0.035, 0.37), rot=(24, 0, 0))
    hprof = [(0.115, -0.1), (0.145, -0.03), (0.152, 0.05), (0.135, 0.13), (0.09, 0.19), (0.035, 0.22)]

    def hood_r(a, z):
        r0 = interp(hprof, z)
        c = math.cos(a * 5 + 0.8)
        return r0 * (1 + 0.075 * c * max(0.0, 0.2 - z) * 4)
    hb = lathe_fn(hood_r, [-0.1, -0.03, 0.01, 0.05, 0.09, 0.13, 0.19, 0.22], 18, cap_top=True, cap_bottom=True,
                  ysc=1.12)
    bmesh.ops.translate(hb, verts=hb.verts, vec=(0, 0.03, 0))
    # the veil falls from the hood down the back onto the shoulders; a slight peak at the crown
    for v in hb.verts:
        back = max(0.0, min(1.0, (v.co.y + 0.02) / 0.18))
        low = max(0.0, (0.06 - v.co.z) / 0.16)
        v.co.z -= 0.15 * back * low
        v.co.y += 0.05 * back * low
        v.co.x *= 1.0 + 0.25 * back * low
        if v.co.z > 0.15:
            v.co.y += 0.25 * (v.co.z - 0.15)
    sb.bm_dent(hb, (0, -0.17, 0.02), 0.12, 0.065)
    caps = sb.bm_cut(hb, (0.1, -0.02, 0.17), Vector((0.7, -0.3, 0.65)).normalized())  # chunk off the crown
    sb.bm_roughen(hb, [f for f in caps if f.is_valid], rng, 0.008)
    sb.bm_noise(hb, 0.004, 9.0, seed=8)
    mk("hood", head, hb)
    # hood rim framing the hidden face
    rim = sb.torus("hood_rim", head, major=0.1, minor=0.02, loc=(0, -0.118, 0.025), rot=(98, 0, 0),
                   material=MATS[ST], major_segments=14, minor_segments=4)
    rim.scale = (1.0, 1.25, 1.0)
    A.ellipsoid("face", head, (0.12, 0.1, 0.16), loc=(0, -0.1, 0.02), material=MATS[ST], seg=10, rings=6)
    # glowing crack over the crown of the hood (reads from the high camera)
    cr = []
    for i, (a, z) in enumerate(((-1.25, 0.04), (-1.4, 0.1), (-1.6, 0.15), (-2.1, 0.19), (-2.6, 0.17), (-2.9, 0.12))):
        r = hood_r(a, z) + 0.006
        cr.append((math.cos(a) * r, math.sin(a) * r * 1.12 + 0.03, z))
    crack("crack_crown", head, cr, 0.0065)
    # hands pressed over the face, fingers spread up over the brow
    bpy.context.view_layer.update()
    to_head = head.matrix_world.inverted() @ torso.matrix_world
    for s in (-1, 1):
        pc = Vector((s * 0.046, -0.168, 0.0))
        tilt = -s * 18.0
        A.ellipsoid(f"palm_{s}", head, (0.092, 0.042, 0.14), loc=tuple(pc), rot=(-8, tilt, 0), material=MATS[ST],
                    seg=8, rings=5)
        rotm = Matrix.Rotation(math.radians(tilt), 3, "Y")
        for k in range(4):
            o = -0.03 + 0.02 * k
            b0 = pc + rotm @ Vector((o, -0.004, 0.05))
            dv = rotm @ Vector((o * 0.6, 0.0, 1.0))
            ln = 0.07 + 0.012 * (1.5 - abs(k - 1.5))
            sb.ptube(f"finger_{s}_{k}", head, [b0, b0 + dv * ln * 0.55 + Vector((0, -0.006, 0)),
                                               b0 + dv * ln + Vector((0, 0.022, 0))],
                     [0.0125, 0.0115, 0.008], sides=4, material=MATS[ST])
        tb0 = pc + rotm @ Vector((s * 0.04, 0.0, -0.035))
        sb.ptube(f"thumb_{s}", head, [tb0, tb0 + Vector((s * 0.012, 0.015, -0.035)),
                                      tb0 + Vector((s * 0.01, 0.035, -0.06))],
                 [0.014, 0.012, 0.009], sides=4, material=MATS[ST])
        wrist = Vector((s * 0.055, -0.15, -0.045))
        elbow_t = Vector((s * 0.16, -0.16, 0.1))
        elbow_h = to_head @ elbow_t
        fa = sb.bm_limb([wrist, (wrist + elbow_h) * 0.5 + Vector((s * 0.01, -0.01, 0)), elbow_h],
                        [0.03, 0.036, 0.04], sides=6, samples=1)
        mk(f"forearm_{s}", head, fa)
        ua = sb.bm_limb([(s * 0.2, 0.0, 0.25), (s * 0.2, -0.09, 0.17), elbow_t], [0.055, 0.05, 0.045], sides=7,
                        samples=1)
        sb.bm_noise(ua, 0.004, 9.0, seed=s)
        moss(ua, 0.6, 0.2, 9.0, 8.0)
        mk(f"upperarm_{s}", torso, ua)
        # tears of light running from beneath the hands
        crack(f"tear_{s}", head, [(s * 0.03, -0.17, -0.04), (s * 0.036, -0.158, -0.075), (s * 0.03, -0.14, -0.1)],
              0.006, MATS[TE])
        crack(f"tear_b_{s}", head, [(s * 0.075, -0.15, 0.0), (s * 0.085, -0.135, -0.05)], 0.0045, MATS[TE])

    # ------------------------------------------------------------ broken stone halo with gilt inlay
    halo = sb.empty("halo", torso, loc=(0, 0.075, 0.56), rot=(-52, 0, 0))
    hring = sb.bm_box((1.0, 0.035, 1.0), (14, 1, 1))
    sb.bm_arc(hring, (0, 0, 0), 0.15, 0.19, -50, 235)
    sb.bm_noise(hring, 0.004, 12.0, seed=9)
    sb.bm_chip(hring, rng, 1, 0.03)
    moss(hring, 0.6, 0.2, 10.0, 9.0, up_vec=(0, -1, 0.3))
    mk("halo_ring", halo, hring)
    gilt = sb.bm_box((1.0, 0.012, 1.0), (14, 1, 1))
    sb.bm_arc(gilt, (0, 0, 0), 0.163, 0.177, -40, 228)
    for f in gilt.faces:
        f.material_index = GI
    mk("halo_gilt", halo, gilt, loc=(0, -0.016, 0))
    crack("halo_glow", halo, [(math.cos(math.radians(a)) * 0.17, -0.024, math.sin(math.radians(a)) * 0.17)
                              for a in (40, 70, 100, 130)], 0.0045)

    # ------------------------------------------------------------ carved stone wings
    WP = dict(up=28, sweep=40, pitch=52)
    wing_L = sb.empty("wing_L", torso, loc=(-0.12, 0.13, 0.25), rot=A.wing_pose(-1, **WP))
    wing_R = sb.empty("wing_R", torso, loc=(0.12, 0.13, 0.25), rot=A.wing_pose(1, **WP))
    lr, lh, lhl = wing_parts(-1, rng)
    mk("wing_L_root", wing_L, lr)
    wing_L_hand = sb.empty("wing_L_hand", wing_L, loc=lhl, rot=(0, 8, 0))
    mk("wing_L_tip", wing_L_hand, lh)
    rr, _n, _l = wing_parts(1, rng, broken=True)
    mk("wing_R_stump", wing_R, rr)

    # ------------------------------------------------------------ merge, clean, animate
    A.merge_by_joint(root)
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH":
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.material_slot_remove_unused()
    animate(root, base, chunk_plinth, body, robe_L, robe_R, torso, chunk_sh, head, halo, wing_L, wing_L_hand,
            wing_R)
    A.report("penitent_statue")
    return root


# ----------------------------------------------------------------------------- animation

def animate(root, base, chunk_plinth, body, robe_L, robe_R, torso, chunk_sh, head, halo, wing_L, wing_L_hand,
            wing_R):
    J = S.joints(root)

    # idle: dead still... then stone grinds: a shiver, the head creaks a few degrees, settles.
    c = S.Clip("idle", 90, joints=J)
    c.key(head, 0)
    c.key(head, 30, rot=(0, 0, 0), ease="expo_out")
    c.key(head, 34, rot=(-2.5, 0, 3.5))
    c.key(head, 66, rot=(-2.5, 0, 3.5), ease="expo_out")
    c.key(head, 71, rot=(0, 0, 0))
    c.key(torso, 0)
    c.key(torso, 28, rot=(0, 0, 0), ease="expo_out")
    c.key(torso, 33, rot=(-0.8, 0, 1.0))
    c.key(torso, 64, rot=(-0.8, 0, 1.0), ease="expo_out")
    c.key(torso, 70, rot=(0, 0, 0))
    S.jitter(c, torso, rot=(0.5, 0.3, 0.5), freq=14, seed=1, start=27, end=36)
    S.jitter(c, head, rot=(0.9, 0.5, 0.9), freq=16, seed=2, start=29, end=37)
    S.jitter(c, torso, rot=(0.5, 0.3, 0.5), freq=14, seed=3, start=63, end=72)
    S.jitter(c, head, rot=(0.8, 0.4, 0.8), freq=16, seed=4, start=65, end=73)
    S.jitter(c, wing_L, rot=(0.6, 0.6, 0.3), freq=12, seed=5, start=28, end=36)
    S.jitter(c, wing_R, rot=(0.6, 0.6, 0.3), freq=12, seed=6, start=64, end=72)
    S.jitter(c, chunk_sh, rot=(2, 2, 2), freq=18, seed=7, start=28, end=34)
    S.noise(c, body, rot=(0.15, 0.15, 0.1), freq=0.4, seed=8)
    c.bake()

    # walk: it does not walk. It rocks its plinth from corner to corner, grinding forward.
    c = S.Clip("walk", 32, joints=J)
    tilt = 3.2
    c.add(base, lambda f: (-1.2, tilt * S.wave(c, f), 0))
    c.add(base, lambda f: (0, 0, 0.3 * math.sin(math.radians(tilt * abs(S.wave(c, f))))), "loc")
    c.add(torso, lambda f: (1.5 * S.wave(c, f, 2), -tilt * 0.4 * S.wave(c, f, 1, -0.08), 0))
    c.add(head, lambda f: (0, -tilt * 0.4 * S.wave(c, f, 1, -0.12), 0))
    c.add(wing_L, lambda f: (0, 2.0 * S.wave(c, f, 1, -0.15), 0))
    c.add(wing_R, lambda f: (0, 2.0 * S.wave(c, f, 1, -0.15), 0))
    S.jitter(c, body, rot=(0.6, 0.4, 0.6), freq=14, seed=11)
    S.jitter(c, head, rot=(0.6, 0.4, 0.6), freq=12, seed=12)
    c.bake()

    # windup: groaning crouch. Rises a hair, then sinks and hunches, wings lift, it trembles.
    crouch = {body: {"rot": (-3, 0, 0), "scale": (1.07, 1.07, 0.84)},
              torso: {"rot": (17, 0, 0), "loc": (0, 0, -0.02)},
              head: {"rot": (8, 0, 0)},
              wing_L: {"rot": (-8, 22, 18)}, wing_L_hand: {"rot": (0, 10, 0)},
              halo: {"rot": (-6, 0, 0)}, base: {"rot": (0, 0, 0)}}
    c = S.Clip("windup", 14, joints=J)
    c.pose(0, {body: {"rot": (0, 0, 0), "scale": (1, 1, 1)}, torso: {"rot": (0, 0, 0)}, head: {"rot": (0, 0, 0)},
               wing_L: {"rot": (0, 0, 0)}, wing_L_hand: {"rot": (0, 0, 0)}, halo: {"rot": (0, 0, 0)}}, mirror=True)
    c.pose(3, {body: {"rot": (1.5, 0, 0), "scale": (0.98, 0.98, 1.03)}, torso: {"rot": (-3, 0, 0)},
               head: {"rot": (-4, 0, 0)}}, ease="cubic_inout")
    c.pose(10, crouch, ease="smooth", mirror=True)
    c.pose(14, {body: {"rot": (-3.5, 0, 0), "scale": (1.08, 1.08, 0.82)}, torso: {"rot": (18, 0, 0), "loc": (0, 0, -0.022)},
                head: {"rot": (9, 0, 0)}, wing_L: {"rot": (-9, 25, 20)}, wing_L_hand: {"rot": (0, 12, 0)},
                halo: {"rot": (-7, 0, 0)}}, mirror=True)
    S.jitter(c, body, rot=(1.4, 0.8, 1.4), freq=15, seed=21, start=5, end=14, fade=3)
    S.jitter(c, head, rot=(1.5, 1, 1.5), freq=13, seed=22, start=6, end=14, fade=3)
    S.jitter(c, chunk_sh, rot=(3, 3, 3), freq=18, seed=23, start=6, end=14, fade=2)
    c.bake()

    # attack: the leap. Godot lifts the rig along the arc (peak early, falls fast) and the stomp
    # lands on the LAST frame -> the clip ends on the impact squash ("land" holds it).
    c = S.Clip("attack", 22, joints=J)
    c.pose(0, {body: {"rot": (-3.5, 0, 0), "scale": (1.08, 1.08, 0.82)}, torso: {"rot": (18, 0, 0), "loc": (0, 0, -0.022)},
               head: {"rot": (9, 0, 0)}, wing_L: {"rot": (-9, 25, 20)}, wing_L_hand: {"rot": (0, 12, 0)},
               halo: {"rot": (-7, 0, 0)}}, ease="quad_out", mirror=True)
    c.pose(3, {body: {"rot": (-8, 0, 0), "scale": (0.93, 0.93, 1.13)}, torso: {"rot": (-10, 0, 0), "loc": (0, 0, 0.01)},
               head: {"rot": (-12, 0, 0)}, wing_L: {"rot": (-15, 48, 40)}, wing_L_hand: {"rot": (0, 20, 0)},
               halo: {"rot": (6, 0, 0)}}, ease="cubic_out", mirror=True)
    c.pose(8, {body: {"rot": (-3, 0, 0), "scale": (1, 1, 1.02)}, torso: {"rot": (-4, 0, 0), "loc": (0, 0, 0)},
               head: {"rot": (-6, 0, 0)}, wing_L: {"rot": (0, -14, 34)}, wing_L_hand: {"rot": (0, -16, 0)},
               halo: {"rot": (-4, 0, 0)}}, ease="sine_inout", mirror=True)
    c.pose(13, {body: {"rot": (5, 0, 0), "scale": (1, 1, 1)}, torso: {"rot": (2, 0, 0)},
                head: {"rot": (-2, 0, 0)}, wing_L: {"rot": (-6, 14, 30)}, wing_L_hand: {"rot": (0, 4, 0)},
                halo: {"rot": (2, 0, 0)}}, ease="quad_in", mirror=True)
    c.pose(19, {body: {"rot": (12, 0, 0), "scale": (0.97, 0.97, 1.06)}, torso: {"rot": (-6, 0, 0)},
                head: {"rot": (-10, 0, 0)}, wing_L: {"rot": (-12, 46, 26)}, wing_L_hand: {"rot": (0, 22, 0)},
                halo: {"rot": (10, 0, 0)}}, ease="quad_in", mirror=True)
    c.pose(22, {body: {"rot": (5, 0, 0), "scale": (1.14, 1.14, 0.78)}, torso: {"rot": (24, 0, 0), "loc": (0, 0, -0.03)},
                head: {"rot": (14, 0, 0)}, wing_L: {"rot": (6, -18, 22)}, wing_L_hand: {"rot": (0, -14, 0)},
                halo: {"rot": (-12, 0, 0)}, chunk_sh: {"loc": (-0.01, 0, 0.012)}}, mirror=True)
    c.key(chunk_sh, 19, loc=(0, 0, 0))
    S.jitter(c, body, rot=(0.8, 0.5, 0.8), freq=12, seed=31, start=9, end=18, fade=3)
    c.bake()

    # land: impact HOLD (shudders, the shoulder chunk rattles), then grinds back upright.
    land_pose = {body: {"rot": (5, 0, 0), "scale": (1.14, 1.14, 0.78)}, torso: {"rot": (24, 0, 0), "loc": (0, 0, -0.03)},
                 head: {"rot": (14, 0, 0)}, wing_L: {"rot": (6, -18, 22)}, wing_L_hand: {"rot": (0, -14, 0)},
                 halo: {"rot": (-12, 0, 0)}, chunk_sh: {"loc": (-0.01, 0, 0.012)}}
    c = S.Clip("land", 12, joints=J)
    c.pose(0, land_pose, ease="smooth", mirror=True)
    c.pose(2, {body: {"rot": (4, 0, 0), "scale": (1.12, 1.12, 0.8)}, torso: {"rot": (22, 0, 0), "loc": (0, 0, -0.028)},
               head: {"rot": (13, 0, 0)}, wing_L: {"rot": (8, -22, 22)}, wing_L_hand: {"rot": (0, -18, 0)},
               halo: {"rot": (-14, 0, 0)}, chunk_sh: {"loc": (0, 0, 0)}}, ease="smooth", mirror=True)
    c.pose(5, {body: {"rot": (3, 0, 0), "scale": (1.1, 1.1, 0.82)}, torso: {"rot": (20, 0, 0), "loc": (0, 0, -0.025)},
               head: {"rot": (12, 0, 0)}, wing_L: {"rot": (6, -18, 20)}, wing_L_hand: {"rot": (0, -12, 0)},
               halo: {"rot": (-10, 0, 0)}}, ease="sine_inout", mirror=True)
    c.pose(12, {body: {"rot": (0, 0, 0), "scale": (1, 1, 1)}, torso: {"rot": (0, 0, 0), "loc": (0, 0, 0)},
                head: {"rot": (0, 0, 0)}, wing_L: {"rot": (0, 0, 0)}, wing_L_hand: {"rot": (0, 0, 0)},
                halo: {"rot": (0, 0, 0)}, chunk_sh: {"loc": (0, 0, 0)}}, mirror=True)
    S.jitter(c, body, rot=(1.6, 0.8, 1.6), freq=16, seed=41, start=0, end=6, fade=1)
    S.jitter(c, chunk_sh, rot=(5, 5, 5), freq=18, seed=42, start=0, end=6, fade=1)
    S.jitter(c, head, rot=(1.2, 0.8, 1.2), freq=12, seed=43, start=5, end=12, fade=2)
    c.bake()

    # hit: a chip and a jolt - knocked back a hair, the shoulder chunk jumps and drops back.
    c = S.Clip("hit", 9, joints=J)
    c.pose(0, {body: {"rot": (0, 0, 0), "loc": (0, 0, 0)}, torso: {"rot": (0, 0, 0)}, head: {"rot": (0, 0, 0)},
               chunk_sh: {"rot": (0, 0, 0), "loc": (0, 0, 0)}}, ease="expo_out")
    c.pose(1, {body: {"rot": (-4, 0, 2.5), "loc": (0, 0.03, 0)}, torso: {"rot": (-7, 0, -3)}, head: {"rot": (-6, 0, 4)},
               chunk_sh: {"rot": (-14, 10, -18), "loc": (-0.02, 0.01, 0.035)}}, ease="quad_out")
    c.pose(4, {body: {"rot": (1, 0, -0.6), "loc": (0, 0.012, 0)}, torso: {"rot": (2, 0, 0.8)}, head: {"rot": (1.5, 0, -1)},
               chunk_sh: {"rot": (4, -3, 5), "loc": (0, 0, 0)}}, ease="sine_inout")
    c.pose(9, {body: {"rot": (0, 0, 0), "loc": (0, 0, 0)}, torso: {"rot": (0, 0, 0)}, head: {"rot": (0, 0, 0)},
               chunk_sh: {"rot": (0, 0, 0), "loc": (0, 0, 0)}})
    S.jitter(c, torso, rot=(1.2, 0.6, 1.2), freq=16, seed=51, start=1, end=7, fade=2)
    c.bake()

    # death: a last shudder, then it comes apart - the robe splits down the fissure and the halves
    # fall outward, the torso drops, the weeping head (hands still over its face) tumbles forward,
    # the wings and halo snap off, the plinth corner slides away. Everything settles by ~f24.
    c = S.Clip("death", 32, joints=J)
    S.jitter(c, body, rot=(2.2, 1.2, 2.2), freq=15, seed=61, start=0, end=7, fade=2)
    c.key(head, 0)
    c.key(head, 4, rot=(-16, 0, 5), ease="quad_in")
    c.key(head, 7, rot=(-14, 0, 4), loc=(0, 0, 0.0), ease="quad_in")
    c.key(head, 16, rot=(95, 14, 26), loc=(0, -0.26, -0.5), ease="quad_out")
    c.key(head, 19, rot=(84, 14, 28), loc=(0, -0.29, -0.45), ease="quad_in")
    c.key(head, 22, rot=(98, 16, 30), loc=(0, -0.31, -0.5), ease="sine_out")
    c.key(head, 32, rot=(98, 16, 30), loc=(0, -0.31, -0.5))
    # robe halves fall outward around their outer hem
    for j, sg in ((robe_L, -1), (robe_R, 1)):
        c.key(j, 0)
        c.key(j, 6, rot=(0, sg * 2, 0), ease="quad_in")
        c.key(j, 17, rot=(-6 * sg, sg * 82, 4 * sg), ease="quad_out")
        c.key(j, 20, rot=(-5 * sg, sg * 72, 4 * sg), ease="quad_in")
        c.key(j, 23, rot=(-6 * sg, sg * 84, 4 * sg))
        c.key(j, 32, rot=(-6 * sg, sg * 84, 4 * sg))
    # torso drops onto the plinth, tipping back
    c.key(torso, 0)
    c.key(torso, 7, rot=(-4, 0, 0), ease="quad_in")
    c.key(torso, 16, rot=(-38, 6, -10), loc=(0, 0.05, -0.5), ease="quad_out")
    c.key(torso, 19, rot=(-30, 6, -10), loc=(0, 0.05, -0.46), ease="quad_in")
    c.key(torso, 22, rot=(-40, 6, -10), loc=(0, 0.05, -0.5))
    c.key(torso, 32, rot=(-40, 6, -10), loc=(0, 0.05, -0.5))
    # wings snap off and fall outward
    c.key(wing_L, 0)
    c.key(wing_L, 6, rot=(0, 8, 0), ease="quad_in")
    c.key(wing_L, 17, rot=(30, -55, 25), loc=(-0.15, 0.05, -0.15), ease="bounce_out")
    c.key(wing_L, 25, rot=(34, -62, 25), loc=(-0.16, 0.05, -0.18))
    c.key(wing_L_hand, 0)
    c.key(wing_L_hand, 12, rot=(0, -10, 0), ease="quad_out")
    c.key(wing_L_hand, 18, rot=(0, 25, 0), ease="bounce_out")
    c.key(wing_L_hand, 25, rot=(0, 20, 0))
    c.key(wing_R, 0)
    c.key(wing_R, 5, rot=(4, -6, 0), ease="quad_in")
    c.key(wing_R, 15, rot=(40, 50, -20), loc=(0.12, 0.12, -0.15), ease="bounce_out")
    c.key(wing_R, 24, rot=(44, 56, -20), loc=(0.12, 0.13, -0.17))
    # halo slides off behind
    c.key(halo, 0)
    c.key(halo, 5, rot=(4, 0, 0), ease="quad_in")
    c.key(halo, 15, rot=(-30, 0, 25), loc=(0.05, 0.16, -0.32), ease="bounce_out")
    c.key(halo, 24, rot=(-32, 0, 25), loc=(0.05, 0.17, -0.34))
    # shoulder chunk pops off first
    c.key(chunk_sh, 0)
    c.key(chunk_sh, 4, rot=(-20, -10, -25), loc=(-0.06, -0.02, 0.06), ease="quad_out")
    c.key(chunk_sh, 8, rot=(-40, -20, -50), loc=(-0.14, -0.04, 0.03), ease="quad_in")
    c.key(chunk_sh, 15, rot=(-80, -30, -80), loc=(-0.3, -0.05, -0.2), ease="bounce_out")
    c.key(chunk_sh, 22, rot=(-90, -30, -90), loc=(-0.32, -0.05, -0.22))
    # plinth corner cracks away
    c.key(chunk_plinth, 0)
    c.key(chunk_plinth, 9, rot=(0, 0, 0), ease="quad_in")
    c.key(chunk_plinth, 16, rot=(-14, 18, -6), loc=(0.05, -0.05, -0.02), ease="bounce_out")
    c.key(chunk_plinth, 24, rot=(-16, 20, -6), loc=(0.06, -0.06, -0.025))
    c.bake()

