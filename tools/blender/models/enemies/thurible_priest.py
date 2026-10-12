"""Censer Cleric (thurible_priest): a tall hooded cleric of the Host hovering above the ground in
layered vestments - an ash under-robe falling to a tattered hem, a pale over-tunic, a gold-trimmed
scapular and a long dark stole embroidered in gold, a scalloped mantle, a rope cincture. Its face
is lost in a deep gothic cowl where only a faint glow burns. Small folded wings at its back, a
rayed halo behind the hood, prayer beads dangling from its left hand. With its right it swings an
ornate filigree censer (pierced dome over glowing embers) on a real link chain.

Joints: body (ground pivot) > skirt / chest > head > halo, arm_L > fore_L, arm_R > fore_R > grip
> chain_0..chain_3 > censer > ember. The chain is a follow_through spring chain in every clip.
"censer" is the joint Godot hangs the smoke / light on.
Anims: idle, fly (loops), windup (pendulum backswing, embers flare), attack (thrust swing,
impact hold), hit, death (robes deflate, the censer slips from the hand and drops)."""
import importlib.util
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

import sb
import sbanim as S

_spec = importlib.util.spec_from_file_location("_angel", os.path.join(os.path.dirname(__file__), "_angel.py"))
AN = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(AN)

CATEGORY = "enemies"

WAIST = 0.82          # waist height (skirt / chest pivot)
YS = 0.86             # front-back squash of the body
GROUND = -0.28        # where the floor is in game (hover 0.3): the corpse settles here


# ============================================================================ geometry helpers

def _interp(prof, z):
    """Radius of a (r, z) profile (any order) at height z (clamped)."""
    p = sorted(prof, key=lambda q: q[1])
    if z <= p[0][1]:
        return p[0][0]
    for (r0, z0), (r1, z1) in zip(p[:-1], p[1:]):
        if z <= z1:
            u = (z - z0) / max(z1 - z0, 1e-9)
            return r0 + (r1 - r0) * u
    return p[-1][0]


class Drape:
    """Cloth layer of revolution: profile [(r, z)] + vertical folds that deepen toward the hem."""

    def __init__(self, prof, folds=0, amp=0.0, ph=0.0, ys=YS):
        self.prof = prof
        self.folds, self.amp, self.ph, self.ys = folds, amp, ph, ys
        zs = [z for _, z in prof]
        self.ztop, self.zbot = max(zs), min(zs)

    def r(self, a, z):
        w = (self.ztop - z) / max(self.ztop - self.zbot, 1e-9)
        f = 1.0 + self.amp * w * math.cos(self.folds * a + self.ph) if self.folds else 1.0
        return _interp(self.prof, z) * f

    def p(self, a, z, out=0.0):
        rr = self.r(a, z) + out
        return Vector((math.cos(a) * rr, math.sin(a) * rr * self.ys, z))


def shell(name, parent, rows, material, closed=True, flip=False, loc=(0, 0, 0), rot=(0, 0, 0),
          scale=(1, 1, 1), smooth=True):
    """Surface from rows of points (bottom -> top, each row ordered counter-clockwise seen from
    above => normals face outward). Open sectors when closed=False. flip = inward normals."""
    bm = bmesh.new()
    vr = [[bm.verts.new(tuple(p)) for p in row] for row in rows]
    n = len(rows[0])
    for lo, hi in zip(vr[:-1], vr[1:]):
        for k in range(n if closed else n - 1):
            k1 = (k + 1) % n
            f = (lo[k], lo[k1], hi[k1], hi[k])
            bm.faces.new(tuple(reversed(f)) if flip else f)
    obj = sb._new_mesh_obj(name, bm)
    return sb._finish(obj, parent, material, loc, rot, scale, 0.0, 0, smooth, name)


def drape_rows(d, zs, a0=0.0, a1=360.0, seg=24, out=0.0, hem=None):
    """Rows of a Drape between angles a0..a1 (deg) at heights zs (bottom -> top).
    hem(k, a) -> dz added to the bottom row (tatters / scallops)."""
    full = abs(a1 - a0) >= 359.9
    cnt = seg if full else seg + 1
    rows = []
    for i, z in enumerate(zs):
        row = []
        for k in range(cnt):
            a = math.radians(a0 + (a1 - a0) * k / seg)
            zz = z + (hem(k, a) if (hem and i == 0) else 0.0)
            row.append(d.p(a, zz, out))
        rows.append(row)
    return rows, full


def drape(name, parent, d, zs, material, seg=24, a0=0.0, a1=360.0, out=0.0, hem=None, flip=False):
    rows, full = drape_rows(d, zs, a0, a1, seg, out, hem)
    return shell(name, parent, rows, material, closed=full, flip=flip)


def trim(name, parent, d, z, material, seg=24, a0=0.0, a1=360.0, out=0.012, r=0.011, hem=None, sides=3):
    """Gold band following a Drape at height z (or along its hem)."""
    full = abs(a1 - a0) >= 359.9
    pts = []
    for k in range(seg + 1):
        a = math.radians(a0 + (a1 - a0) * k / seg)
        zz = z + (hem(k % seg if full else k, a) if hem else 0.0)
        pts.append(d.p(a, zz, out))
    if full:
        pts[-1] = pts[0]
    return sb.ptube(name, parent, pts, [r] * len(pts), sides=sides, material=material, caps=not full)


