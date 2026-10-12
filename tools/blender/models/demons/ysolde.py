"""Ysolde, the Pale Reaper: a gaunt wraith that never touches the ground. A deep peaked hood over a
carved, cracked bone mask with soul-fire eyes, long ridged horns swept back through the hood, a pale
tattered shroud over the shoulders, an open robe showing a bone ribcage around a glowing soul,
layered ragged robe strips that float and trail (each strip is a joint chain with physics
follow-through), long skeletal fingers, a bone soul lantern and talismans at the girdle and a few
soul wisps circling the hem.

Animations (sbanim): idle (hover bob, robe undulating), walk (forward-leaning glide, robe streaming
back), attack (wide reaping sweep with a soul-light arc), hit, death (convulse, unravel, sink into
a heap of rags), cheer (rises, arms spread, head cocks slowly at a wrong angle)."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import sbanim as A  # noqa: E402
import _demon_kit as K  # noqa: E402
from _demon_kit import SIDES, sname  # noqa: E402
import sbmat  # noqa: E402

CATEGORY = "demons"
# Procedural sbmat surfaces (porous bone, aged ivory, robe/shroud weave, chain iron...) baked into
# one atlas (tools/blender/bake.py); the soul / crack / arc glows stay flat emissive materials.
BAKE = {"size": 1024, "samples": 16}

HIP_H = 1.2


# ============================================================================ local helpers

def strip_chain(name, parent, loc, yaw, widths, lens, material, flare=10.0, curl=4.0, rag=0.6, seed=0,
                cup=0.02, thick=0.01, segs=(3, 2), point=0.0, overlap=0.035):
    """A hanging cloth strip made of len(lens) joints (each the parent of the next), one panel each.
    Rest pose: tilted `flare` deg outward (local -Y after the yaw), each next link `curl` more."""
    js = []
    p = parent
    n = len(lens)
    for i in range(n):
        j = sb.empty(f"{name}_{i}", p, loc=loc if i == 0 else (0, 0, -lens[i - 1]),
                     rot=(-flare, 0, yaw) if i == 0 else (-curl, 0, 0))
        last = i == n - 1
        K.panel(f"{name}_{i}_m", j, widths[i], widths[i + 1], lens[i] + (0.0 if last else overlap), material,
                segs=(segs[0], segs[1] + (1 if last else 0)), cup=cup, rag=rag if last else 0.0,
                seed=seed + i * 3, thick=thick, point=point if last else 0.0, flare=0.0)
        js.append(j)
        p = j
    return js


def bone_finger(prefix, parent, base, dirs, lens, r0, mat_bone, mat_claw):
    """Skeletal finger: phalanges along successive directions, knuckle bulges, a hooked bone tip."""
    from mathutils import Vector
    pts = [Vector(base)]
    for d, L in zip(dirs, lens):
        dv = Vector(d).normalized()
        pts.append(pts[-1] + dv * L)
    path = []
    radii = []
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        r = r0 * (0.86 ** i)
        path += [a, a.lerp(b, 0.5)]
        radii += [r * 1.25, r * 0.72]
    path.append(pts[-1])
    radii.append(r0 * (0.86 ** (len(pts) - 1)) * 1.15)
    K.loft(prefix, parent, path, radii, mat_bone, segs=5, cap_round=0.8)
    tipd = (pts[-1] - pts[-2]).normalized()
    K.horn(prefix + "_tip", parent, [pts[-1], pts[-1] + tipd * 0.022 + Vector((0, -0.006, 0)),
                                      pts[-1] + tipd * 0.04 + Vector((0, -0.016, 0))],
           radii[-1] * 0.8, 0.0012, mat_claw, segs=5, n=2)


def build():
    # ------------------------------------------------------------------ materials
    L = K.lin
    bone = sbmat.bone("Ysolde_Bone", L((0.74, 0.7, 0.62)), scale=1.2)
    bone_old = sbmat.aged_ivory("Ysolde_BoneIvory", L((0.52, 0.48, 0.41)), scale=1.2)
    horn = sbmat.horn("Ysolde_HornBone", L((0.16, 0.145, 0.14)), rough=0.42, rings=26.0)
    robe = sbmat.linen("Ysolde_RobeCloth", L((0.11, 0.1, 0.11)), weave=75.0, rough=0.9, stain=0.4,
                       stain_col=L((0.2, 0.19, 0.18)), grime_col=L((0.02, 0.02, 0.025)))
    robe_in = sbmat.linen("Ysolde_InnerRobeCloth", L((0.2, 0.19, 0.2)), weave=75.0, rough=0.93, stain=0.4,
                          stain_col=L((0.13, 0.12, 0.12)), grime_col=L((0.03, 0.03, 0.035)))
    shroud = sbmat.linen("Ysolde_ShroudLinen", L((0.5, 0.48, 0.44)), weave=90.0, rough=0.93, stain=0.7,
                         stain_col=L((0.33, 0.29, 0.24)))
    hood = sbmat.linen("Ysolde_HoodCloth", L((0.095, 0.09, 0.1)), weave=75.0, rough=0.9, stain=0.3,
                       stain_col=L((0.18, 0.17, 0.17)), grime_col=L((0.015, 0.015, 0.02)))
    cord = sbmat.linen("Ysolde_Cord", L((0.25, 0.21, 0.17)), weave=120.0, rough=0.9, stain=0.3)
    iron = sbmat.worn_steel("Ysolde_IronChain", L((0.22, 0.22, 0.23)), roughness=0.5, scale=3.0, rust=0.25,
                            edge_k=2.2)
    void = K.mat("Ysolde_Void", (0.008, 0.008, 0.012), 1.0)
    soul = K.mat("Ysolde_SoulGlow", (0.5, 0.7, 0.8), 0.4, 0.0, (0.62, 0.86, 1.0), 14.0)
    soul_soft = K.mat("Ysolde_SoulCoreGlow", (0.3, 0.45, 0.55), 0.5, 0.0, (0.5, 0.78, 1.0), 5.0)
    crackm = K.mat("Ysolde_MaskCrackGlow", (0.5, 0.7, 0.8), 0.4, 0.0, (0.55, 0.85, 1.0), 9.0)
    arcm = K.mat("Ysolde_ReapArcGlow", (0.6, 0.85, 1.0), 0.4, 0.0, (0.6, 0.88, 1.0), 10.0)

    R = K.humanoid("Ysolde", hip_h=HIP_H, legs=False, spine=0.24, chest=0.34, neck=0.1, shoulder_w=0.19,
                   shoulder_z=0.29, upper=0.33, fore=0.33, arm_out=11, spine_rot=6, head_rot=-6)
    rng = random.Random(9)
    H, SP, C, Hd = R.hips, R.spine, R.chest, R.head
    chains = {"robe": [], "inner": [], "cloak": [], "mantle": [], "sleeve": [], "charm": []}

    # ================================================================== floating robe
    # girdle of vertebrae + dark inner core that tapers into a soul-lit void (seen through the gaps)
    K.loft("robe_core", H, [(0, 0, 0.1), (0, 0, -0.05), (0, 0.01, -0.3), (0, 0.02, -0.52)],
           [(0.14, 0.11), (0.155, 0.12), (0.13, 0.11), (0.06, 0.05)], robe_in, segs=12)
    sb.sphere("robe_soul", H, 0.06, loc=(0, 0.02, -0.5), scale=(1, 1, 1.5), material=soul_soft, segments=8, rings=5)
    for k in range(12):
        a = math.radians(k * 30)
        sb.sphere(f"girdle_bone{k}", H, 0.027, loc=(math.sin(a) * 0.165, -math.cos(a) * 0.13, 0.05),
                  scale=(1.0, 0.75, 1.35), rot=(0, 0, k * 30), material=bone_old if k % 2 else bone,
                  segments=7, rings=4)
    K.loft("girdle_cord", H, [(math.sin(math.radians(a)) * 0.158, -math.cos(math.radians(a)) * 0.123, 0.05)
                              for a in range(0, 361, 30)], [0.01] * 13, cord, segs=4, caps=(False, False))
    # outer robe: 12 long ragged strips, longer at the back (a train), each a 3-link chain
    for k in range(12):
        if k == 0:          # open front: the pale shroud and the soul-lit core show through
            continue
        a = k * 30 + rng.uniform(-5, 5)
        ar = math.radians(a)
        back = 0.5 - 0.5 * math.cos(ar)          # 0 front .. 1 back
        L = 0.72 + 0.26 * back + rng.uniform(-0.05, 0.05)
        w0 = 0.12
        js = strip_chain(f"robe{k}", H, (math.sin(ar) * 0.15, -math.cos(ar) * 0.118, 0.07), a,
                         [w0, w0 * 1.4, w0 * 1.9, w0 * 2.1], [L * 0.32, L * 0.33, L * 0.35], robe,
                         flare=17 + 5 * back, curl=5, rag=0.7, seed=5 + k * 11, cup=0.025, thick=0.011,
                         point=0.25)
        chains["robe"].append((js, a))
    # inner, lighter under-layer (fills the gaps between the outer strips, shorter)
    for k in range(9):
        a = k * 40 + (rng.uniform(-6, 6) if k else 0.0)
        ar = math.radians(a)
        L = 0.7 + 0.12 * (0.5 - 0.5 * math.cos(ar)) + rng.uniform(-0.06, 0.08)
        js = strip_chain(f"veil{k}", H, (math.sin(ar) * 0.13, -math.cos(ar) * 0.1, 0.0), a,
                         [0.12, 0.16, 0.2, 0.18], [L * 0.33, L * 0.33, L * 0.34], shroud,
                         flare=13, curl=4, rag=0.65, seed=70 + k * 5, cup=0.03, thick=0.009, point=0.15)
        chains["inner"].append((js, a))

    # ================================================================== torso: open robe over a ribcage
    K.loft("waist", SP, [(0, 0.01, -0.06), (0, 0.015, 0.1), (0, 0.01, 0.25)],
           [(0.105, 0.08), (0.085, 0.07), (0.12, 0.09)], robe, segs=10)
    for k in range(5):     # spine knuckles at the back of the waist
        sb.sphere(f"lumbar{k}", SP, 0.02, loc=(0, 0.08 + 0.003 * k, -0.02 + 0.055 * k), scale=(1.4, 0.8, 0.9),
                  material=bone_old, segments=6, rings=4)
    # dark cavity + the caged soul
    K.loft("cavity", C, [(0, 0.02, -0.04), (0, 0.0, 0.12), (0, 0.01, 0.26)], [(0.1, 0.07), (0.12, 0.08), (0.09, 0.06)],
           void, segs=10)
    sb.sphere("soul_heart", C, 0.045, loc=(0, -0.04, 0.13), scale=(1, 0.8, 1.2), material=soul, segments=8, rings=5)
    # robe torso: back and sides, open at the front (lon 50..310)
    K.shell("torso_robe", C, (0.16, 0.12, 0.24), lat=(-60, 75), lon=(48, 312), segs=(14, 5), thick=0.012,
            material=robe, loc=(0, 0.015, 0.12), flare=0.1)
    for k in range(7):     # thoracic spine bumps visible above the robe
        sb.sphere(f"thor{k}", C, 0.018, loc=(0, 0.125 - 0.004 * k, 0.33 - 0.05 * k), scale=(1.3, 0.8, 0.9),
                  material=bone_old, segments=6, rings=4)
    K.loft("sternum", C, [(0, -0.115, 0.27), (0, -0.125, 0.15), (0, -0.11, 0.04)], [0.014, 0.017, 0.01], bone, segs=6)
    for s in SIDES:
        for k in range(5):
            z = 0.27 - k * 0.055
            w = 0.135 - 0.006 * k
            pts = [(s * 0.012, -0.118, z), (s * w * 0.55, -0.112, z - 0.012), (s * w * 0.95, -0.05, z - 0.04),
                   (s * w, 0.04, z - 0.03), (s * 0.04, 0.1, z + 0.01)]
            K.loft(f"rib_{sname(s)}{k}", C, K.catmull(pts, 2), [0.007, 0.009, 0.01, 0.01, 0.0095, 0.009, 0.009, 0.008, 0.007],
                   bone, segs=5)
        K.loft(f"clavicle_{sname(s)}", C, [(s * 0.02, -0.09, 0.32), (s * 0.1, -0.06, 0.33), (s * 0.17, -0.01, 0.31)],
               [0.012, 0.013, 0.012], bone_old, segs=5)
    # pale shroud mantle over the shoulders: 10 tattered 2-link strips
    for k in range(10):
        a = k * 36 + 8
        ar = math.radians(a)
        back = 0.5 - 0.5 * math.cos(ar)
        if abs(((a + 180) % 360) - 180) < 30:      # keep the chest open
            continue
        L = 0.24 + 0.12 * back + rng.uniform(0, 0.06)
        js = strip_chain(f"mantle{k}", C, (math.sin(ar) * 0.13, -math.cos(ar) * 0.1, 0.4), a,
                         [0.13, 0.16, 0.15], [L * 0.45, L * 0.55], shroud, flare=48 - 18 * back, curl=26 - 6 * back,
                         rag=0.7, seed=40 + k * 7, cup=0.03, thick=0.009, segs=(3, 2), point=0.2, overlap=0.03)
        chains["mantle"].append((js, a))
    # long trailing cloak tails off the back of the shoulders (4 links each)
    for k, x in enumerate((-0.11, 0.0, 0.11)):
        Lc = (1.12, 1.28, 1.08)[k]
        js = strip_chain(f"cloak{k}", C, (x, 0.12, 0.32), x * 60, [0.17, 0.2, 0.22, 0.22, 0.18],
                         [Lc * 0.22, Lc * 0.25, Lc * 0.26, Lc * 0.27], robe, flare=-8, curl=-2, rag=0.75,
                         seed=31 + k * 13, cup=-0.03, thick=0.012, segs=(4, 2), point=0.3)
        # flip so the panel faces backwards (+Y): yaw 180 on the root link
        js[0].rotation_euler[2] = math.radians(180 + x * 60)
        js[0].rotation_euler[0] = math.radians(-14)
        chains["cloak"].append((js, 180.0))

    # ================================================================== arms: bone pauldrons, ragged sleeves, skeletal hands
    for s in SIDES:
        Ar, Fo, Ha = R.arm[s], R.fore[s], R.hand[s]
        n = sname(s)
        K.loft(f"upper_{n}", Ar, [(0, 0, 0.04), (0, 0, -0.17), (0, 0, -0.34)], [0.05, 0.042, 0.045], robe, segs=8)
        for k in range(3):   # layered bone lames, each smaller
            K.shell(f"paul{k}_{n}", Ar, (0.11 - k * 0.012, 0.115 - k * 0.012, 0.085), lat=(0, 90), lon=(-180, 180),
                    segs=(10, 3), thick=0.014, material=bone if k == 0 else bone_old,
                    loc=(s * (0.02 + k * 0.012), 0, 0.03 - k * 0.055), rot=(0, -s * (22 + k * 10), 0), flare=0.12)
        for k in range(3):
            K.horn(f"paul_spine_{n}{k}", Ar, [(s * 0.05, -0.05 + k * 0.05, 0.1), (s * 0.1, -0.06 + k * 0.06, 0.18),
                                               (s * 0.13, -0.05 + k * 0.08, 0.26)],
                   0.014, 0.0015, bone_old, segs=5, n=2)
        # forearm: radius + ulna exposed below the sleeve
        K.loft(f"radius_{n}", Fo, [(0.012, -0.008, 0.0), (0.016, -0.012, -0.17), (0.008, -0.01, -0.33)],
               [0.016, 0.011, 0.014], bone, segs=5)
        K.loft(f"ulna_{n}", Fo, [(-0.012, 0.01, 0.0), (-0.014, 0.012, -0.17), (-0.006, 0.008, -0.33)],
               [0.013, 0.009, 0.012], bone_old, segs=5)
        K.loft(f"sleevecuff_{n}", Fo, [(0, 0, 0.03), (0, 0, -0.08)], [0.055, 0.07], robe, segs=8)
        for k in range(5):   # bell sleeve: 2-link ragged strips around the forearm
            a = k * 72 + 20
            ar = math.radians(a)
            back = 0.5 - 0.5 * math.cos(ar)
            L = 0.24 + 0.14 * back + rng.uniform(0, 0.05)
            js = strip_chain(f"sleeve{k}_{n}", Fo, (math.sin(ar) * 0.06, -math.cos(ar) * 0.06, -0.03), a,
                             [0.08, 0.1, 0.09], [L * 0.45, L * 0.55], robe, flare=14, curl=4, rag=0.7,
                             seed=60 + k * 5 + (30 if s > 0 else 0), thick=0.008, segs=(2, 2), point=0.2)
            chains["sleeve"].append((js, a))
        # skeletal hand: wrist + metacarpals on the hand joint, phalanges on a "fingers" joint (curl)
        sb.sphere(f"wrist_{n}", Ha, 0.02, loc=(0, -0.004, -0.008), scale=(1.3, 0.9, 1), material=bone_old,
                  segments=7, rings=4)
        Fi = sb.empty(f"fingers_{n}", Ha, loc=(0, -0.01, -0.085))
        R.extra.append(Fi)
        R.fingers = getattr(R, "fingers", {})
        R.fingers[s] = Fi
        for i in range(4):
            x = (i - 1.5) * 0.017
            K.loft(f"meta{i}_{n}", Ha, [(x * 0.4, -0.004, -0.01), (x, -0.01, -0.085)], [0.006, 0.0075], bone, segs=5)
            spread = (i - 1.5) * 0.12
            L0 = (0.05, 0.058, 0.055, 0.045)[i]
            bone_finger(f"finger{i}_{n}", Fi, (x, 0, 0),
                        [(spread, -0.25, -1), (spread * 0.8, -0.55, -1), (spread * 0.5, -0.9, -0.8)],
                        [L0, L0 * 0.8, L0 * 0.62], 0.0068, bone, bone_old)
        bone_finger(f"thumb_{n}", Ha, (-s * 0.026, -0.016, -0.03),
                    [(-s * 0.4, -0.6, -1), (-s * 0.2, -0.9, -0.7)], [0.04, 0.034], 0.0065, bone, bone_old)

    # ================================================================== head: deep hood, carved bone mask, swept horns
    K.loft("neck_m", R.neck, [(0, 0.01, -0.05), (0, 0, 0.1)], [0.03, 0.026], bone_old, segs=6)
    sb.sphere("hood_void", Hd, 0.105, loc=(0, -0.0, 0.12), scale=(1, 1.05, 1.25), material=void, segments=12, rings=8)
    K.shell("hood", Hd, (0.15, 0.165, 0.21), lat=(-55, 90), lon=(42, 318), segs=(20, 8), thick=0.015, material=hood,
            loc=(0, 0.02, 0.12), flare=0.22)
    K.horn("hood_peak", Hd, [(0, 0.1, 0.27), (0, 0.2, 0.27), (0, 0.3, 0.2), (0, 0.36, 0.1)], 0.07, 0.006, hood,
           segs=8, n=3)
    K.shell("hood_drape", Hd, (0.2, 0.18, 0.17), lat=(-62, 12), lon=(-180, 180), segs=(18, 3), thick=0.01,
            material=hood, loc=(0, 0.035, -0.02), flare=0.3)
    # bone mask: an ellipsoid plate with brow, cheekbones, a long chin, sockets and glowing cracks
    MC, MR = (0, -0.035, 0.12), (0.072, 0.1, 0.125)
    K.shell("mask", Hd, MR, lat=(-75, 62), lon=(-80, 80), segs=(12, 8), thick=0.012, material=bone, loc=MC, sharp=60)
    K.horn("mask_chin", Hd, [K.on_ell(MC, MR, -60, 0, 0.98), (0, -0.115, -0.04), (0, -0.095, -0.1)], 0.026, 0.004,
           bone, segs=6, n=2)
    K.loft("mask_brow", Hd, K.catmull([K.on_ell(MC, MR, 30, -62, 1.04), K.on_ell(MC, MR, 36, -25, 1.08),
                                       K.on_ell(MC, MR, 30, 0, 1.06), K.on_ell(MC, MR, 36, 25, 1.08),
                                       K.on_ell(MC, MR, 30, 62, 1.04)], 2),
           [0.008, 0.012, 0.014, 0.012, 0.011, 0.012, 0.014, 0.012, 0.008], bone_old, segs=5)
    K.loft("mask_nose", Hd, [K.on_ell(MC, MR, 8, 0, 1.0), K.on_ell(MC, MR, -10, 0, 1.03)], [0.004, 0.012], void,
           segs=3, ref=(0, 0, 1))
    for s in SIDES:
        n = sname(s)
        K.loft(f"mask_cheek_{n}", Hd, K.catmull([K.on_ell(MC, MR, -2, s * 60, 1.02), K.on_ell(MC, MR, -10, s * 36, 1.05),
                                                 K.on_ell(MC, MR, -30, s * 16, 1.02)], 2),
               [0.008, 0.011, 0.011, 0.009, 0.006], bone_old, segs=5)
        sb.sphere(f"socket_{n}", Hd, 0.025, loc=K.on_ell(MC, MR, 16, s * 26, 0.97), scale=(1.25, 0.55, 0.85),
                  rot=(0, s * 14, -s * 18), material=void, segments=8, rings=5)
        sb.sphere(f"eye_{n}", Hd, 0.012, loc=K.on_ell(MC, MR, 15, s * 25, 1.06), scale=(1.3, 0.5, 0.75),
                  rot=(0, s * 14, -s * 18), material=soul, segments=8, rings=4)
        # tear-crack running from the socket down the cheek + a branch into the brow
        K.crack(f"mask_crack_{n}", Hd, MC, MR, [(8, s * 27), (-6, s * 31), (-24, s * 27), (-42, s * 20)], crackm,
                r=0.004, off=1.012)
        # teeth slits
        for t in range(3):
            x = s * (0.006 + t * 0.013)
            K.loft(f"mask_tooth{t}_{n}", Hd, [K.on_ell(MC, MR, -36, s * (4 + t * 10), 1.01),
                                              K.on_ell(MC, MR, -52, s * (4 + t * 9), 1.0)], [0.0035, 0.002], void,
                   segs=3, ref=(0, 0, 1))
        # horns: long, ridged, swept back from the temples through the hood, tips hooking up. Spread
        # wider than anatomy needs (characters-polish): from the high game camera they are her
        # silhouette, and soul-fire burns at the tips.
        hp = [(s * 0.07, -0.03, 0.21), (s * 0.17, 0.0, 0.29), (s * 0.27, 0.09, 0.36), (s * 0.33, 0.23, 0.39),
              (s * 0.35, 0.38, 0.36), (s * 0.33, 0.5, 0.28), (s * 0.3, 0.57, 0.34)]
        K.horn(f"horn_{n}", Hd, hp, 0.05, 0.003, horn, segs=8, n=4, ridges=0.16)
        sb.sphere(f"horn_soulfire_{n}", Hd, 0.018, loc=hp[-1], scale=(1, 1, 1.7), material=soul, segments=8, rings=5)
    K.crack("mask_crack_brow", Hd, MC, MR, [(52, -6), (40, 4), (30, 2), (24, 8)], crackm, r=0.0035, off=1.012)

    # ================================================================== girdle charms: soul lantern + bone talismans
    # lantern on the left hip: chain link -> lantern
    lj0 = sb.empty("lantern_0", H, loc=(0.16, -0.08, 0.04), rot=(0, 0, 20))
    K.chain("lantern_chain_a", lj0, [(0, 0, 0), (0, 0, -0.12)], iron, link=0.04, wire=0.005)
    lj1 = sb.empty("lantern_1", lj0, loc=(0, 0, -0.12))
    K.chain("lantern_chain_b", lj1, [(0, 0, 0), (0, 0, -0.1)], iron, link=0.04, wire=0.005)
    lj2 = sb.empty("lantern_2", lj1, loc=(0, 0, -0.1))
    sb.cylinder("lantern_cap", lj2, r1=0.045, r2=0.012, depth=0.035, loc=(0, 0, -0.04), material=bone_old,
                segments=8, bevel=0.0)
    sb.cylinder("lantern_base", lj2, r1=0.02, r2=0.048, depth=0.03, loc=(0, 0, -0.17), material=bone_old,
                segments=8, bevel=0.0)
    for k in range(5):
        a = k * 72
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        K.loft(f"lantern_rib{k}", lj2, [(ca * 0.04, sa * 0.04, -0.04), (ca * 0.052, sa * 0.052, -0.1),
                                        (ca * 0.044, sa * 0.044, -0.145)], [0.005, 0.006, 0.005], bone, segs=4)
    sb.sphere("lantern_soul", lj2, 0.03, loc=(0, 0, -0.095), scale=(1, 1, 1.3), material=soul, segments=8, rings=5)
    K.horn("lantern_drip", lj2, [(0, 0, -0.17), (0, 0, -0.21), (0.005, 0, -0.24)], 0.008, 0.001, bone_old, segs=4, n=2)
    chains["charm"].append([lj0, lj1, lj2])
    # talismans on the right / back: cord -> bone charm
    for k, (a, kind) in enumerate(((-55, "skull"), (-100, "verts"), (150, "fingers"), (-150, "skull"))):
        ar = math.radians(a)
        t0 = sb.empty(f"talis{k}_0", H, loc=(math.sin(ar) * 0.17, -math.cos(ar) * 0.135, 0.03), rot=(0, 0, a))
        Lk = 0.09 + 0.03 * (k % 2)
        K.loft(f"talis_cord{k}", t0, [(0, 0, 0), (0, 0, -Lk)], [0.004, 0.004], cord, segs=4)
        t1 = sb.empty(f"talis{k}_1", t0, loc=(0, 0, -Lk))
        if kind == "skull":
            sb.sphere(f"talis_skull{k}", t1, 0.03, loc=(0, 0, -0.03), scale=(0.9, 1.0, 1.0), material=bone, segments=8, rings=5)
            sb.sphere(f"talis_jaw{k}", t1, 0.02, loc=(0, -0.008, -0.055), scale=(0.9, 0.9, 0.7), material=bone_old,
                      segments=6, rings=4)
            for e in SIDES:
                sb.sphere(f"talis_eye{k}{sname(e)}", t1, 0.008, loc=(e * 0.012, -0.024, -0.03), material=void,
                          segments=5, rings=3)
        elif kind == "verts":
            for v in range(4):
                sb.sphere(f"talis_vert{k}{v}", t1, 0.017 - v * 0.002, loc=(0, 0, -0.015 - v * 0.03),
                          scale=(1.3, 1.0, 0.7), material=bone if v % 2 else bone_old, segments=7, rings=4)
        else:
            for v in range(3):
                K.horn(f"talis_bone{k}{v}", t1, [(0, 0, 0), ((v - 1) * 0.01, -0.004, -0.05), ((v - 1) * 0.02, -0.012, -0.09)],
                       0.006, 0.0015, bone, segs=4, n=2)
        chains["charm"].append([t0, t1])

    # ================================================================== soul wisps + reap arc (vfx joints)
    wisps = []
    for k in range(3):
        w = sb.empty(f"wisp{k}", R.body, loc=(0, 0, 0.75))
        sb.sphere(f"wisp{k}_m", w, 0.03, scale=(1, 1, 1.6), material=soul, segments=8, rings=5)
        K.horn(f"wisp{k}_tail", w, [(0, 0, 0.02), (0, 0.02, 0.08), (0.01, 0.0, 0.15)], 0.022, 0.002, soul_soft, segs=5, n=2)
        R.extra.append(w)
        wisps.append(w)
    arc = sb.empty("reap_arc", R.body, loc=(0, -0.05, 1.5), rot=(0, -14, 0))
    pts, rad = [], []
    N = 16
    for i in range(N + 1):
        u = i / (N)
        ang = math.radians(-175 + 165 * u)          # sweeps from the right side, across the front, to the left
        r = 1.0 + 0.08 * math.sin(math.pi * u)
        pts.append((math.cos(ang) * r, math.sin(ang) * r, -0.12 * u + 0.06))
        rad.append(0.004 + 0.036 * math.sin(math.pi * u ** 0.7))
    # ang -160 -> x=-0.94 (right side), -90 -> front (-Y), -20 -> left: matches a right-to-left reap
    sb.ptube("reap_arc_m", arc, pts, rad, sides=5, material=arcm)
    sb.ptube("reap_arc_m2", arc, [(x * 0.86, y * 0.86, z - 0.05) for x, y, z in pts],
             [r * 0.55 for r in rad], sides=4, material=soul_soft)
    R.extra.append(arc)

    animate(R, chains, wisps, arc)
    K.finalize(R.root)
    return R.root


# ============================================================================ animation

def animate(R, chains, wisps, arc):
    ALL = [j for j in A.joints(R.root) if j.name not in ("look",) and j is not R.root]
    H, SP, C, NK, Hd, B = R.hips, R.spine, R.chest, R.neck, R.head, R.body
    aL, aR = R.arm[1], R.arm[-1]
    fL, fR = R.fore[1], R.fore[-1]
    hL, hR = R.hand[1], R.hand[-1]
    gL, gR = R.fingers[1], R.fingers[-1]
    HIDE = {"scale": (0.001, 0.001, 0.001)}

    def strips(kind):
        return chains[kind]

    def secondary(c, robe_g=3.0, wind=None, floor=None, freq=1.5, damp=0.14):
        """Physics follow-through on every strip / charm (soft, ghostly: low gravity, loose)."""
        for js, _a in strips("robe"):
            A.follow_through(c, js, freq=freq, damping=damp, gravity=robe_g, falloff=0.85, wind=wind, floor=floor,
                             max_angle=85)
        for js, _a in strips("inner"):
            A.follow_through(c, js, freq=freq * 1.15, damping=damp * 1.2, gravity=robe_g, falloff=0.85, wind=wind,
                             floor=floor, max_angle=80)
        for js, _a in strips("cloak"):
            A.follow_through(c, js, freq=freq * 0.85, damping=0.22, gravity=robe_g + 3.0, falloff=0.85, wind=wind,
                             floor=floor, max_angle=55)
        for js, _a in strips("mantle"):
            A.follow_through(c, js, freq=2.4, damping=0.16, gravity=4.0, falloff=0.85, wind=wind and _mul(wind, 0.5),
                             floor=floor, max_angle=60)
        for js, _a in strips("sleeve"):
            A.follow_through(c, js, freq=2.0, damping=0.14, gravity=5.0, falloff=0.85, wind=wind and _mul(wind, 0.6),
                             floor=floor, max_angle=75)
        for js in strips("charm"):
            A.follow_through(c, js, freq=2.2, damping=0.12, gravity=9.0, falloff=0.9, floor=floor, max_angle=70)

    def ripple(c, amp=5.0, cycles=2, kinds=("robe", "inner", "cloak"), inward=0.0):
        """Travelling billow around the hem: each strip's links breathe in/out, phase by angle + link."""
        for kind in kinds:
            for js, a in strips(kind):
                off = a / 360.0
                for i, j in enumerate(js):
                    w = amp * (0.6 + 0.4 * i)
                    c.add(j, (lambda f, w=w, off=off, i=i:
                              (w * A.wave(c, f, cycles, -off * 2 - i * 0.12) + inward,
                               0.35 * w * A.wave(c, f, cycles, -off * 2 - i * 0.12 + 0.25), 0)), "rot")

    def wisp_orbit(c, cycles=1, r=0.42, z0=0.0, dz=0.22, trail=0.0, speed_sign=1):
        for k, w in enumerate(wisps):
            def fn(f, k=k):
                p = A.phase(c, f, cycles, k / 3.0) * speed_sign
                ang = 2 * math.pi * p
                rr = r * (1.0 + 0.15 * math.sin(2 * math.pi * (A.phase(c, f, cycles * 2, k * 0.37))))
                return (math.cos(ang) * rr, math.sin(ang) * rr * 0.85 + trail,
                        z0 + dz * math.sin(2 * math.pi * A.phase(c, f, cycles * 2, k * 0.29)) + 0.12 * k)
            c.add(w, fn, "loc")

    def hide_arc(c):
        c.key(arc, 0, **HIDE)

    # ------------------------------------------------------------------ idle (loop, 72 f): hover + undulate
    c = A.Clip("idle", 72, joints=ALL)
    hide_arc(c)
    c.add(B, lambda f: (0, 0, 0.05 * A.wave(c, f, 1, 0.0) + 0.012 * A.wave(c, f, 2, 0.3)), "loc")
    c.add(B, lambda f: (1.2 * A.wave(c, f, 1, -0.15), 1.0 * A.wave(c, f, 1, 0.2), 0), "rot")
    c.pose(0, {SP: {"rot": (4, 0, 0)}, C: {"rot": (3, 0, 0)}, NK: {"rot": (6, 0, 0)}, Hd: {"rot": (4, 0, 0)},
               aL: {"rot": (-6, -4, 0)}, fL: {"rot": (-14, 0, 0)}, hL: {"rot": (-8, 0, 0)}, gL: {"rot": (-18, 0, 0)}},
           mirror=True)
    A.breathe(c, C, amp=1.6, rise=0.006, swell=0.01, cycles=1, shoulders=[aL, aR], head=Hd)
    A.noise(c, Hd, rot=(3, 4, 4), freq=0.35, seed=4)
    A.noise(c, aL, rot=(3, 2, 2), freq=0.3, seed=5)
    A.noise(c, aR, rot=(3, 2, 2), freq=0.3, seed=6)
    A.noise(c, gL, rot=(10, 0, 0), freq=0.6, seed=7)       # bony fingers slowly flex
    A.noise(c, gR, rot=(10, 0, 0), freq=0.6, seed=8)
    # arms lag the bob (drag)
    c.add(aL, lambda f: (3 * A.wave(c, f, 1, -0.12), 0, 0))
    c.add(aR, lambda f: (3 * A.wave(c, f, 1, -0.15), 0, 0))
    ripple(c, amp=5.0, cycles=2)
    wisp_orbit(c, cycles=1)
    secondary(c)
    c.bake()

    # ------------------------------------------------------------------ walk (loop, 36 f): gliding drift
    c = A.Clip("walk", 36, joints=ALL)
    hide_arc(c)
    c.pose(0, {B: {"loc": (0, 0, 0.1)}, H: {"rot": (10, 0, 0)}, SP: {"rot": (5, 0, 0)}, C: {"rot": (2, 0, 0)},
               NK: {"rot": (-7, 0, 0)}, Hd: {"rot": (-5, 0, 0)},
               aL: {"rot": (26, -14, 0)}, fL: {"rot": (-10, 0, 0)}, hL: {"rot": (14, 0, 0)}, gL: {"rot": (-8, 0, 0)}},
           mirror=True)
    c.add(B, lambda f: (0, 0, 0.035 * A.wave(c, f, 2, 0.0)), "loc")
    c.add(B, lambda f: (0.025 * A.wave(c, f, 1, 0.0), 0, 0), "loc")
    c.add(H, lambda f: (2.0 * A.wave(c, f, 2, -0.1), 3.5 * A.wave(c, f, 1, 0.05), 4 * A.wave(c, f, 1, 0.1)), "rot")
    c.add(SP, lambda f: (1.5 * A.wave(c, f, 2, -0.2), -2.0 * A.wave(c, f, 1, 0.0), -3 * A.wave(c, f, 1, 0.0)), "rot")
    c.add(Hd, lambda f: (-1.5 * A.wave(c, f, 2, -0.3), 0, 0), "rot")
    c.add(aL, lambda f: (6 * A.wave(c, f, 1, -0.15), 0, 0))
    c.add(aR, lambda f: (6 * A.wave(c, f, 1, 0.35), 0, 0))
    A.overlap(c, [aL, fL, hL, gL], delay=2.5, decay=0.8)
    A.overlap(c, [aR, fR, hR, gR], delay=2.5, decay=0.8)
    # robe strips sweep back (in each strip's local frame: back = (sin a, cos a))
    for kind, T in (("robe", 18), ("inner", 14), ("cloak", 0), ("sleeve", 0)):
        for js, a in strips(kind):
            ar = math.radians(a)
            if T:
                c.key(js[0], 0, rot=(T * math.cos(ar), -T * math.sin(ar), 0))
    ripple(c, amp=7.0, cycles=2)
    wisp_orbit(c, cycles=1, r=0.32, trail=0.45, z0=0.1)
    secondary(c, robe_g=2.5, wind=(0, 5.0, 0.4), freq=1.6, damp=0.12)
    c.bake()

    # ------------------------------------------------------------------ attack (one-shot): the reap
    c = A.Clip("attack", 44, joints=ALL)
    antic = {B: {"loc": (0, 0.06, 0.1)}, H: {"rot": (-4, 0, -14)}, SP: {"rot": (-8, 6, -24)}, C: {"rot": (-6, 4, -14)},
             NK: {"rot": (0, 0, 10)}, Hd: {"rot": (6, -6, 14)},
             aR: {"rot": (25, 95, -20)}, fR: {"rot": (-40, 0, 0)}, hR: {"rot": (-10, 0, 0)}, gR: {"rot": (-45, 0, 0)},
             aL: {"rot": (-40, -20, 0)}, fL: {"rot": (-55, 0, 0)}, hL: {"rot": (-20, 0, 0)}, gL: {"rot": (-30, 0, 0)}}
    strike = {B: {"loc": (0, -0.16, 0.0)}, H: {"rot": (10, 0, 16)}, SP: {"rot": (12, -6, 30)}, C: {"rot": (6, -4, 16)},
              NK: {"rot": (-4, 0, -12)}, Hd: {"rot": (-6, 4, -14)},
              aR: {"rot": (-82, 25, 60)}, fR: {"rot": (-6, 0, 0)}, hR: {"rot": (14, 0, 0)}, gR: {"rot": (10, 0, 0)},
              aL: {"rot": (40, -45, 0)}, fL: {"rot": (-25, 0, 0)}, hL: {"rot": (12, 0, 0)}, gL: {"rot": (-10, 0, 0)}}
    follow = {j: {k: tuple(x * (1.08 if j in (aR, SP, C, H) else 0.95) for x in v) for k, v in d.items()}
              for j, d in strike.items()}
    ev = A.attack(c, {"antic": antic, "strike": strike, "follow": follow}, start=0, antic=13, antic_hold=5, strike=3,
                  hold=5, recover=16, overshoot=0.12, push=0.08)
    A.jitter(c, aR, rot=(1.5, 1.5, 1.5), start=12, end=18)
    A.jitter(c, gR, rot=(6, 0, 0), start=11, end=18)
    A.noise(c, Hd, rot=(2, 2, 2), freq=0.5, seed=12)
    imp = ev["impact"]
    c.key(arc, 0, ease="constant", **HIDE)
    c.key(arc, imp - 2, ease="constant", scale=(0.75, 0.75, 0.75), rot=(0, 0, -25))
    c.key(arc, imp - 1, ease="constant", scale=(1, 1, 1), rot=(0, 0, 0))
    c.key(arc, imp + 1, ease="constant", scale=(1.08, 1.08, 1.0), rot=(0, 0, 10))
    c.key(arc, imp + 3, ease="constant", scale=(1.14, 1.14, 0.7), rot=(0, 0, 18))
    c.key(arc, imp + 5, ease="constant", **HIDE)
    # robe billows out at the antic, snaps around with the sweep
    for js, a in strips("robe") + strips("inner"):
        c.key(js[0], 0)
        c.key(js[0], 13, rot=(-10, 0, 0))
        c.key(js[0], imp, rot=(-4, -10, 0), ease="quad_out")
        c.key(js[0], 43, rot=(0, 0, 0))
    wisp_orbit(c, cycles=1, r=0.45)
    secondary(c, freq=1.7)
    c.bake()
    print("YSOLDE attack impact frame", imp)

    # ------------------------------------------------------------------ hit (one-shot recoil)
    c = A.Clip("hit", 22, joints=ALL)
    hide_arc(c)
    A.hit_react(c, {B: {"loc": (0, 0.12, 0.05)}, H: {"rot": (-10, 0, 4)}, SP: {"rot": (-12, 0, -6)},
                    C: {"rot": (-10, 3, 8), "scale": (1.03, 1.03, 0.97)}, Hd: {"rot": (-22, 8, -16)},
                    aL: {"rot": (-30, -40, 0)}, aR: {"rot": (-20, 35, 0)}, fL: {"rot": (-35, 0, 0)},
                    fR: {"rot": (-30, 0, 0)}, gL: {"rot": (25, 0, 0)}, gR: {"rot": (25, 0, 0)}},
                start=0, rise=2, settle=14, wobble=1.0, stagger=0.8)
    wisp_orbit(c, cycles=1, r=0.5)
    secondary(c, freq=1.8)
    c.bake()

    # ------------------------------------------------------------------ death (one-shot): convulse, unravel, sink
    c = A.Clip("death", 64, joints=ALL)
    hide_arc(c)
    # body: lift on the recoil, hang, then sink into the robe (accelerating), small settle bounce
    c.key(B, 0, loc=(0, 0, 0), rot=(0, 0, 0), ease="expo_out")
    c.key(B, 5, loc=(0, 0.08, 0.14), rot=(-6, 0, 0), ease="sine_inout")
    c.key(B, 13, loc=(0, 0.06, 0.16), rot=(-4, 3, 0), ease="quad_in")
    c.key(B, 32, loc=(0, -0.05, -0.86), rot=(6, 0, 4), ease="quad_out")
    c.key(B, 36, loc=(0, -0.05, -0.82), rot=(5, 0, 4), ease="quad_in")
    c.key(B, 40, loc=(0, -0.05, -0.87), rot=(6, 0, 4), ease="sine_out")
    c.key(B, 63, loc=(0, -0.05, -0.88), rot=(6, 0, 4))
    conv = {H: {"rot": (-8, 0, 0)}, SP: {"rot": (-18, 0, 4)}, C: {"rot": (-14, 0, 0)}, NK: {"rot": (-16, 0, 0)},
            Hd: {"rot": (-28, 10, 22)}, aL: {"rot": (-30, -70, 0)}, fL: {"rot": (-30, 0, 0)}, gL: {"rot": (30, 0, 0)},
            hL: {"rot": (20, 0, 0)}}
    slump = {H: {"rot": (20, 0, 0)}, SP: {"rot": (34, 0, 8)}, C: {"rot": (22, 0, 4)}, NK: {"rot": (26, 0, 0)},
             Hd: {"rot": (30, -12, 30)}, aL: {"rot": (-28, -42, 6)}, fL: {"rot": (-10, 0, 0)}, gL: {"rot": (-30, 0, 0)},
             hL: {"rot": (10, 0, 0)}}
    c.pose(0, {j: {"rot": (0, 0, 0)} for j in conv}, mirror=True, ease="expo_out")
    c.pose(5, conv, mirror=True, ease="sine_inout")
    c.pose(13, {j: {"rot": tuple(x * 1.1 for x in d["rot"])} for j, d in conv.items()}, mirror=True, ease="quad_in")
    c.pose(31, slump, mirror=True, ease="back_out:1.6")
    c.pose(40, {j: {"rot": tuple(x * 1.05 for x in d["rot"])} for j, d in slump.items()}, mirror=True, ease="sine_out")
    c.pose(63, {j: {"rot": tuple(x * 1.05 for x in d["rot"])} for j, d in slump.items()}, mirror=True)
    A.jitter(c, Hd, rot=(6, 6, 8), start=5, end=14, freq=11)
    A.jitter(c, gL, rot=(14, 0, 0), start=4, end=16, freq=10)
    A.jitter(c, gR, rot=(14, 0, 0), start=4, end=16, freq=10, seed=3)
    # robe unravels: strips peel outward like petals as she sinks, then lie spread on the ground
    for kind, spread in (("robe", 62), ("inner", 48), ("cloak", -20)):
        for js, a in strips(kind):
            c.key(js[0], 0)
            c.key(js[0], 13, rot=(-6, 0, 0), ease="quad_in")
            c.key(js[0], 34, rot=(-spread, 0, 0), ease="back_out:1.4")
            c.key(js[0], 63, rot=(-spread * 1.05, 0, 0))
            for i, j in enumerate(js[1:], 1):
                c.key(j, 0)
                c.key(j, 13, rot=(4, 0, 0))
                c.key(j, 34, rot=(spread * 0.25 * i, 0, 0))
                c.key(j, 63, rot=(spread * 0.3 * i, 0, 0))
    # wisps scatter up and out, then wink out
    for k, w in enumerate(wisps):
        ang = 2 * math.pi * k / 3
        c.key(w, 0, loc=(math.cos(ang) * 0.4, math.sin(ang) * 0.4, 0.1), scale=(1, 1, 1))
        c.key(w, 22, loc=(math.cos(ang) * 0.9, math.sin(ang) * 0.9, 1.0), scale=(1.3, 1.3, 1.3), ease="quad_in")
        c.key(w, 30, loc=(math.cos(ang) * 1.1, math.sin(ang) * 1.1, 1.4), scale=(0.001, 0.001, 0.001), ease="constant")
    secondary(c, floor=0.03, robe_g=4.0, freq=1.6)
    c.bake()

    # ------------------------------------------------------------------ cheer (one-shot): an unsettling rise
    c = A.Clip("cheer", 60, joints=ALL)
    hide_arc(c)
    c.key(B, 0, loc=(0, 0, 0), ease="sine_inout")
    c.key(B, 12, loc=(0, 0.02, -0.1), ease="expo_out")
    c.key(B, 19, loc=(0, 0, 0.26), ease="sine_inout")
    c.key(B, 44, loc=(0, 0, 0.3), ease="sine_inout")
    c.key(B, 59, loc=(0, 0, 0))
    curl = {SP: {"rot": (18, 0, 0)}, C: {"rot": (10, 0, 0)}, NK: {"rot": (18, 0, 0)}, Hd: {"rot": (20, 0, 0)},
            aL: {"rot": (-30, 10, 30)}, fL: {"rot": (-70, 0, 0)}, gL: {"rot": (-50, 0, 0)}}
    spread = {SP: {"rot": (-14, 0, 0)}, C: {"rot": (-8, 0, 0)}, NK: {"rot": (-6, 0, 0)},
              aL: {"rot": (-30, -105, 0)}, fL: {"rot": (-20, 0, 0)}, hL: {"rot": (-20, 0, 0)}, gL: {"rot": (25, 0, 0)}}
    rest = {j: {"rot": (0, 0, 0)} for j in list(curl) + list(spread)}
    c.pose(0, rest, mirror=True, ease="sine_inout")
    c.pose(12, curl, mirror=True, ease="expo_out")
    c.pose(19, spread, mirror=True, ease="sine_inout")
    c.pose(44, {j: {"rot": tuple(x * 1.06 for x in d["rot"])} for j, d in spread.items()}, mirror=True, ease="sine_inout")
    c.pose(59, rest, mirror=True)
    # the head: bows, snaps up, then cocks slowly to an impossible angle and back
    c.key(Hd, 0, rot=(0, 0, 0), ease="sine_inout")
    c.key(Hd, 12, rot=(22, 0, 0), ease="expo_out")
    c.key(Hd, 18, rot=(-14, 0, 0), ease="sine_inout")
    c.key(Hd, 32, rot=(-8, 38, 8), ease="sine_inout")
    c.key(Hd, 40, rot=(-8, 40, 10), ease="expo_out")
    c.key(Hd, 43, rot=(-10, -18, -6), ease="sine_inout")
    c.key(Hd, 59, rot=(0, 0, 0))
    A.jitter(c, Hd, rot=(3, 5, 3), start=20, end=44, freq=9)
    A.jitter(c, gL, rot=(18, 0, 0), start=19, end=46, freq=7, seed=2)
    A.jitter(c, gR, rot=(18, 0, 0), start=19, end=46, freq=7, seed=5)
    for js, a in strips("robe") + strips("inner"):
        c.key(js[0], 0)
        c.key(js[0], 12, rot=(6, 0, 0))
        c.key(js[0], 20, rot=(-26, 0, 0), ease="sine_inout")
        c.key(js[0], 44, rot=(-22, 0, 0), ease="sine_inout")
        c.key(js[0], 59, rot=(0, 0, 0))
    ripple(c, amp=6.0, cycles=3)
    wisp_orbit(c, cycles=2, r=0.6, dz=0.35, z0=0.25)
    secondary(c, freq=1.6)
    c.bake()


def _mul(v, s):
    return tuple(x * s for x in v)
