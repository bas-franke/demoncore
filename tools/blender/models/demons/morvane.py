"""Morvane, the Hexbinder: gaunt warlock in layered plum robes with deep folds and gilt-embroidered
trims, a towering ribbed collar, a bone mask under a branching antler crown, a hexfire sigil above
his right palm and a floating grimoire (curved pages, clasps, ribbons, orbiting glyphs and leaves).

Animations (sbanim): idle (brooding, grimoire hover), walk (crouched run, IK feet planted at
RUN_SPEED m/s), attack (channelled hex: gesture + grimoire flare), hit, death (robes collapse,
grimoire falls), cheer (sinister laugh, grimoire raised). Every hanging part (robe panels, outer coat,
cape, stoles, tabard, sleeve drapes, belt talismans, antler charms, book ribbons/clasp) is a
follow-through chain.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import sb  # noqa: E402
import sbanim as A  # noqa: E402
import _demon_kit as K  # noqa: E402
from _demon_kit import SIDES, sname  # noqa: E402
from mathutils import Vector  # noqa: E402
import sbmat  # noqa: E402

CATEGORY = "demons"
# Procedural sbmat surfaces (ashen skin, robe/wool weave, gilt embroidery, antler, bone, leather...)
# baked into one atlas (tools/blender/bake.py); hex/rune/eye glows stay flat emissive materials.
BAKE = {"size": 1024, "samples": 16}
RUN_SPEED = 6.0       # m/s the walk clip is authored for (player move_speed)
WALK_FRAMES = 18
CONTACT = 0.22        # fraction of the cycle each foot is planted


# =============================================================================== mesh helpers

def solid_grid(name, parent, fn, nu, nv, material, thick=0.012, u_rng=(-0.5, 0.5), v_rng=(0.0, 1.0),
               sub=(0, 0, 0), axis=(0, 1, 0), offset=0.0, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Closed slab from a surface fn(u, v) -> (x, y, z): front = surface, back = surface + axis*thick.
    `axis` may be a callable (u, v) -> vector (points to the INSIDE of the cloth)."""
    bm = bmesh.new()
    sub = Vector(sub)

    def ax(u, v):
        a = axis(u, v) if callable(axis) else axis
        return Vector(a).normalized()

    F, B = [], []
    for j in range(nv + 1):
        v = v_rng[0] + (v_rng[1] - v_rng[0]) * j / nv
        fr, br = [], []
        for i in range(nu + 1):
            u = u_rng[0] + (u_rng[1] - u_rng[0]) * i / nu
            n = ax(u, v)
            p = Vector(fn(u, v)) - sub - n * offset
            fr.append(bm.verts.new(p))
            br.append(bm.verts.new(p + n * thick))
        F.append(fr)
        B.append(br)
    for j in range(nv):
        for i in range(nu):
            bm.faces.new((F[j][i], F[j][i + 1], F[j + 1][i + 1], F[j + 1][i]))
            bm.faces.new((B[j][i], B[j + 1][i], B[j + 1][i + 1], B[j][i + 1]))
    for i in range(nu):   # top / bottom walls
        bm.faces.new((F[0][i], B[0][i], B[0][i + 1], F[0][i + 1]))
        bm.faces.new((F[nv][i], F[nv][i + 1], B[nv][i + 1], B[nv][i]))
    for j in range(nv):   # side walls
        bm.faces.new((F[j][0], F[j + 1][0], B[j + 1][0], B[j][0]))
        bm.faces.new((F[j][nu], B[j][nu], B[j + 1][nu], F[j + 1][nu]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return K._obj(name, bm, parent, material, loc, rot, True, None)


def cloth_fn(top_w, bot_w, length, cup=0.0, flare=0.0, folds=0.0, depth=0.0, rag=0.0, seed=0, point=0.0,
             nu=8, wpow=1.0):
    """Hanging cloth surface: top edge centred at the origin, hangs -Z, faces -Y. Deep vertical folds
    (`folds` waves across the width, `depth` m), a ragged / pointed hem."""
    rng = random.Random(seed)
    cols = [rng.random() if i % 2 else rng.random() * 0.4 for i in range(nu + 1)]
    ph = rng.random() * 6.28

    def ragf(u):
        x = (u + 0.5) * nu
        i = min(int(x), nu - 1)
        t = x - i
        return cols[i] * (1 - t) + cols[i + 1] * t

    def fn(u, v):
        w = top_w + (bot_w - top_w) * (v ** wpow)
        hem = 1.0 - rag * ragf(u) * v ** 4 + point * (1.0 - abs(2 * u)) * v ** 2
        z = -length * v * hem
        y = (cup * (2 * u) ** 2 - flare * v * v
             + depth * math.sin(2 * math.pi * folds * (u + 0.5) + ph) * (0.25 + 0.75 * v))
        return (u * w, y, z)
    return fn


def hanging(name, parent, loc, rot, fn, splits, material, nu=8, nvs=None, thick=0.012, trims=None,
            gilt=None, overlap=0.02):
    """Joint chain name0..nameN carrying consecutive v-slices of the cloth fn.
    trims = list of ("hem"|"left"|"right", size m). Returns (joints, tip vector)."""
    js = []
    prev = Vector((0, 0, 0))
    nvs = nvs or [2] * (len(splits) - 1)
    for k in range(len(splits) - 1):
        v0, v1 = splits[k], splits[k + 1]
        P0 = Vector(fn(0.0, v0))
        if k == 0:
            j = sb.empty(f"{name}{k}", parent, loc=loc, rot=rot)
        else:
            j = sb.empty(f"{name}{k}", js[-1], loc=tuple(P0 - prev))
        prev = P0
        last = k == len(splits) - 2
        vt = v1 if last else min(1.0, v1 + overlap)
        solid_grid(f"{name}{k}_m", j, fn, nu, nvs[k], material, thick, v_rng=(v0, vt), sub=P0)
        for kind, size in (trims or []):
            if kind == "hem" and last:
                L = abs(fn(0.0, 1.0)[2]) or 1.0
                solid_grid(f"{name}{k}_hem", j, fn, nu, 1, gilt, thick + 0.006, v_rng=(1.0 - size / L, 1.0),
                           sub=P0, offset=0.003)
            elif kind in ("left", "right"):
                w = max(abs(fn(0.5, (v0 + v1) / 2)[0]) * 2, 1e-3)
                du = size / w
                ur = (-0.5, -0.5 + du) if kind == "left" else (0.5 - du, 0.5)
                solid_grid(f"{name}{k}_{kind}", j, fn, 1, nvs[k], gilt, thick + 0.006, u_rng=ur, v_rng=(v0, vt),
                           sub=P0, offset=0.003)
        js.append(j)
    tip = Vector(fn(0.0, splits[-1])) - prev
    return js, tip


def ring_pts(cx, cy, cz, rx, ry, n=24, plane="xy"):
    pts = []
    for i in range(n + 1):
        a = 2 * math.pi * i / n
        if plane == "xy":
            pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a), cz))
        else:  # xz
            pts.append((cx + rx * math.cos(a), cy, cz + ry * math.sin(a)))
    return pts


def ring(name, parent, c, rx, ry, r, material, n=24, plane="xy", hh=None, segs=4):
    """Closed piping ring (belt, trims, sigil circles). hh = (vertical, radial) half sizes."""
    pts = ring_pts(*c, rx, ry, n, plane)
    rr = [hh if hh else r] * len(pts)
    return K.loft(name, parent, pts, rr, material, segs=segs, caps=(False, False),
                  ref=(0, 0, 1) if plane == "xy" else (0, 1, 0))


