"""Skarn, the Chain Warden: a hulking jailer in riveted black-iron plate. A barred cage helm locks
over a burning face, a furnace grate glows in his breastplate, crossed chains bind his torso,
layered pauldrons carry draped chain, and huge gauntlets end in rusted manacles. A meat hook
swings on a long chain from his right fist; a broken chain with an iron weight hangs from the left.
His belt carries the key ring and a dangling shackle over a tattered tabard.

Joints: K.humanoid rig + follow-through chains (hook, wrist, keys, shackle, tabard front/back).
Animations (sbanim): idle, walk (matched to 6 m/s), attack (hook throw), hit, death, cheer."""
import math
import os
import sys

import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import sbanim as A  # noqa: E402
import _demon_kit as K  # noqa: E402
from _demon_kit import SIDES, sname  # noqa: E402
import sbmat  # noqa: E402

CATEGORY = "demons"
# Procedural sbmat surfaces (battered iron plate, rust blooms, chain, leather, horn...) baked into
# one atlas (tools/blender/bake.py); furnace / eye / ember glows stay flat emissive materials.
BAKE = {"size": 1024, "samples": 16}
MOVE_SPEED = 6.0     # player.gd move_speed: the walk cycle is timed so feet stay planted at this speed


# ----------------------------------------------------------------------------- local mesh helpers

def _link(bm, p, t, n, length, wire, maj=6, mn=4):
    """One oval chain link (stadium torus) centred at p, long axis t, plane spanned by t and n."""
    b = t.cross(n)
    a = length * 0.5
    c = length * 0.3
    rings = []
    for i in range(maj):
        th = 2 * math.pi * (i + 0.5) / maj
        cen = p + t * (math.cos(th) * a) + n * (math.sin(th) * c)
        tan = (t * (-math.sin(th) * a) + n * (math.cos(th) * c)).normalized()
        out = tan.cross(b).normalized()
        ring = []
        for k in range(mn):
            ph = 2 * math.pi * k / mn + math.pi / mn
            ring.append(bm.verts.new(cen + out * (math.cos(ph) * wire) + b * (math.sin(ph) * wire)))
        rings.append(ring)
    for i in range(maj):
        r0, r1 = rings[i], rings[(i + 1) % maj]
        for k in range(mn):
            bm.faces.new((r0[k], r0[(k + 1) % mn], r1[(k + 1) % mn], r1[k]))


def links(name, parent, points, material, link=0.07, wire=0.011, maj=6, mn=4, smooth_n=3, closed=False):
    """Interlocking links along a smoothed path (cheaper than K.chain: maj*mn quads per link)."""
    pts = [Vector(p) for p in points]
    if closed:
        pts = pts + [pts[0]]
    path = K.catmull(pts, smooth_n) if len(pts) > 2 else pts
    total = sum((b - a).length for a, b in zip(path[:-1], path[1:]))
    step = link * 0.8
    count = max(1, int(round(total / step)))
    if closed and count % 2:
        count += 1
    step = total / count
    samples = []
    d_next = 0.0 if not closed else step * 0.5
    acc = 0.0
    for a, b in zip(path[:-1], path[1:]):
        seg = b - a
        L = seg.length
        while d_next <= acc + L + 1e-9 and len(samples) < count + (0 if closed else 1):
            u = (d_next - acc) / L if L > 1e-9 else 0.0
            samples.append((a + seg * u, seg.normalized()))
            d_next += step
        acc += L
    bm = bmesh.new()
    up = Vector((0, 0, 1))
    for i, (p, t) in enumerate(samples):
        n = up - t * up.dot(t)
        if n.length < 1e-3:
            n = Vector((1, 0, 0)) - t * t.x
        n.normalize()
        if i % 2:
            n = t.cross(n)
        _link(bm, p, t, n, link, wire, maj, mn)
    return K._obj(name, bm, parent, material, (0, 0, 0), (0, 0, 0), True, None)


