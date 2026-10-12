"""Archon of the Seventh Gate (elite angel, SLAM): a towering knight in layered, gold-filigreed
ivory plate. A great helm under a crown of blades with a burning cross-shaped visor, a breastplate
engraved with the winged sun and the Eye of the Throne, a heavy folded cape, TWO pairs of great
wings, a three-ring blazing halo, and a huge two-handed greatsword whose fuller burns with runes.

Rig (empties, forward = -Y, L = +X): body (ground pivot) > hips > thigh/shin/foot_L/R,
tabard_0..2, spine > chest > head, pauldron_L/R, arms (shoulder line) > fore (elbow line) > sword
(both fists on the grip), cape_0..4, wing_L/R(+_hand), wing2_L/R(+_hand), halo_mount > halo
(spin, 7 shards) / halo_inner / halo_outer.

Anims (30 fps):
  idle    72 f loop   breathing, slow menacing head scan, wings settle, cape sway, halos turn
  walk    36 f loop   heavy planted stride (WALK_SPEED m/s in model units, see archon.gd)
  windup  33 f        dip, then the blade is hauled high overhead, wings flare, halo swells;
                      trembling hold (stretched over the slam wind-up)
  attack   9 f        expo downswing, the blade bites the ground on f7 (stretched over charge_time)
  recover 27 f        impact hold (blade in the ground), heave it out, back to guard
                      (played by archon.gd during the slam recovery)
  hit     18 f        stagger
  death   84 f        reels, kneels on its planted sword, the halo shatters, it falls
"""
import importlib.util
import math
import os
import random

import bmesh
from mathutils import Euler, Matrix
import sb
import sbanim as A
import sbmat

_spec = importlib.util.spec_from_file_location("_angel", os.path.join(os.path.dirname(__file__), "_angel.py"))
K = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(K)

CATEGORY = "enemies"

# Ivory plate, gold and blade steel are procedural (sbmat graphs: engraved gold filigree inlaid
# in the ivory, edge wear, cavity grime) baked into one 1024 atlas; everything else stays flat.
# Every non-emissive surface is baked (a baked mesh must not mix in flat materials: their faces
# keep default UVs and wreck the atlas packing), so the glowing parts (visor, runes, halo, eye)
# live on their own joints with flat emissive materials.
BAKE = {"size": 1024, "samples": 16}


def pmat(name, color, roughness=0.5, metallic=0.0):
    """Plain colour, but flagged for baking (so it can share a mesh with baked materials)."""
    m, _ = sbmat._new(name, color, roughness, metallic)
    return m


def filigree_ivory(name, tint=(0.84, 0.8, 0.7), inlay=(0.95, 0.7, 0.3), scale=1.0, bevel=0.01):
    """Ivory plate engraved with scrolling gold-inlaid filigree (warped ring + band scrollwork),
    polished worn edges, warm grime in the crevices."""
    m, g = sbmat._new(name, tint, 0.36, 0.1)
    if g is None:
        return m
    co = g.co(scale)
    warp = g.vadd(co, g.vscale(g.noise(co, 2.2, 3.0, 0.5, color=True), 0.16))
    w1 = g.wave(warp, 4.5, "RINGS", "SPHERICAL", "SIN", 6.0, 2.0)
    w2 = g.wave(warp, 7.0, "BANDS", "Z", "SIN", 4.0, 2.0)
    line = g.maxf(g.remap(w1, 0.11, 0.03), g.mul(g.remap(w2, 0.09, 0.02), g.remap(g.noise(co, 3.0, 2.0), 0.45, 0.6)))
    cav = g.cavity(0.1)
    edge = g.edges(bevel, 0.05, g.noise(co, 15.0, 3.0))
    yel = g.remap(g.noise(co, 2.2, 5.0), 0.4, 0.75)
    col = g.mix(g.mul(yel, 0.22), tint, (0.7, 0.6, 0.42))
    col = g.mix(edge, col, sbmat._lin(tint, 1.15))
    col = g.mix(line, col, inlay)
    col = g.mix(g.mul(cav, 0.85), col, (0.2, 0.14, 0.07))
    rough = g.lerp(line, g.lerp(edge, 0.4, 0.24), 0.22)
    rough = g.lerp(cav, rough, 0.75)
    metal = g.mul(line, 0.95)
    nrm = g.bump(g.mul(line, -1.0), 0.35, 0.002)
    g.out(col, rough, metal, nrm)
    return m

BULK = 1.3
LEG_LEN = 0.85
WALK = dict(stride=24, frames=36)
WALK_SPEED = A.stride_speed(LEG_LEN, WALK["stride"], WALK["frames"])

SWORD_REST = 131.0     # sword pitch in the fore frame: blade low, point forward-down
HALO_N = 7             # 7 shards / 14 rays -> 7-fold symmetry (seamless spin loops)


# ============================================================================ geometry helpers

