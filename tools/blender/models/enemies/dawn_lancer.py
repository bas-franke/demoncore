"""Dawn Lancer: a winged knight of the first light. It glides leaning far forward on great swept
wings, legs trailing, a very long ornate lance couched under its arm with a pennant streaming
from below the burning point. Crested great helm crowned with gold sun-rays, a thin halo behind,
layered gold-trimmed ivory plate, a cape and a back tabard that stream in the wind.

Anims: fly (hovering glide loop: slow wing beat, cloth follow-through), windup (rears back,
lance lowers and draws back, wings gather in - the charge telegraph), attack (the charge:
explosive dash pose, wings swept back, cloth streaming; time-stretched over the dash),
hit (recoil), death (wings fail, it falls out of the air and the wings crumple)."""
import importlib.util
import math
import os

import bpy
import sb
import sbanim as N
import sbmat

_spec = importlib.util.spec_from_file_location("_angel", os.path.join(os.path.dirname(__file__), "_angel.py"))
A = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(A)

CATEGORY = "enemies"
# Procedural sbmat surfaces (_angel.baked_mats + ivory lance / banner cloth) baked into one atlas
# (tools/blender/bake.py); the visor and holy-light glows stay flat emissive materials.
BAKE = {"size": 1024, "samples": 16}

H = 0.95            # knight scale
HOVER = 0.24        # glide height added to the hips
LEAN = 48.0         # forward lean of the hips (deg)
CHEST_LEAN = 4.0
LANCE_X = -(LEAN + CHEST_LEAN) + 10.0   # lance rest pitch in the chest frame -> 10 deg nose-down in the world
WING_UP, WING_SWEEP = 10.0, 26.0
WING_AOA = -6.0     # wing angle of attack in the level frame (trailing edge down)
P0 = LEAN + CHEST_LEAN


def wing_local(P, up, sweep, pitch=0.0):
    """Euler (deg) in the CHEST frame for the +X wing root so that, with the chest pitched P deg
    forward in the world, the wing is raised `up`, swept back `sweep` and pitched `pitch` relative
    to a LEVEL frame (the body pitch is cancelled, so 'sweep back' stays sweep back in a dive)."""
    from mathutils import Euler, Matrix
    R = math.radians
    m = (Matrix.Rotation(R(-P), 3, "X") @ Matrix.Rotation(R(sweep), 3, "Z") @ Matrix.Rotation(R(-up), 3, "Y")
         @ Matrix.Rotation(R(WING_AOA + pitch), 3, "X"))
    rest = Euler((R(-P0 + WING_AOA), R(-WING_UP), R(WING_SWEEP)))
    return tuple(math.degrees(a) for a in m.to_euler("XYZ", rest))


WING_REST = wing_local(P0, WING_UP, WING_SWEEP)
SPAN = 1.3