def build():
    L = K.lin
    skin = sbmat.skin("Skarn_Skin", L((0.3, 0.13, 0.11)), rough=0.62, pores=90.0, scars=0.8,
                      crease=L((0.09, 0.035, 0.03)), high=L((0.45, 0.22, 0.18)))
    plate = sbmat.worn_steel("Skarn_PlateIron", L((0.42, 0.4, 0.37)), roughness=0.36, rust=0.08, grime=1.0)
    dark = sbmat.worn_steel("Skarn_BlackIron", L((0.12, 0.11, 0.105)), roughness=0.48, rust=0.3,
                            edge_k=3.5, scratch_k=2.0)
    chain_m = sbmat.worn_steel("Skarn_ChainIron", L((0.24, 0.22, 0.205)), roughness=0.42, scale=3.0, rust=0.35,
                               edge_k=2.0)
    rust = sbmat.worn_steel("Skarn_RustIron", L((0.36, 0.17, 0.08)), roughness=0.75, rust=1.0, wear=0.5)
    bronze = sbmat.worn_steel("Skarn_KeyBronze", L((0.45, 0.3, 0.14)), roughness=0.45, edge_k=1.5,
                              scratch_k=1.25)
    cloth = sbmat.linen("Skarn_TabardCloth", L((0.2, 0.075, 0.055)), weave=70.0, rough=0.93, stain=0.6,
                        stain_col=L((0.11, 0.06, 0.04)), grime_col=L((0.03, 0.015, 0.01)))
    leather = sbmat.leather("Skarn_Leather", L((0.15, 0.09, 0.06)), scale=0.55)
    horn = sbmat.horn("Skarn_HornBone", L((0.3, 0.27, 0.23)), rough=0.6, tip=L((0.1, 0.085, 0.075)))
    fire = K.mat("Skarn_FurnaceGlow", (0.5, 0.2, 0.04), 0.5, 0.0, (1.0, 0.45, 0.08), 9.0)
    eyes = K.mat("Skarn_EyeGlow", (0.7, 0.35, 0.06), 0.5, 0.0, (1.0, 0.62, 0.18), 16.0)
    ember = K.mat("Skarn_FaceEmber", (0.4, 0.12, 0.03), 0.6, 0.0, (1.0, 0.35, 0.05), 3.5)

    R = K.humanoid("Skarn", hip_h=1.03, thigh=0.48, shin=0.45, hip_w=0.145, spine=0.25, chest=0.42,
                   neck=0.08, shoulder_w=0.34, shoulder_z=0.33, upper=0.34, fore=0.34, arm_out=15,
                   spine_rot=8, head_rot=-8)

    def rivets(name, parent, pts, r=0.013, material=dark):
        for i, p in enumerate(pts):
            sb.sphere(f"{name}{i}", parent, r, loc=p, material=material, segments=5, rings=3)

    def seg_chain(name, parent, loc, nseg, seg, link, wire, rot=(0, 0, 0), first=0):
        """Hanging chain of `nseg` joints (each `seg` long, hanging along -Z) for follow_through."""
        js = []
        p = parent
        per = max(1, int(round(seg / (link * 0.8))))
        for i in range(nseg):
            j = sb.empty(f"{name}{i}", p, loc=loc if i == 0 else (0, 0, -seg), rot=rot if i == 0 else (0, 0, 0))
            bm = bmesh.new()
            for m in range(per):
                z = -(m + 0.5) * seg / per
                n = Vector((1, 0, 0)) if (i * per + m + first) % 2 == 0 else Vector((0, 1, 0))
                _link(bm, Vector((0, 0, z)), Vector((0, 0, -1)), n, link, wire)
            K._obj(f"{name}{i}_m", bm, j, chain_m)
            js.append(j)
            p = j
        R.extra.extend(js)
        return js

    # ================================================================ hips: belt, tabard, hanging gear
    H = R.hips
    K.loft("pelvis", H, [(0, 0, -0.16), (0, 0, -0.04), (0, 0, 0.1)], [(0.18, 0.14), (0.23, 0.17), (0.22, 0.165)], leather, segs=10)
    K.shell("belt", H, (0.25, 0.19, 0.075), lat=(-40, 40), lon=(-180, 180), segs=(14, 2), thick=0.03, material=leather,
            loc=(0, 0, 0.05))
    sb.box("belt_buckle_plate", H, size=(0.15, 0.04, 0.13), loc=(0, -0.205, 0.05), material=dark, bevel=0.012)
    sb.torus("belt_buckle_ring", H, 0.045, 0.011, loc=(0, -0.232, 0.05), rot=(90, 0, 0), material=rust,
             major_segments=10, minor_segments=4)
    rivets("belt_rivet", H, [(math.sin(math.radians(a)) * 0.262, -math.cos(math.radians(a)) * 0.2, 0.05)
                             for a in (-140, -100, -60, 60, 100, 140, 180)], 0.012)
    links("waist_chain", H, [(math.sin(math.radians(a)) * 0.27, -math.cos(math.radians(a)) * 0.21,
                              -0.02 - 0.05 * math.cos(math.radians(a)) + 0.02 * math.sin(math.radians(a)))
                             for a in range(0, 360, 30)], chain_m, link=0.08, wire=0.012, maj=6, mn=3, closed=True)

    # tattered tabard, front and back (segmented for follow-through)
    tab_f, tab_b = [], []
    p = H
    wf = [0.27, 0.26, 0.245, 0.23, 0.22]
    for i in range(4):
        j = sb.empty(f"tabard_f{i}", p, loc=(0, -0.215, 0.01) if i == 0 else (0, 0, -0.15), rot=(-3, 0, 0) if i == 0 else (0, 0, 0))
        K.panel(f"tabard_f{i}_m", j, wf[i], wf[i + 1], 0.17 if i < 3 else 0.2, cloth, segs=(3, 1), rag=0.45 if i == 3 else 0.0,
                seed=11, thick=0.012, cup=0.02)
        tab_f.append(j)
        p = j
    sb.torus("tabard_sigil", tab_f[1], 0.055, 0.009, loc=(0, -0.012, -0.08), rot=(90, 0, 0), material=dark,
             major_segments=10, minor_segments=3)
    sb.box("tabard_sigil_bar", tab_f[1], size=(0.012, 0.01, 0.16), loc=(0, -0.013, -0.08), material=dark, bevel=0.0)
    p = H
    wb = [0.36, 0.35, 0.34, 0.32, 0.31, 0.3]
    for i in range(5):
        j = sb.empty(f"tabard_b{i}", p, loc=(0, 0.2, 0.03) if i == 0 else (0, 0, -0.15), rot=(4, 0, 0) if i == 0 else (0, 0, 0))
        K.panel(f"tabard_b{i}_m", j, wb[i], wb[i + 1], 0.17 if i < 4 else 0.2, cloth, segs=(3, 1), rag=0.5 if i == 4 else 0.0,
                seed=17, thick=0.012, cup=-0.03, rot=(0, 0, 180))
        tab_b.append(j)
        p = j
    R.extra.extend(tab_f + tab_b)

    # key ring on the left hip, shackle chain on the right hip
    keyc = seg_chain("keychain", H, (0.25, -0.08, 0.0), 2, 0.07, 0.06, 0.009)
    kr = sb.empty("keyring", keyc[-1], loc=(0, 0, -0.07))
    R.extra.append(kr)
    sb.torus("keyring_m", kr, 0.06, 0.008, loc=(0, 0, -0.06), rot=(0, 90, 0), material=rust, major_segments=12, minor_segments=4)
    for k, ang in enumerate((-50, -15, 20, 55)):
        a = math.radians(ang)
        base = Vector((0, math.sin(a) * 0.06, -0.06 - math.cos(a) * 0.06))
        d = Vector((0, math.sin(a) * 0.5, -1)).normalized()
        L = 0.15 + 0.025 * (k % 2)
        sb.torus(f"key{k}_bow", kr, 0.022, 0.006, loc=base + d * 0.022, rot=(0, 90, 0), material=bronze,
                 major_segments=8, minor_segments=3)
        sb.ptube(f"key{k}_shaft", kr, [base + d * 0.04, base + d * L], [0.007, 0.006], sides=4, material=bronze)
        tip = base + d * L
        sb.box(f"key{k}_bit", kr, size=(0.008, 0.035, 0.03), loc=tip - d * 0.02 + Vector((0, 0.015, 0)),
               rot=(math.degrees(math.atan2(d.y, -d.z)), 0, 0), material=bronze, bevel=0.0)
    shc = seg_chain("beltchain", H, (-0.25, -0.02, -0.02), 4, 0.1, 0.07, 0.011)
    shk = sb.empty("shackle", shc[-1], loc=(0, 0, -0.1))
    R.extra.append(shk)
    K.horn("shackle_u", shk, [(0, -0.05, -0.12), (0, -0.055, -0.05), (0, -0.03, -0.01), (0, 0.0, 0.0), (0, 0.03, -0.01),
                              (0, 0.055, -0.05), (0, 0.05, -0.12)], 0.012, 0.011, rust, segs=5, n=2)
    sb.cylinder("shackle_bolt", shk, r1=0.012, depth=0.13, loc=(0, -0.065, -0.125), rot=(-90, 0, 0), material=rust,
                segments=6, bevel=0.0)

    # ================================================================ legs: riveted plate, heavy sabatons
    for s in SIDES:
        T, S, F = R.thigh[s], R.shin[s], R.foot[s]
        n = sname(s)
        K.loft(f"thigh_{n}", T, [(0, 0, 0.06), (0, 0, -0.2), (0, 0, -0.48)], [0.13, 0.12, 0.085], leather, segs=9)
        K.shell(f"cuisse_{n}", T, (0.145, 0.14, 0.21), lat=(-60, 72), lon=(-100, 100), segs=(6, 4), thick=0.024, material=plate,
                loc=(0, -0.005, -0.22), sharp=30)
        rivets(f"cuisse_rivet_{n}", T, [(s * 0.07, -0.145, -0.1), (s * -0.07, -0.145, -0.1), (0, -0.155, -0.3)])
        # tassets ride on the thigh (no clipping in the stride)
        for k in range(3):
            K.shell(f"tasset_{n}{k}", T, (0.17 - 0.008 * k, 0.16 - 0.008 * k, 0.07), lat=(-45, 25),
                    lon=(s * 45 - 85, s * 45 + 85), segs=(5, 1), thick=0.022, material=plate if k != 1 else dark,
                    loc=(s * 0.02, -0.01, 0.07 - 0.075 * k), flare=0.12, sharp=30)
        K.shell(f"knee_{n}", S, (0.1, 0.09, 0.1), lat=(-50, 90), lon=(-115, 115), segs=(6, 3), thick=0.024, material=plate,
                loc=(0, -0.04, 0.01), flare=0.15, sharp=30)
        K.shell(f"knee_wing_{n}", S, (0.07, 0.03, 0.07), lat=(-80, 80), lon=(-180, 180), segs=(6, 3), thick=0.0,
                material=dark, loc=(s * 0.085, -0.06, 0.0))
        K.horn(f"knee_spike_{n}", S, [(0, -0.12, 0.03), (0, -0.17, 0.06), (0, -0.19, 0.11)], 0.022, 0.003, dark, segs=5, n=2)
        K.loft(f"shin_{n}", S, [(0, 0, 0.02), (0, 0, -0.45)], [0.085, 0.065], leather, segs=8)
        K.shell(f"greave_{n}", S, (0.105, 0.105, 0.21), lat=(-80, 78), lon=(-180, 180), segs=(8, 4), thick=0.024, material=plate,
                loc=(0, 0, -0.23), flare=0.12, sharp=30)
        sb.ptube(f"greave_ridge_{n}", S, [(0, -0.1, -0.06), (0, -0.112, -0.2), (0, -0.108, -0.36)], [0.012, 0.014, 0.012],
                 sides=4, material=dark)
        rivets(f"greave_rivet_{n}", S, [(s * 0.08, -0.07, -0.08), (s * -0.08, -0.07, -0.08), (s * 0.085, -0.07, -0.33),
                                        (s * -0.085, -0.07, -0.33)])
        K.loft(f"sabaton_{n}", F, [(0, 0.07, -0.01), (0, -0.01, -0.025), (0, -0.12, -0.035), (0, -0.2, -0.045)],
               [(0.075, 0.05), (0.09, 0.05), (0.082, 0.04), (0.06, 0.022)], plate, segs=6, sharp=35)
        for k in range(2):
            K.shell(f"sabaton_lame_{n}{k}", F, (0.085 - 0.006 * k, 0.05, 0.05), lat=(-10, 80), lon=(-100, 100), segs=(5, 2),
                    thick=0.015, material=dark, loc=(0, -0.05 - 0.06 * k, -0.025), sharp=30)

    # ================================================================ torso: barrel breastplate, furnace grate, crossed chains
    SP, C = R.spine, R.chest
    K.loft("belly", SP, [(0, 0, -0.08), (0, 0, 0.12), (0, 0, 0.28)], [(0.21, 0.16), (0.23, 0.17), (0.26, 0.18)], leather, segs=10)
    for k, z in enumerate((-0.01, 0.075, 0.16)):
        K.shell(f"fauld{k}", SP, (0.245 + k * 0.012, 0.19 + k * 0.007, 0.075), lat=(-55, 22), lon=(-180, 180), segs=(12, 2),
                thick=0.022, material=plate if k % 2 == 0 else dark, loc=(0, 0, z), flare=0.1, sharp=30)
    K.loft("torso", C, [(0, 0, -0.06), (0, 0, 0.12), (0, 0, 0.3), (0, 0.01, 0.42)], [(0.26, 0.18), (0.3, 0.2), (0.31, 0.2), (0.17, 0.14)],
           skin, segs=10)
    bp_c, bp_r = (0, 0.0, 0.18), (0.335, 0.245, 0.3)
    K.shell("breastplate", C, bp_r, lat=(-58, 64), lon=(-180, 180), segs=(14, 6), thick=0.032, material=plate, loc=bp_c,
            sharp=28)
    # keel ridge down the front and the plackart over the belly
    sb.ptube("bp_keel", C, [K.on_ell(bp_c, bp_r, la, 0, 1.05) for la in (55, 35, 12)], [0.012, 0.02, 0.015], sides=4,
             material=dark)
    K.shell("plackart", C, (0.3, 0.235, 0.12), lat=(-30, 40), lon=(-110, 110), segs=(8, 2), thick=0.024, material=dark,
            loc=(0, -0.025, 0.0), flare=0.06, sharp=30)
    # furnace grate: glowing core behind black-iron bars
    sb.sphere("furnace", C, 0.1, loc=(0, -0.215, 0.2), scale=(1.25, 0.35, 1.0), material=fire, segments=10, rings=6)
    for k in range(5):
        z = 0.12 + k * 0.038
        K.loft(f"grate{k}", C, [(-0.11, -0.24 + 0.004 * abs(k - 2), z), (0, -0.258, z), (0.11, -0.24 + 0.004 * abs(k - 2), z)],
               [0.009, 0.011, 0.009], dark, segs=4)
    for s in SIDES:
        K.loft(f"grate_frame_{sname(s)}", C, [(s * 0.13, -0.226, 0.09), (s * 0.142, -0.24, 0.2), (s * 0.13, -0.226, 0.31)],
               [0.016] * 3, dark, segs=5)
    K.loft("grate_lintel", C, [(-0.14, -0.232, 0.315), (0, -0.25, 0.325), (0.14, -0.232, 0.315)], [0.016] * 3, dark, segs=5)
    K.crack("bp_crack0", C, bp_c, bp_r, [(30, -60), (18, -72), (22, -88)], fire, r=0.006, off=1.06)
    K.crack("bp_crack1", C, bp_c, bp_r, [(-20, 50), (-8, 62), (-14, 78)], fire, r=0.006, off=1.06)
    rivets("bp_rivet", C, [K.on_ell(bp_c, bp_r, la, lo, 1.1) for la, lo in
                           ((48, -45), (48, 45), (52, -18), (52, 18), (-40, -55), (-40, 55), (-45, -20), (-45, 20),
                            (8, -95), (8, 95), (-20, -100), (-20, 100), (40, 160), (40, -160))], 0.015)
    # crossed binding chains (an X over the chest) with a great padlock at the crossing
    for tag, tilt in (("a", 33), ("b", -33)):
        pts = []
        for i in range(12):
            a = 2 * math.pi * i / 12
            x, y = math.cos(a) * 0.345, math.sin(a) * 0.265
            ang = math.radians(tilt)
            pts.append((x * math.cos(ang), y, 0.19 + x * math.sin(ang)))
        links(f"bind_chain_{tag}", C, pts, chain_m, link=0.085, wire=0.013, maj=6, mn=3, closed=True)
    sb.box("padlock_body", C, size=(0.1, 0.045, 0.09), loc=(0, -0.29, 0.13), material=rust, bevel=0.012)
    K.horn("padlock_shackle", C, [(-0.03, -0.29, 0.17), (-0.032, -0.29, 0.215), (0, -0.29, 0.235), (0.032, -0.29, 0.215),
                                  (0.03, -0.29, 0.17)], 0.01, 0.01, dark, segs=5, n=2)
    sb.box("padlock_slot", C, size=(0.012, 0.01, 0.03), loc=(0, -0.314, 0.125), material=fire, bevel=0.0)
    # gorget: tall flared collar shielding the neck
    K.shell("gorget", C, (0.2, 0.17, 0.11), lat=(-30, 60), lon=(-180, 180), segs=(12, 3), thick=0.03, material=plate,
            loc=(0, 0.0, 0.42), flare=0.25, sharp=30)
    K.shell("gorget_collar", C, (0.17, 0.15, 0.09), lat=(-10, 70), lon=(-180, 180), segs=(12, 2), thick=0.02, material=dark,
            loc=(0, 0.01, 0.5), flare=-0.1, sharp=30)
    # back: iron ring bolted between the shoulders (the chains' anchor)
    sb.torus("back_ring", C, 0.07, 0.016, loc=(0, 0.27, 0.27), rot=(80, 0, 0), material=rust, major_segments=12, minor_segments=4)
    sb.box("back_ring_bolt", C, size=(0.08, 0.04, 0.06), loc=(0, 0.25, 0.33), material=dark, bevel=0.01)

    # ================================================================ arms: layered pauldrons, huge gauntlets, manacles
    for s in SIDES:
        Ar, Fo, Ha = R.arm[s], R.fore[s], R.hand[s]
        n = sname(s)
        K.loft(f"upperarm_{n}", Ar, [(0, 0, 0.06), (0, 0, -0.15), (0, 0, -0.34)], [0.105, 0.1, 0.085], skin, segs=9)
        K.shell(f"rerebrace_{n}", Ar, (0.11, 0.11, 0.12), lat=(-70, 70), lon=(-180, 180), segs=(8, 3), thick=0.02, material=plate,
                loc=(0, 0, -0.2), flare=0.1, sharp=30)
        # pauldron: dome + three overlapping lames + raised neck guard
        K.shell(f"paul_{n}", Ar, (0.23, 0.25, 0.19), lat=(-8, 90), lon=(-180, 180), segs=(10, 4), thick=0.035, material=plate,
                loc=(s * 0.05, 0, 0.03), rot=(0, -s * 16, 0), flare=0.14, sharp=30)
        for k in range(3):
            K.shell(f"paul_lame_{n}{k}", Ar, (0.235 + 0.008 * k, 0.255 + 0.006 * k, 0.075), lat=(-50, 22),
                    lon=(s * 90 - 92, s * 90 + 92), segs=(6, 2), thick=0.026, material=dark if k == 1 else plate,
                    loc=(s * (0.07 + 0.022 * k), 0, -0.02 - 0.075 * k), rot=(0, -s * (22 + 7 * k), 0), flare=0.16, sharp=30)
        K.shell(f"paul_guard_{n}", Ar, (0.03, 0.2, 0.1), lat=(0, 90), lon=(-180, 180), segs=(8, 2), thick=0.0, material=dark,
                loc=(-s * 0.07, 0.0, 0.17), rot=(0, -s * 25, 0), sharp=30)
        rivets(f"paul_rivet_{n}", Ar, [(s * 0.2, -0.13, 0.08), (s * 0.2, 0.13, 0.08), (s * 0.27, 0.0, 0.04), (s * 0.12, -0.2, 0.06),
                                       (s * 0.12, 0.2, 0.06)], 0.017)
        for k, (yy, zz) in enumerate(((-0.07, 0.19), (0.07, 0.19), (0.0, 0.215))):
            K.horn(f"paul_stud_{n}{k}", Ar, [(s * 0.08, yy, zz), (s * 0.1, yy * 1.2, zz + 0.05), (s * 0.12, yy * 1.3, zz + 0.09)],
                   0.024, 0.004, dark, segs=5, n=2)
        links(f"paul_chain_{n}", Ar, [(s * -0.02, -0.24, 0.0), (s * 0.12, -0.23, 0.15), (s * 0.26, -0.05, 0.12), (s * 0.27, 0.12, 0.05),
                                      (s * 0.14, 0.24, -0.04)], chain_m, link=0.075, wire=0.012, maj=6, mn=3)
        # gauntlet: leather forearm, plated vambrace, a big bell cuff, rusted manacle at the wrist
        K.loft(f"forearm_{n}", Fo, [(0, 0, 0.02), (0, 0, -0.33)], [0.09, 0.075], leather, segs=8)
        K.shell(f"couter_{n}", Fo, (0.09, 0.09, 0.09), lat=(-30, 90), lon=(-180, 180), segs=(8, 3), thick=0.02, material=plate,
                loc=(0, 0.035, 0.0), rot=(-70, 0, 0), flare=0.1, sharp=30)
        K.horn(f"couter_spike_{n}", Fo, [(0, 0.1, 0.0), (0, 0.15, 0.02), (0, 0.2, 0.06)], 0.022, 0.003, dark, segs=5, n=2)
        K.shell(f"vambrace_{n}", Fo, (0.11, 0.11, 0.15), lat=(-75, 70), lon=(-180, 180), segs=(8, 3), thick=0.022, material=plate,
                loc=(0, 0, -0.14), sharp=30)
        K.shell(f"gaunt_cuff_{n}", Fo, (0.135, 0.135, 0.08), lat=(-60, 40), lon=(-180, 180), segs=(10, 2), thick=0.022,
                material=dark, loc=(0, 0, -0.25), flare=0.22, sharp=30)
        K.shell(f"manacle_{n}", Fo, (0.12, 0.12, 0.035), lat=(-60, 60), lon=(-180, 180), segs=(10, 2), thick=0.025, material=rust,
                loc=(0, 0, -0.325))
        rivets(f"manacle_rivet_{n}", Fo, [(s * 0.125, 0, -0.325), (0, -0.125, -0.325)], 0.016, rust)
        K.shell(f"gaunt_hand_{n}", Ha, (0.075, 0.055, 0.09), lat=(-60, 80), lon=(-180, 180), segs=(8, 3), thick=0.0, material=plate,
                loc=(0, 0, -0.05), sharp=35)
        K.shell(f"gaunt_knuckle_{n}", Ha, (0.08, 0.04, 0.03), lat=(-80, 80), lon=(-120, 120), segs=(6, 2), thick=0.0, material=dark,
                loc=(0, -0.03, -0.14), sharp=30)
        K.claw_hand(f"hand_{n}", Ha, plate, dark, size=1.8, claw_len=0.035, curl=72 if s < 0 else 45)

    # broken chain hanging from the LEFT manacle, ending in an iron weight
    wristc = seg_chain("wristchain_L", R.fore[1], (0.02, 0.1, -0.33), 4, 0.1, 0.072, 0.012, rot=(-6, 0, 0))
    wt = sb.empty("weight_L", wristc[-1], loc=(0, 0, -0.1))
    R.extra.append(wt)
    sb.torus("weight_eye", wt, 0.025, 0.008, loc=(0, 0, -0.02), rot=(0, 90, 0), material=rust, major_segments=8, minor_segments=3)
    sb.sphere("weight_ball", wt, 0.07, loc=(0, 0, -0.1), material=dark, segments=10, rings=6)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        K.horn(f"weight_spike{k}", wt, [(math.cos(a) * 0.06, math.sin(a) * 0.06, -0.1), (math.cos(a) * 0.1, math.sin(a) * 0.1, -0.1)],
               0.018, 0.003, dark, segs=4, n=1)

    # the great meat hook on its chain, gripped in the RIGHT fist
    hookc = seg_chain("hookchain", R.hand[-1], (0, -0.025, -0.13), 5, 0.1, 0.085, 0.014)
    hk = sb.empty("hook", hookc[-1], loc=(0, 0, -0.1))
    R.extra.append(hk)
    sb.torus("hook_eye", hk, 0.035, 0.012, loc=(0, 0, -0.03), rot=(0, 90, 0), material=rust, major_segments=10, minor_segments=4)
    K.horn("hook_m", hk, [(0, 0, -0.06), (0, 0, -0.2), (0, -0.02, -0.3), (0, -0.1, -0.35), (0, -0.18, -0.31), (0, -0.2, -0.22),
                          (0, -0.19, -0.15)], 0.032, 0.004, dark, segs=7, n=3)
    K.horn("hook_barb", hk, [(0, -0.19, -0.2), (0, -0.165, -0.24), (0, -0.14, -0.26)], 0.014, 0.002, dark, segs=4, n=2)
    sb.ptube("hook_collar", hk, [(0, 0, -0.07), (0, 0, -0.11)], [0.04, 0.036], sides=6, material=rust)

    # ================================================================ head: cage helm over a burning face
    K.loft("neck_m", R.neck, [(0, 0, -0.05), (0, 0, 0.1)], [0.11, 0.09], skin, segs=8)
    Hd = R.head
    K.loft("skull", Hd, [(0, 0.04, 0.0), (0, 0.0, 0.08), (0, -0.01, 0.17), (0, 0.01, 0.24)],
           [(0.075, 0.07), (0.105, 0.11), (0.1, 0.1), (0.06, 0.06)], skin, segs=10, subdiv=1)
    K.loft("jaw", Hd, [(0, -0.02, 0.05), (0, -0.115, 0.035)], [(0.09, 0.05), (0.065, 0.035)], skin, segs=8)
    K.loft("brow", Hd, [(-0.075, -0.09, 0.165), (0, -0.115, 0.175), (0.075, -0.09, 0.165)], [0.022, 0.026, 0.022], skin, segs=6)
    sb.sphere("face_ember", Hd, 0.08, loc=(0, -0.055, 0.11), scale=(1.0, 0.75, 1.1), material=ember, segments=10, rings=6)
    for s in SIDES:
        sb.sphere(f"eye_{sname(s)}", Hd, 0.02, loc=(s * 0.045, -0.105, 0.145), scale=(1.6, 0.6, 0.75), material=eyes, segments=8, rings=4)
        K.horn(f"tusk_{sname(s)}", Hd, [(s * 0.04, -0.11, 0.05), (s * 0.05, -0.13, 0.09), (s * 0.06, -0.12, 0.12)], 0.012, 0.002,
               horn, segs=4, n=2)
    sb.box("maw", Hd, size=(0.075, 0.025, 0.022), loc=(0, -0.122, 0.07), material=fire, bevel=0.0)
    bars = 12
    for k in range(bars):
        a = 2 * math.pi * (k + 0.5) / bars
        x, y = math.sin(a), -math.cos(a)
        bend = 0.012 if k in (5, 6) else 0.0     # two front bars bent outward (pried from within)
        K.loft(f"cage_bar{k}", Hd, [(x * 0.155, y * 0.155, -0.03), (x * (0.165 + bend), y * (0.165 + bend * 3), 0.13),
                                    (x * 0.12, y * 0.12, 0.29), (x * 0.03, y * 0.03, 0.35)],
               [0.012, 0.012, 0.011, 0.01], dark, segs=4)
    for z, r in ((-0.025, 0.158), (0.12, 0.168), (0.26, 0.135)):
        K.shell(f"cage_band{int(z * 1000)}", Hd, (r, r, 0.024), lat=(-60, 60), lon=(-180, 180), segs=(12, 2), thick=0.014,
                material=plate, loc=(0, 0, z))
    sb.ptube("cage_spine", Hd, [(0, 0.16, -0.02), (0, 0.17, 0.13), (0, 0.13, 0.28), (0, 0.04, 0.35)], [0.018] * 4, sides=4,
             material=plate)
    rivets("cage_rivet", Hd, [(math.sin(a) * 0.172, -math.cos(a) * 0.172, 0.12) for a in
                              (math.radians(x) for x in range(-150, 181, 60))], 0.013)
    K.horn("cage_spike", Hd, [(0, 0, 0.34), (0, 0, 0.44), (0, 0.01, 0.53)], 0.032, 0.003, plate, segs=6, n=2)
    sb.torus("cage_top_ring", Hd, 0.045, 0.012, loc=(0, 0.02, 0.37), rot=(90, 0, 90), material=rust, major_segments=10,
             minor_segments=4)
    # cage lock hanging at the chin
    sb.box("cage_lock", Hd, size=(0.06, 0.03, 0.06), loc=(0, -0.175, -0.07), material=rust, bevel=0.008)
    K.horn("cage_lock_hasp", Hd, [(-0.018, -0.175, -0.04), (0, -0.175, -0.015), (0.018, -0.175, -0.04)], 0.007, 0.007, dark, segs=4, n=2)
    for s in SIDES:   # horns bursting out between the bars (wide: they read from the high game camera)
        K.horn(f"horn_{sname(s)}", Hd, [(s * 0.08, 0.0, 0.2), (s * 0.2, 0.02, 0.24), (s * 0.31, -0.01, 0.33),
                                        (s * 0.36, -0.09, 0.44)],
               0.046, 0.004, horn, segs=6, n=2, ridges=0.12)

    # ================================================================ silhouette (characters-polish): furnace stacks
    # Two squat smokestacks bolted to the back, venting embers (Godot attaches particles to the
    # fx_embers_* joints), so the warden reads as a walking furnace from above; glowing seams on
    # the pauldrons carry the furnace light out to the shoulders.
    for s in SIDES:
        n = sname(s)
        base = (s * 0.12, 0.25, 0.24)
        mid = (s * 0.15, 0.31, 0.48)
        top = (s * 0.2, 0.36, 0.72)
        K.loft(f"stack_{n}", C, [base, mid, top], [0.075, 0.065, 0.07], dark, segs=8, caps=(True, False))
        for k, z in enumerate((0.36, 0.56)):
            u = (z - 0.24) / 0.48
            cx, cy = base[0] + (top[0] - base[0]) * u, base[1] + (top[1] - base[1]) * u
            sb.torus(f"stack_band_{n}{k}", C, 0.074, 0.012, loc=(cx, cy, z), rot=(0, s * 8, 0), material=rust,
                     major_segments=12, minor_segments=4)
        sb.torus(f"stack_lip_{n}", C, 0.072, 0.016, loc=top, rot=(0, s * 10, 0), material=dark, major_segments=12,
                 minor_segments=4)
        sb.cylinder(f"stack_fire_{n}", C, 0.058, 0.05, 0.02, loc=(top[0], top[1], top[2] - 0.03), rot=(0, s * 10, 0),
                    material=fire, segments=10, bevel=0.0)
        sb.empty(f"fx_embers_{n}", C, loc=(top[0], top[1], top[2] + 0.04))
        K.crack(f"paul_seam_{n}", R.arm[s], (s * 0.05, 0, 0.03), (0.23, 0.25, 0.19),
                [(55, s * 40), (40, s * 75), (48, s * 110), (30, s * 140)], fire, r=0.007, off=1.12)

    K.finalize(R.root)
    animate(R, dict(tab_f=tab_f, tab_b=tab_b, keys=keyc + [kr], shackle=shc + [shk], wrist=wristc + [wt],
                    hook=hookc + [hk]))
    return R.root