def sheet(name, parent, t0, t1, length, w0, w1, folds=3.0, depth=0.035, thick=0.016, nx=12,
          curl=0.03, material=None, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Solid folded cloth panel hanging from its joint (top edge at z=0, down -Z). t0/t1 = the
    panel's span (0..1) of the whole garment, so folds deepen continuously down the chain."""
    bm = bmesh.new()
    grid = []
    for j, t in enumerate((t0, t1)):
        w = w0 + (w1 - w0) * j
        rf, rb = [], []
        for i in range(nx + 1):
            u = i / nx
            x = (u - 0.5) * w
            y = depth * math.sin(u * folds * 2 * math.pi) * (0.3 + 0.7 * t) + curl * (2 * u - 1) ** 2
            z = -length * j
            rf.append(bm.verts.new((x, y - thick * 0.5, z)))
            rb.append(bm.verts.new((x, y + thick * 0.5, z)))
        grid.append((rf, rb))
    (f0, b0), (f1, b1) = grid
    for i in range(nx):
        bm.faces.new((f0[i], f0[i + 1], f1[i + 1], f1[i]))
        bm.faces.new((b0[i + 1], b0[i], b1[i], b1[i + 1]))
    ring_f = f0 + [f1[nx]] + list(reversed(f1)) + [f0[0]]
    ring_b = b0 + [b1[nx]] + list(reversed(b1)) + [b0[0]]
    # boundary: top row, right side, bottom row, left side
    bound = [(f0[i], f0[i + 1], b0[i + 1], b0[i]) for i in range(nx)]
    bound += [(f1[i], f1[i + 1], b1[i + 1], b1[i]) for i in range(nx)]
    bound += [(f0[0], f1[0], b1[0], b0[0]), (f0[nx], f1[nx], b1[nx], b0[nx])]
    del ring_f, ring_b
    for q in bound:
        bm.faces.new(q)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = sb._new_mesh_obj(name, bm)
    return sb._finish(obj, parent, material, loc, rot, (1, 1, 1), 0.0, 0, True, name)


def quads(name, parent, rects, y, material, both=True):
    """Flat glyph quads [(cx, cz, w, h, angle_deg), ...] in the XZ plane at depth y (facing -Y);
    `both` mirrors them onto the +Y face at -y. Cheap engraved / glowing inlays (2 tris each)."""
    bm = bmesh.new()
    for side in ((1, -1) if both else (1,)):
        yy = y * side
        for cx, cz, w, h, ang in rects:
            a = math.radians(ang)
            ca, sa = math.cos(a), math.sin(a)
            pts = []
            for px, pz in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
                pts.append(bm.verts.new((cx + px * ca - pz * sa, yy, cz + px * sa + pz * ca)))
            f = bm.faces.new(pts if side == 1 else list(reversed(pts)))
            f.normal_update()
    obj = sb._new_mesh_obj(name, bm)
    o = sb._finish(obj, parent, material, (0, 0, 0), (0, 0, 0), (1, 1, 1), 0.0, 0, False, name)
    # make every quad face outward (-Y for the front set, +Y for the back set)
    for p in o.data.polygons:
        want = -1 if p.center.y < 0 else 1
        if p.normal.y * want < 0:
            p.flip()
    return o


def blade_mesh(name, parent, z0, length, w0, w1, t, material):
    """Greatsword blade along +Z: flattened hexagonal section (sharp edges, flat faces), tapering
    from w0 to w1 then a long point."""
    rows = [(z0, w0 * 1.08), (z0 + 0.06, w0), (z0 + length * 0.5, (w0 + w1) * 0.5),
            (z0 + length * 0.86, w1), (z0 + length, 0.003)]
    bm = bmesh.new()
    ring = []
    for z, w in rows:
        tt = t * (0.35 if w < 0.01 else 1.0)
        sec = [(w, 0), (w * 0.4, -tt), (-w * 0.4, -tt), (-w, 0), (-w * 0.4, tt), (w * 0.4, tt)]
        ring.append([bm.verts.new((x, y, z)) for x, y in sec])
    for a, b in zip(ring[:-1], ring[1:]):
        for k in range(6):
            bm.faces.new((a[k], a[(k + 1) % 6], b[(k + 1) % 6], b[k]))
    bm.faces.new(list(reversed(ring[0])))
    bm.faces.new(ring[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = sb._new_mesh_obj(name, bm)
    return sb._finish(obj, parent, material, (0, 0, 0), (0, 0, 0), (1, 1, 1), 0.0, 0, False, name)


def arc(name, parent, r, minor, a0, a1, material, n=6, sides=5):
    """Arc of a ring in the local XY plane (degrees a0..a1)."""
    pts = [(r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), r * math.sin(math.radians(a0 + (a1 - a0) * i / n)), 0)
           for i in range(n + 1)]
    return sb.ptube(name, parent, pts, [minor] * len(pts), sides=sides, material=material)


def pfeather(name, parent, length, width, thick, loc, rot, material, curve=0.12, steps=3):
    """Broad feather (rounded tip, full vane) hanging along +Z from its quill (like K.feather)."""
    bm = bmesh.new()
    rows = []
    for i in range(steps + 1):
        t = i / steps
        w = width * (0.72 + 0.28 * math.sin(math.pi * min(t * 1.3, 1.0))) * math.sqrt(max(0.0, 1.0 - t ** 3)) + 0.004
        z = t * length
        y = curve * t * t * length
        rows.append([bm.verts.new((-w, y - thick, z)), bm.verts.new((w, y - thick, z)),
                     bm.verts.new((w, y + thick * 0.4, z)), bm.verts.new((-w, y + thick * 0.4, z))])
    for a, b in zip(rows[:-1], rows[1:]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = sb._new_mesh_obj(name, bm)
    return sb._finish(obj, parent, material, loc, rot, (1, 1, 1), 0.0, 0, False, name)


def great_wing(name, parent, s, loc, span, m, bone_mat, cov_mat, n_prim=10, n_sec=8, n_cov=6, width=0.1,
               up=20.0, sweep=30.0, pitch=60.0):
    """Layered feathered wing on side s (+1 = +X): shoulder joint `name` and `name_hand` (the outer
    half with the primaries). Broad overlapping feathers in three ranks (secondaries, primaries,
    coverts) so the wing reads as a solid fan from the high camera. Returns (root, hand)."""
    root = sb.empty(name, parent, loc=loc, rot=K.wing_pose(s, up, sweep, pitch))
    elbow = sb.Vector((s * span * 0.42, 0.0, span * 0.1))
    hand = sb.empty(name + "_hand", root, loc=tuple(elbow))
    tip = sb.Vector((s * span * 0.6, 0.0, span * 0.02))
    K.seg(name + "_arm", root, (0, 0, 0), elbow, span * 0.05, span * 0.035, material=bone_mat, segments=7)
    K.seg(name + "_fore", hand, (0, 0, 0), tip * 0.92, span * 0.035, span * 0.012, material=bone_mat, segments=6)
    sb.sphere(name + "_knuckle", hand, radius=span * 0.045, material=m["gold_baked"], segments=7, rings=5)
    fmat, tmat = m["feather_baked"], m["feather_tip_baked"]
    for i in range(n_sec):
        t = (i + 0.5) / n_sec
        p = elbow * (0.08 + 0.92 * t)
        ln = span * (0.5 + 0.1 * t)
        pfeather(f"{name}_sec{i}", root, ln, width * span, 0.005 * span,
                 (p.x, 0.014 * span * (1 - t), p.z - 0.02 * span), (0, 180 - s * (-2 + 10 * t), 0),
                 fmat if i % 3 else tmat, curve=0.1)
    for i in range(n_prim):
        t = (i + 0.5) / n_prim
        p = tip * (0.05 + 0.95 * t)
        ln = span * (0.6 + 0.3 * t - 0.12 * t * t)
        pfeather(f"{name}_pri{i}", hand, ln, width * span * (1.0 - 0.2 * t), 0.005 * span,
                 (p.x, 0.012 * span * (1 - t), p.z - 0.01 * span), (0, 180 - s * (10 + 58 * t ** 1.2), 0),
                 fmat if i % 2 == 0 else tmat, curve=0.16)
    for i in range(n_cov):
        t = (i + 0.5) / n_cov
        if t < 0.6:
            par, p = root, elbow * (t / 0.6)
        else:
            par, p = hand, tip * ((t - 0.6) / 0.4) * 0.7
        pfeather(f"{name}_cov{i}", par, span * 0.26, width * span * 1.15, 0.007 * span,
                 (p.x, -0.016 * span, p.z + 0.01 * span), (0, 180 - s * (6 + 36 * t), 0), cov_mat, curve=0.08,
                 steps=2)
    return root, hand


def wpose(s, up=0.0, sweep=0.0, pitch=0.0):
    """Wing rotation OFFSET for side s (+1 = +X/L): up = raise, sweep = fold back, pitch."""
    return (pitch, -s * up, s * sweep)


# ============================================================================ build

def build():
    m = K.mats()
    ivory = filigree_ivory("Archon_IvoryPlate")
    ivory_d = filigree_ivory("Archon_IvoryShadow", tint=(0.62, 0.57, 0.47), scale=1.3)
    gold = sbmat.gold_filigree("Archon_GoldFiligree", tint=(0.95, 0.68, 0.28))
    gold_d = pmat("Archon_GoldAged", (0.52, 0.36, 0.14), 0.42, 1.0)
    gold_flat = sb.mat("Archon_GoldHaloStud", (0.85, 0.63, 0.27), roughness=0.28, metallic=1.0)
    steel = sbmat.worn_steel("Archon_SteelBlade", tint=(0.66, 0.68, 0.72), roughness=0.2, grime=0.5)
    mail = sbmat.worn_steel("Archon_SteelMail", tint=(0.3, 0.3, 0.31), roughness=0.45, scale=3.0)
    cape_m = sbmat.linen("Archon_ClothCape", tint=(0.2, 0.22, 0.3))
    tabard_m = sbmat.linen("Archon_ClothTabard", tint=(0.8, 0.76, 0.66))
    leather = sbmat.leather("Archon_LeatherGrip", tint=(0.2, 0.11, 0.06))
    void = pmat("Archon_VoidSlit", (0.01, 0.01, 0.012), 1.0, 0.0)
    visor = sb.mat("Archon_VisorLight", (1.0, 0.93, 0.72), roughness=0.3, emission=(1.0, 0.86, 0.5), strength=9.0)
    fuller = sb.mat("Archon_FullerLight", (1.0, 0.85, 0.55), roughness=0.3, emission=(1.0, 0.72, 0.32), strength=4.0)
    rune = sb.mat("Archon_RuneLight", (1.0, 0.97, 0.86), roughness=0.3, emission=(1.0, 0.94, 0.75), strength=10.0)
    halo_m = sb.mat("Archon_HaloLight", (1.0, 0.9, 0.62), roughness=0.4, emission=(1.0, 0.84, 0.5), strength=7.0)
    halo_w = sb.mat("Archon_HaloCore", (1.0, 0.98, 0.9), roughness=0.4, emission=(1.0, 0.96, 0.86), strength=10.0)
    m["gold_baked"] = gold
    m["feather_baked"] = sbmat.feathers("Archon_WingFeather", tint=(0.9, 0.88, 0.82), sheen=(0.95, 0.93, 0.88),
                                        barbs=60.0)
    m["feather_tip_baked"] = sbmat.feathers("Archon_WingFeatherTip", tint=(0.72, 0.66, 0.55),
                                            sheen=(0.8, 0.74, 0.62), barbs=60.0)
    rnd = random.Random(7)

    root = sb.root("Archon")
    body = sb.empty("body", root)
    hips = sb.empty("hips", body, loc=(0, 0, 0.98))

    # ------------------------------------------------------------------ legs
    thigh, shin, foot = {}, {}, {}
    for sd, s in (("L", 1), ("R", -1)):
        th = thigh[sd] = sb.empty(f"thigh_{sd}", hips, loc=(s * 0.13, 0, -0.04))
        K.seg(f"thighmail_{sd}", th, (0, 0, 0), (0, 0, -0.42), 0.085, 0.07, material=mail, segments=8)
        K.lathe(f"cuisse_{sd}", th, [(0.0, -0.4), (0.07, -0.38), (0.098, -0.22), (0.095, -0.06), (0.07, 0.0),
                                     (0.0, 0.01)], segments=10, material=ivory, loc=(0, -0.016, 0),
                scale=(1.05, 0.88, 1))
        K.ring(f"cuisse_trim_{sd}", th, 0.088, 0.009, loc=(0, -0.014, -0.36), material=gold, seg=12, mseg=3)
        sh = shin[sd] = sb.empty(f"shin_{sd}", th, loc=(0, 0, -0.43))
        K.ellipsoid(f"poleyn_{sd}", sh, (0.13, 0.1, 0.12), loc=(0, -0.05, 0.0), material=gold, seg=10, rings=6)
        K.feather(f"poleyn_wing_{sd}", sh, length=0.14, width=0.045, thickness=0.01, loc=(s * 0.05, -0.05, -0.01),
                  rot=(0, s * 70, 0), material=gold, steps=2)
        K.spike(f"kneespike_{sd}", sh, (0, -0.09, 0.0), (0, -0.5, 1), 0.1, 0.07, 0.024, material=ivory)
        K.lathe(f"greave_{sd}", sh, [(0.0, -0.4), (0.06, -0.39), (0.082, -0.26), (0.09, -0.13), (0.07, -0.02),
                                     (0.0, 0.0)], segments=10, material=ivory, scale=(1.0, 1.05, 1))
        sb.box(f"greave_ridge_{sd}", sh, size=(0.014, 0.02, 0.3), loc=(0, -0.092, -0.2), material=gold, bevel=0.0)
        ft = foot[sd] = sb.empty(f"foot_{sd}", sh, loc=(0, 0, -0.42))
        K.ellipsoid(f"sabaton_{sd}", ft, (0.13, 0.3, 0.1), loc=(0, -0.08, -0.045), material=ivory, seg=10, rings=6)
        for k in range(2):
            K.ellipsoid(f"sab_lame{k}_{sd}", ft, (0.12 - k * 0.02, 0.1, 0.08), loc=(0, -0.11 - k * 0.07, -0.03 - k * 0.01),
                        material=gold if k else ivory_d, seg=8, rings=5)
        K.ellipsoid(f"toecap_{sd}", ft, (0.08, 0.1, 0.06), loc=(0, -0.21, -0.055), material=gold, seg=8, rings=5)
        K.ring(f"ankle_{sd}", ft, 0.07, 0.012, loc=(0, -0.01, 0.02), material=gold, seg=10, mseg=3)

    # ------------------------------------------------------------------ hips: faulds, mail, tassets, belt
    K.lathe("mailskirt", hips, [(0.24 * BULK, -0.34), (0.2 * BULK, 0.06)], segments=14, material=mail)
    for k in range(3):
        K.lathe(f"fauld{k}", hips, [(0.215 * BULK + k * 0.012, -0.05 - k * 0.055), (0.2 * BULK + k * 0.012, 0.02 - k * 0.055)],
                segments=16, material=ivory if k != 1 else ivory_d)
        K.ring(f"fauld_trim{k}", hips, 0.212 * BULK + k * 0.012, 0.007, loc=(0, 0, -0.05 - k * 0.055),
               material=gold, seg=16, mseg=3)
    K.ring("belt", hips, 0.205 * BULK, 0.024, loc=(0, 0, 0.07), material=gold_d, seg=16, mseg=4)
    K.ellipsoid("buckle", hips, (0.11, 0.04, 0.09), loc=(0, -0.2 * BULK * 0.95, 0.07), material=gold, seg=10, rings=6)
    for i, a in enumerate((-38, 38, -95, 95, -150, 150)):
        ca, sa = math.sin(math.radians(a)), -math.cos(math.radians(a))
        r = 0.23 * BULK
        for k in range(2):
            K.plate(f"tasset{i}_{k}", hips, [(-0.085, 0.0), (0.085, 0.0), (0.075, -0.17), (0.0, -0.2), (-0.075, -0.17)],
                    0.014, material=ivory if k == 0 else gold,
                    loc=(ca * (r + k * 0.012), sa * (r + k * 0.012), -0.06 - k * 0.13), rot=(-14, 0, a))
    # tabard (front cloth chain off the belt) with a gold hem
    tabard = [sb.empty("tabard_0", hips, loc=(0, -0.2 * BULK - 0.04, 0.04))]
    for i in range(1, 3):
        tabard.append(sb.empty(f"tabard_{i}", tabard[-1], loc=(0, 0, -0.24)))
    for i, tj in enumerate(tabard):
        sheet(f"tabard_m{i}", tj, i / 3, (i + 1) / 3, 0.26, 0.2 + i * 0.015, 0.215 + i * 0.015, folds=1.5,
              depth=0.012, thick=0.012, nx=6, curl=0.0, material=tabard_m)
    sb.box("tabard_hem", tabard[2], size=(0.24, 0.02, 0.03), loc=(0, 0, -0.25), material=gold, bevel=0.0)
    K.plate("tabard_sigil", tabard[0], [(0, 0.0), (0.045, -0.06), (0, -0.16), (-0.045, -0.06)], 0.006,
            material=gold, loc=(0, -0.012, -0.04))

    # ------------------------------------------------------------------ spine / abdomen
    spine = sb.empty("spine", hips, loc=(0, 0, 0.12))
    for k in range(3):
        K.lathe(f"plackart{k}", spine, [(0.19 * BULK - k * 0.008, -0.05 + k * 0.07), (0.2 * BULK - k * 0.006, 0.03 + k * 0.07)],
                segments=16, material=ivory, scale=(1, 0.8, 1))
        K.ring(f"plack_trim{k}", spine, 0.2 * BULK - k * 0.006, 0.006, loc=(0, 0, 0.03 + k * 0.07), material=gold,
               seg=16, mseg=3).scale = (1, 0.8, 1)

    # ------------------------------------------------------------------ chest: cuirass + engraved winged-sun relief
    chest = sb.empty("chest", spine, loc=(0, 0, 0.18))
    prof = [(0.0, -0.03), (0.17, -0.03), (0.2, 0.08), (0.232, 0.2), (0.236, 0.27), (0.2, 0.36), (0.13, 0.42),
            (0.0, 0.43)]
    CY = 0.75
    sb.lathe("cuirass", chest, prof, segments=20, material=ivory, scale=(BULK, CY, 1))

    def r_at(z):
        for (r0, z0), (r1, z1) in zip(prof[:-1], prof[1:]):
            if z0 <= z <= z1 and z1 > z0:
                return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
        return prof[-1][0]

    def front(x, z, out=0.006):
        r = r_at(z)
        q = max(0.0, 1.0 - (x / (r * BULK)) ** 2)
        return -(r * CY) * math.sqrt(q) - out

    sb.box("ridge", chest, size=(0.018, 0.03, 0.32), loc=(0, front(0, 0.2, 0.0), 0.2), rot=(4, 0, 0),
           material=gold, bevel=0.0)
    # neckline + waist filigree lines following the plate
    for nm, zz, span in (("neckline", 0.36, 0.2), ("waistline", 0.0, 0.27)):
        pts = []
        for i in range(9):
            x = -span + 2 * span * i / 8
            z = zz + (0.03 * math.cos(math.pi * x / span) if nm == "neckline" else -0.01 * math.cos(math.pi * x / span))
            pts.append((x, front(x, z, 0.004), z))
        sb.ptube(nm, chest, pts, [0.009] * len(pts), sides=4, material=gold)
    # scroll filigree over each pectoral (engraved spirals)
    for s in (1, -1):
        pts = []
        for i in range(12):
            u = i / 11
            ang = 2.6 * math.pi * u
            rr = 0.085 * (1 - 0.75 * u)
            x = s * (0.16 + rr * math.cos(ang) * 0.9)
            z = 0.22 + rr * math.sin(ang)
            pts.append((x, front(x, z, 0.004), z))
        sb.ptube(f"scroll_{'L' if s > 0 else 'R'}", chest, pts, [0.007] * len(pts), sides=4, material=gold)
    # winged sun: gold disc + rays + relief wings across the chest, the Eye of the Throne at its heart
    sun_z = 0.24
    K.lathe("sun_disc", chest, [(0.0, 0.0), (0.075, 0.0), (0.07, 0.012), (0.0, 0.018)], segments=16,
            material=gold, loc=(0, front(0, sun_z, 0.0), sun_z), rot=(90, 0, 0))
    for i in range(12):
        a = math.radians(i * 30 + 15)
        x, z = math.cos(a) * 0.075, sun_z + math.sin(a) * 0.075
        K.spike(f"sunray{i}", chest, (x, front(x, z, 0.0) - 0.008, z), (math.cos(a), -0.2, math.sin(a)),
                0.055 if i % 2 else 0.085, 0.026, 0.008, material=gold, up=(0, -1, 0))
    for s in (1, -1):
        for k in range(4):
            x0 = s * (0.09 + k * 0.035)
            z0 = sun_z + 0.01 - k * 0.012
            ang = s * (72 - k * 9)
            K.feather(f"relief_wing{k}_{'L' if s > 0 else 'R'}", chest, length=0.2 - k * 0.025, width=0.022,
                      thickness=0.004, loc=(x0, front(x0, z0, 0.004), z0), rot=(90 - 8, 0, 0), material=gold,
                      steps=2).rotation_euler.rotate_axis("Y", math.radians(ang))
    eye = K.eye("breast_eye", chest, (0, front(0, sun_z, 0.02), sun_z), 0.075, (0, -1, 0.05), m)
    # back plate ridge + cape clasps
    sb.box("backridge", chest, size=(0.02, 0.03, 0.3), loc=(0, 0.17, 0.2), material=gold, bevel=0.0)
    K.lathe("gorget", chest, [(0.16, 0.34), (0.15, 0.4), (0.11, 0.46), (0.085, 0.5), (0.0, 0.5)], segments=14,
            material=ivory, scale=(1.15, 0.95, 1))
    for k in range(2):
        K.ring(f"gorget_lame{k}", chest, 0.15 - k * 0.03, 0.01, loc=(0, 0, 0.39 + k * 0.05), material=gold,
               seg=14, mseg=3).scale = (1.15, 0.95, 1)

    # ------------------------------------------------------------------ pauldrons (own joints)
    paul = {}
    for sd, s in (("L", 1), ("R", -1)):
        p = paul[sd] = sb.empty(f"pauldron_{sd}", chest, loc=(s * 0.31, 0.0, 0.32))
        for k in range(4):
            mt = ivory if k % 2 == 0 else ivory_d
            K.lathe(f"paul{k}_{sd}", p, [(0.0, -0.05), (0.15 - k * 0.012, -0.045), (0.14 - k * 0.012, 0.0),
                                        (0.1 - k * 0.01, 0.045), (0.0, 0.06)], segments=11, material=mt,
                    loc=(s * (0.02 + 0.018 * k), 0, 0.05 - k * 0.062), rot=(0, s * (24 + 13 * k), 0),
                    scale=(1.0, 1.12, 1.0))
            K.ring(f"paul_trim{k}_{sd}", p, 0.146 - k * 0.012, 0.009, loc=(s * (0.02 + 0.018 * k), 0, 0.006 - k * 0.062),
                   rot=(0, s * (24 + 13 * k), 0), material=gold, seg=12, mseg=3).scale = (1.0, 1.12, 1.0)
        # upswept gold flange of feather-blades
        for k in range(4):
            K.feather(f"paul_flange{k}_{sd}", p, length=0.2 - k * 0.03, width=0.035, thickness=0.008,
                      loc=(s * (0.06 + 0.035 * k), 0.03 - 0.02 * k, 0.07), rot=(0, s * (8 + 14 * k), 0),
                      material=gold, steps=2)
        K.ellipsoid(f"paul_boss_{sd}", p, (0.06, 0.06, 0.06), loc=(s * 0.09, -0.05, 0.06), material=gold, seg=8, rings=5)

    # ------------------------------------------------------------------ arms: shared two-handed chain
    arms = sb.empty("arms", chest, loc=(0, 0, 0.30))
    fore = sb.empty("fore", arms, loc=(0, -0.1, -0.28))
    for sd, s in (("L", 1), ("R", -1)):
        shp = (s * 0.31, 0, 0)
        el = (s * 0.25, -0.1, -0.28)
        K.seg(f"rerebrace_{sd}", arms, shp, el, 0.07, 0.06, material=ivory, segments=10)
        K.seg(f"bicep_mail_{sd}", arms, shp, (s * 0.29, -0.02, -0.08), 0.075, 0.072, material=mail, segments=8)
        K.ring(f"rere_trim_{sd}", arms, 0.066, 0.008, loc=(s * 0.27, -0.065, -0.19), rot=(-20, s * 8, 0),
               material=gold, seg=10, mseg=3)
        K.ellipsoid(f"couter_{sd}", fore, (0.11, 0.11, 0.11), loc=(s * 0.25, 0.01, 0.0), material=gold, seg=8, rings=6)
        K.spike(f"couter_spike_{sd}", fore, (s * 0.25, 0.05, 0.0), (s * 0.3, 1, -0.2), 0.08, 0.05, 0.02, material=ivory)
        hand = (s * 0.06, -0.2, -0.17)
        K.seg(f"vambrace_{sd}", fore, (s * 0.25, 0, 0), hand, 0.064, 0.05, material=ivory, segments=10)
        hv = sb.Vector(hand)
        ev = sb.Vector((s * 0.25, 0, 0))
        K.seg(f"cuff_flare_{sd}", fore, ev.lerp(hv, 0.62), ev.lerp(hv, 0.86), 0.058, 0.074, material=ivory_d,
              segments=10)
        for k, u in enumerate((0.2, 0.42)):
            K.seg(f"vamb_lame{k}_{sd}", fore, ev.lerp(hv, u), ev.lerp(hv, u + 0.07), 0.071, 0.067, material=gold,
                  segments=10)
        sv = sb.Vector(shp)
        lv = sb.Vector(el)
        K.seg(f"rere_lame_{sd}", arms, sv.lerp(lv, 0.45), sv.lerp(lv, 0.56), 0.078, 0.074, material=ivory_d,
              segments=10)
        K.ring(f"vamb_cuff_{sd}", fore, 0.058, 0.012, loc=(s * 0.1, -0.16, -0.135), rot=(55, 0, s * 60),
               material=gold, seg=10, mseg=3)

    # ------------------------------------------------------------------ the greatsword (fists on its grip)
    sword = sb.empty("sword", fore, loc=(0, -0.2, -0.17), rot=(SWORD_REST, 0, 0))
    K.seg("grip", sword, (0, 0, -0.24), (0, 0, 0.12), 0.024, 0.026, material=leather, segments=8)
    for k in range(3):
        K.ring(f"grip_wrap{k}", sword, 0.027, 0.006, loc=(0, 0, -0.2 + k * 0.13), material=gold, seg=8, mseg=3)
    K.lathe("pommel", sword, [(0.0, -0.37), (0.03, -0.36), (0.055, -0.31), (0.05, -0.27), (0.024, -0.245),
                              (0.0, -0.24)], segments=10, material=gold)
    K.spike("pommel_spike", sword, (0, 0, -0.36), (0, 0, -1), 0.05, 0.03, 0.03, material=gold)
    for sd, s, z in (("L", 1, 0.04), ("R", -1, -0.1)):
        K.ellipsoid(f"fist_{sd}", sword, (0.1, 0.11, 0.1), loc=(0.0, 0.0, z), material=ivory, seg=8, rings=6)
        K.ring(f"fist_knuckles_{sd}", sword, 0.05, 0.012, loc=(0, 0, z), material=gold, seg=10, mseg=3)
    # crossguard: gold bar sweeping into feathered wings, a sunstone at the heart
    K.seg("guard_bar", sword, (-0.18, 0, 0.15), (0.18, 0, 0.15), 0.028, 0.028, material=gold, segments=8)
    for sd, s in (("L", 1), ("R", -1)):
        for k in range(3):
            K.feather(f"guard_wing{k}_{sd}", sword, length=0.24 - k * 0.05, width=0.04 - k * 0.006, thickness=0.01,
                      loc=(s * (0.13 + k * 0.03), 0, 0.15), rot=(0, s * (62 - k * 20), 0), material=gold, steps=2)
        K.ellipsoid(f"guard_cap_{sd}", sword, (0.05, 0.05, 0.05), loc=(s * 0.19, 0, 0.15), material=gold_d, seg=8, rings=5)
    K.ellipsoid("guard_heart", sword, (0.075, 0.06, 0.1), loc=(0, 0, 0.17), material=gold, seg=10, rings=6)
    glow_s = sb.empty("sword_glow", sword)
    K.ellipsoid("sunstone", glow_s, (0.04, 0.07, 0.05), loc=(0, 0, 0.17), material=rune, seg=8, rings=5)
    sb.box("ricasso", sword, size=(0.13, 0.034, 0.12), loc=(0, 0, 0.24), material=gold_d, bevel=0.0, taper=(0.85, 0.9))
    BL0, BLL = 0.28, 1.36
    blade_mesh("blade", sword, BL0, BLL, 0.07, 0.058, 0.02, steel)
    # glowing fuller + rune glyphs on both faces
    quads("fuller", glow_s, [(0, BL0 + 0.55, 0.024, 1.0, 0)], -0.0205, fuller)
    glyphs = []
    for i in range(9):
        z = BL0 + 0.12 + i * 0.11
        w = 0.012
        kind = i % 3
        glyphs.append((0, z, w, 0.07, 0))
        if kind == 0:
            glyphs += [(0.0, z + 0.015, 0.03, 0.009, 35), (0.0, z - 0.015, 0.03, 0.009, -35)]
        elif kind == 1:
            glyphs += [(0.008, z + 0.02, 0.026, 0.009, 60), (-0.008, z - 0.012, 0.026, 0.009, 60)]
        else:
            glyphs += [(0.0, z, 0.034, 0.009, 0)]
    quads("runes", glow_s, glyphs, -0.0225, rune)

    # ------------------------------------------------------------------ head: great helm + crown of blades
    head = sb.empty("head", chest, loc=(0, 0, 0.46))
    K.seg("neck", chest, (0, 0, 0.38), (0, 0, 0.52), 0.07, 0.065, material=mail, segments=8)
    sb.lathe("helm", head, [(0.0, -0.02), (0.118, -0.02), (0.13, 0.06), (0.134, 0.16), (0.128, 0.24), (0.11, 0.285),
                            (0.0, 0.3)], segments=18, material=ivory, scale=(1.0, 1.1, 1.0))
    # faceplate: a keel down the face, flanked by angled cheek plates
    K.plate("face_L", head, [(0.0, 0.25), (0.115, 0.24), (0.125, 0.04), (0.06, -0.03), (0.0, -0.035)], 0.02,
            material=ivory, loc=(0.0, -0.13, 0.0), rot=(0, 0, -18))
    K.plate("face_R", head, [(0.0, 0.25), (-0.115, 0.24), (-0.125, 0.04), (-0.06, -0.03), (0.0, -0.035)], 0.02,
            material=ivory, loc=(0.0, -0.13, 0.0), rot=(0, 0, 18))
    sb.box("keel", head, size=(0.022, 0.04, 0.29), loc=(0, -0.152, 0.11), material=gold, bevel=0.0)
    sb.box("visor_dark", head, size=(0.2, 0.03, 0.04), loc=(0, -0.152, 0.15), material=void, bevel=0.0)
    glow_h = sb.empty("visor_glow", head)
    sb.box("visor", glow_h, size=(0.19, 0.02, 0.016), loc=(0, -0.168, 0.15), material=visor, bevel=0.0)
    sb.box("visor_v", glow_h, size=(0.016, 0.02, 0.11), loc=(0, -0.172, 0.095), material=visor, bevel=0.0)
    for k in range(3):
        for s in (1, -1):
            sb.box(f"breath{k}_{'L' if s > 0 else 'R'}", head, size=(0.012, 0.02, 0.03),
                   loc=(s * (0.04 + 0.02 * k), -0.152 + 0.01 * k, 0.05), material=void, bevel=0.0)
    K.ring("helm_band", head, 0.133, 0.012, loc=(0, 0, 0.2), material=gold, seg=18, mseg=3).scale = (1.0, 1.1, 1.0)
    K.ring("helm_rim", head, 0.12, 0.012, loc=(0, 0, -0.015), material=gold, seg=18, mseg=3).scale = (1.0, 1.1, 1.0)
    # crown of blades: a gold circlet with 11 upswept sword-blades, tallest at the brow
    K.ring("crown_circlet", head, 0.122, 0.018, loc=(0, 0, 0.255), material=gold, seg=18, mseg=4).scale = (1.0, 1.1, 1.0)
    NB = 11
    for i in range(NB):
        a = math.radians(-150 + 300 * i / (NB - 1))
        c = 1.0 - abs(i - (NB - 1) / 2) / ((NB - 1) / 2)
        ln = 0.14 + 0.24 * c ** 1.4
        x, y = math.sin(a) * 0.125, -math.cos(a) * 0.137
        out = math.radians(30 - 18 * c)
        d = (math.sin(a) * math.sin(out), -math.cos(a) * math.sin(out), math.cos(out))
        K.spike(f"crown_blade{i}", head, (x, y, 0.245), d, ln, 0.04 + 0.016 * c, 0.012,
                material=steel if i % 2 else gold, up=(math.sin(a), -math.cos(a), 0))
    K.ellipsoid("crown_gem", glow_h, (0.04, 0.03, 0.055), loc=(0, -0.15, 0.27), material=rune, seg=8, rings=5)

    # ------------------------------------------------------------------ halo: three rings, the main one in 7 shards
    mount = sb.empty("halo_mount", chest, loc=(0, 0.25, 0.72), rot=(90, 0, 0))
    halo = sb.empty("halo", mount)
    R0 = 0.36
    shards = []
    for i in range(HALO_N):
        a0, a1 = 360 * i / HALO_N, 360 * (i + 1) / HALO_N
        mid = math.radians((a0 + a1) * 0.5)
        sj = sb.empty(f"halo_shard{i}", halo)
        shards.append((sj, mid))
        arc(f"halo_arc{i}", sj, R0, 0.024, a0 + 1.5, a1 - 1.5, halo_m, n=5, sides=5)
        arc(f"halo_core{i}", sj, R0, 0.012, a0 + 3, a1 - 3, halo_w, n=4, sides=4)
        for k in range(2):
            ra = math.radians(a0 + (a1 - a0) * (0.25 + 0.5 * k))
            ln = 0.3 if k == 0 else 0.17
            K.spike(f"halo_ray{i}_{k}", sj, (math.cos(ra) * (R0 + 0.025), math.sin(ra) * (R0 + 0.025), 0),
                    (math.cos(ra), math.sin(ra), 0), ln, 0.04 if k == 0 else 0.03, 0.012, material=halo_m)
        sb.sphere(f"halo_stud{i}", sj, radius=0.026, loc=(math.cos(math.radians(a0)) * R0, math.sin(math.radians(a0)) * R0, 0),
                  material=gold_flat, segments=5, rings=3)
    inner = sb.empty("halo_inner", mount)
    K.ring("halo_inner_ring", inner, 0.25, 0.011, material=halo_w, seg=24, mseg=3)
    K.ring("halo_inner_band", inner, 0.225, 0.006, material=gold_flat, seg=24, mseg=3)
    for i in range(HALO_N * 2):
        a = 2 * math.pi * i / (HALO_N * 2)
        K.spike(f"halo_tick{i}", inner, (math.cos(a) * 0.2, math.sin(a) * 0.2, 0), (math.cos(a), math.sin(a), 0),
                0.05, 0.016, 0.006, material=halo_m if i % 2 else gold_flat)
    outer = sb.empty("halo_outer", mount)
    K.ring("halo_outer_ring", outer, 0.5, 0.008, material=halo_m, seg=32, mseg=3)
    for i in range(HALO_N):
        a = 2 * math.pi * (i + 0.5) / HALO_N
        K.spike(f"halo_star{i}", outer, (math.cos(a) * 0.47, math.sin(a) * 0.47, 0), (math.cos(a), math.sin(a), 0),
                0.12, 0.03, 0.01, material=halo_w)


    # ------------------------------------------------------------------ cape: heavy, folded, 5 links
    cape = [sb.empty("cape_0", chest, loc=(0, 0.2, 0.36), rot=(-8, 0, 0))]
    for i in range(1, 5):
        cape.append(sb.empty(f"cape_{i}", cape[-1], loc=(0, 0, -0.27), rot=(3, 0, 0)))
    for i, cj in enumerate(cape):
        w0 = 0.5 + i * 0.07
        sheet(f"cape_m{i}", cj, i / 5, (i + 1) / 5, 0.29, w0, w0 + 0.07, folds=3.0, depth=0.04, thick=0.022,
              nx=14, curl=0.05 + 0.02 * i, material=cape_m)
    # lining glimpsed at the hem + gold hem band
    sb.box("cape_hem", cape[4], size=(0.86, 0.03, 0.03), loc=(0, 0.06, -0.285), material=gold, bevel=0.0)
    K.ring("cape_mantle", cape[0], 0.2, 0.03, loc=(0, -0.04, 0.0), rot=(90 + 8, 0, 0), material=cape_m,
           seg=14, mseg=4).scale = (1.4, 0.7, 1)
    for s in (1, -1):
        K.ellipsoid(f"cape_clasp_{'L' if s > 0 else 'R'}", chest, (0.08, 0.05, 0.08), loc=(s * 0.2, 0.12, 0.38),
                    material=gold, seg=8, rings=5)

    # ------------------------------------------------------------------ wings: two pairs
    WU = dict(up=24, sweep=30, pitch=66)
    WL = dict(up=-22, sweep=46, pitch=70)
    wing = {}
    for sd, s in (("L", 1), ("R", -1)):
        r1, h1 = great_wing(f"wing_{sd}", chest, s, (s * 0.13, 0.22, 0.36), 1.3, m, ivory, ivory, n_prim=10,
                            n_sec=8, n_cov=6, width=0.085, **WU)
        r2, h2 = great_wing(f"wing2_{sd}", chest, s, (s * 0.11, 0.22, 0.14), 0.86, m, ivory, ivory, n_prim=7,
                            n_sec=5, n_cov=4, width=0.09, **WL)
        wing[sd] = (r1, h1, r2, h2, s)

    # ================================================================== animation
    ALL = A.joints(root)
    tL, tR, sL, sR, fL, fR = thigh["L"], thigh["R"], shin["L"], shin["R"], foot["L"], foot["R"]
    pL, pR = paul["L"], paul["R"]
    rig = {"hips": hips, "spine": spine, "chest": chest, "head": head, "thigh": (tL, tR), "shin": (sL, sR),
           "foot": (fL, fR)}

    def wings(c, f, up=0.0, sweep=0.0, pitch=0.0, hand=0.0, up2=None, sweep2=None, pitch2=None, hand2=None,
              ease="smooth"):
        """Key both wing pairs (offsets from rest); `hand` opens(+)/folds(-) the outer half."""
        up2 = up * 0.6 if up2 is None else up2
        sweep2 = sweep * 0.8 if sweep2 is None else sweep2
        pitch2 = pitch if pitch2 is None else pitch2
        hand2 = hand if hand2 is None else hand2
        for sd in ("L", "R"):
            r1, h1, r2, h2, s = wing[sd]
            c.key(r1, f, rot=wpose(s, up, sweep, pitch), ease=ease)
            c.key(h1, f, rot=wpose(s, hand, -hand * 0.6), ease=ease)
            c.key(r2, f, rot=wpose(s, up2, sweep2, pitch2), ease=ease)
            c.key(h2, f, rot=wpose(s, hand2, -hand2 * 0.6), ease=ease)

    def halo_spin(c, turns=1, inner_turns=-1, outer_turns=1):
        step = 360.0 / HALO_N
        c.add(halo, lambda f: (0, 0, turns * step * f / c.frames), "rot")
        c.add(inner, lambda f: (0, 0, inner_turns * step * f / c.frames), "rot")
        c.add(outer, lambda f: (0, 0, outer_turns * step * f / c.frames), "rot")

    def cloth(c, floor=None, freq=1.5, wind=None):
        A.follow_through(c, cape, freq=freq, damping=0.12, gravity=6.0, falloff=0.85, inertia=1.0,
                         max_angle=70, wind=wind, floor=floor)
        A.follow_through(c, tabard, freq=2.4, damping=0.16, gravity=6.0, falloff=0.85, floor=floor)

    # ---------------------------------------------------------------- idle (loop)
    c = A.Clip("idle", 72, joints=ALL)
    A.breathe(c, chest, amp=2.2, rise=0.01, swell=0.012, cycles=1, shoulders=[pL, pR], head=head)
    c.add(hips, lambda f: (0.012 * A.wave(c, f), 0, -0.008 * abs(A.wave(c, f))), "loc")
    c.add(hips, lambda f: (0, 1.5 * A.wave(c, f), 0), "rot")
    # slow menacing scan: look left, hold, look right
    c.key(head, 0, rot=(4, 0, 0))
    c.key(head, 14, rot=(5, 0, 14), ease="sine_inout")
    c.key(head, 30, rot=(5, 0, 14), ease="sine_inout")
    c.key(head, 48, rot=(4, 0, -10), ease="sine_inout")
    c.key(head, 62, rot=(4, 0, -10), ease="sine_inout")
    A.noise(c, head, rot=(1.5, 1.5, 1.5), freq=0.5, seed=4)
    A.noise(c, arms, rot=(1.5, 0, 1.2), freq=0.4, seed=5)
    c.add(sword, lambda f: (2.0 * A.wave(c, f, offset=0.2), 0, 1.5 * A.wave(c, f, 2)), "rot")
    # wings: twice a loop they lift, half-open, and settle heavily
    for f0 in (0, 36):
        wings(c, f0, 0, 0, 0, 0)
        wings(c, f0 + 8, up=7, sweep=-6, pitch=-4, hand=6, ease="sine_inout")
        wings(c, f0 + 13, up=8, sweep=-7, pitch=-5, hand=8, ease="quad_out")
        wings(c, f0 + 22, up=-2, sweep=2, pitch=1, hand=-2, ease="sine_inout")
    for sd in ("L", "R"):
        r1, h1, r2, h2, s = wing[sd]
        A.noise(c, h1, rot=(1.5, 2, 2), freq=0.6, seed=11 + s)
        A.noise(c, h2, rot=(1.5, 2, 2), freq=0.7, seed=21 + s)
    halo_spin(c)
    A.noise(c, mount, rot=(1.0, 1.0, 0), loc=(0, 0, 0.006), freq=0.4, seed=9)
    cloth(c, wind=(0, 1.2, 0))
    c.bake()

    # ---------------------------------------------------------------- walk (loop): heavy, planted
    c = A.Clip("walk", WALK["frames"], joints=ALL)
    A.walk(c, rig, stride=WALK["stride"], knee=52, load=14, stance=0.62, lean=5, twist=7, hip_yaw=6,
           hip_roll=3.5, heavy=0.8, head_stab=0.85)
    c.key(arms, 0, rot=(-4, 0, 0))
    c.add(arms, lambda f: (2.5 * A.wave(c, f, 2, 0.1), 0, 3.0 * A.wave(c, f, 1, 0.1)), "rot")
    c.add(sword, lambda f: (3.0 * A.wave(c, f, 2, 0.25), 0, 0), "rot")
    c.add(pL, lambda f: (0, 0, 0.01 * A.wave(c, f, 2, 0.15)), "loc")
    c.add(pR, lambda f: (0, 0, 0.01 * A.wave(c, f, 2, 0.15)), "loc")
    wings(c, 0, up=-4, sweep=4)
    for sd in ("L", "R"):
        r1, h1, r2, h2, s = wing[sd]
        c.add(r1, lambda f, s=s: wpose(s, 4.0 * A.wave(c, f, 2, 0.12), 0, 0), "rot")
        c.add(h1, lambda f, s=s: wpose(s, 5.0 * A.wave(c, f, 2, 0.2), 0, 0), "rot")
        c.add(r2, lambda f, s=s: wpose(s, 3.0 * A.wave(c, f, 2, 0.16), 0, 0), "rot")
    halo_spin(c, 1, -1, 1)
    c.add(mount, lambda f: (0, 0, 0.008 * A.wave(c, f, 2, 0.3)), "loc")
    cloth(c, freq=1.4)
    c.bake()
    print("ARCHON WALK speed (model m/s) =", round(WALK_SPEED, 3))

    # ---------------------------------------------------------------- windup: the blade raised overhead
    RAISE = {arms: {"rot": (-166, 0, 0)}, fore: {"rot": (-24, 0, 0)}, sword: {"rot": (40, 0, 0)},
             chest: {"rot": (-14, 0, 0)}, spine: {"rot": (-6, 0, 0)}, head: {"rot": (-14, 0, 0)},
             hips: {"loc": (0, 0.05, -0.06)}, pL: {"rot": (0, -22, 0), "loc": (0, 0, 0.05)},
             pR: {"rot": (0, 22, 0), "loc": (0, 0, 0.05)},
             tL: {"rot": (-24, 0, 0)}, sL: {"rot": (26, 0, 0)}, fL: {"rot": (-2, 0, 0)},
             tR: {"rot": (20, 0, 0)}, sR: {"rot": (14, 0, 0)}, fR: {"rot": (-34, 0, 0)}}
    DIP = {arms: {"rot": (14, 0, 0)}, fore: {"rot": (6, 0, 0)}, sword: {"rot": (8, 0, 0)},
           chest: {"rot": (8, 0, 0)}, head: {"rot": (6, 0, 0)}, hips: {"loc": (0, 0, -0.05)},
           tL: {"rot": (-10, 0, 0)}, sL: {"rot": (18, 0, 0)}, fL: {"rot": (-8, 0, 0)},
           tR: {"rot": (-6, 0, 0)}, sR: {"rot": (14, 0, 0)}, fR: {"rot": (-8, 0, 0)}}
    c = A.Clip("windup", 33, joints=ALL)
    for j in set(RAISE) | set(DIP):
        c.key(j, 0)
    c.pose(6, DIP, ease="sine_inout")
    c.pose(20, RAISE, ease="quart_out")
    push = {j: {k: tuple(v * 1.05 for v in d[k]) for k in d} for j, d in RAISE.items()}
    c.pose(33, push, ease="sine_inout")
    A.jitter(c, arms, rot=(1.6, 0.8, 1.2), freq=10, start=21, end=33)
    A.jitter(c, head, rot=(1.0, 0.8, 1.0), freq=8, start=21, end=33, seed=3)
    wings(c, 0)
    wings(c, 6, up=-6, sweep=6, pitch=3, hand=-6, ease="sine_inout")
    wings(c, 18, up=18, sweep=-30, pitch=6, hand=22, up2=12, sweep2=-24, pitch2=4, ease="back_out:1.6")
    wings(c, 33, up=21, sweep=-33, pitch=8, hand=26, up2=14, sweep2=-27, pitch2=6, ease="sine_inout")
    c.key(mount, 0, scale=(1, 1, 1))
    c.key(mount, 6, scale=(0.94, 0.94, 0.94), ease="sine_inout")
    c.key(mount, 20, scale=(1.3, 1.3, 1.3), loc=(0, 0.04, 0.05), ease="back_out:1.4")
    c.key(mount, 33, scale=(1.38, 1.38, 1.38), loc=(0, 0.04, 0.06), ease="sine_inout")
    c.key(mount, 0, loc=(0, 0, 0))
    c.add(halo, lambda f: (0, 0, 2.2 * f * f / 33), "rot")            # spins up
    c.add(inner, lambda f: (0, 0, -2.6 * f * f / 33), "rot")
    c.add(outer, lambda f: (0, 0, 1.2 * f), "rot")
    c.key(outer, 0, scale=(1, 1, 1))
    c.key(outer, 20, scale=(1.12, 1.12, 1.12), ease="back_out")
    c.key(eye, 0, scale=(1, 1, 1))
    c.key(eye, 18, scale=(1.4, 1.4, 1.6), ease="back_out")
    cloth(c, freq=1.6)
    c.bake()

    # ---------------------------------------------------------------- attack: the downswing (impact f7)
    IMPACT = {arms: {"rot": (-58, 0, 0)}, fore: {"rot": (-6, 0, 0)}, sword: {"rot": (8, 0, 0)},
              chest: {"rot": (26, 0, 0)}, spine: {"rot": (12, 0, 0)}, head: {"rot": (-6, 0, 0)},
              hips: {"loc": (0, -0.1, -0.16)}, pL: {"rot": (0, 6, 0)}, pR: {"rot": (0, -6, 0)},
              tL: {"rot": (-48, 0, 0)}, sL: {"rot": (58, 0, 0)}, fL: {"rot": (-10, 0, 0)},
              tR: {"rot": (32, 0, 0)}, sR: {"rot": (34, 0, 0)}, fR: {"rot": (-48, 0, 0)}}
    c = A.Clip("attack", 9, joints=ALL)
    c.pose(0, push)
    hi = {j: {k: tuple(v * 1.07 for v in d[k]) for k in d} for j, d in RAISE.items()}
    c.pose(1, hi, ease="quad_in")
    over = {j: {k: tuple(v * 1.08 for v in d[k]) for k in d} for j, d in IMPACT.items()}
    c.pose(6, over, ease="quad_out")
    c.pose(9, IMPACT)
    wings(c, 0, up=21, sweep=-33, pitch=8, hand=26, up2=14, sweep2=-27, pitch2=6)
    wings(c, 1, up=26, sweep=-34, pitch=4, hand=28, up2=18, sweep2=-28, pitch2=2, ease="quad_in")
    wings(c, 6, up=-26, sweep=-14, pitch=24, hand=-10, up2=-20, sweep2=-10, ease="quad_out")
    wings(c, 9, up=-22, sweep=-10, pitch=20, hand=-6, up2=-16, sweep2=-8)
    c.key(mount, 0, scale=(1.38, 1.38, 1.38), loc=(0, 0.04, 0.06))
    c.key(mount, 1, scale=(1.42, 1.42, 1.42), loc=(0, 0.04, 0.06), ease="quad_in")
    c.key(mount, 6, scale=(1.6, 1.6, 1.6), loc=(0, 0.0, 0.0), ease="quad_out")
    c.key(mount, 9, scale=(1.5, 1.5, 1.5), loc=(0, 0.0, 0.0))
    c.add(halo, lambda f: (0, 0, 2.2 * 33 + 30 * f), "rot")
    c.add(inner, lambda f: (0, 0, -2.6 * 33 - 34 * f), "rot")
    c.add(outer, lambda f: (0, 0, 1.2 * 33 + 10 * f), "rot")
    c.key(outer, 0, scale=(1.12, 1.12, 1.12))
    c.key(outer, 6, scale=(1.3, 1.3, 1.3), ease="quad_out")
    c.key(eye, 0, scale=(1.4, 1.4, 1.6))
    A.jitter(c, chest, rot=(1.5, 1.0, 1.0), freq=14, start=6, end=9, fade=1)
    cloth(c, freq=1.8)
    c.bake()

    # ---------------------------------------------------------------- recover: impact hold -> heave -> guard
    c = A.Clip("recover", 27, joints=ALL)
    c.pose(0, IMPACT)
    settle = {j: {k: tuple(v * 0.97 for v in d[k]) for k in d} for j, d in IMPACT.items()}
    c.pose(9, settle, ease="sine_inout")
    heave = {arms: {"rot": (-62, 0, 0)}, fore: {"rot": (-16, 0, 0)}, sword: {"rot": (20, 0, 0)},
             chest: {"rot": (6, 0, 0)}, spine: {"rot": (2, 0, 0)}, head: {"rot": (2, 0, 0)},
             hips: {"loc": (0, -0.04, -0.07)}, tL: {"rot": (-26, 0, 0)}, sL: {"rot": (30, 0, 0)},
             fL: {"rot": (-4, 0, 0)}, tR: {"rot": (16, 0, 0)}, sR: {"rot": (16, 0, 0)}, fR: {"rot": (-26, 0, 0)}}
    c.pose(16, heave, ease="quad_inout")
    for j in set(IMPACT) | set(heave):
        c.key(j, 27, ease="sine_inout")
    A.jitter(c, arms, rot=(1.2, 0.6, 0.8), freq=9, start=9, end=15, seed=2)
    wings(c, 0, up=-22, sweep=-10, pitch=20, hand=-6, up2=-16, sweep2=-8)
    wings(c, 9, up=-18, sweep=-6, pitch=16, hand=-4, up2=-12, sweep2=-6, ease="sine_inout")
    wings(c, 18, up=6, sweep=-4, pitch=-2, hand=6, ease="sine_inout")
    wings(c, 27, ease="sine_inout")
    c.key(mount, 0, scale=(1.5, 1.5, 1.5))
    c.key(mount, 10, scale=(1.25, 1.25, 1.25), ease="sine_inout")
    c.key(mount, 27, scale=(1, 1, 1), ease="sine_inout")
    c.key(outer, 0, scale=(1.3, 1.3, 1.3))
    c.key(outer, 27, scale=(1, 1, 1), ease="sine_inout")
    c.key(eye, 0, scale=(1.4, 1.4, 1.6))
    c.key(eye, 27, scale=(1, 1, 1), ease="sine_inout")
    halo_spin(c, 1, -1, 1)
    cloth(c, freq=1.6)
    c.bake()

    # ---------------------------------------------------------------- hit: stagger
    c = A.Clip("hit", 18, joints=ALL)
    A.hit_react(c, {hips: {"loc": (0, 0.05, -0.03), "rot": (-4, 0, 0)}, spine: {"rot": (-6, 0, 3)},
                    chest: {"rot": (-10, 3, 6)}, head: {"rot": (-14, 0, -9)}, arms: {"rot": (10, 0, -5)},
                    sword: {"rot": (6, 0, 4)}, pL: {"loc": (0, 0, 0.02)},
                    wing["L"][0]: {"rot": wpose(1, 12, -14, -6)}, wing["R"][0]: {"rot": wpose(-1, 12, -14, -6)},
                    wing["L"][2]: {"rot": wpose(1, 8, -10)}, wing["R"][2]: {"rot": wpose(-1, 8, -10)},
                    mount: {"scale": (1.15, 1.15, 1.15)}},
                start=0, rise=2, settle=13, wobble=1.0, stagger=0.6)
    c.key(eye, 0, scale=(1, 1, 1))
    c.key(eye, 2, scale=(1.35, 1.35, 1.5), ease="quad_out")
    c.key(eye, 14, scale=(1, 1, 1), ease="sine_inout")
    halo_spin(c, 0.25, -0.25, 0.25)
    cloth(c, freq=1.8)
    c.bake()

    # ---------------------------------------------------------------- death: kneels on the sword, halo shatters, falls
    c = A.Clip("death", 84, joints=ALL)
    REEL = {hips: {"loc": (0, 0.08, -0.03)}, chest: {"rot": (-14, 4, 8)}, spine: {"rot": (-6, 0, 3)},
            head: {"rot": (-22, 0, -10)}, arms: {"rot": (14, 0, -6)}, sword: {"rot": (4, 0, 0)},
            tL: {"rot": (10, 0, 0)}, sL: {"rot": (6, 0, 0)}, tR: {"rot": (-14, 0, 0)}, sR: {"rot": (10, 0, 0)}}
    KNEEL = {hips: {"loc": (0, 0.02, -0.4), "rot": (6, 0, 0)}, spine: {"rot": (10, 0, 0)}, chest: {"rot": (6, 0, 0)},
             head: {"rot": (34, 0, 0)},
             tL: {"rot": (-86, 0, -4)}, sL: {"rot": (84, 0, 0)}, fL: {"rot": (2, 0, 0)},
             tR: {"rot": (-2, 0, 4)}, sR: {"rot": (96, 0, 0)}, fR: {"rot": (-50, 0, 0)},
             arms: {"rot": (-58, 0, 0)}, fore: {"rot": (-38, 0, 0)}, sword: {"rot": (85, 0, 0)},
             pL: {"loc": (0, 0, -0.02)}, pR: {"loc": (0, 0, -0.02)}}
    for j in set(REEL) | set(KNEEL):
        c.key(j, 0)
    c.pose(4, REEL, ease="quad_out")
    c.pose(16, KNEEL, ease="quad_in")
    sag = {j: {k: tuple(v * 1.04 for v in d[k]) for k in d} for j, d in KNEEL.items()}
    sag[head] = {"rot": (44, 0, 6)}
    c.pose(19, sag, ease="quad_out")
    c.pose(46, sag, ease="sine_inout")
    # topple: let go of the sword and fall forward onto the side
    c.key(body, 0)
    c.key(body, 46, ease="quad_in")
    c.key(body, 62, rot=(74, 0, 18), loc=(0, -0.05, 0.1), ease="quad_out")
    c.key(body, 65, rot=(70, 0, 17), loc=(0, -0.05, 0.12), ease="quad_in")
    c.key(body, 68, rot=(74, 0, 18), loc=(0, -0.05, 0.1), ease="quad_out")
    LIMP = {hips: {"loc": (0, 0.0, -0.3), "rot": (0, 0, 0)}, spine: {"rot": (-4, 0, 0)}, chest: {"rot": (-6, 0, 0)},
            head: {"rot": (-10, 0, 30)}, tL: {"rot": (-40, 0, 0)}, sL: {"rot": (60, 0, 0)}, fL: {"rot": (20, 0, 0)},
            tR: {"rot": (-30, 0, 0)}, sR: {"rot": (70, 0, 0)}, fR: {"rot": (20, 0, 0)},
            arms: {"rot": (-80, 0, 10)}, fore: {"rot": (-10, 0, 0)}, sword: {"rot": (30, 0, 0)},
            pL: {"loc": (0, 0, 0)}, pR: {"loc": (0, 0, 0)}}
    c.pose(62, LIMP, ease="back_out:1.3")
    c.pose(84, LIMP)
    # wings: flare in the reel, droop while kneeling, splay on the ground
    wings(c, 0)
    wings(c, 4, up=18, sweep=-14, pitch=-10, hand=12, ease="quad_out")
    wings(c, 18, up=-20, sweep=14, pitch=10, hand=-14, up2=-16, sweep2=10, ease="sine_inout")
    wings(c, 46, up=-26, sweep=18, pitch=12, hand=-18, up2=-20, sweep2=12, ease="quad_in")
    wings(c, 62, up=-34, sweep=-24, pitch=-40, hand=10, up2=-22, sweep2=-8, ease="back_out:1.5")
    wings(c, 84, up=-34, sweep=-24, pitch=-40, hand=10, up2=-22, sweep2=-8)
    # halo: flickers in the reel, sputters while kneeling, then SHATTERS (f30)
    c.key(mount, 0, scale=(1, 1, 1))
    c.key(mount, 3, scale=(1.3, 1.3, 1.3), ease="quad_out")
    c.key(mount, 14, scale=(0.9, 0.9, 0.9), ease="sine_inout")
    c.key(mount, 22, scale=(0.94, 0.94, 0.94), ease="sine_inout")
    c.key(mount, 29, scale=(0.82, 0.82, 0.82), ease="expo_in")
    c.key(mount, 31, scale=(1.25, 1.25, 1.25), ease="quad_out")
    c.key(mount, 0, loc=(0, 0, 0))
    c.key(mount, 30, loc=(0, 0, -0.04))
    A.jitter(c, halo, rot=(0, 0, 6), freq=12, start=18, end=30, seed=6)
    c.add(halo, lambda f: (0, 0, 40 * (1 - math.exp(-f / 20.0))), "rot")
    for i, (sj, mid) in enumerate(shards):
        d = (math.cos(mid), math.sin(mid))
        far = 0.55 + 0.25 * rnd.random()
        c.key(sj, 0)
        c.key(sj, 30, rot=(0, 0, 0), loc=(0, 0, 0), ease="expo_out")
        c.key(sj, 44, rot=(rnd.uniform(-120, 120), rnd.uniform(-120, 120), rnd.uniform(-90, 90)),
              loc=(d[0] * far, d[1] * far - 0.25, rnd.uniform(-0.3, 0.3)), ease="quad_in")
        c.key(sj, 0, scale=(1, 1, 1))
        c.key(sj, 34, scale=(1, 1, 1), ease="quad_in")
        c.key(sj, 46, scale=(0.01, 0.01, 0.01), ease="constant")
    for ring_j, burst in ((inner, 1.6), (outer, 1.35)):
        c.key(ring_j, 0, scale=(1, 1, 1))
        c.key(ring_j, 29, scale=(0.9, 0.9, 0.9), ease="expo_out")
        c.key(ring_j, 36, scale=(burst, burst, burst), ease="quad_in")
        c.key(ring_j, 40, scale=(0.01, 0.01, 0.01), ease="constant")
    c.key(eye, 0, scale=(1, 1, 1))
    c.key(eye, 3, scale=(1.4, 1.4, 1.6), ease="quad_out")
    c.key(eye, 30, scale=(1.2, 1.2, 1.3), ease="quad_in")
    c.key(eye, 40, scale=(0.05, 0.05, 0.05), ease="constant")
    cloth(c, floor=0.03, freq=1.6)
    c.bake()

    K.merge_by_joint(root)
    # Merged meshes inherit the transform of whichever part became active (often a scaled
    # ellipsoid): fold rotation/scale into the vertices so every mesh sits at unit scale (the
    # bake's per-object texel equalisation and UV packing go badly wrong otherwise).
    for o in [o for o in root.children_recursive if o.type == "MESH"]:
        if any(abs(s - 1.0) > 1e-5 for s in o.scale) or any(abs(r) > 1e-6 for r in o.rotation_euler):
            o.data.transform(Matrix.LocRotScale(None, o.rotation_euler, o.scale))
            o.rotation_euler = (0, 0, 0)
            o.scale = (1, 1, 1)
            o.data.update()
    K.report("archon")
    return root