def feather(name, parent, length, width, thick, loc, rot, material, curve=0.12, steps=3):
    """Broad blade feather with a raised rachis and a blunt, cut tip (reads as layered plumage
    from above, not a comb of spikes). Tip at local +Z, curls toward local +Y."""
    import bmesh
    bm = bmesh.new()
    rows = []
    for i in range(steps + 1):
        t = i / steps
        w = width * (0.68 + 0.32 * math.sin(math.pi * min(1.0, t * 1.5))) * (1.0 - 0.55 * t * t) + 0.003
        z = t * length
        y = curve * t * t * length
        tz = z - (0.18 * width if i == steps else 0.0)   # slanted cut at the tip
        rows.append([bm.verts.new((-w, y, tz)), bm.verts.new((0, y - thick, z)),
                     bm.verts.new((w, y, z)), bm.verts.new((0, y + thick * 0.5, z))])
    for a, b in zip(rows[:-1], rows[1:]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = sb._new_mesh_obj(name, bm)
    return sb._finish(obj, parent, material, loc, rot, (1, 1, 1), 0.0, 0, False, name)


def lance_dir(off_x):
    """Unit vector along the lance (forward) in the CHEST frame for a lance offset pitch."""
    a = math.radians(LANCE_X + off_x)
    return (0.0, -math.cos(a), -math.sin(a))


def build():
    m = A.baked_mats()
    slit = sb.mat("Lancer_VisorLight", (1.0, 0.9, 0.6), roughness=0.3, emission=(1.0, 0.82, 0.45), strength=7.0)
    lance_ivory = sbmat.aged_ivory("Lancer_IvoryLance", (0.68, 0.64, 0.54), scale=1.5)
    banner = sbmat.linen("Lancer_ClothBanner", (0.64, 0.6, 0.51), weave=100.0, rough=0.9, stain=0.45,
                         stain_col=(0.44, 0.38, 0.28), grime_col=(0.13, 0.11, 0.08))
    banner_gold = sbmat.silk("Lancer_ClothBannerGold", (0.6, 0.42, 0.15), rough=0.7)
    cape_mat = sbmat.linen("Lancer_ClothCape", (0.6, 0.56, 0.48), weave=100.0, rough=0.92, stain=0.4,
                           stain_col=(0.42, 0.36, 0.27), grime_col=(0.12, 0.1, 0.08))
    rig = A.Rig()
    root = sb.root("DawnLancer")
    J = A.knight(rig, root, m, h=H, bulk=1.0, skirt=0.8)
    hips, chest, head = J["hips"], J["chest"], J["head"]
    tL, tR, sL, sR = J["thigh_L"], J["thigh_R"], J["shin_L"], J["shin_R"]
    aL, aR, fL, fR = J["arm_L"], J["arm_R"], J["fore_L"], J["fore_R"]
    bpy.data.objects.remove(bpy.data.objects["tabard_back"])   # replaced by a streaming chain
    # tri budget: drop the small details that vanish from the high camera, cheapen the rest
    for nm in ("toecap_L", "toecap_R", "cuff_L", "cuff_R", "pauldron2_L", "pauldron2_R", "sabaton_L", "sabaton_R",
               "couter_L", "couter_R"):
        bpy.data.objects.remove(bpy.data.objects[nm])
    for sd in ("L", "R"):
        A.ellipsoid(f"sabaton_{sd}", J[f"shin_{sd}"], (0.095 * H, 0.25 * H, 0.08 * H), loc=(0, -0.06 * H, -0.4 * H),
                    material=m["ivory"], seg=8, rings=5)
        A.ellipsoid(f"couter_{sd}", J[f"fore_{sd}"], (0.085 * H, 0.09 * H, 0.08 * H), material=m["gold"], seg=7,
                    rings=4)
    R = math.radians

    # ---------------------------------------------------------------- glide pose
    hips.location.z += HOVER
    hips.rotation_euler = (R(LEAN), 0, 0)
    chest.rotation_euler = (R(CHEST_LEAN), 0, 0)
    head.rotation_euler = (R(-(LEAN + CHEST_LEAN) + 8), 0, 0)
    tL.rotation_euler = (R(10), 0, R(-3))
    tR.rotation_euler = (R(22), 0, R(3))
    sL.rotation_euler = (R(30), 0, 0)
    sR.rotation_euler = (R(18), 0, 0)
    aR.rotation_euler = (R(18), R(-8), R(-6))     # lance arm: elbow back, forearm forward along the lance
    fR.rotation_euler = (R(-82), 0, 0)
    aL.rotation_euler = (R(58), R(18), 0)         # off arm swept back like a diver's
    fL.rotation_euler = (R(-12), 0, 0)

    # ---------------------------------------------------------------- crested great helm + sun crown
    A.lathe("helm", head, [(0.0, -0.035), (0.088, -0.03), (0.104, 0.05), (0.11, 0.13), (0.094, 0.2),
                           (0.055, 0.25), (0.0, 0.27)], segments=12, material=m["ivory"], scale=(1.0, 1.12, 1.0))
    A.ellipsoid("visor", head, (0.17, 0.1, 0.17), loc=(0, -0.075, 0.09), material=m["ivory"], seg=10, rings=6)
    sb.box("visor_slit", head, size=(0.15, 0.03, 0.016), loc=(0, -0.122, 0.11), material=slit, bevel=0.0)
    sb.box("visor_slit_v", head, size=(0.016, 0.03, 0.09), loc=(0, -0.124, 0.075), material=slit, bevel=0.0)
    A.ring("brow", head, 0.108, 0.014, loc=(0, 0.0, 0.135), material=m["gold"], seg=12, mseg=3).scale = (1, 1.1, 1)
    # tall swept gold crest along the midline (outline x -> +Y after the 90 deg turn)
    A.plate("crest", head, [(-0.1, 0.17), (-0.02, 0.29), (0.1, 0.36), (0.3, 0.38), (0.22, 0.31),
                            (0.12, 0.24), (0.06, 0.18)], 0.016, material=m["gold"], rot=(0, 0, 90))
    # sun-ray crown: gold rays radiating up and out from the brow band, longest at the back
    nr = 9
    for i in range(nr):
        az = math.radians(-150 + 300 * i / (nr - 1))    # 0 = back (+Y); skips the front
        ca, sa = math.cos(az), math.sin(az)
        long_ = i % 2 == 0
        tilt = 0.55 if long_ else 0.75
        d = (sa * tilt, ca * tilt, 1.0)
        ln = (0.3 if long_ else 0.17) * (0.75 + 0.25 * abs(ca))
        A.spike(f"crown_ray{i}", head, (sa * 0.1, ca * 0.11, 0.14), d, ln, 0.04 if long_ else 0.03, 0.012,
                material=m["gold"], up=(-sa, -ca, 0.2))
    halo = rig.add(A.halo("halo", head, (0, 0.17, 0.2), 0.24, m, rays=0, upright=True, seg=16, band=False,
                          minor=0.012))

    # ---------------------------------------------------------------- breastplate sun medallion
    A.ring("sun_medal", chest, 0.045, 0.012, loc=(0, -0.155, 0.22), rot=(90 - 6, 0, 0), material=m["gold"], seg=10,
           mseg=3)
    sb.sphere("sun_core", chest, radius=0.03, loc=(0, -0.158, 0.22), scale=(1, 0.5, 1), material=m["halo"],
              segments=8, rings=4)

    # ---------------------------------------------------------------- cape (3 links) and back tabard (2)
    cape = [rig.add(sb.empty("cape_0", chest, loc=(0, 0.14, 0.34), rot=(36, 0, 0)))]
    for i in range(1, 3):
        cape.append(rig.add(sb.empty(f"cape_{i}", cape[-1], loc=(0, 0, -0.24))))
    for i, cj in enumerate(cape):
        w0, w1 = 0.17 + 0.03 * i, 0.2 + 0.03 * i
        if i < 2:
            out = [(-w0, 0.01), (w0, 0.01), (w1, -0.25), (-w1, -0.25)]
        else:
            out = [(-w0, 0.01), (w0, 0.01), (w1, -0.2), (w1 * 0.5, -0.27), (0, -0.21), (-w1 * 0.5, -0.27), (-w1, -0.2)]
        A.plate(f"cape_m{i}", cj, out, 0.014, material=cape_mat)
    A.plate("cape_hem", cape[2], [(-0.26, -0.18), (0.26, -0.18), (0.26, -0.2), (0.13, -0.27), (0, -0.21),
                                  (-0.13, -0.27), (-0.26, -0.2)], 0.02, material=m["gold"])
    A.plate("cape_clasp", cape[0], [(-0.2, 0.03), (0.2, 0.03), (0.17, -0.04), (-0.17, -0.04)], 0.03,
            material=m["gold"])
    tab = [rig.add(sb.empty("tabard_0", hips, loc=(0, 0.16, 0.0), rot=(14, 0, 0)))]
    tab.append(rig.add(sb.empty("tabard_1", tab[0], loc=(0, 0, -0.22))))
    A.plate("tabard_m0", tab[0], [(-0.085, 0.06), (0.085, 0.06), (0.08, -0.23), (-0.08, -0.23)], 0.012,
            material=m["cloth"])
    A.plate("tabard_m1", tab[1], [(-0.08, 0.0), (0.08, 0.0), (0.07, -0.2), (0.0, -0.27), (-0.07, -0.2)], 0.012,
            material=m["cloth"])
    A.plate("tabard_trim", tab[1], [(-0.075, -0.17), (0.075, -0.17), (0.0, -0.26)], 0.018, material=m["gold"])

    # ---------------------------------------------------------------- wings: great, swept, layered
    def lancer_wing(sd, s):
        wr = rig.add(sb.empty(f"wing_{sd}", chest, loc=(s * 0.1, 0.14, 0.3),
                              rot=(WING_REST[0], s * WING_REST[1], s * WING_REST[2])))
        el = (s * SPAN * 0.4, 0.0, 0.05 * SPAN)
        wh = rig.add(sb.empty(f"wing_{sd}_hand", wr, loc=el))
        wrist = (s * SPAN * 0.3, 0.02, -0.01)
        wt = rig.add(sb.empty(f"wing_{sd}_tip", wh, loc=wrist))
        fing = (s * SPAN * 0.2, 0.05, -0.01)
        # armored wing bones: ivory upper arm with a gold leading edge, gold hand and finger
        A.seg(f"wing_{sd}_arm", wr, (0, 0, 0), el, 0.05, 0.034, material=m["ivory"], segments=7)
        A.plate(f"wing_{sd}_edge", wr, [(0.0, 0.0), (s * SPAN * 0.4, 0.06), (s * SPAN * 0.36, 0.02),
                                        (s * 0.05, -0.04)], 0.02, material=m["gold"], loc=(0, -0.035, 0.02),
                rot=(0, 0, 0))
        sb.sphere(f"wing_{sd}_knuckle", wh, radius=0.045, material=m["gold"], segments=7, rings=4)
        A.seg(f"wing_{sd}_fore", wh, (0, 0, 0), wrist, 0.034, 0.024, material=m["gold"], segments=6)
        A.seg(f"wing_{sd}_finger", wt, (0, 0, 0), fing, 0.024, 0.008, material=m["gold"], segments=5)
        A.spike(f"wing_{sd}_claw", wt, fing, (s, -0.25, 0.1), 0.12, 0.035, 0.014, material=m["gold"])

        def fe(name, par, base, length, width, ang, mat, curve=0.12, steps=3, z=0.0, thick=0.006):
            feather(name, par, length, width * 1.7, thick * 1.6, (base[0], base[1], base[2] + z),
                    (-90, 0, -s * ang), mat, curve=curve, steps=steps)

        # secondaries (root + hand): long, trailing straight back
        for i in range(5):
            t = (i + 0.4) / 5
            fe(f"wing_{sd}_sec{i}", wr, (el[0] * t, 0.0, el[2] * t - 0.01), SPAN * (0.46 + 0.1 * t), 0.075,
               -2 + 6 * t, m["feather"] if i % 2 else m["feather_tip"])
        for i in range(3):
            t = (i + 0.5) / 3
            fe(f"wing_{sd}_hsec{i}", wh, (wrist[0] * t, 0.0, -0.01), SPAN * (0.57 + 0.04 * t), 0.075, 6 + 6 * t,
               m["feather"] if i % 2 == 0 else m["feather_tip"])
        # primaries: longest, swept out toward the tip, whip with the tip joint
        for i in range(6):
            t = (i + 0.5) / 6
            fe(f"wing_{sd}_pri{i}", wt, (fing[0] * t, fing[1] * t, -0.01), SPAN * (0.6 + 0.18 * t), 0.068 * (1 - 0.2 * t),
               12 + 34 * t ** 1.1, m["feather"] if i % 2 == 0 else m["feather_tip"], curve=0.16)
        # coverts: a shorter overlapping row of ivory armor scales on top, gold marginals at the edge
        for i in range(4):
            t = (i + 0.5) / 4
            fe(f"wing_{sd}_cov{i}", wr, (el[0] * t, -0.02, el[2] * t), SPAN * 0.24, 0.085, 4 * t, m["ivory"],
               steps=2, z=0.022, thick=0.01, curve=0.08)
        for i in range(3):
            t = (i + 0.5) / 3
            fe(f"wing_{sd}_hcov{i}", wh, (wrist[0] * t, -0.02, 0.0), SPAN * 0.26, 0.08, 8 + 12 * t, m["ivory"],
               steps=2, z=0.02, thick=0.01, curve=0.08)
        return wr, wh, wt

    wL, wLh, wLt = lancer_wing("L", -1)
    wR, wRh, wRt = lancer_wing("R", 1)

    # ---------------------------------------------------------------- the lance (local -Y = forward)
    lance = rig.add(sb.empty("lance", chest, loc=(0.2, -0.04, 0.15), rot=(LANCE_X, 0, -3)))
    A.seg("lance_butt", lance, (0, 0.48, 0), (0, 0.1, 0), 0.026, 0.03, material=m["haft"], segments=7)
    sb.sphere("lance_pommel", lance, radius=0.045, loc=(0, 0.5, 0), material=m["gold"], segments=7, rings=4)
    A.seg("lance_grip", lance, (0, 0.12, 0), (0, -0.1, 0), 0.034, 0.034, material=m["leather"], segments=7)
    A.lathe("lance_vamplate", lance, [(0.03, 0.08), (0.06, 0.12), (0.15, 0.3), (0.13, 0.32), (0.05, 0.34)],
            segments=12, material=m["gold"], rot=(90, 0, 0))
    A.seg("lance_shaft", lance, (0, -0.32, 0), (0, -1.95, 0), 0.062, 0.024, material=lance_ivory, segments=9)
    for i, (y, r) in enumerate(((-0.7, 0.056), (-1.35, 0.04))):
        A.ring(f"lance_band{i}", lance, r, 0.013, loc=(0, y, 0), rot=(90, 0, 0), material=m["gold"], seg=8, mseg=3)
    # sun collar + leaf blade
    A.lathe("lance_collar", lance, [(0.02, 1.9), (0.06, 1.95), (0.035, 2.0)], segments=8, material=m["gold"],
            rot=(90, 0, 0))
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.26
        A.spike(f"lance_sunray{i}", lance, (math.cos(a) * 0.05, -1.95, math.sin(a) * 0.05),
                (math.cos(a), -0.6, math.sin(a)), 0.1, 0.03, 0.01, material=m["gold"], up=(0, -1, 0))
    A.lathe("lance_blade", lance, [(0.0, 1.98), (0.055, 2.06), (0.042, 2.24), (0.0, 2.48)], segments=4,
            material=m["steel"], rot=(90, 0, 0), scale=(1.0, 0.4, 1.0), smooth=False)
    tip = rig.add(sb.empty("lance_glow", lance, loc=(0, -2.15, 0)))
    A.ellipsoid("lance_core", tip, (0.05, 0.3, 0.05), material=m["light"], seg=6, rings=4)
    for i, d in enumerate(((1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1))):
        A.spike(f"lance_flare{i}", tip, (d[0] * 0.025, 0, d[2] * 0.025), d, 0.1, 0.025, 0.008, material=m["light"],
                up=(0, 1, 0))
    # pennant streaming back from under the collar (4 links along +Y)
    pen = [rig.add(sb.empty("pennant_0", lance, loc=(0, -1.86, -0.03), rot=(-4, -38, 0)))]
    for i in range(1, 4):
        pen.append(rig.add(sb.empty(f"pennant_{i}", pen[-1], loc=(0, 0.2, 0))))
    heights = (0.3, 0.26, 0.21, 0.16, 0.12)
    for i, pj in enumerate(pen):
        h0, h1 = heights[i], heights[i + 1]
        if i < 3:
            out = [(0.0, 0.0), (0.205, 0.0), (0.205, -h1), (0.0, -h0)]
        else:
            out = [(0.0, 0.0), (0.3, 0.02), (0.16, -h0 * 0.5), (0.3, -h0 - 0.02), (0.0, -h0)]
        A.plate(f"pennant_m{i}", pj, out, 0.01, material=banner, rot=(0, 0, 90))
        A.plate(f"pennant_stripe{i}", pj, [(0.0, -h0 * 0.62), (0.205 if i < 3 else 0.12, -h1 * 0.62 if i < 3 else -h0 * 0.6),
                                           (0.205 if i < 3 else 0.12, -h1 * 0.78 if i < 3 else -h0 * 0.75),
                                           (0.0, -h0 * 0.78)], 0.016, material=banner_gold, rot=(0, 0, 90))
    A.seg("pennant_bar", pen[0], (0, 0, 0.01), (0, 0, -0.31), 0.012, 0.012, material=m["gold"], segments=5)

    # ================================================================== animations
    ALL = N.joints(root)
    WRch = [wR, wRh, wRt]
    hand_R, hand_L = J["hand_R"], J["hand_L"]

    def secondary(c, wind=6.0, cape_f=1.7, pen_f=2.4, floor=None, gravity=4.0, flutter=1.0):
        for i, pj in enumerate(pen):
            N.noise(c, pj, rot=(4 * flutter, 0, 16 * flutter * (0.6 + 0.2 * i)), freq=1.8, seed=11 + i)
        for i, cj in enumerate(cape):
            N.noise(c, cj, rot=(6 * flutter, 3 * flutter, 2 * flutter), freq=1.2, seed=21 + i)
        w = (0, wind, 0) if wind else None
        N.follow_through(c, cape, freq=cape_f, damping=0.13, gravity=gravity, falloff=0.85, wind=w, floor=floor)
        N.follow_through(c, tab, freq=2.4, damping=0.16, gravity=gravity, falloff=0.85, wind=w, floor=floor)
        N.follow_through(c, pen, freq=pen_f, damping=0.1, gravity=gravity * 0.3, falloff=0.9, wind=w, floor=floor,
                         max_angle=60)

    def wings(c, f, up, sweep, hand=(0, 0, 0), tipr=(0, 0, 0), pitch=0.0, P=P0, ease="smooth"):
        """Keys both wings (mirrored). up / sweep / pitch are ABSOLUTE angles relative to a level
        frame while the chest is pitched P deg forward; hand/tip = offsets for the +X (R) wing."""
        loc = wing_local(P, up, sweep, pitch)
        off = tuple(a - b for a, b in zip(loc, WING_REST))
        c.pose(f, {wR: {"rot": off}, wRh: {"rot": hand}, wRt: {"rot": tipr}}, ease=ease, mirror=True)

    # ---------------------------------------------------------------- fly: hovering glide loop
    c = N.Clip("fly", 48, joints=ALL)
    N.wing_beat(c, WRch, cycles=1, amp=17, bias=-2, down=0.42, lag=0.1, flex=16, sweep=10, twist=6,
                body=hips, lift=0.035, pitch=2.0)
    N.noise(c, hips, rot=(1.5, 1.5, 3), loc=(0.01, 0.015, 0.0), freq=0.5, seed=1)
    N.noise(c, head, rot=(2, 3, 1.5), freq=0.5, seed=2)
    c.add(tL, lambda f: (5 * N.wave(c, f, offset=-0.25), 0, 0), "rot")
    c.add(tR, lambda f: (4 * N.wave(c, f, offset=-0.3), 0, 0), "rot")
    N.overlap(c, [tL, sL], delay=3, decay=0.9, gain=1.3)
    N.overlap(c, [tR, sR], delay=3, decay=0.9, gain=1.3)
    c.add(lance, lambda f: (1.5 * N.wave(c, f, offset=-0.15), 0, 0), "rot")
    c.add(aL, lambda f: (4 * N.wave(c, f, offset=-0.2), 0, 0), "rot")
    c.add(halo, lambda f: (0, 0, 10 * N.wave(c, f)), "rot")
    c.add(halo, lambda f: (0.04 * N.wave(c, f, cycles=2),) * 3, "scale")
    c.add(tip, lambda f: (0.18 * N.wave(c, f, cycles=3),) * 3, "scale")
    secondary(c, wind=7.0)
    c.bake()

    # ---------------------------------------------------------------- windup: rear back, couch the lance
    BACK = -40.0                                   # hips pitch offset (rears up)
    lw = 48.0 + 8.0                                # lance pitch offset: comes level and aims a touch low
    pull = tuple(-0.26 * v for v in lance_dir(lw))  # draw the lance back along its axis
    P_REAR, P_PUSH = P0 + BACK - 8, P0 + 1.1 * (BACK - 8)
    c = N.Clip("windup", 36, joints=ALL)
    rear = {hips: {"rot": (BACK, 0, 0), "loc": (0, 0.14, 0.12)}, chest: {"rot": (-8, 0, 0)},
            head: {"rot": (40, 0, 0)},
            tL: {"rot": (-34, 0, 0)}, tR: {"rot": (-22, 0, 0)}, sL: {"rot": (26, 0, 0)}, sR: {"rot": (34, 0, 0)},
            lance: {"rot": (lw, 0, 3), "loc": pull}, aR: {"rot": (22, 0, 0)}, fR: {"rot": (-6, 0, 0)},
            aL: {"rot": (-80, -10, 0)}, fL: {"rot": (-30, 0, 0)},
            tip: {"scale": (2.4, 2.4, 2.4)}, halo: {"scale": (1.15, 1.15, 1.15)}}
    c.pose(0, {j: {k: ((1, 1, 1) if k == "scale" else (0, 0, 0)) for k in d} for j, d in rear.items()},
           ease="sine_inout")
    wings(c, 0, WING_UP, WING_SWEEP, ease="sine_inout")
    # wings beat up once (gathering), then draw in tight, high and back
    wings(c, 7, 44, 20, hand=(0, -14, 0), tipr=(0, -10, 0), P=24, ease="sine_inout")
    c.pose(16, rear, ease="sine_inout")
    wings(c, 16, 50, 70, hand=(0, 18, 30), tipr=(0, 14, 26), P=P_REAR, ease="sine_inout")
    pushed = {j: {k: (tuple(1 + (x - 1) * 1.35 for x in v) if k == "scale" else tuple(x * 1.1 for x in v))
                  for k, v in d.items()} for j, d in rear.items()}
    pushed[tip] = {"scale": (3.6, 3.6, 3.6)}
    c.pose(34, pushed, ease="smooth")
    wings(c, 34, 56, 76, hand=(0, 22, 34), tipr=(0, 18, 30), P=P_PUSH)
    c.hold(34, 36)
    N.jitter(c, lance, rot=(1.2, 0.8, 1.2), freq=11, seed=3, start=18, end=36)
    N.jitter(c, chest, rot=(0.8, 0.6, 0.8), freq=9, seed=4, start=18, end=36)
    N.jitter(c, wRt, rot=(2, 2, 2), freq=10, seed=5, start=16, end=36)
    N.jitter(c, wLt, rot=(2, 2, 2), freq=10, seed=6, start=16, end=36)
    c.add(tip, lambda f: (0.35 * max(0.0, f - 16) / 20 * N.wave(c, f, cycles=7),) * 3, "scale")
    c.add(halo, lambda f: (0, 0, 40 * N.ease("quad_in", f / 36)), "rot")
    N.noise(c, hips, loc=(0, 0, 0.012), freq=1.0, seed=7)
    secondary(c, wind=4.0, flutter=0.8)
    c.bake()

    # ---------------------------------------------------------------- attack: the charge
    DASH = 36.0
    lv = -(DASH + 2 + 10.0)                          # lance pitch offset: exactly level in the world
    thrust = tuple(0.16 * v for v in lance_dir(lv))
    c = N.Clip("attack", 30, joints=ALL)
    c.pose(0, pushed, ease="expo_out")
    wings(c, 0, 56, 76, hand=(0, 22, 34), tipr=(0, 18, 30), P=P_PUSH, ease="expo_out")
    dash = {hips: {"rot": (DASH, 0, 0), "loc": (0, -0.16, -0.08)}, chest: {"rot": (2, 0, 0)},
            head: {"rot": (-DASH + 4, 0, 0)},
            tL: {"rot": (-6, 0, 2)}, tR: {"rot": (-16, 0, -2)}, sL: {"rot": (-22, 0, 0)}, sR: {"rot": (-8, 0, 0)},
            lance: {"rot": (lv, 0, 3), "loc": thrust}, aR: {"rot": (-4, 0, 0)}, fR: {"rot": (-4, 0, 0)},
            aL: {"rot": (-50, -4, 0)}, fL: {"rot": (10, 0, 0)},
            tip: {"scale": (2.5, 2.5, 2.5)}, halo: {"scale": (1.1, 1.1, 1.1)},
            cape[0]: {"rot": (-34, 0, 0)}, tab[0]: {"rot": (-10, 0, 0)}}
    over = {j: {k: (tuple(1 + (x - 1) * 1.12 for x in v) if k == "scale" else tuple(x * 1.12 for x in v))
                for k, v in d.items()} for j, d in dash.items()}
    c.pose(4, over, ease="sine_inout")              # explosive: overshoot on the launch
    wings(c, 4, -6, 84, hand=(0, -6, 20), tipr=(0, -4, 16), pitch=4, P=P0 + 1.12 * (DASH + 2), ease="sine_inout")
    c.pose(8, dash, ease="smooth")
    wings(c, 8, -2, 78, hand=(0, -4, 16), tipr=(0, -2, 12), pitch=2, P=P0 + DASH + 2)
    c.pose(23, dash, ease="sine_inout")
    wings(c, 23, -2, 78, hand=(0, -4, 16), tipr=(0, -2, 12), pitch=2, P=P0 + DASH + 2, ease="sine_inout")
    ease_back = {j: {k: (tuple(1 + (x - 1) * 0.3 for x in v) if k == "scale" else tuple(x * 0.3 for x in v))
                     for k, v in d.items()} for j, d in dash.items()}
    c.pose(30, ease_back)
    wings(c, 30, 16, 40, hand=(0, 6, 8), P=P0 + 0.3 * (DASH + 2))
    N.noise(c, hips, rot=(1.5, 1.0, 2.0), loc=(0, 0, 0.015), freq=5, seed=8, start=5, end=24, fade=3)
    N.jitter(c, wRt, rot=(3, 4, 2), freq=12, seed=9, start=4, end=25)
    N.jitter(c, wLt, rot=(3, 4, 2), freq=12, seed=10, start=4, end=25)
    N.jitter(c, lance, rot=(0.6, 0.4, 0.6), freq=10, seed=12, start=4, end=25)
    c.add(halo, lambda f: (0, 0, 60 * N.ease("sine_out", f / 30)), "rot")
    secondary(c, wind=26.0, cape_f=2.2, pen_f=3.0, gravity=2.0, flutter=1.6)
    c.events["impact"] = 4
    c.bake()

    # ---------------------------------------------------------------- hit
    c = N.Clip("hit", 18, joints=ALL)
    N.hit_react(c, {hips: {"rot": (-14, 0, 9), "loc": (0, 0.09, 0.04)}, chest: {"rot": (-9, 4, 7)},
                    head: {"rot": (-18, 0, -9)}, lance: {"rot": (-10, 0, 4)},
                    wR: {"rot": (0, -22, -12)}, wL: {"rot": (0, 18, 10)},
                    wRh: {"rot": (0, 16, 0)}, wLh: {"rot": (0, -12, 0)},
                    tL: {"rot": (-14, 0, 0)}, tR: {"rot": (-10, 0, 0)}, aL: {"rot": (-20, 0, 0)}},
                rise=2, settle=13, stagger=0.8)
    c.add(tip, lambda f: ((-0.5 * N._response(f, 1, 8, 0.5)),) * 3, "scale")
    secondary(c, wind=5.0)
    c.bake()

    # ---------------------------------------------------------------- death: falls out of the sky
    # struck and thrown back -> wings fail and flail -> drops (quad_in, gravity) and slams face
    # down -> bounce -> the wings crumple: one splays broken on the ground, the other folds over.
    c = N.Clip("death", 54, joints=ALL)
    IMP = 24
    PRONE = 90.0 - LEAN                              # hips offset that lays the body flat, face down
    drop = -(hips.location.z - 0.25)

    def wing_side(f, side, up, sweep, hand, tipr, P, pitch=0.0, ease="smooth"):
        off = tuple(a - b for a, b in zip(wing_local(P, up, sweep, pitch), WING_REST))
        if side == "R":
            c.key(wR, f, rot=off, ease=ease)
            c.key(wRh, f, rot=hand, ease=ease)
            c.key(wRt, f, rot=tipr, ease=ease)
        else:
            mv = lambda v: (v[0], -v[1], -v[2])  # noqa: E731
            c.key(wL, f, rot=mv(off), ease=ease)
            c.key(wLh, f, rot=mv(hand), ease=ease)
            c.key(wLt, f, rot=mv(tipr), ease=ease)

    c.key(hips, 0, rot=(0, 0, 0), loc=(0, 0, 0), ease="expo_out")
    c.key(hips, 4, rot=(-24, -6, 8), loc=(0, 0.12, 0.1), ease="sine_inout")         # struck: thrown back
    c.key(hips, 11, rot=(-6, -16, 14), loc=(0, 0.1, 0.02), ease="quad_in")           # wings fail
    c.key(hips, IMP, rot=(PRONE, -8, 18), loc=(0, -0.2, drop), ease="quad_out")      # slams face down
    c.key(hips, IMP + 3, rot=(PRONE - 7, -8, 18), loc=(0, -0.24, drop + 0.07), ease="quad_in")
    c.key(hips, IMP + 6, rot=(PRONE, -8, 19), loc=(0, -0.26, drop), ease="quad_out")
    c.key(hips, IMP + 8, rot=(PRONE - 2, -8, 19), loc=(0, -0.27, drop + 0.015), ease="quad_in")
    c.key(hips, IMP + 10, rot=(PRONE, -8, 19), loc=(0, -0.27, drop), ease="constant")
    limbs = ((head, (-28, 0, 10), (-6, 0, 42)), (chest, (-10, 4, 6), (0, 0, 4)),
             (tL, (-36, 0, 0), (-20, 0, -8)), (tR, (-24, 0, 0), (-30, 0, 10)),
             (sL, (24, 0, 0), (-12, 0, 0)), (sR, (36, 0, 0), (6, 0, 0)),
             (aL, (-70, -20, 0), (-54, 26, 0)), (fL, (-30, 0, 0), (-14, 0, 0)),
             (aR, (-24, 0, 0), (-22, 0, 0)), (fR, (6, 0, 0), (10, 0, 0)),
             (lance, (-24, 6, 10), (-(PRONE + CHEST_LEAN), 26, 0)))
    for j, r0, r1 in limbs:
        c.key(j, 0, rot=(0, 0, 0), ease="expo_out")
        c.key(j, 4, rot=r0, ease="sine_inout")
        c.key(j, IMP - 2, rot=tuple(a * 0.25 + b * 0.75 for a, b in zip(r0, r1)), ease="back_out:2.0")
        c.key(j, IMP + 6, rot=r1, ease="constant")
    PD = P0 + PRONE
    # R wing: jerks up, flails, slams down and splays broken across the ground
    wing_side(0, "R", WING_UP, WING_SWEEP, (0, 0, 0), (0, 0, 0), P0, ease="expo_out")
    wing_side(4, "R", 62, 4, (0, -24, -6), (0, -18, 0), 16, ease="sine_inout")
    wing_side(11, "R", -10, 30, (0, 30, 20), (0, 26, 16), 34, ease="sine_inout")
    wing_side(17, "R", 50, 46, (0, -30, 8), (0, -16, 6), 60, ease="quad_in")
    wing_side(IMP, "R", -8, 40, (0, 8, 30), (0, 2, 26), PD, ease="back_out:1.6")
    wing_side(IMP + 12, "R", -5, 58, (0, -6, 58), (0, -10, 64), PD, ease="constant")
    # L wing: the other way round, and it ends folded up over the back, crumpled
    wing_side(0, "L", WING_UP, WING_SWEEP, (0, 0, 0), (0, 0, 0), P0, ease="expo_out")
    wing_side(4, "L", 56, 10, (0, -20, 0), (0, -14, 0), 16, ease="sine_inout")
    wing_side(11, "L", 40, 46, (0, -34, 10), (0, -24, 8), 34, ease="sine_inout")
    wing_side(17, "L", -16, 20, (0, 34, 14), (0, 24, 10), 60, ease="quad_in")
    wing_side(IMP, "L", 30, 70, (0, -20, 50), (0, -10, 40), PD, ease="back_out:1.8")
    wing_side(IMP + 12, "L", 38, 92, (0, -46, 84), (0, -30, 70), PD, ease="constant")
    c.key(tip, 0, scale=(1, 1, 1), ease="expo_out")
    c.key(tip, 3, scale=(2.6, 2.6, 2.6), ease="quad_in")
    c.key(tip, 12, scale=(0.01, 0.01, 0.01), ease="constant")
    c.key(halo, 0, rot=(0, 0, 0), scale=(1, 1, 1), ease="sine_out")
    c.key(halo, 6, rot=(0, 0, 50), scale=(1.25, 1.25, 1.25), ease="quad_in")
    c.key(halo, 20, rot=(0, 0, 160), scale=(0.01, 0.01, 0.01), ease="constant")
    secondary(c, wind=2.0, gravity=9.0, floor=0.03, flutter=0.4)
    c.events["impact"] = IMP
    c.bake()

    A.finish(root, "dawn_lancer")
    if os.environ.get("SB_TRI_DETAIL"):
        dg = bpy.context.evaluated_depsgraph_get()
        rows = []
        for o in bpy.context.scene.objects:
            if o.type == "MESH":
                me = o.evaluated_get(dg).to_mesh()
                me.calc_loop_triangles()
                rows.append((len(me.loop_triangles), o.name))
                o.evaluated_get(dg).to_mesh_clear()
        for t, nme in sorted(rows, reverse=True):
            print(f"  TRI {t:5d} {nme}")
        print("MESHES", len(rows))
    return root