# ============================================================================= animation

def animate(R, ch):
    ALL = [j for j in A.joints(R.root, include_root=False) if j.name != "look"]
    th, sh, ft = (R.thigh[1], R.thigh[-1]), (R.shin[1], R.shin[-1]), (R.foot[1], R.foot[-1])
    ar, fo, ha = (R.arm[1], R.arm[-1]), (R.fore[1], R.fore[-1]), (R.hand[1], R.hand[-1])
    rig = {"hips": R.hips, "spine": R.spine, "chest": R.chest, "head": R.head, "thigh": th, "shin": sh, "foot": ft,
           "arm": ar, "fore": fo}
    hook, wrist = ch["hook"], ch["wrist"]

    def trail(c, root, side, back=0.0):
        """Keys a fist/wrist chain to hang straight down (+`back` deg trailing), cancelling the arm's
        pitch, so the keyed pose agrees with gravity and one-shots start from a settled chain."""
        def fn(f):
            x = sum(c.eval(j, "rot", f)[0] for j in (ar[side], fo[side], ha[side])) - 8.0
            return (-x + back, 0, 0)
        c.add(root, fn)

    def tabard_clear(c, k=0.75):
        """Front tabard lifts with whichever thigh is forward, back tabard with the one behind."""
        def front(f):
            fwd = min(c.eval(th[0], "rot", f)[0], c.eval(th[1], "rot", f)[0], 0.0)
            return (fwd * k, 0, 0)

        def back(f):
            bwd = max(c.eval(th[0], "rot", f)[0], c.eval(th[1], "rot", f)[0], 0.0)
            return (bwd * k * 0.6, 0, 0)
        c.add(ch["tab_f"][0], front)
        c.add(ch["tab_b"][0], back)

    def secondary(c, floor=None, hook_freq=0.45, hook_damp=0.08, hook_max=170, wind=None):
        A.follow_through(c, hook, freq=hook_freq, damping=hook_damp, gravity=9.8, falloff=0.97, tip=(0, 0, -0.3), floor=floor, wind=wind,
                         max_angle=hook_max)
        A.follow_through(c, wrist, freq=0.5, damping=0.1, gravity=9.8, falloff=0.95, tip=(0, 0, -0.17), floor=floor, wind=wind,
                         max_angle=170)
        A.follow_through(c, ch["keys"], freq=0.9, damping=0.12, gravity=9.8, falloff=0.9, tip=(0, 0, -0.18), floor=floor, wind=wind)
        A.follow_through(c, ch["shackle"], freq=0.5, damping=0.1, gravity=9.8, falloff=0.95, tip=(0, 0, -0.12),
                         floor=floor, wind=wind, max_angle=170)
        A.follow_through(c, ch["tab_f"], freq=2.6, damping=0.16, gravity=6.0, falloff=0.85, tip=(0, 0, -0.18), floor=floor, wind=wind)
        A.follow_through(c, ch["tab_b"], freq=2.4, damping=0.15, gravity=6.0, falloff=0.85, tip=(0, 0, -0.18), floor=floor, wind=wind)

    stance = {th[0]: {"rot": (-12, -4, 0)}, sh[0]: {"rot": (22, 0, 0)}, ft[0]: {"rot": (-10, 4, 0)},
              R.hips: {"loc": (0, 0.01, -0.03)}, R.spine: {"rot": (4, 0, 0)}, R.neck: {"rot": (-4, 0, 0)},
              ar[0]: {"rot": (-6, 0, 0)}, fo[0]: {"rot": (-18, 0, 0)},
              ar[1]: {"rot": (-10, 0, 0)}, fo[1]: {"rot": (-28, 0, 0)}}

    # ---------------------------------------------------------------- idle (loop): heavy breathing, chains sway
    c = A.Clip("idle", 90, joints=ALL)
    c.pose(0, stance, mirror=True)
    A.breathe(c, R.chest, amp=2.6, rise=0.01, swell=0.02, cycles=2, shoulders=[ar[0], ar[1]], head=R.head)
    c.add(R.hips, lambda f: (0.014 * A.wave(c, f), 0, -0.006 * abs(A.wave(c, f))), "loc")
    c.add(R.hips, lambda f: (0, 1.6 * A.wave(c, f), 0), "rot")
    c.add(R.spine, lambda f: (0, -1.2 * A.wave(c, f, offset=-0.05), 0), "rot")
    A.noise(c, R.head, rot=(3, 6, 2), freq=0.35, seed=3)
    A.noise(c, ha[1], rot=(5, 4, 8), freq=0.4, seed=5)      # the hook fist idly rolls -> chain swings
    A.noise(c, fo[1], rot=(4, 0, 3), freq=0.3, seed=6)
    A.noise(c, fo[0], rot=(3, 0, 3), freq=0.33, seed=7)
    A.noise(c, hook[0], rot=(10, 0, 8), freq=0.45, seed=8)
    A.noise(c, wrist[0], rot=(8, 0, 6), freq=0.5, seed=9)
    trail(c, hook[0], 1)
    trail(c, wrist[0], 0)
    tabard_clear(c)
    secondary(c, floor=0.03)
    c.bake()

    # ---------------------------------------------------------------- walk (loop): heavy stomping stride
    stride, st, leg = 40.0, 0.42, R.thigh_len + R.shin_len
    reach = leg * (math.sin(math.radians(stride)) + math.sin(math.radians(stride * 0.8)))
    frames = max(10, int(round(reach * A.FPS / (st * MOVE_SPEED))))
    c = A.Clip("walk", frames, joints=ALL)
    A.walk(c, rig, stride=stride, knee=64, load=14, stance=st, heavy=1.0, arm=14, elbow=24, elbow_swing=12, lean=8,
           twist=7, hip_roll=5, hip_yaw=8, sway=0.035, arm_out=7, head_stab=0.8)
    c.add(fo[1], lambda f: (-14, 0, 0), "rot")               # hook fist carried forward
    c.add(ar[1], lambda f: (-6, 0, 0), "rot")
    c.add(R.spine, lambda f: (0, 1.5 * A.wave(c, f, cycles=2), 0), "rot")
    tabard_clear(c, 0.8)

    # at this cadence a loose chain would whirl around the fist: key the hanging chains to trail
    # down-and-back (cancelling the arm swing) and let a stiffer spring + drag do the swaying
    trail(c, hook[0], 1, 28)
    trail(c, wrist[0], 0, 24)
    c.add(ch["shackle"][0], lambda f: (20, 0, 0))
    c.add(ch["keys"][0], lambda f: (15, 0, 0))
    A.follow_through(c, hook, freq=2.2, damping=0.25, gravity=9.8, falloff=0.9, tip=(0, 0, -0.3), floor=0.03, max_angle=60)
    A.follow_through(c, wrist, freq=2.2, damping=0.25, gravity=9.8, falloff=0.9, tip=(0, 0, -0.17), floor=0.03, max_angle=60)
    A.follow_through(c, ch["keys"], freq=2.0, damping=0.2, gravity=9.8, falloff=0.9, tip=(0, 0, -0.18), wind=(0, 6, 0))
    A.follow_through(c, ch["shackle"], freq=1.8, damping=0.2, gravity=9.8, falloff=0.9, tip=(0, 0, -0.12), wind=(0, 6, 0),
                     max_angle=70)
    A.follow_through(c, ch["tab_f"], freq=2.6, damping=0.16, gravity=6.0, falloff=0.85, tip=(0, 0, -0.18), wind=(0, 8, 0))
    A.follow_through(c, ch["tab_b"], freq=2.4, damping=0.15, gravity=6.0, falloff=0.85, tip=(0, 0, -0.18), wind=(0, 8, 0))
    c.bake()
    print(f"SKARN walk frames={frames} speed={A.stride_speed(leg, stride, frames, stance=st):.2f} m/s")

    # ---------------------------------------------------------------- attack: wind up overhead, hurl the hook forward
    c = A.Clip("attack", 40, joints=ALL)
    c.pose(0, {th[0]: {"rot": (0, 0, 0)}}, mirror=True)
    antic = {ar[1]: {"rot": (25, 120, 10)}, fo[1]: {"rot": (-75, 0, 0)}, ha[1]: {"rot": (20, 0, 0)},
             R.chest: {"rot": (-10, 6, -26)}, R.spine: {"rot": (-6, 0, -12)}, R.hips: {"loc": (0, 0.07, -0.08), "rot": (0, 0, -8)},
             R.head: {"rot": (6, 0, 16)}, R.neck: {"rot": (0, 0, 8)},
             ar[0]: {"rot": (-55, -25, 0)}, fo[0]: {"rot": (-40, 0, 0)},
             th[0]: {"rot": (-24, -6, 0)}, sh[0]: {"rot": (30, 0, 0)}, ft[0]: {"rot": (-6, 6, 0)},
             th[1]: {"rot": (12, 6, 0)}, sh[1]: {"rot": (20, 0, 0)}, ft[1]: {"rot": (-32, -6, 0)}}
    strike = {ar[1]: {"rot": (-100, 5, -10)}, fo[1]: {"rot": (-4, 0, 0)}, ha[1]: {"rot": (-10, 0, 0)},
              R.chest: {"rot": (18, -6, 30)}, R.spine: {"rot": (14, 0, 12)}, R.hips: {"loc": (0, -0.16, -0.15), "rot": (0, 0, 10)},
              R.head: {"rot": (-14, 0, -12)}, R.neck: {"rot": (0, 0, -6)},
              ar[0]: {"rot": (35, -30, 0)}, fo[0]: {"rot": (-30, 0, 0)},
              th[0]: {"rot": (-46, -6, 0)}, sh[0]: {"rot": (52, 0, 0)}, ft[0]: {"rot": (-6, 6, 0)},
              th[1]: {"rot": (28, 6, 0)}, sh[1]: {"rot": (24, 0, 0)}, ft[1]: {"rot": (-52, -6, 0)}}
    follow = {j: {k: tuple(x * 0.9 for x in v) for k, v in d.items()} for j, d in strike.items()}
    follow[ar[1]] = {"rot": (-80, 5, -18)}
    ev = A.attack(c, {"antic": antic, "strike": strike, "follow": follow}, start=0, antic=11, antic_hold=4, strike=3,
                  hold=5, recover=15, overshoot=0.12, push=0.08)
    A.jitter(c, ar[1], rot=(1.5, 1.5, 1.5), start=11, end=15)
    A.jitter(c, R.chest, rot=(0.8, 0.8, 0.8), start=ev["impact"], end=ev["impact"] + 5, freq=14)
    # the hook chain: dragged up behind the shoulder in the wind-up, whipped out straight ahead of
    # the fist at impact (links lag one after another), held, then dropping under its own weight
    imp = ev["impact"]
    links_ = hook[:-1]
    for i, j in enumerate(links_):
        lag = i / (len(links_) - 1)
        c.key(j, 0, rot=(0, 0, 0))
        c.key(j, 11, rot=(150 if i == 0 else 12, 0, 0), ease="sine_inout")
        c.key(j, imp - 4, rot=(165 if i == 0 else 16, 0, 0), ease="quad_in")
        c.key(j, imp - 1, rot=(70 if i == 0 else 30 + 10 * lag, 0, 0), ease="quad_out")
        c.key(j, imp + 1, rot=(0 if i == 0 else 6 * (1 - lag), 0, 0), ease="sine_out")
        c.key(j, imp + 4, rot=(-4, 0, 0), ease="quad_in")
        c.key(j, imp + 10, rot=(55 if i == 0 else 12, 0, 0), ease="smooth")
        c.key(j, 40, rot=(0, 0, 0))
    c.key(hook[-1], 0, rot=(0, 0, 0))
    c.key(hook[-1], imp - 1, rot=(40, 0, 0), ease="quad_out")
    c.key(hook[-1], imp + 2, rot=(-35, 0, 0), ease="smooth")
    c.key(hook[-1], imp + 6, rot=(-25, 0, 0), ease="smooth")
    c.key(hook[-1], 40, rot=(0, 0, 0))
    tabard_clear(c)
    secondary(c, floor=0.03, hook_freq=4.0, hook_damp=0.22, hook_max=60)
    c.bake()
    print("SKARN attack impact frame", ev["impact"])

    # ---------------------------------------------------------------- hit (one-shot recoil)
    c = A.Clip("hit", 20, joints=ALL)
    c.pose(0, stance, mirror=True)
    A.hit_react(c, {R.hips: {"loc": (0, 0.08, -0.04), "rot": (-6, 0, 0)}, R.spine: {"rot": (-10, 0, 5)},
                    R.chest: {"rot": (-14, 4, 8), "scale": (1.03, 1.03, 0.97)}, R.head: {"rot": (-20, 0, -12)},
                    ar[0]: {"rot": (-28, -20, 0)}, ar[1]: {"rot": (-18, 22, 0)}, fo[0]: {"rot": (-30, 0, 0)},
                    fo[1]: {"rot": (-20, 0, 0)}, th[0]: {"rot": (-8, 0, 0)}, sh[0]: {"rot": (14, 0, 0)}},
                start=0, rise=2, settle=13, wobble=1.0, stagger=1.0)
    trail(c, hook[0], 1)
    trail(c, wrist[0], 0)
    tabard_clear(c)
    secondary(c, floor=0.03, hook_damp=0.3)
    c.bake()

    # ---------------------------------------------------------------- death: buckle to the knees, crash face-down
    c = A.Clip("death", 66, joints=ALL)
    buckle = {R.hips: {"loc": (0, 0.05, -0.32)}, th[0]: {"rot": (-55, -6, 0)}, sh[0]: {"rot": (95, 0, 0)}, ft[0]: {"rot": (-30, 0, 0)},
              th[1]: {"rot": (-30, 8, 0)}, sh[1]: {"rot": (100, 0, 0)}, ft[1]: {"rot": (-10, 0, 0)},
              R.spine: {"rot": (22, 0, 4)}, R.chest: {"rot": (8, 0, 0)}, R.head: {"rot": (28, 0, 0)},
              ar[0]: {"rot": (-15, -10, 0)}, ar[1]: {"rot": (-25, 10, 0)}, fo[0]: {"rot": (-10, 0, 0)}, fo[1]: {"rot": (-15, 0, 0)}}
    limp = {R.hips: {"loc": (0, 0.0, -0.22)}, th[0]: {"rot": (-12, -8, 0)}, sh[0]: {"rot": (25, 0, 0)}, ft[0]: {"rot": (30, 0, 0)},
            th[1]: {"rot": (-4, 10, 0)}, sh[1]: {"rot": (12, 0, 0)}, ft[1]: {"rot": (35, 0, 0)},
            R.spine: {"rot": (-8, 0, 0)}, R.chest: {"rot": (-6, 0, 0)}, R.head: {"rot": (-30, 0, 30)},
            ar[0]: {"rot": (-140, -40, 0)}, ar[1]: {"rot": (-60, 70, 0)}, fo[0]: {"rot": (-15, 0, 0)}, fo[1]: {"rot": (-20, 0, 0)}}
    imp = A.death(c, R.body, fall=(84, 0, -10), drop=(0, -0.05, 0.27), stagger=7, buckle=11, topple=12, bounce=0.05,
                  recoil={R.chest: {"rot": (-14, 0, 6)}, R.head: {"rot": (-20, 0, 0)}, ar[1]: {"rot": (-30, 20, 0)}},
                  buckle_pose=buckle, limp_pose=limp)
    A.jitter(c, R.chest, rot=(1.5, 1.0, 1.5), start=imp, end=imp + 6, freq=12)
    trail(c, hook[0], 1)
    trail(c, wrist[0], 0)
    tabard_clear(c)
    secondary(c, floor=0.04)
    c.bake()
    print("SKARN death impact frame", imp)

    # ---------------------------------------------------------------- cheer: gather, rise, arms flung wide, roar, chains rattle
    c = A.Clip("cheer", 60, joints=ALL)
    gather = {R.hips: {"loc": (0, 0.03, -0.12)}, th[0]: {"rot": (-30, -8, 0)}, sh[0]: {"rot": (55, 0, 0)}, ft[0]: {"rot": (-25, 8, 0)},
              R.spine: {"rot": (20, 0, 0)}, R.chest: {"rot": (10, 0, 0)}, R.head: {"rot": (14, 0, 0)},
              ar[0]: {"rot": (-30, -10, 20)}, fo[0]: {"rot": (-70, 0, 0)}}
    roar = {R.hips: {"loc": (0, 0.02, -0.06)}, th[0]: {"rot": (-14, -12, 0)}, sh[0]: {"rot": (24, 0, 0)}, ft[0]: {"rot": (-10, 12, 0)},
            R.spine: {"rot": (-12, 0, 0)}, R.chest: {"rot": (-14, 0, 0), "scale": (1.04, 1.04, 1.02)}, R.head: {"rot": (-30, 0, 0)},
            R.neck: {"rot": (-6, 0, 0)},
            ar[0]: {"rot": (-25, -118, 0)}, fo[0]: {"rot": (-30, 0, 0)}, ha[0]: {"rot": (-15, 0, 0)}}
    c.pose(0, {j: {k: (0, 0, 0) if k != "scale" else (1, 1, 1) for k in v} for j, v in roar.items()}, mirror=True)
    c.pose(10, gather, mirror=True, ease="quad_in")
    c.pose(16, roar, mirror=True, ease="back_out:1.4")
    c.pose(40, {j: {k: (tuple(x * 1.06 for x in v) if k != "scale" else v) for k, v in d.items()} for j, d in roar.items()},
           mirror=True, ease="sine_inout")
    c.pose(60, {j: {k: (0, 0, 0) if k != "scale" else (1, 1, 1) for k in v} for j, v in roar.items()}, mirror=True)
    for j, amp in ((ar[0], 3.0), (ar[1], 3.0), (R.chest, 1.2), (R.head, 2.0), (fo[0], 2.5), (fo[1], 2.5)):
        A.jitter(c, j, rot=(amp, amp, amp), start=17, end=40, freq=11, seed=hash(j.name) % 97)
    for j in (hook[0], wrist[0], ch["keys"][0], ch["shackle"][0]):
        A.jitter(c, j, rot=(10, 0, 10), start=16, end=42, freq=7, seed=len(j.name))
    trail(c, hook[0], 1)
    trail(c, wrist[0], 0)
    tabard_clear(c)
    secondary(c, floor=0.03)
    c.bake()