def vstrip(name, parent, d, a_c, half_w, z0, z1, material, rows=5, out=0.01, extra=None):
    """Vertical strip lying on a Drape (panels, stoles) centred on angle a_c (deg), half width in
    metres. extra(z) -> additional outward offset."""
    rws = []
    for i in range(rows + 1):
        z = z0 + (z1 - z0) * i / rows
        rr = d.r(math.radians(a_c), z)
        da = math.degrees(half_w / max(rr, 1e-3))
        row = []
        for k in range(3):
            a = math.radians(a_c - da + da * k)
            o = out + (extra(z) if extra else 0.0)
            row.append(d.p(a, z, o))
        rws.append(row)
    return shell(name, parent, rws, material, closed=False)


def place_world(obj, world_loc):
    bpy.context.view_layer.update()
    obj.matrix_world = Matrix.Translation(Vector(world_loc))
    return obj


def link_chain(prefix, parent, length, n, material, size=0.026, wire=0.0052, z0=0.0):
    """Real interlocking links hanging down local -Z from z0 (alternating 90 deg)."""
    step = length / n
    for i in range(n):
        o = AN.ring(f"{prefix}{i}", parent, size * 0.5, wire, loc=(0, 0, z0 - step * (i + 0.5)),
                    rot=(90, 0, 90 * (i % 2)), material=material, seg=6, mseg=3)
        o.scale = (1.0, 1.55, 1.0)   # elongated link (local Y of the torus -> world Z)


# ============================================================================ build