def page_block(name, parent, s, w, h, t, material, n=7):
    """Open-book page stack on the +X (s=1) / -X side: rises from the gutter, curls down to the edge."""
    bm = bmesh.new()
    prof = []
    for i in range(n + 1):
        u = i / n
        z = 0.004 + t * (math.sin(math.pi * 0.5 * min(1.0, u * 2.2)) ** 0.6) * (1.0 - 0.45 * u * u)
        prof.append((s * (0.006 + w * u), z))
    prof.append((s * (0.006 + w), 0.001))
    prof.append((s * 0.006, 0.001))
    ring0 = [bm.verts.new((x, -h / 2, z)) for x, z in prof]
    ring1 = [bm.verts.new((x, h / 2, z)) for x, z in prof]
    m = len(prof)
    for i in range(m):
        bm.faces.new((ring0[i], ring0[(i + 1) % m], ring1[(i + 1) % m], ring1[i]))
    bm.faces.new(ring0)
    bm.faces.new(list(reversed(ring1)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    K._obj(name, bm, parent, material, (0, 0, 0), (0, 0, 0), True, None)

    def top(u):
        return 0.004 + t * (math.sin(math.pi * 0.5 * min(1.0, u * 2.2)) ** 0.6) * (1.0 - 0.45 * u * u)
    return top


def rad(*a):
    return tuple(math.radians(x) for x in a)


# =============================================================================== build

def build():
    # ------------------------------------------------------------------ materials (surface keywords)
    L = K.lin
    skin = sbmat.skin("Morvane_Skin", L((0.42, 0.37, 0.41)), rough=0.62, pores=120.0, veins=0.35,
                      crease=L((0.16, 0.12, 0.16)), high=L((0.55, 0.5, 0.53)), vein_col=L((0.24, 0.16, 0.28)))
    robe = sbmat.linen("Morvane_RobeCloth", L((0.2, 0.07, 0.15)), weave=90.0, rough=0.84, stain=0.4,
                       stain_col=L((0.12, 0.05, 0.09)), grime_col=L((0.03, 0.012, 0.025)))
    wool = sbmat.linen("Morvane_CloakWool", L((0.095, 0.048, 0.088)), weave=55.0, rough=0.92, stain=0.3,
                       stain_col=L((0.15, 0.11, 0.12)), grime_col=L((0.02, 0.01, 0.018)))
    silk = sbmat.silk("Morvane_LiningSilk", L((0.38, 0.07, 0.17)), rough=0.55)
    legc = sbmat.linen("Morvane_LegWrapCloth", L((0.085, 0.05, 0.07)), weave=70.0, rough=0.9,
                       stain_col=L((0.16, 0.12, 0.1)), grime_col=L((0.02, 0.012, 0.015)))
    gilt = sbmat.gold_filigree("Morvane_GiltEmbroidery", tint=L((0.76, 0.55, 0.25)), scale=1.6)
    bronze = sbmat.worn_steel("Morvane_BronzeClasp", L((0.46, 0.32, 0.16)), roughness=0.4, edge_k=1.5,
                              scratch_k=1.25, grime=0.8)
    antler = sbmat.horn("Morvane_Antler", L((0.6, 0.55, 0.46)), rough=0.65, rings=14.0, tip=L((0.3, 0.25, 0.2)))
    bonec = sbmat.bone("Morvane_BoneCharm", L((0.7, 0.64, 0.52)), scale=1.5)
    mask_m = sbmat.aged_ivory("Morvane_MaskBone", L((0.74, 0.69, 0.6)), scale=1.2)
    belt_m = sbmat.leather("Morvane_BeltLeather", L((0.17, 0.09, 0.05)), scale=0.55)
    boot = sbmat.leather("Morvane_BootLeather", L((0.11, 0.065, 0.055)), scale=0.55)
    book_m = sbmat.leather("Morvane_BookLeather", L((0.24, 0.075, 0.06)), scale=0.55)
    page_m = sbmat.aged_ivory("Morvane_PageParchment", L((0.72, 0.63, 0.46)), scale=0.8)
    cord = sbmat.linen("Morvane_CordRope", L((0.32, 0.23, 0.15)), weave=120.0, rough=0.9, stain=0.3)
    claw = sbmat.horn("Morvane_Claw", L((0.1, 0.08, 0.08)), rough=0.4, rings=45.0)
    shadow = K.mat("Morvane_Shadow", (0.015, 0.008, 0.015), 0.9)
    wax = K.mat("Morvane_WaxSeal", (0.45, 0.05, 0.08), 0.45)
    hex_ = K.mat("Morvane_HexGlow", (0.4, 0.1, 0.5), 0.5, 0.0, (0.78, 0.25, 1.0), 9.0)
    rune = K.mat("Morvane_RuneGlow", (0.3, 0.08, 0.4), 0.5, 0.0, (0.75, 0.3, 1.0), 6.0)
    eyes = K.mat("Morvane_EyeGlow", (0.5, 0.2, 0.6), 0.5, 0.0, (0.88, 0.45, 1.0), 16.0)

    R = K.humanoid("Morvane", hip_h=1.0, thigh=0.47, shin=0.45, hip_w=0.1, spine=0.24, chest=0.34,
                   neck=0.11, shoulder_w=0.21, shoulder_z=0.28, upper=0.31, fore=0.29, arm_out=12,
                   spine_rot=9, head_rot=-4)
    # brooding rest pose: hunched, right palm raised (sigil), left hand reaching toward the grimoire
    R.chest.rotation_euler = rad(4, 0, 0)
    R.arm[-1].rotation_euler = rad(-26, 10, -4)
    R.fore[-1].rotation_euler = rad(-72, 0, 6)
    R.hand[-1].rotation_euler = rad(-12, 0, 0)
    R.arm[1].rotation_euler = rad(-14, -20, 0)
    R.fore[1].rotation_euler = rad(-48, 0, -14)
    R.hand[1].rotation_euler = rad(-18, 0, 0)
    chains = {}    # follow-through groups

    # ------------------------------------------------------------------ legs: wrapped cloth, pointed boots
    for s in SIDES:
        n = sname(s)
        K.loft(f"thigh_{n}", R.thigh[s], [(0, 0, 0.05), (0, -0.01, -0.2), (0, 0, -0.47)], [0.085, 0.075, 0.058], legc, segs=8)
        K.loft(f"shin_{n}", R.shin[s], [(0, 0, 0.03), (0, 0.005, -0.2), (0, 0, -0.42)], [0.06, 0.055, 0.045], legc, segs=8)
        for k in range(2):   # leg wraps
            ring(f"wrap_{n}{k}", R.shin[s], (0, 0.004, -0.16 - k * 0.12), 0.06 - k * 0.004, 0.06 - k * 0.004, 0.007,
                 cord, n=8, segs=4)
        K.loft(f"boot_{n}", R.foot[s], [(0, 0.04, 0.06), (0, 0.03, 0.0), (0, -0.06, -0.03), (0, -0.17, -0.04),
                                        (0, -0.24, -0.02)],
               [(0.05, 0.05), (0.052, 0.055), (0.05, 0.04), (0.03, 0.016), (0.006, 0.006)], boot, segs=8)
        sb.box(f"sole_{n}", R.foot[s], size=(0.085, 0.24, 0.012), loc=(0, -0.07, -0.042), material=claw, bevel=0.0)

    H = R.hips
    K.loft("pelvis", H, [(0, 0, -0.12), (0, 0, 0.0), (0, 0, 0.14)], [(0.15, 0.12), (0.17, 0.13), (0.17, 0.13)], robe, segs=12)

    # ------------------------------------------------------------------ under-robe: pleated, front slit, gilt hem
    under = [28, 60, 92, 124, 154, 180, -154, -124, -92, -60, -28]
    chains["robe"] = []
    for i, a in enumerate(under):
        ar = math.radians(a)
        fn = cloth_fn(0.12, 0.215, 0.97, cup=0.02, flare=0.0, folds=1.0, depth=0.026, seed=11 + i * 5, nu=6)
        tr = [("hem", 0.045)]
        if a == 28:
            tr.append(("left", 0.03))
        if a == -28:
            tr.append(("right", 0.03))
        js, tip = hanging(f"robe{i}_", H, (math.sin(ar) * 0.16, -math.cos(ar) * 0.13, 0.07), (-7, 0, a), fn,
                          (0, 0.45, 1.0), robe, nu=6, nvs=[1, 3], thick=0.012, trims=tr, gilt=gilt)
        chains["robe"].append((js, tip, a))

    # front tabard between the slit: silk with gilt borders and a column of glowing runes
    fn = cloth_fn(0.13, 0.15, 0.82, cup=0.01, folds=0.5, depth=0.006, point=0.08, seed=3, nu=4)
    js, tip = hanging("tabard", H, (0, -0.165, 0.09), (-4, 0, 0), fn, (0, 0.34, 0.68, 1.0), silk, nu=4,
                      nvs=[1, 1, 2], thick=0.008, trims=[("left", 0.018), ("right", 0.018)], gilt=gilt)
    for k, j in enumerate(js):
        v0 = (0, 0.34, 0.68)[k]
        for q in range(2):
            v = v0 + 0.1 + q * 0.13
            P = Vector(fn(0, v)) - Vector(fn(0, v0))
            glow = k == 1 and q == 0
            sb.box(f"tabard_rune{k}{q}", j, size=(0.03, 0.004, 0.04) if glow else (0.05, 0.004, 0.012),
                   loc=(P.x, P.y - 0.004, P.z), rot=(0, 45 if glow else 0, 0), material=rune if glow else gilt, bevel=0.0)
    chains["tabard"] = (js, tip)

    # outer coat: open at the front, longest at the back, ragged hem
    coat = [70, 100, 130, 158, -158, -130, -100, -70]
    clen = [0.9, 0.96, 1.0, 1.03, 1.03, 1.0, 0.96, 0.9]
    chains["coat"] = []
    for i, a in enumerate(coat):
        ar = math.radians(a)
        fn = cloth_fn(0.135, 0.25, clen[i], cup=0.025, folds=1.0, depth=0.03, rag=0.22, seed=40 + i * 3, nu=5)
        tr = []
        if a == 70:
            tr = [("left", 0.028)]
        if a == -70:
            tr = [("right", 0.028)]
        js, tip = hanging(f"coat{i}_", H, (math.sin(ar) * 0.2, -math.cos(ar) * 0.165, 0.13), (-10, 0, a), fn,
                          (0, 0.45, 1.0), wool, nu=5, nvs=[1, 3], thick=0.014, trims=tr, gilt=gilt)
        chains["coat"].append((js, tip, a))

    # ------------------------------------------------------------------ belt, buckle, pouches, talismans
    ring("belt", H, (0, 0, 0.13), 0.212, 0.178, None, belt_m, n=20, hh=(0.032, 0.012), segs=6)
    ring("belt_stitch", H, (0, 0, 0.13), 0.222, 0.188, 0.004, gilt, n=20, segs=3)
    sb.cylinder("buckle", H, r1=0.05, depth=0.016, loc=(0, -0.178, 0.13), rot=(90, 0, 0), material=gilt, segments=6, bevel=0.0)
    sb.cylinder("buckle_core", H, r1=0.026, depth=0.01, loc=(0, -0.192, 0.13), rot=(90, 30, 0), material=hex_, segments=6, bevel=0.0)
    for k, (a, sx) in enumerate(((52, 1), (-52, 1), (118, 0.8))):
        ar = math.radians(a)
        p = (math.sin(ar) * 0.225, -math.cos(ar) * 0.19, 0.075)
        sb.box(f"pouch{k}", H, size=(0.085 * sx, 0.05, 0.095), loc=p, rot=(0, 0, a), material=belt_m, bevel=0.0)
        sb.box(f"pouch_flap{k}", H, size=(0.09 * sx, 0.056, 0.04), loc=(p[0] * 1.02, p[1] * 1.02, 0.11), rot=(-8, 0, a),
               material=belt_m, bevel=0.0)
        sb.sphere(f"pouch_stud{k}", H, 0.011, loc=(math.sin(ar) * 0.256, -math.cos(ar) * 0.222, 0.1), material=gilt,
                  segments=8, rings=4)
    # scroll case at the back-right
    sb.cylinder("scroll_case", H, r1=0.03, depth=0.24, loc=(-0.17, 0.17, -0.05), rot=(12, -20, 0), material=belt_m, segments=8, bevel=0.0)
    sb.cylinder("scroll_case_cap", H, r1=0.034, depth=0.03, loc=(-0.13, 0.215, 0.17), rot=(12, -20, 0), material=gilt, segments=8, bevel=0.0)

    chains["talisman"] = []

    def talisman(tname, a, cord_len, kind):
        ar = math.radians(a)
        t0 = sb.empty(f"{tname}0", H, loc=(math.sin(ar) * 0.228, -math.cos(ar) * 0.194, 0.1), rot=(0, 0, a))
        K.loft(f"{tname}_cord", t0, [(0, 0, 0.0), (0, -0.005, -cord_len * 0.5), (0, 0, -cord_len)], [0.005] * 3, cord, segs=4,
               caps=(False, False))
        t1 = sb.empty(f"{tname}1", t0, loc=(0, 0, -cord_len))
        if kind == "skull":
            sb.sphere(f"{tname}_skull", t1, 0.036, loc=(0, 0, -0.04), scale=(0.9, 1.0, 1.0), material=bonec, segments=10, rings=7)
            sb.box(f"{tname}_jaw", t1, size=(0.04, 0.035, 0.022), loc=(0, -0.012, -0.075), material=bonec, bevel=0.006)
            for s in SIDES:
                sb.sphere(f"{tname}_socket{sname(s)}", t1, 0.011, loc=(s * 0.014, -0.03, -0.042), material=shadow, segments=6, rings=4)
            tip = (0, 0, -0.09)
        elif kind == "tablet":
            sb.box(f"{tname}_tablet", t1, size=(0.05, 0.014, 0.085), loc=(0, 0, -0.045), material=bonec, bevel=0.006)
            sb.box(f"{tname}_glyph", t1, size=(0.022, 0.004, 0.04), loc=(0, -0.009, -0.045), rot=(0, 45, 0), material=rune, bevel=0.0)
            tip = (0, 0, -0.09)
        elif kind == "scroll":
            sb.cylinder(f"{tname}_scroll", t1, r1=0.018, depth=0.11, loc=(-0.055, 0, -0.025), rot=(0, 90, 0), material=page_m, segments=8, bevel=0.0)
            sb.sphere(f"{tname}_seal", t1, 0.016, loc=(0, -0.02, -0.03), scale=(1, 0.4, 1), material=wax, segments=8, rings=5)
            for x in (-0.06, 0.06):
                sb.cylinder(f"{tname}_end{x}", t1, r1=0.021, depth=0.008, loc=(x, 0, -0.025), rot=(0, 90, 0), material=gilt,
                            segments=8, bevel=0.0)
            tip = (0, 0, -0.05)
        else:  # bundle of finger bones with a glowing bead
            for q in range(3):
                x = (q - 1) * 0.014
                K.horn(f"{tname}_bone{q}", t1, [(x, 0, 0), (x * 1.5, -0.004, -0.05), (x * 1.8, 0, -0.09 - q * 0.01)], 0.007, 0.003,
                       bonec, segs=5, n=2)
            sb.sphere(f"{tname}_bead", t1, 0.012, loc=(0, -0.004, 0.0), material=hex_, segments=8, rings=5)
            tip = (0, 0, -0.1)
        chains["talisman"].append(([t0, t1], Vector(tip)))

    talisman("tal_skull", -38, 0.13, "skull")
    talisman("tal_tablet", 36, 0.1, "tablet")
    talisman("tal_scroll", -86, 0.07, "scroll")
    talisman("tal_bones", 82, 0.12, "bones")

    # ------------------------------------------------------------------ torso, lapels, stoles, mantle
    SP, C = R.spine, R.chest
    K.loft("waist", SP, [(0, 0, -0.08), (0, 0, 0.12), (0, 0, 0.26)], [(0.165, 0.128), (0.15, 0.115), (0.17, 0.125)], robe, segs=12)
    K.loft("torso", C, [(0, 0, -0.06), (0, 0, 0.1), (0, 0.01, 0.24), (0, 0.012, 0.33)],
           [(0.175, 0.128), (0.195, 0.135), (0.19, 0.13), (0.1, 0.085)], robe, segs=14)
    for s in SIDES:   # crossed lapels with gilt piping
        lf = cloth_fn(0.1, 0.06, 0.4, cup=0.02, seed=2, nu=3)
        solid_grid(f"lapel_{sname(s)}", C, lf, 3, 4, wool, 0.012, loc=(s * 0.045, -0.128, 0.33), rot=(4, 0, s * 18))
        solid_grid(f"lapel_trim_{sname(s)}", C, lf, 1, 4, gilt, 0.018, u_rng=((-0.5, -0.36) if s > 0 else (0.36, 0.5)),
                   offset=0.003, loc=(s * 0.045, -0.128, 0.33), rot=(4, 0, s * 18))
    # rune stoles hanging from the neck, over the mantle, down past the belt
    chains["stole"] = []
    for s in SIDES:
        n = sname(s)
        fn = cloth_fn(0.062, 0.075, 0.92, folds=0.5, depth=0.004, point=0.07, seed=5 + s, nu=2)
        js, tip = hanging(f"stole_{n}", C, (s * 0.075, -0.17, 0.33), (-26, 0, s * -4), fn, (0, 0.3, 0.62, 1.0), silk,
                          nu=2, nvs=[2, 2, 2], thick=0.008, trims=[("hem", 0.05), ("left", 0.012), ("right", 0.012)], gilt=gilt)
        for k, j in enumerate(js):
            v0 = (0, 0.3, 0.62)[k]
            for q in range(2):   # one glowing rune per link between gilt embroidered diamonds
                v = v0 + 0.09 + q * 0.14
                P = Vector(fn(0, v)) - Vector(fn(0, v0))
                glow = q == 1
                sb.box(f"stole_rune_{n}{k}{q}", j, size=(0.02, 0.004, 0.03) if glow else (0.026, 0.004, 0.026),
                       loc=(P.x, P.y - 0.005, P.z), rot=(0, 45, 0), material=rune if glow else gilt, bevel=0.0)
        chains["stole"].append((js, tip))
    # two-layer shoulder mantle, gilt trim on each hem
    for k in range(2):
        rx, ry, rz = 0.235 - k * 0.03, 0.185 - k * 0.022, 0.22 - k * 0.04
        cz = 0.17 + k * 0.08
        fl = 0.3
        K.shell(f"mantle{k}", C, (rx, ry, rz), lat=(-10, 80), lon=(-180, 180), segs=(16, 4), thick=0.014,
                material=wool if k == 0 else robe, loc=(0, 0.012, cz), flare=fl)
        la = math.radians(-10)
        ring(f"mantle_trim{k}", C, (0, 0.012, cz + rz * math.sin(la)), rx * math.cos(la) * (1 + fl) + 0.006,
             ry * math.cos(la) * (1 + fl) + 0.006, None, gilt, n=18, hh=(0.012, 0.006), segs=4)
    for s in SIDES:   # morse clasps at the throat, joined by a gilt chain
        sb.cylinder(f"clasp_{sname(s)}", C, r1=0.026, depth=0.012, loc=(s * 0.07, -0.105, 0.37), rot=(80, 0, 0),
                    material=bronze, segments=6, bevel=0.0)
        sb.sphere(f"clasp_gem_{sname(s)}", C, 0.011, loc=(s * 0.07, -0.118, 0.37), scale=(1, 0.5, 1), material=hex_,
                  segments=6, rings=4)
    K.loft("clasp_chain", C, [(-0.07, -0.118, 0.365), (0, -0.14, 0.33), (0.07, -0.118, 0.365)], [0.0045] * 3, gilt, segs=4)

    # ------------------------------------------------------------------ towering ribbed collar
    cc = Vector((0, 0.03, 0.3))

    def collar_fn(inset=0.0):
        def fn(u, v):
            lon = math.radians(72 + 216 * u)
            hgt = 0.5 * (0.42 + 0.58 * math.sin(math.pi * u) ** 0.7)
            spike = max(0.0, math.cos(2 * math.pi * 3.5 * (u - 0.5) * 2 / 2)) ** 8
            z = hgt * v * (1.0 + 0.16 * spike * v ** 3)
            rx = 0.15 + 0.15 * v ** 1.5 - inset
            ry = 0.13 + 0.12 * v ** 1.5 - inset
            return (cc.x + rx * math.sin(lon), cc.y - ry * math.cos(lon) + 0.13 * v * v, cc.z + z)
        return fn

    def collar_in(u, v):
        lon = math.radians(72 + 216 * u)
        return (-math.sin(lon), math.cos(lon), 0)

    solid_grid("collar", C, collar_fn(), 14, 4, wool, 0.014, u_rng=(0, 1), axis=collar_in)
    solid_grid("collar_lining", C, collar_fn(0.016), 14, 4, silk, 0.006, u_rng=(0, 1), axis=collar_in)
    cf = collar_fn(-0.004)
    K.loft("collar_piping", C, [cf(i / 20, 1.0) for i in range(21)], [0.008] * 21, gilt, segs=4)
    for k, u in enumerate((0.16, 0.31, 0.5, 0.69, 0.84)):
        cfi = collar_fn(0.02)
        top = Vector(cfi(u, 1.0))
        tipv = top + (top - Vector(cfi(u, 0.85))).normalized() * 0.03
        K.horn(f"collar_rib{k}", C, [cfi(u, 0.12), cfi(u, 0.55), tuple(top), tuple(tipv)], 0.011, 0.002, antler, segs=4, n=2)

    # ------------------------------------------------------------------ cape down the back with a hex sigil
    fn = cloth_fn(0.34, 0.66, 1.22, cup=0.09, folds=2.5, depth=0.03, rag=0.25, seed=21, nu=10)
    js, tip = hanging("cape", C, (0, 0.165, 0.29), (-8, 0, 180), fn, (0, 0.25, 0.5, 0.75, 1.0), wool, nu=10,
                      nvs=[2, 2, 2, 2], thick=0.014, trims=[("left", 0.022), ("right", 0.022)], gilt=gilt)
    P = Vector(fn(0, 0.14))
    ring("cape_sigil", js[0], (P.x, P.y - 0.008, P.z), 0.075, 0.075, 0.005, rune, n=20, plane="xz")
    for q in range(3):
        a = math.pi / 2 + q * 2 * math.pi / 3
        b = a + 2 * math.pi / 3
        pa = Vector((0.075 * math.cos(a), 0, 0.075 * math.sin(a)))
        pb = Vector((0.075 * math.cos(b), 0, 0.075 * math.sin(b)))
        m = (pa + pb) / 2
        sb.box(f"cape_tri{q}", js[0], size=((pb - pa).length, 0.004, 0.006), loc=(P.x + m.x, P.y - 0.009, P.z + m.z),
               rot=(0, -math.degrees(math.atan2((pb - pa).z, (pb - pa).x)), 0), material=rune, bevel=0.0)
    chains["cape"] = (js, tip)

    # ------------------------------------------------------------------ arms: bell sleeves, drapes, long hands
    chains["sleeve"] = []
    for s in SIDES:
        A_, Fo, Ha = R.arm[s], R.fore[s], R.hand[s]
        n = sname(s)
        K.loft(f"upper_{n}", A_, [(0, 0, 0.07), (0, 0, -0.12), (0, 0, -0.31)], [0.088, 0.082, 0.076], robe, segs=10,
               profile=lambda u, v: 1.0 + 0.08 * math.sin(u * 2 * math.pi * 4) * v)
        K.loft(f"forearm_{n}", Fo, [(0, 0, 0.02), (0, 0, -0.29)], [0.038, 0.03], skin, segs=8)
        sl = [(0, 0, 0.05), (0, 0.0, -0.08), (0, 0.015, -0.19), (0, 0.035, -0.29)]
        K.loft(f"sleeve_{n}", Fo, sl, [0.072, 0.082, 0.098, 0.118], robe, segs=12, caps=(False, False),
               profile=lambda u, v: 1.0 + 0.09 * math.sin(u * 2 * math.pi * 4) * v)
        K.loft(f"sleeve_in_{n}", Fo, [(x, y, z + 0.006) for x, y, z in sl], [0.064, 0.074, 0.088, 0.106], silk, segs=12,
               caps=(False, False))
        ring(f"cuff_{n}", Fo, (0, 0.035, -0.288), 0.12, 0.12, 0.0065, gilt, n=14, segs=4)
        # trailing drape hanging from the back of the sleeve
        dfn = cloth_fn(0.17, 0.02, 0.46, cup=0.06, folds=1.0, depth=0.015, seed=31 + s, nu=4, wpow=1.4)
        js, tip = hanging(f"sleeve_drape_{n}", Fo, (0, 0.085, -0.06), (0, 0, 180), dfn, (0, 0.5, 1.0), robe, nu=4,
                          nvs=[2, 2], thick=0.01, trims=[("left", 0.016), ("right", 0.016)], gilt=gilt)
        chains["sleeve"].append((js, tip))
        K.claw_hand(f"hand_{n}", Ha, skin, claw, size=1.12, claw_len=0.05, curl=24, bony=True, spread=1.15)
        sb.box(f"hand_rune_{n}", Ha, size=(0.024, 0.004, 0.024), loc=(0, 0.022, -0.06), rot=(0, 45, 0), material=rune, bevel=0.0)

    # hexfire sigil above the right palm: two counter-spinning rings, hexagram, glyphs, flare
    Hr = R.hand[-1]
    sig = sb.empty("sigil", Hr, loc=(0, -0.13, -0.08))
    ring("sigil_ring", sig, (0, 0, 0), 0.085, 0.085, 0.0055, hex_, n=24, plane="xz")
    for q in range(6):
        a = math.pi / 2 + q * 2 * math.pi / 3 + (math.pi if q >= 3 else 0)
        b = a + 2 * math.pi / 3
        pa = Vector((0.083 * math.cos(a), 0, 0.083 * math.sin(a)))
        pb = Vector((0.083 * math.cos(b), 0, 0.083 * math.sin(b)))
        m = (pa + pb) / 2
        sb.box(f"sigil_hex{q}", sig, size=((pb - pa).length, 0.003, 0.005), loc=tuple(m),
               rot=(0, -math.degrees(math.atan2((pb - pa).z, (pb - pa).x)), 0), material=hex_, bevel=0.0)
    sb.sphere("sigil_core", sig, 0.026, material=hex_, segments=10, rings=6)
    sig_o = sb.empty("sigil_outer", sig)
    ring("sigil_ring2", sig_o, (0, 0, 0), 0.125, 0.125, 0.004, rune, n=28, plane="xz")
    for q in range(6):
        a = q * math.pi / 3
        sb.box(f"sigil_glyph{q}", sig_o, size=(0.022, 0.003, 0.03), loc=(0.145 * math.cos(a), 0, 0.145 * math.sin(a)),
               rot=(0, -math.degrees(a), 0), material=rune, bevel=0.0)
    sig_f = sb.empty("sigil_flare", sig)
    sb.sphere("sigil_flare_core", sig_f, 0.07, material=hex_, segments=10, rings=6)
    for q in range(8):
        a = q * math.pi / 4
        sb.box(f"sigil_ray{q}", sig_f, size=(0.26 if q % 2 else 0.16, 0.006, 0.012),
               loc=(0.13 * math.cos(a) * (1 if q % 2 else 0.62), 0, 0.13 * math.sin(a) * (1 if q % 2 else 0.62)),
               rot=(0, -math.degrees(a), 0), material=hex_, bevel=0.0)
    sig_f.scale = (0.01, 0.01, 0.01)
    # small binding sigil at the left palm
    Hl = R.hand[1]
    sigl = sb.empty("sigil_L", Hl, loc=(0, -0.1, -0.1))
    ring("sigil_L_ring", sigl, (0, 0, 0), 0.055, 0.055, 0.004, rune, n=18, plane="xz")
    for q in range(3):
        a = q * 2 * math.pi / 3
        sb.box(f"sigil_L_glyph{q}", sigl, size=(0.018, 0.003, 0.024), loc=(0.07 * math.cos(a), 0, 0.07 * math.sin(a)),
               rot=(0, -math.degrees(a), 0), material=rune, bevel=0.0)

    # ------------------------------------------------------------------ head: gaunt face, bone mask, antler crown
    K.loft("neck_m", R.neck, [(0, 0, -0.05), (0, 0, 0.11)], [0.048, 0.042], skin, segs=8)
    Hd = R.head
    K.loft("skull", Hd, [(0, 0.02, 0.0), (0, -0.02, 0.05), (0, -0.025, 0.12), (0, -0.005, 0.2), (0, 0.02, 0.245)],
           [(0.034, 0.034), (0.048, 0.055), (0.068, 0.08), (0.078, 0.086), (0.045, 0.045)], skin, segs=10, subdiv=1)
    K.loft("jaw", Hd, [(0, -0.03, 0.09), (0, -0.07, 0.04), (0, -0.088, 0.0)], [(0.045, 0.03), (0.03, 0.022), (0.012, 0.012)],
           skin, segs=8)
    sb.box("mouth", Hd, size=(0.036, 0.01, 0.005), loc=(0, -0.08, 0.05), rot=(-20, 0, 0), material=shadow, bevel=0.0)
    K.shell("mask", Hd, (0.074, 0.07, 0.075), lat=(-28, 58), lon=(-78, 78), segs=(10, 4), thick=0.008, material=mask_m,
            loc=(0, -0.03, 0.14))
    K.horn("mask_ridge", Hd, [(0, -0.1, 0.2), (0, -0.108, 0.15), (0, -0.104, 0.1)], 0.01, 0.004, mask_m, segs=5, n=2)
    for s in SIDES:
        n = sname(s)
        sb.sphere(f"socket_{n}", Hd, 0.018, loc=(s * 0.03, -0.094, 0.14), rot=(0, 0, s * 15), scale=(1.3, 0.5, 0.75),
                  material=shadow, segments=8, rings=5)
        sb.sphere(f"eye_{n}", Hd, 0.0095, loc=(s * 0.031, -0.1, 0.141), rot=(0, s * 18, s * 15), scale=(1.5, 0.45, 0.5),
                  material=eyes, segments=8, rings=4)
        K.horn(f"brow_{n}", Hd, [(s * 0.018, -0.1, 0.165), (s * 0.055, -0.09, 0.185), (s * 0.08, -0.06, 0.22)], 0.008, 0.002,
               mask_m, segs=4, n=2)
        sb.sphere(f"cheek_{n}", Hd, 0.022, loc=(s * 0.045, -0.07, 0.085), scale=(0.7, 1.0, 1.1), material=skin, segments=8, rings=5)
    for k in range(5):   # bony chin spines like a beard
        x = (k - 2) * 0.015
        K.horn(f"chin_spike{k}", Hd, [(x, -0.08, 0.02), (x * 1.3, -0.09, -0.04), (x * 1.5, -0.08, -0.11 + 0.02 * abs(k - 2))],
               0.008, 0.0015, antler, segs=4, n=2)
    K.shell("cowl", Hd, (0.11, 0.115, 0.16), lat=(-35, 88), lon=(95, 265), segs=(10, 5), thick=0.012, material=wool,
            loc=(0, 0.02, 0.12), flare=0.2)
    # crown: gilt circlet, small spikes, hex gem, branching antlers
    ring("circlet", Hd, (0, -0.005, 0.195), 0.086, 0.095, None, gilt, n=20, hh=(0.012, 0.005), segs=4)
    for k in range(5):
        a = math.radians(-50 + k * 25)
        p = (math.sin(a) * 0.09, -math.cos(a) * 0.1 - 0.005, 0.2)
        K.horn(f"circlet_spike{k}", Hd, [p, (p[0] * 1.05, p[1] * 1.05, 0.25 + (0.02 if k == 2 else 0))], 0.008, 0.001, gilt,
               segs=4, n=1)
    sb.sphere("circlet_gem", Hd, 0.016, loc=(0, -0.106, 0.205), scale=(1, 0.5, 1.4), material=hex_, segments=8, rings=6)
    chains["charm"] = []
    # Antler crown scale: full size so the crown reads as Morvane's silhouette from the high game
    # camera (characters-polish; was 0.78).
    sc = 1.0
    for s in SIDES:
        n = sname(s)

        def P(x, y, z):
            return (s * x * sc, y * sc, z * sc)
        beam = [P(0.07, 0.0, 0.2), P(0.12, 0.01, 0.27), P(0.2, 0.04, 0.35), P(0.26, 0.08, 0.45), P(0.28, 0.13, 0.55),
                P(0.26, 0.19, 0.63)]
        K.horn(f"antler_{n}", Hd, beam, 0.024, 0.005, antler, segs=6, n=3, ridges=0.08)
        tines = [
            [P(0.11, 0.0, 0.26), P(0.13, -0.08, 0.31), P(0.12, -0.11, 0.37)],
            [P(0.2, 0.04, 0.35), P(0.3, -0.02, 0.39), P(0.36, -0.03, 0.46)],
            [P(0.3, -0.02, 0.39), P(0.33, -0.08, 0.43), P(0.33, -0.1, 0.47)],
            [P(0.26, 0.08, 0.45), P(0.21, 0.04, 0.54), P(0.19, 0.03, 0.6)],
            [P(0.28, 0.13, 0.55), P(0.37, 0.14, 0.6), P(0.41, 0.16, 0.67)],
            [P(0.37, 0.14, 0.6), P(0.38, 0.2, 0.64)],
        ]
        for i, tn in enumerate(tines):
            K.horn(f"tine_{n}{i}", Hd, tn, 0.014 if i < 5 else 0.009, 0.002, antler, segs=4, n=2)
        # hexfire kindled on the crown's highest tines: violet points of light that read from above
        for i in (1, 4):
            sb.sphere(f"tine_flame_{n}{i}", Hd, 0.016, loc=tines[i][-1], scale=(1, 1, 1.6), material=hex_,
                      segments=8, rings=5)
        # bone charm dangling from the second tine
        c0 = sb.empty(f"charm_{n}0", Hd, loc=P(0.3, -0.02, 0.385))
        K.loft(f"charm_cord_{n}", c0, [(0, 0, 0), (0, 0, -0.08)], [0.004, 0.004], cord, segs=4)
        c1 = sb.empty(f"charm_{n}1", c0, loc=(0, 0, -0.08))
        K.horn(f"charm_fang_{n}", c1, [(0, 0, 0.0), (0, -0.006, -0.03), (0, 0, -0.055)], 0.009, 0.001, bonec, segs=5, n=2)
        sb.sphere(f"charm_bead_{n}", c1, 0.009, loc=(0, 0, 0.004), material=hex_, segments=6, rings=4)
        chains["charm"].append(([c0, c1], Vector((0, 0, -0.055))))

    # ------------------------------------------------------------------ the grimoire (floats at his left)
    G = sb.empty("grimoire", R.root, loc=(0.54, -0.22, 1.3), rot=(35, 0, -20))
    GB = sb.empty("book", G)        # unanimated scale holder (keeps the Godot light node unscaled)
    GB.scale = (1.2, 1.2, 1.2)
    halves = {}
    page_tops = {}
    for s in SIDES:
        n = sname(s)
        half = sb.empty(f"book_half_{n}", GB, rot=(0, -s * 12, 0))
        halves[s] = half
        sb.box(f"cover_{n}", half, size=(0.245, 0.335, 0.02), loc=(s * 0.124, 0, -0.01), material=book_m, bevel=0.006)
        for y in (-0.15, 0.15):
            sb.box(f"corner_{n}{y}", half, size=(0.045, 0.045, 0.026), loc=(s * 0.228, y, -0.008), rot=(0, 0, 45 if y > 0 else -45),
                   material=gilt, bevel=0.0)
        # outer cover: gilt frame and a glowing hex eye
        for (sx, sy, x, y) in ((0.19, 0.012, s * 0.125, 0.135), (0.19, 0.012, s * 0.125, -0.135),
                               (0.012, 0.27, s * 0.03, 0.0), (0.012, 0.27, s * 0.22, 0.0)):
            sb.box(f"cover_frame_{n}{x:.2f}{y:.2f}", half, size=(sx, sy, 0.006), loc=(x, y, -0.021), material=gilt, bevel=0.0)
        sb.cylinder(f"cover_boss_{n}", half, r1=0.04, depth=0.008, loc=(s * 0.125, 0, -0.022), rot=(180, 0, 0), material=gilt,
                    segments=6, bevel=0.0)
        sb.sphere(f"cover_eye_{n}", half, 0.02, loc=(s * 0.125, 0, -0.03), scale=(1, 1.4, 0.45), material=hex_, segments=8, rings=5)
        top = page_block(f"pages_{n}", half, s, 0.215, 0.305, 0.034, page_m)
        page_tops[s] = top
        # glowing script lines + a circle diagram, following the page curl
        for k in range(6):
            u = 0.25 + 0.6 * ((k * 0.37) % 1.0)
            y = -0.12 + k * 0.048
            if s > 0 and -0.06 < y < 0.06:
                continue
            u0, u1 = 0.18, 0.86 - 0.12 * (k % 2)
            x0, x1 = 0.006 + 0.215 * u0, 0.006 + 0.215 * u1
            z0, z1 = top(u0), top(u1)
            sb.box(f"script_{n}{k}", half, size=(math.hypot(x1 - x0, z1 - z0), 0.009, 0.002),
                   loc=(s * (x0 + x1) / 2, y, (z0 + z1) / 2 + 0.002),
                   rot=(0, s * -math.degrees(math.atan2(z1 - z0, x1 - x0)), 0), material=rune, bevel=0.0)
        if s > 0:
            zc = top(0.55) + 0.003
            ring("page_circle", half, (s * (0.006 + 0.215 * 0.55), 0, zc), 0.06, 0.06, 0.003, rune, n=16, segs=3)
            for q in range(3):
                a = q * 2 * math.pi / 3 + 0.3
                sb.box(f"page_glyph{q}", half, size=(0.02, 0.02, 0.002),
                       loc=(0.124 + 0.035 * math.cos(a), 0.035 * math.sin(a), zc), rot=(0, 0, 45), material=rune, bevel=0.0)
    K.loft("book_spine", GB, [(0, -0.168, -0.014), (0, 0.168, -0.014)], [(0.024, 0.02), (0.024, 0.02)], book_m, segs=8)
    for y in (-0.1, 0.0, 0.1):
        K.loft(f"spine_band{y}", GB, [(0, y - 0.006, -0.014), (0, y + 0.006, -0.014)], [0.027, 0.027], gilt, segs=8)
    # clasp strap hanging off the right cover's fore-edge
    cl0 = sb.empty("clasp0", halves[-1], loc=(-0.248, 0.0, -0.012))
    sb.box("clasp_strap0", cl0, size=(0.012, 0.04, 0.075), loc=(0, 0, -0.035), material=book_m, bevel=0.0)
    cl1 = sb.empty("clasp1", cl0, loc=(0, 0, -0.07))
    sb.box("clasp_strap1", cl1, size=(0.012, 0.04, 0.05), loc=(0, 0, -0.022), material=book_m, bevel=0.0)
    sb.box("clasp_buckle", cl1, size=(0.016, 0.05, 0.03), loc=(0, 0, -0.05), material=gilt, bevel=0.004)
    chains["clasp"] = ([cl0, cl1], Vector((0, 0, -0.065)))
    # silk ribbon markers trailing from the top of the spine
    chains["ribbon"] = []
    for q, x in enumerate((0.02, -0.025)):
        rfn = cloth_fn(0.014, 0.014, 0.24 - q * 0.05, point=0.15, seed=q, nu=1)
        js, tip = hanging(f"ribbon{q}_", GB, (x, 0.165, 0.01), (90, 0, 0), rfn, (0, 0.33, 0.66, 1.0), silk if q == 0 else gilt,
                          nu=1, nvs=[1, 1, 1], thick=0.003)
        chains["ribbon"].append((js, tip))
    # orbiting glyph shards, drifting loose leaves, flare burst (hidden: scale 0.01)
    gly = sb.empty("book_glyphs", GB, loc=(0, 0, 0.13))
    for q in range(4):
        a = q * math.pi / 2
        sb.box(f"orbit_glyph{q}", gly, size=(0.035, 0.005, 0.055), loc=(0.2 * math.cos(a), 0.2 * math.sin(a), 0.03 * (q % 2)),
               rot=(0, 45, math.degrees(a) + 90), material=rune, bevel=0.0)
    leaves = sb.empty("book_leaves", GB, loc=(0, 0, 0.06))
    for q in range(2):
        a = q * math.pi + 0.6
        sb.box(f"leaf{q}", leaves, size=(0.075, 0.1, 0.0025), loc=(0.3 * math.cos(a), 0.3 * math.sin(a), 0.04 - q * 0.08),
               rot=(15 - q * 30, 20, math.degrees(a)), material=page_m, bevel=0.0)
        sb.box(f"leaf_script{q}", leaves, size=(0.045, 0.006, 0.001),
               loc=(0.3 * math.cos(a), 0.3 * math.sin(a), 0.0425 - q * 0.08), rot=(15 - q * 30, 20, math.degrees(a)),
               material=rune, bevel=0.0)
    flare = sb.empty("book_flare", GB, loc=(0, 0, 0.07))
    sb.sphere("flare_core", flare, 0.08, material=hex_, segments=10, rings=6)
    for q in range(10):
        a = q * math.pi / 5
        L = 0.34 if q % 2 else 0.22
        sb.box(f"flare_ray{q}", flare, size=(L, 0.012, 0.006), loc=(L * 0.55 * math.cos(a), L * 0.55 * math.sin(a), 0),
               rot=(0, 0, math.degrees(a)), material=hex_, bevel=0.0)
    ring("flare_ring", flare, (0, 0, 0), 0.26, 0.26, 0.006, hex_, n=24, segs=3)
    flare.scale = (0.01, 0.01, 0.01)

    animate(R, G, halves, gly, leaves, flare, sig, sig_o, sig_f, sigl, chains)
    K.finalize(R.root)
    return R.root


# =============================================================================== animation

def leg_ik(fwd, dz, L1=0.47, L2=0.45):
    """Thigh forward angle and knee flex (degrees) that put the ankle at (fwd, dz) from the hip joint."""
    D = min(max(math.hypot(fwd, dz), 0.25), L1 + L2 - 1e-4)
    phi = math.atan2(fwd, -dz)
    alpha = math.acos(max(-1.0, min(1.0, (L1 * L1 + D * D - L2 * L2) / (2 * L1 * D))))
    knee = math.pi - math.acos(max(-1.0, min(1.0, (L1 * L1 + L2 * L2 - D * D) / (2 * L1 * L2))))
    return math.degrees(phi + alpha), math.degrees(knee)


def smooth(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


def animate(R, G, halves, gly, leaves, flare, sig, sig_o, sig_f, sigl, chains):
    ALL = [j for j in A.joints(R.root, include_root=False) if j.name != "look"]
    tL, tR = R.thigh[1], R.thigh[-1]
    sL, sR = R.shin[1], R.shin[-1]
    fL, fR = R.foot[1], R.foot[-1]
    aL, aR = R.arm[1], R.arm[-1]
    oL, oR = R.fore[1], R.fore[-1]
    hL, hR = R.hand[1], R.hand[-1]
    hips, spine, chest, neck, head, body = R.hips, R.spine, R.chest, R.neck, R.head, R.body
    hbL, hbR = halves[1], halves[-1]
    BIG = (100, 100, 100)      # flare joints rest at scale 0.01
    HIDE = (1, 1, 1)

    def thigh_fwd(c, j, f):
        return -c.eval(j, "rot", f)[0]

    def push_robes(c, k_front=0.55, k_back=0.45):
        """Robe/coat panels are pushed out by the thighs (offset from each leg's own swing)."""
        for group, kf in (("robe", 1.0), ("coat", 0.7)):
            for js, tip, a in chains[group]:
                ar = math.radians(a)
                wl = min(1.0, max(0.0, 0.5 + math.sin(ar) * 1.2))
                wf, wb = max(0.0, math.cos(ar)), max(0.0, -math.cos(ar))

                def fn(f, wl=wl, wf=wf, wb=wb, kf=kf):
                    t_l, t_r = thigh_fwd(c, tL, f), thigh_fwd(c, tR, f)
                    fw = wl * max(0.0, t_l) + (1 - wl) * max(0.0, t_r)
                    bk = wl * max(0.0, -t_l) + (1 - wl) * max(0.0, -t_r)
                    return (-(wf * fw * k_front + wb * bk * k_back) * kf, 0, 0)
                c.add(js[0], fn, "rot")
        js, tip = chains["tabard"]
        c.add(js[0], lambda f: (-0.45 * max(0.0, thigh_fwd(c, tL, f), thigh_fwd(c, tR, f)), 0, 0), "rot")

    def secondary(c, wind=None, floor=None, soft=1.0):
        w2 = None if wind is None else tuple(x * 0.6 for x in wind)
        for js, tip, a in chains["robe"]:
            A.follow_through(c, js, freq=1.6 * soft, damping=0.2, gravity=7.0, falloff=0.85, tip=tip, wind=w2, floor=floor,
                             max_angle=60)
        for js, tip, a in chains["coat"]:
            A.follow_through(c, js, freq=1.25 * soft, damping=0.12, gravity=7.0, falloff=0.85, tip=tip, wind=w2, floor=floor,
                             max_angle=75)
        js, tip = chains["cape"]
        A.follow_through(c, js, freq=1.2 * soft, damping=0.12, gravity=7.0, falloff=0.88, tip=tip, wind=wind, floor=floor)
        js, tip = chains["tabard"]
        A.follow_through(c, js, freq=1.9, damping=0.14, gravity=7.0, falloff=0.85, tip=tip, wind=w2, floor=floor)
        for js, tip in chains["stole"]:
            A.follow_through(c, js, freq=1.8, damping=0.12, gravity=7.0, falloff=0.85, tip=tip, wind=wind, floor=floor)
        for js, tip in chains["sleeve"]:
            A.follow_through(c, js, freq=1.7, damping=0.12, gravity=7.0, falloff=0.85, tip=tip, wind=wind, floor=floor)
        for js, tip in chains["talisman"]:
            A.follow_through(c, js, freq=2.4, damping=0.07, gravity=8.0, falloff=0.9, tip=tip, wind=w2, floor=floor)
        for js, tip in chains["charm"]:
            A.follow_through(c, js, freq=2.6, damping=0.08, gravity=8.0, falloff=0.9, tip=tip, wind=w2, floor=floor)
        for js, tip in chains["ribbon"]:
            A.follow_through(c, js, freq=2.0, damping=0.1, gravity=6.0, falloff=0.85, tip=tip, wind=wind, floor=floor)
        js, tip = chains["clasp"]
        A.follow_through(c, js, freq=2.4, damping=0.1, gravity=8.0, falloff=0.9, tip=tip, floor=floor)

    def props_rest(c):
        c.key(flare, 0, scale=HIDE)
        c.key(sig_f, 0, scale=HIDE)

    # ================================================================== idle: brooding, grimoire hover
    c = A.Clip("idle", 90, joints=ALL)
    props_rest(c)
    A.breathe(c, chest, amp=2.4, rise=0.008, swell=0.012, cycles=2, shoulders=[aL, aR], head=head)
    c.add(hips, lambda f: (0.012 * A.wave(c, f), 0, -0.006 * abs(A.wave(c, f))), "loc")
    c.add(hips, lambda f: (0, 1.5 * A.wave(c, f), 0), "rot")
    c.add(spine, lambda f: (1.2 * A.wave(c, f, 1, 0.3), -1.0 * A.wave(c, f), 0), "rot")
    for s, (t, sh) in ((1, (tL, sL)), (-1, (tR, sR))):
        c.add(t, lambda f, s=s: (0, -s * 1.5 * A.wave(c, f), 0), "rot")
    A.noise(c, head, rot=(3, 5, 2), freq=0.35, seed=1)
    A.noise(c, aR, rot=(2, 1, 2), freq=0.3, seed=3)
    A.noise(c, oR, rot=(3, 0, 2), freq=0.4, seed=4)
    A.noise(c, aL, rot=(2, 2, 2), freq=0.3, seed=5)
    c.add(hL, lambda f: (6 * A.wave(c, f, 1, 0.1), 0, 3 * A.wave(c, f, 2)), "rot")   # fingers coax the book
    c.add(G, lambda f: (0.015 * A.wave(c, f, 1, 0.25), 0.012 * A.wave(c, f, 2), 0.045 * A.wave(c, f, 2)), "loc")
    c.add(G, lambda f: (4 * A.wave(c, f, 2, 0.15), 3 * A.wave(c, f, 1), 7 * A.wave(c, f, 1, 0.4)), "rot")
    for s, hb in ((1, hbL), (-1, hbR)):
        c.add(hb, lambda f, s=s: (0, -s * 5 * A.wave(c, f, 2, 0.3), 0), "rot")      # pages breathe
    c.add(gly, lambda f: (0, 0, 360.0 * f / c.frames), "rot")
    c.add(gly, lambda f: (0, 0, 0.015 * A.wave(c, f, 3)), "loc")
    c.add(leaves, lambda f: (0, 0, -360.0 * f / c.frames), "rot")
    c.add(leaves, lambda f: (0, 0, 0.03 * A.wave(c, f, 1, 0.5)), "loc")
    c.add(sig, lambda f: (0, 360.0 * f / c.frames, 0), "rot")
    c.add(sig, lambda f: (0, 0.01 * A.wave(c, f, 2), 0), "loc")
    c.add(sig_o, lambda f: (0, -720.0 * f / c.frames, 0), "rot")
    c.add(sigl, lambda f: (0, -360.0 * f / c.frames, 0), "rot")
    secondary(c)
    c.bake()

    # ================================================================== walk: crouched gliding run, IK feet planted
    F = WALK_FRAMES
    T = F / 30.0
    S = CONTACT
    d = RUN_SPEED * S * T
    h0, bob, lift, kick = -0.115, 0.03, 0.3, 0.16
    thigh_z0 = R.hip_h - 0.03
    ankle_z0 = 0.05

    def hz(p):
        q = (p % 0.5) / 0.5
        return h0 - bob * math.cos(2 * math.pi * (q - S))

    def foot_path(p):
        """(forward, lift, toe-down pitch) of one ankle at leg phase p (contact at 0)."""
        if p < S:
            u = p / S
            x = d / 2 - d * u
            pitch = -12 * (1 - u / 0.3) if u < 0.3 else (0.0 if u < 0.7 else 30 * ((u - 0.7) / 0.3) ** 2)
            z = 0.13 * math.sin(math.radians(max(pitch, 0.0)))
            return x, z, pitch
        u = (p - S) / (1 - S)
        x = -d / 2 + d * (0.5 - 0.5 * math.cos(math.pi * u)) - kick * math.sin(math.pi * min(1.0, u * 1.5)) * (1 - u)
        z = 0.065 * (1 - u) ** 2 + lift * math.sin(math.pi * u) ** 1.3 * (1 - 0.35 * u)
        pitch = 30 + 15 * (u / 0.3) if u < 0.3 else 45 - 57 * smooth((u - 0.3) / 0.7)
        return x, z, pitch

    def leg(f, side):
        p = ((f / F) + (0.0 if side > 0 else 0.5)) % 1.0
        x, z, pitch = foot_path(p)
        tz = thigh_z0 + hz(f / F)
        t, k = leg_ik(x, (ankle_z0 + z) - tz)
        return t, k, pitch

    yaw, twist = 7.0, 10.0
    c = A.Clip("walk", F, joints=ALL)
    props_rest(c)
    for side, (th, sh, ft) in ((1, (tL, sL, fL)), (-1, (tR, sR, fR))):
        c.add(th, lambda f, side=side: (-leg(f, side)[0], 0, yaw * math.cos(2 * math.pi * f / F)), "rot")
        c.add(sh, lambda f, side=side: (leg(f, side)[1], 0, 0), "rot")
        c.add(ft, lambda f, side=side: (leg(f, side)[2] + leg(f, side)[0] - leg(f, side)[1], 0, 0), "rot")
    c.add(hips, lambda f: (0, 0, hz(f / F)), "loc")
    c.add(hips, lambda f: (0, -2.5 * math.sin(2 * math.pi * f / F), -yaw * math.cos(2 * math.pi * f / F)), "rot")
    c.add(spine, lambda f: (13 + 2.5 * math.cos(4 * math.pi * (f / F - 0.1)), 2.0 * math.sin(2 * math.pi * f / F), 0), "rot")
    c.add(chest, lambda f: (2, 0, (yaw + twist) * math.cos(2 * math.pi * (f / F - 0.05))), "rot")
    c.add(head, lambda f: (-9 - 1.5 * math.cos(4 * math.pi * (f / F - 0.15)), 0, -twist * 0.7 * math.cos(2 * math.pi * (f / F - 0.1))), "rot")
    # arms: counter-swing, right hand keeps the sigil up, left hand trails toward the book
    c.add(aR, lambda f: (12 - 24 * math.cos(2 * math.pi * (f / F - 0.06)), 0, 6), "rot")
    c.add(oR, lambda f: (8 - 10 * max(0.0, math.cos(2 * math.pi * (f / F - 0.12))), 0, 0), "rot")
    c.add(aL, lambda f: (16 + 22 * math.cos(2 * math.pi * (f / F - 0.06)), 0, -4), "rot")
    c.add(oL, lambda f: (-6 - 12 * max(0.0, -math.cos(2 * math.pi * (f / F - 0.12))), 0, 0), "rot")
    c.add(hL, lambda f: (18, 0, 0), "rot")
    # grimoire trails behind-left, bobbing a beat after the body; leaves stream, glyphs tilt
    c.add(G, lambda f: (0.04, 0.22, -0.06 + 0.035 * math.sin(4 * math.pi * (f / F - 0.2))), "loc")
    c.add(G, lambda f: (18 + 4 * math.sin(4 * math.pi * (f / F - 0.3)), 6 * math.sin(2 * math.pi * f / F), 8), "rot")
    for s, hb in ((1, hbL), (-1, hbR)):
        c.add(hb, lambda f, s=s: (0, -s * (10 + 6 * math.sin(4 * math.pi * (f / F - 0.25 - 0.05 * s))), 0), "rot")
    c.add(leaves, lambda f: (0, 0, 0.02 * math.sin(4 * math.pi * f / F)), "loc")
    c.add(leaves, lambda f: (0, 0, 40), "rot")
    c.add(gly, lambda f: (-15, 0, 30), "rot")
    c.add(sig, lambda f: (0, 360.0 * f / F, 0), "rot")
    c.add(sig_o, lambda f: (0, -360.0 * f / F, 0), "rot")
    push_robes(c)
    secondary(c, wind=(0, 6.0, 0))
    c.bake()
    print(f"MORVANE walk native speed = {d / (S * T):.2f} m/s (cycle {F} frames, contact stride {d:.2f} m)")

    # ================================================================== attack: channelled hex
    c = A.Clip("attack", 36, joints=ALL)
    antic = {aR: {"rot": (34, -10, -38)}, oR: {"rot": (-30, 0, 0)}, hR: {"rot": (-10, 0, 0)},
             aL: {"rot": (-40, -15, 0)}, oL: {"rot": (-25, 0, 10)}, hL: {"rot": (-20, 0, 0)},
             spine: {"rot": (-8, 0, 0)}, chest: {"rot": (-8, 0, -22)}, head: {"rot": (-10, 0, 14)},
             hips: {"loc": (0, 0.05, -0.04), "rot": (0, 0, -6)},
             tL: {"rot": (-10, 0, 0)}, sL: {"rot": (14, 0, 0)}, fL: {"rot": (-4, 0, 0)},
             tR: {"rot": (6, 0, 0)}, sR: {"rot": (12, 0, 0)}, fR: {"rot": (-18, 0, 0)}}
    strike = {aR: {"rot": (-58, -4, 10)}, oR: {"rot": (62, 0, -6)}, hR: {"rot": (-62, 0, 0)},
              aL: {"rot": (-55, -30, 0)}, oL: {"rot": (-10, 0, 20)}, hL: {"rot": (-30, 0, 0)},
              spine: {"rot": (16, 0, 0)}, chest: {"rot": (6, 0, 22)}, head: {"rot": (-6, 0, -12)},
              hips: {"loc": (0, -0.12, -0.1), "rot": (0, 0, 8)},
              tL: {"rot": (-34, 0, 0)}, sL: {"rot": (40, 0, 0)}, fL: {"rot": (-6, 0, 0)},
              tR: {"rot": (24, 0, 0)}, sR: {"rot": (24, 0, 0)}, fR: {"rot": (-44, 0, 0)}}
    follow = {j: {k: tuple(x * 0.9 for x in v) for k, v in dct.items()} for j, dct in strike.items()}
    ev = A.attack(c, {"antic": antic, "strike": strike, "follow": follow}, start=0, antic=11, antic_hold=5, strike=3,
                  hold=5, recover=12, overshoot=0.12, push=0.1)
    imp = ev["impact"]
    A.jitter(c, aR, rot=(1.5, 1.0, 1.5), start=9, end=imp)
    A.jitter(c, G, rot=(2, 2, 2), start=6, end=imp + 2)
    # grimoire rises in front-left, opens flat, glyphs spin up, flare at impact
    c.key(G, 0, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key(G, 11, loc=(-0.12, -0.06, 0.16), rot=(18, 0, 16), ease="sine_inout")
    c.key(G, imp - 1, loc=(-0.14, -0.08, 0.19), rot=(22, 0, 18), ease="quad_in")
    c.key(G, imp + 1, loc=(-0.16, -0.16, 0.2), rot=(32, 0, 22), ease="sine_out")
    c.key(G, imp + 6, loc=(-0.15, -0.12, 0.18), rot=(26, 0, 20), ease="quad_inout")
    c.key(G, 36, loc=(0, 0, 0), rot=(0, 0, 0))
    for s, hb in ((1, hbL), (-1, hbR)):
        c.key(hb, 0, rot=(0, 0, 0))
        c.key(hb, 11, rot=(0, s * 8, 0), ease="sine_inout")
        c.key(hb, imp, rot=(0, s * 14, 0), ease="back_out:2")
        c.key(hb, imp + 8, rot=(0, s * 10, 0))
        c.key(hb, 36, rot=(0, 0, 0))
    c.key(gly, 0, rot=(0, 0, 0), scale=(1, 1, 1))
    c.key(gly, imp, rot=(0, 0, 300), scale=(1.5, 1.5, 1.5), ease="expo_out")
    c.key(gly, imp + 6, rot=(0, 0, 420), scale=(1.25, 1.25, 1.25))
    c.key(gly, 36, rot=(0, 0, 540), scale=(1, 1, 1))
    c.key(leaves, 0, rot=(0, 0, 0), loc=(0, 0, 0))
    c.key(leaves, imp, rot=(0, 0, -200), loc=(0, 0, 0.08), ease="expo_out")
    c.key(leaves, 36, rot=(0, 0, -360), loc=(0, 0, 0))
    c.key(flare, 0, scale=HIDE, ease="constant")
    c.key(flare, imp - 1, scale=(40, 40, 40), ease="expo_out")
    c.key(flare, imp + 1, scale=BIG, ease="sine_in")
    c.key(flare, imp + 6, scale=(25, 25, 25), ease="constant")
    c.key(flare, imp + 7, scale=HIDE)
    c.key(sig_f, 0, scale=HIDE)
    c.key(sig_f, 14, scale=(35, 35, 35), ease="quad_in")
    c.key(sig_f, imp, scale=(130, 130, 130), ease="sine_out")
    c.key(sig_f, imp + 7, scale=(30, 30, 30), ease="constant")
    c.key(sig_f, imp + 8, scale=HIDE)
    c.key(sig, 0, rot=(0, 0, 0), scale=(1, 1, 1))
    c.key(sig, imp, rot=(0, 540, 0), scale=(1.7, 1.7, 1.7), ease="back_out:2")
    c.key(sig, 36, rot=(0, 720, 0), scale=(1, 1, 1))
    c.key(sig_o, 0, rot=(0, 0, 0))
    c.key(sig_o, 36, rot=(0, -720, 0))
    secondary(c)
    c.bake()
    print("MORVANE attack impact frame", imp)

    # ================================================================== hit
    c = A.Clip("hit", 18, joints=ALL)
    props_rest(c)
    A.hit_react(c, {hips: {"loc": (0, 0.07, -0.03)}, spine: {"rot": (-11, 0, 4)},
                    chest: {"rot": (-12, 4, 8), "scale": (1.03, 1.03, 0.97)}, head: {"rot": (-18, 0, -10)},
                    aR: {"rot": (-20, 0, 25)}, oR: {"rot": (-18, 0, 0)}, aL: {"rot": (-28, 0, -25)}, oL: {"rot": (-20, 0, 0)},
                    G: {"loc": (0.06, 0.12, -0.05), "rot": (24, 0, 18)}, hbL: {"rot": (0, -16, 0)}, hbR: {"rot": (0, 16, 0)}},
                start=0, rise=2, settle=13, wobble=1.0, stagger=0.8)
    A.hit_react(c, {tL: {"rot": (-6, 0, 0)}, sL: {"rot": (10, 0, 0)}, tR: {"rot": (-5, 0, 0)}, sR: {"rot": (9, 0, 0)},
                    fL: {"rot": (-4, 0, 0)}, fR: {"rot": (-4, 0, 0)}}, start=1, rise=2, settle=12, stagger=0)
    c.key(sig, 0, scale=(1, 1, 1), ease="constant")
    c.key(sig, 1, scale=(0.55, 0.55, 0.55), ease="sine_inout")
    c.key(sig, 12, scale=(1, 1, 1))
    c.add(gly, lambda f: (0, 0, 120 * smooth(f / 18)), "rot")
    secondary(c)
    c.bake()

    # ================================================================== death: crumple to the knees, prostrate; book falls
    c = A.Clip("death", 64, joints=ALL)
    props_rest(c)
    kneel = {hips: {"loc": (0, 0.06, -0.62)}, tL: {"rot": (-70, 0, 6)}, sL: {"rot": (150, 0, 0)}, fL: {"rot": (40, 0, 0)},
             tR: {"rot": (-62, 0, -6)}, sR: {"rot": (145, 0, 0)}, fR: {"rot": (38, 0, 0)},
             spine: {"rot": (14, 0, 0)}, chest: {"rot": (6, 0, 0)}, head: {"rot": (20, 0, 0)},
             aL: {"rot": (6, 0, -6)}, oL: {"rot": (40, 0, 14)}, aR: {"rot": (14, 0, 8)}, oR: {"rot": (60, 0, -6)}}
    slump = {hips: {"loc": (0, 0.1, -0.66), "rot": (18, 0, 0)}, spine: {"rot": (52, 0, 4)}, chest: {"rot": (24, 0, 0)},
             head: {"rot": (18, 0, 14)}, aL: {"rot": (-58, -12, -10)}, oL: {"rot": (52, 0, 18)}, hL: {"rot": (20, 0, 0)},
             aR: {"rot": (-50, 14, 10)}, oR: {"rot": (70, 0, -6)}, hR: {"rot": (25, 0, 0)}}
    for j, ch in kneel.items():
        for k_, v in ch.items():
            c.key(j, 0, **{k_: (0, 0, 0)}, ease="sine_out")
    c.pose(5, {spine: {"rot": (-12, 0, 5)}, chest: {"rot": (-8, 0, 4)}, head: {"rot": (-20, 0, 8)},
               hips: {"loc": (0, 0.05, -0.02)}, aR: {"rot": (-10, 0, 20)}, aL: {"rot": (-18, 0, -18)}}, ease="quad_in")
    c.pose(16, kneel, ease="quad_out")
    c.pose(19, {hips: {"loc": (0, 0.06, -0.6)}}, ease="quad_in")
    c.pose(21, {j: dict(ch) for j, ch in kneel.items() if j in (hips, spine, chest, head)}, ease="sine_inout")
    c.pose(24, {spine: {"rot": (20, 0, 2)}, head: {"rot": (26, 0, 6)}}, ease="quad_in")
    slump_all = {j: dict(kneel.get(j, {}), **ch) for j, ch in slump.items()}
    for j in kneel:
        if j not in slump_all:
            slump_all[j] = kneel[j]
    c.pose(32, slump_all, ease="quad_out")
    bounce = {spine: {"rot": (46, 0, 4)}, chest: {"rot": (20, 0, 0)}}
    c.pose(35, bounce, ease="quad_in")
    c.pose(38, {spine: slump[spine], chest: slump[chest]}, ease="back_out:2")
    c.pose(46, {aL: {"rot": (-64, -16, -14)}, aR: {"rot": (-56, 18, 14)}, head: {"rot": (20, 0, 18)}}, ease="constant")
    # grimoire: flickers, then drops (gravity), lands closed beside him, small bounce
    c.key(G, 0, loc=(0, 0, 0), rot=(0, 0, 0), ease="sine_out")
    c.key(G, 8, loc=(0.04, 0.02, 0.06), rot=(10, 0, -6), ease="quad_in")
    c.key(G, 26, loc=(0.16, -0.18, -1.24), rot=(-35, 88, 30), ease="quad_out")
    c.key(G, 29, loc=(0.17, -0.19, -1.18), rot=(-33, 80, 33), ease="quad_in")
    c.key(G, 32, loc=(0.18, -0.2, -1.24), rot=(-35, 88, 34), ease="constant")
    A.jitter(c, G, rot=(4, 4, 4), start=2, end=10, freq=12)
    for s, hb in ((1, hbL), (-1, hbR)):
        c.key(hb, 0, rot=(0, 0, 0))
        c.key(hb, 12, rot=(0, -s * 10, 0), ease="quad_in")
        c.key(hb, 26, rot=(0, -s * 78, 0), ease="bounce_out")
        c.key(hb, 34, rot=(0, -s * 77, 0), ease="constant")
    c.key(gly, 0, scale=(1, 1, 1), rot=(0, 0, 0))
    c.key(gly, 20, scale=(0.01, 0.01, 0.01), rot=(0, 0, 200), ease="constant")
    c.key(leaves, 0, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key(leaves, 50, loc=(0.0, 0.0, -1.2), rot=(30, 0, 160), ease="constant")
    c.key(sig, 0, scale=(1, 1, 1), rot=(0, 0, 0))
    c.key(sig, 6, scale=(1.3, 1.3, 1.3), rot=(0, 90, 0), ease="quad_in")
    c.key(sig, 18, scale=(0.01, 0.01, 0.01), rot=(0, 200, 0), ease="constant")
    c.key(sigl, 0, scale=(1, 1, 1))
    c.key(sigl, 16, scale=(0.01, 0.01, 0.01), ease="constant")
    secondary(c, floor=0.03)
    c.bake()

    # ================================================================== cheer: sinister laugh, grimoire raised
    c = A.Clip("cheer", 66, joints=ALL)
    props_rest(c)
    gather = {spine: {"rot": (16, 0, 0)}, chest: {"rot": (8, 0, 0)}, head: {"rot": (14, 0, 0)},
              hips: {"loc": (0, 0, -0.06)}, tL: {"rot": (-14, 0, 0)}, sL: {"rot": (26, 0, 0)}, fL: {"rot": (-12, 0, 0)},
              tR: {"rot": (-14, 0, 0)}, sR: {"rot": (26, 0, 0)}, fR: {"rot": (-12, 0, 0)},
              aR: {"rot": (6, 0, 16)}, oR: {"rot": (-20, 0, 0)}, aL: {"rot": (0, 0, -16)}, oL: {"rot": (-30, 0, 0)}}
    rise = {spine: {"rot": (-14, 0, 0)}, chest: {"rot": (-10, 0, 0)}, head: {"rot": (-24, 0, 0)},
            hips: {"loc": (0, 0, 0.02)}, tL: {"rot": (0, 0, 0)}, sL: {"rot": (0, 0, 0)}, fL: {"rot": (0, 0, 0)},
            tR: {"rot": (0, 0, 0)}, sR: {"rot": (0, 0, 0)}, fR: {"rot": (0, 0, 0)},
            aR: {"rot": (-20, 70, 0)}, oR: {"rot": (40, 0, 0)}, hR: {"rot": (-30, 0, 0)},
            aL: {"rot": (-40, -78, 0)}, oL: {"rot": (20, 0, 0)}, hL: {"rot": (-30, 0, 0)}}
    allj = list(dict.fromkeys(list(gather) + list(rise)))

    def full(p):
        return {j: {"rot": p.get(j, {}).get("rot", (0, 0, 0)), "loc": p.get(j, {}).get("loc", (0, 0, 0))} for j in allj}
    c.pose(0, full({}), ease="sine_inout")
    c.pose(14, full(gather), ease="sine_inout")
    c.pose(18, full({j: {k: tuple(x * 1.08 for x in v) for k, v in ch.items()} for j, ch in gather.items()}), ease="cubic_in")
    c.pose(25, full(rise), ease="back_out:1.6")
    c.pose(48, full({j: {k: tuple(x * 0.92 for x in v) for k, v in ch.items()} for j, ch in rise.items()}), ease="sine_inout")
    c.pose(66, full({}))
    # laugh: shoulders and head bounce in a low "heh-heh" rhythm while held
    lw = lambda f: smooth((f - 24) / 4) * (1 - smooth((f - 46) / 8))  # noqa: E731
    c.add(chest, lambda f: (3.5 * lw(f) * math.sin(2 * math.pi * f / 5.0), 0, 0), "rot")
    c.add(head, lambda f: (-4 * lw(f) * math.sin(2 * math.pi * (f - 1) / 5.0), 0, 2 * lw(f) * math.sin(math.pi * f / 9)), "rot")
    c.add(hips, lambda f: (0, 0, 0.01 * lw(f) * abs(math.sin(math.pi * f / 5.0))), "loc")
    A.jitter(c, aR, rot=(2, 2, 2), start=24, end=48)
    A.jitter(c, aL, rot=(2, 2, 2), start=24, end=48, seed=2)
    # grimoire: drawn up over his head, opens flat, flare and glyph storm
    c.key(G, 0, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key(G, 14, loc=(-0.06, 0.02, -0.08), rot=(10, 0, 6), ease="cubic_in")
    c.key(G, 26, loc=(-0.42, 0.1, 0.92), rot=(38, 0, 24), ease="back_out:1.4")
    c.key(G, 48, loc=(-0.4, 0.08, 0.88), rot=(36, 0, 30), ease="sine_inout")
    c.key(G, 66, loc=(0, 0, 0), rot=(0, 0, 0))
    c.add(G, lambda f: (0, 0, 0.03 * lw(f) * math.sin(2 * math.pi * f / 10)), "loc")
    for s, hb in ((1, hbL), (-1, hbR)):
        c.key(hb, 0, rot=(0, 0, 0))
        c.key(hb, 14, rot=(0, -s * 30, 0), ease="cubic_in")
        c.key(hb, 26, rot=(0, s * 14, 0), ease="back_out:2")
        c.key(hb, 48, rot=(0, s * 10, 0))
        c.key(hb, 66, rot=(0, 0, 0))
    c.key(gly, 0, rot=(0, 0, 0), scale=(1, 1, 1))
    c.key(gly, 26, rot=(0, 0, 240), scale=(1.9, 1.9, 1.9), ease="sine_out")
    c.key(gly, 48, rot=(0, 0, 600), scale=(1.7, 1.7, 1.7), ease="sine_inout")
    c.key(gly, 66, rot=(0, 0, 720), scale=(1, 1, 1))
    c.key(leaves, 0, rot=(0, 0, 0), loc=(0, 0, 0), scale=(1, 1, 1))
    c.key(leaves, 26, rot=(0, 0, -300), loc=(0, 0, 0.1), scale=(1.5, 1.5, 1.5), ease="sine_out")
    c.key(leaves, 66, rot=(0, 0, -720), loc=(0, 0, 0), scale=(1, 1, 1))
    c.key(flare, 0, scale=HIDE, ease="constant")
    c.key(flare, 24, scale=(30, 30, 30), ease="expo_out")
    c.key(flare, 28, scale=(115, 115, 115), ease="sine_inout")
    c.key(flare, 44, scale=(70, 70, 70), ease="sine_in")
    c.key(flare, 52, scale=(20, 20, 20), ease="constant")
    c.key(flare, 53, scale=HIDE)
    c.key(sig, 0, rot=(0, 0, 0), scale=(1, 1, 1))
    c.key(sig, 26, rot=(0, 400, 0), scale=(1.6, 1.6, 1.6), ease="back_out:2")
    c.key(sig, 48, rot=(0, 620, 0), scale=(1.5, 1.5, 1.5))
    c.key(sig, 66, rot=(0, 720, 0), scale=(1, 1, 1))
    c.key(sigl, 0, rot=(0, 0, 0), scale=(1, 1, 1))
    c.key(sigl, 26, rot=(0, -300, 0), scale=(1.8, 1.8, 1.8), ease="back_out:2")
    c.key(sigl, 66, rot=(0, -720, 0), scale=(1, 1, 1))
    c.key(sig_o, 0, rot=(0, 0, 0))
    c.key(sig_o, 66, rot=(0, -1080, 0))
    secondary(c)
    c.bake()