def build():
    m = AN.mats()
    ash = sb.mat("Cleric_ClothRobeAsh", (0.4, 0.38, 0.35), roughness=0.96)
    pale = sb.mat("Cleric_ClothRobePale", (0.76, 0.72, 0.62), roughness=0.93)
    hood_m = sb.mat("Cleric_HoodCloth", (0.66, 0.62, 0.53), roughness=0.95)
    stole_m = sb.mat("Cleric_SilkSashStole", (0.13, 0.14, 0.22), roughness=0.7)
    void = sb.mat("Cleric_HoodVoid", (0.012, 0.01, 0.01), roughness=1.0)
    glow = sb.mat("Cleric_FaceGlow", (0.9, 0.7, 0.42), roughness=0.5, emission=(1.0, 0.72, 0.4), strength=2.2)
    hand_m = sb.mat("Cleric_BoneHand", (0.78, 0.72, 0.6), roughness=0.6)
    beads_m = sb.mat("Cleric_IvoryBeads", (0.86, 0.8, 0.66), roughness=0.4)
    rope = sb.mat("Cleric_LeatherRope", (0.42, 0.33, 0.2), roughness=0.9)
    gold, gold_d, ember = m["gold"], m["gold_dark"], m["ember"]

    root = sb.root("CenserCleric")
    body = sb.empty("body", root)                                     # ground / hover pivot

    # ------------------------------------------------------------------ skirt (waist down)
    skirt = sb.empty("skirt", body, loc=(0, 0, WAIST))
    under = Drape([(0.37, -0.8), (0.33, -0.62), (0.26, -0.35), (0.2, -0.1), (0.175, 0.04)], folds=7, amp=0.09, ph=0.4)
    tat = lambda k, a: -0.075 * ((k * 5) % 3) / 2.0 - (0.03 if k % 2 else 0.0)   # noqa: E731
    drape("robe_under", skirt, under, [-0.8, -0.62, -0.38, -0.15, 0.04], ash, seg=24, hem=tat)
    tunic = Drape([(0.305, -0.48), (0.25, -0.25), (0.2, -0.05), (0.185, 0.05)], folds=7, amp=0.07, ph=0.4 + math.pi / 7)
    scal = lambda k, a: -0.035 * (1 - abs(math.cos(k * math.pi / 2)))   # noqa: E731  gentle points
    drape("robe_tunic", skirt, tunic, [-0.48, -0.3, -0.12, 0.05], pale, seg=24, out=0.018, hem=scal)
    trim("tunic_hem_gold", skirt, tunic, -0.455, gold, seg=24, out=0.026, r=0.012, hem=None)
   # scapular: front and back panels over both layers
    top = Drape([(r, z) for r, z in [(0.19, 0.05), (0.2, -0.05), (0.25, -0.25), (0.315, -0.48), (0.35, -0.7),
                                      (0.37, -0.8)]], ys=YS)
    for nm, ac in (("front", -90.0), ("back", 90.0)):
        vstrip(f"scapular_{nm}", skirt, top, ac, 0.085, -0.7, 0.04, pale, rows=5, out=0.028)
        for sx in (-1, 1):
            pts = []
            for i in range(7):
                z = -0.7 + 0.74 * i / 6
                rr = top.r(math.radians(ac), z)
                a = math.radians(ac) + sx * 0.088 / rr
                pts.append(top.p(a, z, 0.034))
            sb.ptube(f"scap_trim_{nm}{sx}", skirt, pts, [0.009] * 7, sides=3, material=gold)
        pts = [top.p(math.radians(ac) + 0.088 / top.r(math.radians(ac), -0.7) * t, -0.7, 0.034) for t in (-1, 0, 1)]
        sb.ptube(f"scap_hem_{nm}", skirt, pts, [0.009] * 3, sides=3, material=gold)
    # embroidered emblem on the front scapular: sunburst cross
    ef = top.p(math.radians(-90), -0.5, 0.048)
    AN.plate("emb_cross_v", skirt, [(-0.012, 0.09), (0.012, 0.09), (0.012, -0.09), (-0.012, -0.09)], 0.006,
             material=gold, loc=tuple(ef), rot=(-8, 0, 0))
    AN.plate("emb_cross_h", skirt, [(-0.06, 0.012), (0.06, 0.012), (0.06, -0.012), (-0.06, -0.012)], 0.006,
             material=gold, loc=tuple(ef + Vector((0, 0, 0.03))), rot=(-8, 0, 0))
    AN.ring("emb_sun", skirt, 0.035, 0.006, loc=tuple(ef + Vector((0, 0, 0.03))), rot=(82, 0, 0), material=gold,
            seg=10, mseg=3)
    for i, z in enumerate((-0.2, -0.3)):
        e = top.p(math.radians(-90), z, 0.046)
        AN.plate(f"emb_lozenge{i}", skirt, [(0, 0.022), (0.016, 0), (0, -0.022), (-0.016, 0)], 0.006,
                 material=gold_d, loc=tuple(e), rot=(-14, 0, 0))
    # long stole: two dark strips over the scapular, fringed gold ends
    for sx in (-1, 1):
        ac = -90.0 + sx * 7.5
        vstrip(f"stole_low{sx}", skirt, top, ac, 0.028, -0.78, 0.04, stole_m, rows=5, out=0.05)
        for e_ in (-1, 1):
            pts = []
            for i in range(4):
                z = -0.78 + 0.82 * i / 3
                rr = top.r(math.radians(ac), z)
                pts.append(top.p(math.radians(ac) + e_ * 0.029 / rr, z, 0.054))
            sb.ptube(f"stole_trim{sx}{e_}", skirt, pts, [0.0055] * 4, sides=3, material=gold)
        ep = top.p(math.radians(ac), -0.7, 0.058)
        AN.plate(f"stole_crossv{sx}", skirt, [(-0.007, 0.035), (0.007, 0.035), (0.007, -0.035), (-0.007, -0.035)],
                 0.005, material=gold, loc=tuple(ep), rot=(-6, 0, sx * 7))
        AN.plate(f"stole_crossh{sx}", skirt, [(-0.022, 0.007), (0.022, 0.007), (0.022, -0.007), (-0.022, -0.007)],
                 0.005, material=gold, loc=tuple(ep + Vector((0, 0, 0.012))), rot=(-6, 0, sx * 7))
        fp = top.p(math.radians(ac), -0.8, 0.05)
        AN.plate(f"stole_fringe{sx}", skirt, [(-0.03, 0.0), (0.03, 0.0), (0.024, -0.05), (0.012, -0.03), (0.0, -0.06),
                                              (-0.012, -0.03), (-0.024, -0.05)], 0.006, material=gold_d,
                 loc=tuple(fp), rot=(-10, 0, sx * 7))
    # rope cincture with knotted tail
    AN.ring("cincture", skirt, 0.205, 0.016, loc=(0, 0, 0.0), material=rope, seg=12, mseg=4).scale = (1, YS, 1)
    sb.ptube("cincture_tail", skirt, [(0.12, -0.16, 0.0), (0.15, -0.2, -0.12), (0.16, -0.22, -0.26), (0.155, -0.24, -0.36)],
             [0.012, 0.011, 0.01, 0.009], sides=4, material=rope)
    for i, z in enumerate((-0.12,)):
        sb.sphere(f"cincture_knot{i}", skirt, radius=0.02, loc=(0.152 - i * 0.006, -0.205 - i * 0.015, z),
                  material=rope, segments=6, rings=4)
    AN.spike("cincture_tassel", skirt, (0.155, -0.24, -0.36), (0, -0.1, -1), 0.07, 0.03, 0.03, material=gold_d)

    # ------------------------------------------------------------------ chest / mantle
    chest = sb.empty("chest", body, loc=(0, 0, WAIST))
    torso = Drape([(0.175, 0.0), (0.19, 0.16), (0.2, 0.28), (0.15, 0.38), (0.075, 0.44)])
    drape("torso_robe", chest, torso, [0.0, 0.16, 0.28, 0.38, 0.44], pale, seg=16, out=0.018)
    for sx in (-1, 1):   # stole on the chest (under the mantle, visible below it)
        ac = -90.0 + sx * 7.5
        vstrip(f"stole_up{sx}", chest, torso, ac + sx * 2.0, 0.028, -0.01, 0.3, stole_m, rows=2, out=0.03)
    mantle = Drape([(0.31, 0.11), (0.29, 0.2), (0.24, 0.3), (0.16, 0.39), (0.1, 0.44)], folds=10, amp=0.05, ph=0.0)
    scallop = lambda k, a: -0.04 * abs(math.sin(k * math.pi / 2)) - (0.035 if math.sin(a) > 0.3 else 0.0)  # noqa: E731
    drape("mantle_hood_robe", chest, mantle, [0.11, 0.2, 0.3, 0.39, 0.44], hood_m, seg=20, hem=scallop)
    trim("mantle_trim_gold", chest, mantle, 0.11, gold, seg=20, out=0.008, r=0.011, hem=scallop)
    # morse (cope clasp) at the breast
    sb.cylinder("morse", chest, r1=0.045, depth=0.016, loc=(0, -0.235, 0.27), rot=(80, 0, 0), material=gold,
                segments=10, bevel=0.0)
    sb.sphere("morse_gem", chest, radius=0.018, loc=(0, -0.252, 0.272), material=glow, segments=6, rings=4)

    # folded wings at the back (small: a cleric, not a warrior)
    # each: a leading edge arching over the shoulder blade, the flight feathers hanging from it
    # down the back, overlapping, tips near the hips.
    wings = []
    for s in (-1, 1):
        wj = sb.empty(f"wing_{'L' if s > 0 else 'R'}", chest, loc=(s * 0.06, 0.2, 0.33), rot=(-12, 0, s * 18))
        edge = [Vector((0, 0, -0.02)), Vector((s * 0.07, 0.01, 0.11)), Vector((s * 0.17, 0.03, 0.13)),
                Vector((s * 0.25, 0.05, 0.04))]
        sb.ptube(f"wing_edge_{s}", wj, edge, [0.03, 0.032, 0.026, 0.016], sides=5, material=m["ivory"])
        for i in range(6):
            t = i / 5.0
            seg_i = min(int(t * 3), 2)
            p = edge[seg_i].lerp(edge[seg_i + 1], t * 3 - seg_i)
            ln = 0.3 + 0.22 * t
            AN.feather(f"wing_f{s}_{i}", wj, length=ln, width=0.05 + 0.012 * t, thickness=0.006,
                       loc=(p.x, p.y + 0.012 * (5 - i) * 0.4, p.z - 0.01), rot=(-6 - 4 * t, 180 + s * (4 + 16 * t), 0),
                       material=m["feather"] if i % 2 == 0 else m["feather_tip"], curve=0.12, steps=3)
        wings.append(wj)

    # ------------------------------------------------------------------ head: deep gothic cowl
    head = sb.empty("head", chest, loc=(0, 0, 0.43))
    AN.ellipsoid("hood_back", head, (0.33, 0.35, 0.38), loc=(0, 0.06, 0.13), material=hood_m, seg=10, rings=7)
    AN.seg("hood_tail", head, (0, 0.17, 0.22), (0, 0.27, 0.0), 0.075, 0.0, material=hood_m, segments=6)
    # cowl tube along the face direction (local z -> forward-down after rot X 100)
    arch = lambda a: 1.0 + 0.22 * max(0.0, math.sin(a)) ** 6    # noqa: E731  gothic point on top
    cprof = [(0.15, -0.06), (0.148, 0.05), (0.14, 0.12)]

    def cowl_rows(scale_r, zs):
        rows = []
        for z in zs:
            row = []
            for k in range(16):
                a = 2 * math.pi * k / 16
                rr = _interp(cprof, z) * scale_r * arch(a)
                row.append(Vector((math.cos(a) * rr * 0.85, math.sin(a) * rr * 1.12, z)))
            rows.append(row)
        return rows
    cowl_loc, cowl_rot = (0, -0.04, 0.14), (98, 0, 0)
    shell("cowl_hood", head, cowl_rows(1.0, [-0.06, 0.05, 0.12]), hood_m, loc=cowl_loc, rot=cowl_rot)
    shell("cowl_void_in", head, cowl_rows(0.9, [-0.06, 0.05, 0.118]), void, flip=True, loc=cowl_loc, rot=cowl_rot)
    rim = [p for p in cowl_rows(1.03, [0.118])[0]]
    rim.append(rim[0])
    o = sb.ptube("cowl_rim_gold", head, rim, [0.012] * len(rim), sides=3, material=gold, caps=False)
    o.location, o.rotation_euler = cowl_loc, [math.radians(a) for a in cowl_rot]
    # rim and the shadow at the back of the cowl, with the faceless glow
    AN.ellipsoid("face_void", head, (0.22, 0.14, 0.26), loc=(0, -0.07, 0.13), material=void, seg=8, rings=6)
    AN.ellipsoid("face_glow", head, (0.07, 0.02, 0.1), loc=(0, -0.138, 0.12), material=glow, seg=8, rings=5)
    halo = AN.halo("halo", head, (0, 0.24, 0.24), 0.2, m, rays=10, ray_len=0.38, upright=True, seg=16, band=False)

    # ------------------------------------------------------------------ arms
    def arm(sd, s, rot_a, rot_f):
        a = sb.empty(f"arm_{sd}", chest, loc=(s * 0.215, 0.0, 0.34), rot=rot_a)
        AN.lathe(f"sleeve_up_{sd}", a, [(0.0, -0.25), (0.075, -0.25), (0.07, -0.12), (0.06, 0.0), (0.0, 0.03)],
                 segments=10, material=pale)
        f = sb.empty(f"fore_{sd}", a, loc=(0, 0, -0.24), rot=rot_f)
        AN.lathe(f"sleeve_bell_{sd}", f, [(0.0, -0.2), (0.125, -0.25), (0.115, -0.2), (0.08, -0.08), (0.065, 0.0),
                                          (0.0, 0.03)], segments=10, material=pale)
        AN.ring(f"cuff_gold_{sd}", f, 0.12, 0.009, loc=(0, 0, -0.235), material=gold, seg=10, mseg=3)
        AN.ellipsoid(f"hand_{sd}", f, (0.06, 0.07, 0.095), loc=(0, 0, -0.27), material=hand_m, seg=7, rings=5)
        AN.seg(f"thumb_{sd}", f, (s * -0.02, -0.03, -0.25), (s * -0.03, -0.05, -0.31), 0.013, 0.009, material=hand_m,
               segments=5)
        return a, f
    arm_L, fore_L = arm("L", 1, (-18, -14, 0), (-95, 0, -35))
    arm_R, fore_R = arm("R", -1, (-28, 16, 0), (-38, 0, 0))

    bpy.context.view_layer.update()
    # prayer beads dangling in a loop from the left hand
    hl = fore_L.matrix_world @ Vector((0, 0, -0.3))
    bead_pts = []
    for i in range(11):
        t = i / 10.0
        ang = math.pi * t
        bead_pts.append(Vector((0.045 * math.cos(ang) - 0.0, -0.01 * math.sin(ang), -0.24 * math.sin(ang) ** 0.85)))
    for i, p in enumerate(bead_pts):
        b = sb.sphere(f"bead{i}", fore_L, radius=0.017 if i % 4 else 0.022, material=beads_m if i % 4 else gold,
                      segments=4, rings=3)
        place_world(b, hl + p)
    md = sb.cylinder("beads_medallion", fore_L, r1=0.034, depth=0.01, rot=(90, 0, 0), material=gold, segments=8,
                     bevel=0.0)
    md.matrix_world = Matrix.Translation(hl + Vector((0.0, -0.01, -0.29))) @ Matrix.Rotation(math.radians(90), 4, "X")
    place_world(sb.sphere("beads_medallion_gem", fore_L, radius=0.012, material=glow, segments=5, rings=3),
                hl + Vector((0.0, -0.018, -0.29)))

    # ------------------------------------------------------------------ chain + censer
    hr = fore_R.matrix_world @ Vector((0, 0, -0.29))
    grip = AN.attach("grip", fore_R, tuple(hr), (0, 0, 0))            # world-aligned at rest
    LINK = 0.105
    chain = [sb.empty("chain_0", grip)]
    for i in range(1, 4):
        chain.append(sb.empty(f"chain_{i}", chain[-1], loc=(0, 0, -LINK)))
    for i, cj in enumerate(chain):
        link_chain(f"link{i}_", cj, LINK, 3, gold)
    K = 1.18
    censer = sb.empty("censer", chain[-1], loc=(0, 0, -LINK))
    AN.ring("censer_bail", censer, 0.022 * K, 0.006, loc=(0, 0, -0.012), rot=(90, 0, 0), material=gold, seg=8, mseg=3)
    AN.lathe("censer_cap", censer, [(0.0, -0.05 * K), (0.035 * K, -0.045 * K), (0.03 * K, -0.03 * K), (0.012 * K, -0.02 * K),
                                    (0.0, -0.018 * K)], segments=8, material=gold)
    rim_z, rim_r = -0.19 * K, 0.105 * K
    for i in range(3):            # three suspension chains from the cap to the bowl rim
        a = 2 * math.pi * i / 3 + math.pi / 2
        p0 = Vector((math.cos(a) * 0.03 * K, math.sin(a) * 0.03 * K, -0.045 * K))
        p1 = Vector((math.cos(a) * (rim_r + 0.008), math.sin(a) * (rim_r + 0.008), rim_z))
        pts = [p0.lerp(p1, t / 3) for t in range(4)]
        sb.ptube(f"censer_strand{i}", censer, pts, [0.005] * 4, sides=3, material=gold)
    # pierced filigree dome: meridian ribs + latitude rings over the glowing embers
    apex = -0.085 * K
    for i in range(6):
        a = 2 * math.pi * (i + 0.5) / 6
        pts = []
        for t in range(4):
            u = t / 3.0
            ang = u * math.pi / 2
            rr = rim_r * 0.98 * math.sin(ang)
            pts.append((math.cos(a) * rr, math.sin(a) * rr, rim_z + (apex - rim_z) * math.cos(ang)))
        sb.ptube(f"censer_rib{i}", censer, pts, [0.009, 0.008, 0.007, 0.006], sides=3, material=gold)
    for j, u in enumerate((0.62,)):
        ang = u * math.pi / 2
        AN.ring(f"censer_lat{j}", censer, rim_r * 0.98 * math.sin(ang), 0.006,
                loc=(0, 0, rim_z + (apex - rim_z) * math.cos(ang)), material=gold, seg=12, mseg=3)
    AN.spike("censer_spire", censer, (0, 0, apex), (0, 0, 1), 0.04 * K, 0.025, 0.025, material=gold)
    # bowl, rim band with studs, foot and pendant
    AN.lathe("censer_bowl", censer, [(0.0, -0.31 * K), (0.04 * K, -0.3 * K), (0.075 * K, -0.27 * K), (0.1 * K, -0.225 * K),
                                     (rim_r, rim_z), (0.0, rim_z + 0.01)], segments=14, material=gold)
    AN.ring("censer_band", censer, rim_r, 0.011, loc=(0, 0, rim_z), material=gold_d, seg=12, mseg=3)
    for i in range(6):
        a = 2 * math.pi * i / 6
        sb.sphere(f"censer_stud{i}", censer, radius=0.012, loc=(math.cos(a) * (rim_r + 0.01), math.sin(a) * (rim_r + 0.01),
                                                                 rim_z), material=ember, segments=4, rings=3)
    AN.ring("censer_foot", censer, 0.04 * K, 0.009, loc=(0, 0, -0.305 * K), material=gold_d, seg=10, mseg=3)
    AN.spike("censer_pendant", censer, (0, 0, -0.31 * K), (0, 0, -1), 0.06 * K, 0.03, 0.03, material=gold)
    # the embers (scale this joint: windup flare / death dimming)
    ember_j = sb.empty("ember", censer, loc=(0, 0, rim_z + 0.015))
    sb.sphere("ember_core", ember_j, radius=0.085 * K, scale=(1, 1, 0.85), material=ember, segments=8, rings=5)
    for i in range(5):
        a = 2 * math.pi * i / 5 + 0.3
        AN.spike(f"ember_tongue{i}", ember_j, (math.cos(a) * 0.03, math.sin(a) * 0.03, 0.02),
                 (math.cos(a) * 0.4, math.sin(a) * 0.4, 1), 0.07 + 0.02 * (i % 2), 0.03, 0.02, material=ember)

    # ============================================================== animation
    ALL = S.joints(root)
    W = {"R": [wings[0]], "L": [wings[1]]}
    hide_pose = {}

    def wings_rest(c):
        pass

    def censer_chain(c, freq=2.6, damping=0.1, wind=None, floor=None, gravity=7.0, max_angle=70.0):
        S.follow_through(c, chain, freq=freq, damping=damping, gravity=gravity, falloff=0.9, max_angle=max_angle,
                         wind=wind, floor=floor)

    def ember_pulse(c, amp=0.1, cycles=3):
        c.add(ember_j, lambda f: (amp * S.wave(c, f, cycles), amp * S.wave(c, f, cycles, 0.3),
                                  amp * 1.4 * S.wave(c, f, cycles, 0.15)), "scale")

    def living(c, amp=1.0):
        S.noise(c, head, rot=(3 * amp, 4 * amp, 3 * amp), freq=0.35, seed=4)
        S.noise(c, W["L"][0], rot=(2, 3, 3), freq=0.4, seed=7)
        c.mirror(W["L"][0], phase=0.5)
        c.add(halo, lambda f: (0, 0, 7 * S.wave(c, f, 1, 0.1)))

    # ---------------------------------------------------------------- idle (loop) 2 s
    c = S.Clip("idle", 60, joints=ALL)
    c.add(body, lambda f: (0, 0, 0.035 * S.wave(c, f)), "loc")
    c.add(body, lambda f: (1.5 * S.wave(c, f, 1, 0.25), 1.2 * S.wave(c, f, 1, 0.5), 0))
    c.add(skirt, lambda f: (2.5 * S.wave(c, f, 1, 0.1), -1.5 * S.wave(c, f, 1, 0.35), 2.0 * S.wave(c, f, 2)))
    S.breathe(c, chest, amp=1.6, rise=0.006, swell=0.012, cycles=2, shoulders=[arm_L, arm_R], head=head)
    # the hand rocks the censer: the arm pumps a little ahead of the pendulum
    c.add(arm_R, lambda f: (6 * S.wave(c, f, 1, 0.12), 0, 2 * S.wave(c, f, 1, 0.37)))
    c.add(chain[0], lambda f: (30 * S.wave(c, f), -7 * S.wave(c, f, 1, 0.25), 0))
    S.noise(c, arm_L, rot=(2, 1, 2), freq=0.3, seed=2)
    living(c)
    ember_pulse(c)
    censer_chain(c)
    c.bake()

    # ---------------------------------------------------------------- fly (loop)
    c = S.Clip("fly", 40, joints=ALL)
    c.key(body, 0, rot=(11, 0, 0))
    c.add(body, lambda f: (2 * S.wave(c, f, 1, 0.25), 0, 0))
    c.add(body, lambda f: (0, 0, 0.04 * S.wave(c, f)), "loc")
    c.key(skirt, 0, rot=(16, 0, 0))     # robes trail back
    c.add(skirt, lambda f: (3 * S.wave(c, f, 2, 0.1), 0, 2.5 * S.wave(c, f, 1)))
    c.key(head, 0, rot=(-9, 0, 0))
    c.key(arm_R, 0, rot=(-8, 0, 0))
    c.key(arm_L, 0, rot=(4, 0, 0))
    c.key(chain[0], 0, rot=(10, 0, 0))
    c.add(chain[0], lambda f: (16 * S.wave(c, f), -5 * S.wave(c, f, 1, 0.25), 0))
    S.breathe(c, chest, amp=1.0, cycles=1)
    c.pose(0, {W["L"][0]: {"rot": (6, 0, 6)}}, mirror=True)
    living(c, 0.7)
    ember_pulse(c, 0.12, 2)
    censer_chain(c, wind=(0, 2.5, 0))
    c.bake()

    # ---------------------------------------------------------------- windup (one-shot) 24 f
    # small forward pre-swing, then a huge pendulum backswing, censer up behind the shoulder
    WU = 24
    WIND_END = {
        body: {"rot": (-4, 0, -16), "loc": (0, 0.04, 0.05)},
        chest: {"rot": (-6, 3, -14)},
        head: {"rot": (6, 0, 20)},
        skirt: {"rot": (-4, 0, 8)},
        arm_R: {"rot": (62, -6, -18)},
        fore_R: {"rot": (18, 0, 0)},
        arm_L: {"rot": (-20, 0, 18)},
        chain[0]: {"rot": (112, 0, -10)},
    }
    c = S.Clip("windup", WU, joints=ALL)
    c.pose(0, {j: {"rot": (0, 0, 0)} for j in WIND_END})
    c.pose(6, {body: {"rot": (4, 0, 5), "loc": (0, -0.02, 0)}, chest: {"rot": (3, 0, 4)}, arm_R: {"rot": (-20, 0, 6)},
               fore_R: {"rot": (-6, 0, 0)}, chain[0]: {"rot": (-18, 0, 4)}, head: {"rot": (-3, 0, -4)}},
           ease="sine_inout")
    c.pose(18, WIND_END, ease="sine_inout")
    c.pose(WU, {j: {k: tuple(x * 1.07 for x in v) for k, v in d.items()} for j, d in WIND_END.items()})
    c.key(ember_j, 0, scale=(1, 1, 1))
    c.key(ember_j, 10, scale=(1.15, 1.15, 1.15), ease="quad_in")
    c.key(ember_j, WU, scale=(1.3, 1.3, 1.7))
    S.jitter(c, ember_j, rot=(6, 6, 10), start=12, end=WU)
    S.jitter(c, arm_R, rot=(1.5, 1, 1.5), start=17, end=WU)
    c.key(halo, 0, rot=(0, 0, 0))
    c.key(halo, WU, rot=(0, 0, 40))
    censer_chain(c, freq=4.0, damping=0.18)
    c.bake()

    # ---------------------------------------------------------------- attack (one-shot) 22 f
    # (the smoke fires as this clip starts: the thrust lands in 3 frames, then holds)
    START = {j: {k: tuple(x * 1.07 for x in v) for k, v in d.items()} for j, d in WIND_END.items()}
    STRIKE = {
        body: {"rot": (8, 0, 14), "loc": (0, -0.08, 0.02)},
        chest: {"rot": (10, -2, 12)},
        head: {"rot": (-10, 0, -8)},
        skirt: {"rot": (10, 0, -6)},
        arm_R: {"rot": (-60, -4, 12)},
        fore_R: {"rot": (-10, 0, 0)},
        arm_L: {"rot": (14, 0, -10)},
        chain[0]: {"rot": (-36, 0, 6)},
    }
    c = S.Clip("attack", 22, joints=ALL)
    c.pose(0, START, ease="quad_in")
    c.pose(3, STRIKE, ease="sine_out")
    c.pose(8, {j: {k: tuple(x * 0.94 for x in v) for k, v in d.items()} for j, d in STRIKE.items()}, ease="quad_inout")
    c.pose(22, {j: {k: tuple(x * 0.12 for x in v) for k, v in d.items()} for j, d in STRIKE.items()})
    c.key(ember_j, 0, scale=(1.32, 1.32, 1.75), ease="quad_in")
    c.key(ember_j, 3, scale=(1.45, 1.45, 2.1), ease="expo_out")
    c.key(ember_j, 9, scale=(1.05, 1.05, 1.0), ease="sine_inout")
    c.key(ember_j, 22, scale=(1, 1, 1))
    c.key(halo, 0, rot=(0, 0, 40), ease="expo_out")
    c.key(halo, 8, rot=(0, 0, 70))
    c.key(halo, 22, rot=(0, 0, 60))
    censer_chain(c, freq=4.5, damping=0.3, max_angle=40.0)
    c.bake()
    print("ATTACK impact frame 3")

    # ---------------------------------------------------------------- hit (one-shot)
    c = S.Clip("hit", 20, joints=ALL)
    S.hit_react(c, {body: {"loc": (0, 0.09, 0.03), "rot": (-12, 0, 5)}, skirt: {"rot": (-8, 0, 4)},
                    chest: {"rot": (-10, 4, 8)}, head: {"rot": (-20, 0, -12)},
                    arm_L: {"rot": (-24, 0, 20)}, arm_R: {"rot": (12, 0, -8)},
                    W["L"][0]: {"rot": (0, 15, -18)}, W["R"][0]: {"rot": (0, -15, 18)}},
                start=0, rise=2, settle=13, wobble=1.0, stagger=1.0)
    c.key(ember_j, 0, scale=(1, 1, 1), ease="expo_out")
    c.key(ember_j, 2, scale=(0.65, 0.65, 0.65), ease="sine_inout")
    c.key(ember_j, 14, scale=(1, 1, 1))
    censer_chain(c, freq=2.6)
    c.bake()

    # ---------------------------------------------------------------- death (one-shot) 42 f
    # the presence leaves the vestments: a convulsion, then the robes deflate onto the floor,
    # the hood folds, the halo shrinks away and the censer slips from the fingers.
    D = 42
    c = S.Clip("death", D, joints=ALL)
    c.key(body, 0, rot=(0, 0, 0), loc=(0, 0, 0), scale=(1, 1, 1), ease="sine_out")
    c.key(body, 6, rot=(-12, 0, 6), loc=(0, 0.04, 0.08), scale=(1, 1, 1), ease="sine_inout")
    c.key(body, 11, rot=(-8, 0, 4), loc=(0, 0.03, 0.06), scale=(1, 1, 1), ease="quad_in")
    c.key(body, 25, rot=(4, 0, 0), loc=(0, 0.02, GROUND), scale=(1, 1, 1), ease="quad_out")
    c.key(body, 29, rot=(2, 0, 0), loc=(0, 0.02, GROUND + 0.015), ease="quad_in")
    c.key(body, 33, rot=(3, 0, 0), loc=(0, 0.02, GROUND), ease="constant")
    # robes: empty cloth crumples (skirt squashes flat and spreads)
    c.key(skirt, 0, scale=(1, 1, 1), rot=(0, 0, 0), loc=(0, 0, 0), ease="sine_inout")
    c.key(skirt, 11, scale=(1.04, 1.04, 0.95), rot=(-4, 0, 0), loc=(0, 0, 0), ease="quad_in")
    c.key(skirt, 25, scale=(1.35, 1.3, 0.16), rot=(3, 0, 4), loc=(0, 0, -WAIST * 0.84 + 0.02), ease="back_out:1.4")
    c.key(skirt, D, scale=(1.4, 1.34, 0.14), rot=(3, 0, 4), loc=(0, 0, -WAIST * 0.85 + 0.02))
    c.key(chest, 0, rot=(0, 0, 0), loc=(0, 0, 0), scale=(1, 1, 1), ease="sine_inout")
    c.key(chest, 11, rot=(-14, 0, 6), loc=(0, 0, 0.02), scale=(1, 1, 1), ease="quad_in")
    c.key(chest, 25, rot=(62, 0, 14), loc=(0, -0.08, -WAIST + 0.16), scale=(1.12, 1.0, 0.55), ease="bounce_out")
    c.key(chest, D, rot=(70, 0, 16), loc=(0, -0.1, -WAIST + 0.12), scale=(1.15, 1.0, 0.5))
    c.key(head, 0, rot=(0, 0, 0), scale=(1, 1, 1), ease="sine_inout")
    c.key(head, 8, rot=(-30, 0, -8), scale=(1, 1, 1), ease="quad_in")
    c.key(head, 25, rot=(25, 20, 30), scale=(1.0, 1.0, 0.6), ease="back_out:2")
    c.key(head, D, rot=(28, 22, 34), scale=(1.0, 1.0, 0.55))
    c.key(halo, 0, scale=(1, 1, 1), rot=(0, 0, 0), ease="sine_out")
    c.key(halo, 7, scale=(1.25, 1.25, 1.25), rot=(0, 0, 50), ease="quad_in")
    c.key(halo, 20, scale=(0.02, 0.02, 0.02), rot=(0, 0, 200), ease="constant")
    for sd, s in (("L", 1), ("R", -1)):
        w0 = W[sd][0]
        c.key(w0, 0, rot=(0, 0, 0), ease="sine_inout")
        c.key(w0, 8, rot=(-10, s * 25, -s * 20), ease="quad_in")
        c.key(w0, 26, rot=(20, -s * 40, s * 10), ease="back_out:2")
        c.key(w0, D, rot=(22, -s * 42, s * 12))
    c.key(arm_L, 0, rot=(0, 0, 0), ease="sine_inout")
    c.key(arm_L, 8, rot=(-30, 0, 25), ease="quad_in")
    c.key(arm_L, 26, rot=(40, -30, 0), ease="back_out:1.5")
    c.key(arm_L, D, rot=(42, -32, 0))
    c.key(fore_L, 0, rot=(0, 0, 0), ease="sine_inout")
    c.key(fore_L, 26, rot=(70, 0, 20), ease="back_out:1.5")
    c.key(fore_L, D, rot=(72, 0, 20))
    c.key(arm_R, 0, rot=(0, 0, 0), ease="sine_inout")
    c.key(arm_R, 7, rot=(-35, 0, -15), ease="quad_in")       # flung up as it convulses
    c.key(arm_R, 26, rot=(35, 30, 0), ease="back_out:1.5")
    c.key(arm_R, D, rot=(36, 32, 0))
    c.key(fore_R, 0, rot=(0, 0, 0), ease="sine_inout")
    c.key(fore_R, 26, rot=(40, 0, 0), ease="back_out:1.5")
    c.key(fore_R, D, rot=(42, 0, 0))
    # the censer falls with the limp arm; its chain piles on the floor (follow_through floor)
    c.key(ember_j, 0, scale=(1.1, 1.1, 1.1), ease="sine_out")
    c.key(ember_j, 8, scale=(1.3, 1.3, 1.6), ease="quad_in")
    c.key(ember_j, 22, scale=(0.75, 0.75, 0.6), ease="sine_out")
    c.key(ember_j, D, scale=(0.35, 0.35, 0.3))
    censer_chain(c, freq=1.6, damping=0.16, gravity=9.0, floor=GROUND + 0.03)
    c.bake()

    AN.finish(root, "thurible_priest")
    return root
