"""Seraph Sentinel: rank-and-file of the Host. A tall knight in ivory plate with engraved gold
trim: layered pauldrons with gilt finials, a plackart and sunburst on the cuirass, a pleated
tabard front and back. The head is a smooth faceless porcelain mask traced with gold filigree,
a thin cold slit of light where eyes would be, a gold crest and temple wings, and a crisp
halo of light above. Wings folded tall behind the back (wrists arching over the head,
primaries hanging to the calves). A tall winged spear held upright, a kite shield with a sun.

Joints (L = +X side): body (ground pivot) > hips > thigh/shin/foot_L/R, tabard_f0/f1,
tabard_b0/b1, spine > chest > head > halo_mount > halo, arm/fore_L/R, hand_R (spear),
wing_L/R > wing_hand_L/R.
Anims: idle, walk (loop, 16 f = 2.55 m/s at scale 1), windup, attack (spear thrust, impact
f15), hit, death (to the knees, then forward; wings settle)."""
import importlib.util
import math
import os

import bpy
from mathutils import Matrix, Vector

import sb
import sbanim as A
import sbmat

_spec = importlib.util.spec_from_file_location("_angel", os.path.join(os.path.dirname(__file__), "_angel.py"))
H = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(H)

CATEGORY = "enemies"
# Procedural sbmat surfaces (_angel.baked_mats: filigreed ivory, engraved gold, worn steel, feather
# barbs, linen) baked into one atlas (tools/blender/bake.py); halo / eye glows stay flat emissive.
BAKE = {"size": 1024, "samples": 16}

# walk tuning (stride_speed of these = WALK_SPEED; seraph_sentinel.gd uses it to match the ground speed)
WALK_FRAMES = 16
WALK_STRIDE = 30.0
WALK_STANCE = 0.56
THIGH_LEN = 0.43
SHIN_LEN = 0.41


# ----------------------------------------------------------------------------- geometry helpers

def orient(d, y_hint):
    """Euler (deg) that turns local +Z to `d` and local +Y toward `y_hint`."""
    z = Vector(d).normalized()
    y = Vector(y_hint)
    y = (y - z * y.dot(z)).normalized()
    x = y.cross(z)
    m = Matrix((x, y, z)).transposed()
    return tuple(math.degrees(a) for a in m.to_euler())


def feather(name, parent, base, tip_dir, face, length, width, mat, curve=0.12, steps=3, thick=0.005):
    """Feather from `base` along `tip_dir`; its flat side faces `face` and the tip curls toward it."""
    return H.feather(name, parent, length=length, width=width, thickness=thick, loc=tuple(base),
                     rot=orient(tip_dir, face), material=mat, curve=curve, steps=steps)


def band(name, parent, r, z0, z1, mat, seg=12, scale=(1, 1, 1), loc=(0, 0, 0), rot=(0, 0, 0), bulge=0.006):
    """Thin raised trim band (open ring strip) between z0 and z1 at radius r."""
    return sb.lathe(name, parent, [(r, z0), (r + bulge, (z0 + z1) * 0.5), (r, z1)], segments=seg, material=mat,
                    scale=scale, loc=loc, rot=rot, caps=False)


def panel(name, parent, w0, w1, length, mat, folds=2.0, depth=0.018, cols=7, thick=0.012, point=0.0,
          phase=0.0, flip=False, z_top=0.0):
    """Pleated cloth panel hanging down -Z from the joint (top edge at z_top), width w0 -> w1
    (half widths), pleats along X (depth in Y). `point` drops the hem's centre. flip = faces +Y."""
    sy = 1.0 if flip else -1.0
    rows = []
    for r, t in enumerate((0.0, 1.0)):
        w = w0 + (w1 - w0) * t
        row = []
        for i in range(cols):
            u = i / (cols - 1)
            x = (u - 0.5) * 2 * w
            fold = depth * (0.3 + 0.7 * t) * math.cos((u * folds + phase) * 2 * math.pi)
            z = z_top - length * t - point * t * (1 - abs(2 * u - 1))
            row.append((x, sy * fold, z))
        rows.append(row)
    verts = []
    for row in rows:
        verts += [v for v in row]
    for row in rows:
        verts += [(x, y - sy * thick, z) for x, y, z in row]
    n = cols
    off = 2 * n
    faces = []
    for i in range(n - 1):
        faces.append([i, i + 1, n + i + 1, n + i])                       # front
        faces.append([off + i, off + n + i, off + n + i + 1, off + i + 1])  # back
        faces.append([i, off + i, off + i + 1, i + 1])                   # top edge
        faces.append([n + i, n + i + 1, off + n + i + 1, off + n + i])   # hem edge
    faces.append([0, n, off + n, off])
    faces.append([n - 1, off + n - 1, off + 2 * n - 1, 2 * n - 1])
    o = sb.mesh_from(name, parent, verts, faces, material=mat, smooth=True)
    return o, rows[1]


def adopt(temp, joint):
    """Re-parents every mesh built under the helper empty `temp` to `joint` (keeping world
    placement) and deletes `temp` - placement helpers without an extra joint/mesh."""
    bpy.context.view_layer.update()
    for ch in list(temp.children):
        mw = ch.matrix_world.copy()
        ch.parent = joint
        ch.matrix_parent_inverse.identity()
        ch.matrix_world = mw
    bpy.data.objects.remove(temp)
    bpy.context.view_layer.update()


def place(name, parent, world_loc, world_rot):
    return H.attach(name, parent, world_loc, world_rot)


# ----------------------------------------------------------------------------- body parts

def build_leg(hips, s, sd, m):
    th = sb.empty(f"thigh_{sd}", hips, loc=(s * 0.1, 0, -0.04))
    sb.cylinder(f"thighmail_{sd}", th, r1=0.062, r2=0.07, depth=0.4, loc=(0, 0, -0.41), material=m["mail"],
                segments=7, bevel=0.0)
    sb.lathe(f"cuisse_{sd}", th, [(0.0, -0.38), (0.06, -0.36), (0.079, -0.22), (0.074, -0.06), (0.05, 0.0)],
             segments=9, material=m["ivory"], loc=(0, -0.012, 0), scale=(1, 0.86, 1), caps=False)
    band(f"cuisse_trim_{sd}", th, 0.08, -0.26, -0.235, m["gold"], seg=9, scale=(1, 0.86, 1), loc=(0, -0.012, 0))
    # tasset: curved plate on the thigh's outer front, gold rim behind
    tas = [(-0.075, 0.03), (0.075, 0.03), (0.07, -0.15), (0.0, -0.19), (-0.07, -0.15)]
    H.plate(f"tasset_{sd}", th, tas, 0.012, material=m["ivory"], loc=(s * 0.035, -0.07, -0.01),
            rot=(-8, 0, s * 38), bulge=0.012)
    H.plate(f"tasset_rim_{sd}", th, [(x * 1.12, z * 1.1 + 0.004) for x, z in tas], 0.008, material=m["gold"],
            loc=(s * 0.04, -0.064, -0.01), rot=(-8, 0, s * 38))

    sh = sb.empty(f"shin_{sd}", th, loc=(0, 0, -THIGH_LEN))
    # poleyn: ivory cup with a gold fan wing on the outside
    sb.lathe(f"poleyn_{sd}", sh, [(0.0, -0.06), (0.06, -0.05), (0.072, 0.0), (0.05, 0.05), (0.0, 0.065)],
             segments=8, material=m["ivory"], loc=(0, -0.045, 0.0), rot=(90, 0, 0), scale=(1.0, 1.0, 0.7))
    H.plate(f"poleyn_wing_{sd}", sh, [(s * x, z) for x, z in ((0, 0.03), (0.07, 0.07), (0.09, 0.0), (0.05, -0.04),
                                                                (0, -0.03))], 0.01,
            material=m["gold"], loc=(s * 0.06, -0.02, 0.0), rot=(0, 0, s * 75))
    sb.lathe(f"greave_{sd}", sh, [(0.04, -0.4), (0.055, -0.36), (0.07, -0.22), (0.072, -0.1), (0.058, -0.03)],
             segments=9, material=m["ivory"], caps=False)
    band(f"greave_trim_{sd}", sh, 0.056, -0.38, -0.355, m["gold"], seg=9)
    sb.box(f"greave_ridge_{sd}", sh, size=(0.012, 0.014, 0.3), loc=(0, -0.071, -0.22), rot=(-2, 0, 0),
           material=m["gold"], bevel=0.0)

    ft = sb.empty(f"foot_{sd}", sh, loc=(0, 0, -SHIN_LEN))
    sb.lathe(f"sabaton_{sd}", ft, [(0.0, -0.06), (0.05, -0.055), (0.062, 0.0), (0.05, 0.1), (0.035, 0.17),
                                    (0.0, 0.2)], segments=7, material=m["ivory"], loc=(0, 0.04, -0.03),
             rot=(90, 0, 0), scale=(1.0, 0.75, 1.0))
    sb.box(f"sole_{sd}", ft, size=(0.1, 0.24, 0.025), loc=(0, -0.045, -0.058), material=m["gold_dark"], bevel=0.0,
           taper=(0.9, 1.0))
    H.spike(f"toecap_{sd}", ft, (0, -0.07, -0.02), (0, -1, -0.15), 0.1, 0.07, 0.03, material=m["gold"])
    return th, sh, ft


def build_torso(hips, m):
    # hips: mail skirt, faulds with a gold hem, belt + buckle
    sb.lathe("mailskirt", hips, [(0.19, -0.28), (0.165, 0.0)], segments=12, material=m["mail"], caps=False,
             scale=(1, 0.85, 1))
    sb.lathe("faulds", hips, [(0.205, -0.13), (0.198, -0.05), (0.18, 0.04), (0.16, 0.1)], segments=12,
             material=m["ivory"], scale=(1, 0.82, 1), caps=False)
    band("faulds_hem", hips, 0.206, -0.135, -0.105, m["gold"], seg=12, scale=(1, 0.82, 1))
    band("belt", hips, 0.168, 0.06, 0.1, m["leather"], seg=12, scale=(1, 0.84, 1), bulge=0.012)
    H.plate("buckle", hips, [(-0.035, 0.0), (0.0, 0.035), (0.035, 0.0), (0.0, -0.035)], 0.012,
            material=m["gold"], loc=(0, -0.152, 0.08), bulge=0.01)

    spine = sb.empty("spine", hips, loc=(0, 0, 0.1))
    sb.lathe("abdomen", spine, [(0.16, -0.02), (0.168, 0.06), (0.158, 0.14)], segments=12, material=m["ivory"],
             scale=(1, 0.76, 1), caps=False)
    band("abdomen_trim", spine, 0.169, 0.045, 0.07, m["gold"], seg=12, scale=(1, 0.76, 1))

    chest = sb.empty("chest", spine, loc=(0, 0, 0.14))
    sb.lathe("cuirass", chest, [(0.15, -0.04), (0.168, 0.02), (0.2, 0.13), (0.214, 0.22), (0.2, 0.3),
                                (0.15, 0.355), (0.085, 0.385), (0.0, 0.39)], segments=14, material=m["ivory"],
             scale=(1, 0.72, 1))
    # plackart: ivory plate over the belly, engraved gold rim behind it
    pk = [(-0.125, 0.0), (0.125, 0.0), (0.115, 0.1), (0.05, 0.17), (0.0, 0.19), (-0.05, 0.17), (-0.115, 0.1)]
    H.plate("plackart", chest, pk, 0.014, material=m["ivory"], loc=(0, -0.142, -0.02), rot=(-10, 0, 0),
            bulge=0.018)
    H.plate("plackart_rim", chest, [(x * 1.1, z * 1.08 - 0.008) for x, z in pk], 0.01, material=m["gold"],
            loc=(0, -0.135, -0.02), rot=(-10, 0, 0))
    sb.box("breast_ridge", chest, size=(0.014, 0.02, 0.15), loc=(0, -0.153, 0.25), rot=(14, 0, 0),
           material=m["gold"], bevel=0.0)
    # sunburst on the breast
    star = []
    for i in range(16):
        a = math.pi * 2 * i / 16 + math.pi / 2
        r = 0.06 if i % 2 == 0 else 0.026
        star.append((math.cos(a) * r, math.sin(a) * r))
    H.plate("breast_sun", chest, star, 0.01, material=m["gold"], loc=(0, -0.158, 0.2), rot=(-16, 0, 0),
            bulge=0.012)
    sb.lathe("gorget", chest, [(0.15, 0.31), (0.125, 0.38), (0.08, 0.43), (0.0, 0.44)], segments=10,
             material=m["gold"], scale=(1, 0.86, 1), caps=False)
    sb.cylinder("neck", chest, r1=0.058, r2=0.054, depth=0.12, loc=(0, 0, 0.4), material=m["mail"], segments=7,
                bevel=0.0)
    # wing mounts on the back
    for s in (-1, 1):
        H.plate(f"wingmount_{s}", chest, [(-0.05, -0.06), (0.05, -0.06), (0.06, 0.06), (0.0, 0.1), (-0.06, 0.06)],
                0.014, material=m["gold"], loc=(s * 0.085, 0.14, 0.26), rot=(180 - 15, 0, s * 20), bulge=0.012)
    return spine, chest


def build_arm(chest, s, sd, m, rest_arm, rest_fore):
    arm = sb.empty(f"arm_{sd}", chest, loc=(s * 0.245, 0.0, 0.31), rot=rest_arm)
    # layered pauldron: a domed top lame + two lower lames, each lower edge gilt
    sb.lathe(f"pauldron0_{sd}", arm, [(0.0, 0.07), (0.07, 0.06), (0.112, 0.02), (0.122, -0.03)], segments=12,
             material=m["ivory"], loc=(s * 0.02, 0, 0.0), rot=(0, s * 24, 0), scale=(1, 1.08, 1), caps=False)
    band(f"pauldron0_trim_{sd}", arm, 0.122, -0.042, -0.025, m["gold"], seg=12, loc=(s * 0.02, 0, 0.0),
         rot=(0, s * 24, 0), scale=(1, 1.08, 1), bulge=0.008)
    for k in (1, 2):
        r = 0.118 - 0.012 * k
        sb.lathe(f"pauldron{k}_{sd}", arm, [(r * 0.86, 0.02), (r, -0.035)], segments=10, material=m["ivory"],
                 loc=(s * (0.03 + 0.016 * k), 0, -0.045 * k), rot=(0, s * (30 + 10 * k), 0), scale=(1, 1.06, 1),
                 caps=False)
    band(f"pauldron2_trim_{sd}", arm, 0.094, -0.05, -0.034, m["gold"], seg=10, loc=(s * 0.062, 0, -0.09),
         rot=(0, s * 50, 0), scale=(1, 1.06, 1))
    # gilt finial: a swept feather rising from the pauldron
    feather(f"pauldron_finial_{sd}", arm, (s * 0.08, 0.02, 0.055), (s * 0.35, 0.5, 1.0), (0, -1, 0), 0.17, 0.03,
            m["gold"], curve=-0.2, steps=2, thick=0.006)
    sb.cylinder(f"rerebrace_{sd}", arm, r1=0.048, r2=0.054, depth=0.22, loc=(0, 0, -0.27), material=m["ivory"],
                segments=8, bevel=0.0)
    fore = sb.empty(f"fore_{sd}", arm, loc=(0, 0, -0.29), rot=rest_fore)
    sb.lathe(f"couter_{sd}", fore, [(0.0, -0.05), (0.06, -0.035), (0.065, 0.0), (0.045, 0.045), (0.0, 0.05)],
             segments=8, material=m["gold"], loc=(0, 0.02, 0), rot=(90, 0, 0), scale=(1, 1, 0.7))
    sb.lathe(f"vambrace_{sd}", fore, [(0.042, -0.25), (0.056, -0.18), (0.054, -0.06), (0.045, 0.0)], segments=8,
             material=m["ivory"], caps=False)
    band(f"vambrace_cuff_{sd}", fore, 0.058, -0.25, -0.215, m["gold"], seg=8)
    return arm, fore


def gauntlet(name, parent, m, loc=(0, 0, 0), rot=(0, 0, 0)):
    H.ellipsoid(name, parent, (0.08, 0.1, 0.1), loc=loc, rot=rot, material=m["ivory"], seg=8, rings=5)


def build_head(chest, m):
    head = sb.empty("head", chest, loc=(0, 0, 0.44))
    c = Vector((0, -0.005, 0.11))
    ax = (0.098, 0.115, 0.138)
    H.ellipsoid("mask", head, (ax[0] * 2, ax[1] * 2, ax[2] * 2), loc=tuple(c), material=m["ivory"], seg=12, rings=8)

    def surf(yaw, el, out=1.012):
        """Point on the mask surface: yaw from the front (+ = toward +X), elevation (deg)."""
        y, e = math.radians(yaw), math.radians(el)
        return tuple(c + Vector((ax[0] * math.sin(y) * math.cos(e), -ax[1] * math.cos(y) * math.cos(e),
                                 ax[2] * math.sin(e))) * out)

    # filigree: central seam, brow scrolls curling back to the temples, cheek tendrils
    sb.ptube("fil_seam", head, [surf(0, el) for el in (52, 30, 8, -15, -38, -58)], [0.006] * 6, sides=3,
             material=m["gold"])
    for s in (-1, 1):
        sb.ptube(f"fil_brow_{s}", head, [surf(s * a, e) for a, e in ((4, 18), (22, 24), (42, 22), (60, 14), (70, 2),
                                                                       (64, -6), (54, -2))],
                 [0.007, 0.007, 0.006, 0.006, 0.005, 0.004, 0.003], sides=3, material=m["gold"])


    # the light where eyes would be: one thin cold slit
    sb.ptube("eye_slit", head, [surf(a, 8, 1.004) for a in (-34, -17, 0, 17, 34)], [0.003, 0.0055, 0.006, 0.0055,
                                                                                     0.003], sides=3,
             material=m["eye"])
    # circlet + crest + temple wings
    band("circlet", head, 0.101, 0.0, 0.026, m["gold"], seg=14, loc=(0, 0.006, 0.152), rot=(-14, 0, 0),
         scale=(1, 1.16, 1), bulge=0.01)
    H.plate("crest", head, [(0.0, 0.0), (0.03, -0.02), (0.13, 0.04), (0.2, 0.12), (0.11, 0.1), (0.06, 0.14),
                            (0.0, 0.08)], 0.012, material=m["gold"], loc=(0, -0.06, 0.2), rot=(0, 0, 90))
    for s in (-1, 1):
        feather(f"temple_wing_{s}", head, (s * 0.09, 0.0, 0.15), (s * 0.45, 0.85, 0.55), (s * 1, 0, 0.3), 0.17,
                0.028, m["gold"], curve=0.15, steps=2, thick=0.005)

    # halo: horizontal ring of light, tilted back, with alternating rays (spins)
    mount = sb.empty("halo_mount", head, loc=(0, 0.06, 0.33), rot=(-14, 0, 0))
    halo = sb.empty("halo", mount)
    H.ring("halo_ring", halo, 0.145, 0.008, material=m["halo"], seg=28, mseg=3)
    for i in range(8):
        a = 2 * math.pi * i / 8
        ln = 0.075 if i % 2 == 0 else 0.04
        ca, sa = math.cos(a), math.sin(a)
        H.spike(f"halo_ray{i}", halo, (ca * 0.153, sa * 0.153, 0), (ca, sa, 0), ln, 0.016, 0.006,
                material=m["halo"])
    return head, halo


def build_wing(chest, s, sd, m):
    """Folded wing on side s: wrist arching above the head, secondaries hanging from the arm,
    primaries (on the hand joint) hanging to the calves, coverts layered on top."""
    root = sb.empty(f"wing_{sd}", chest, loc=(s * 0.09, 0.16, 0.27))
    E = Vector((s * 0.15, 0.1, 0.2))
    W = Vector((s * 0.27, 0.14, 0.52))
    sb.ptube(f"wing_bone_{sd}", root, [(0, 0, 0), tuple(E), tuple(W)], [0.032, 0.027, 0.02], sides=5,
             material=m["ivory"])

    def along(t):
        return (E * (t / 0.35)) if t < 0.35 else E.lerp(W, (t - 0.35) / 0.65)

    # the folded wing's broad side faces back and out (reads from the high camera and from the front)
    def face(t):
        return Vector((s * (0.75 - 0.2 * t), 0.75, 0.0))
    # secondaries: hang from the arm, longer toward the wrist (each one overlaps the previous)
    n_sec = 5
    for i in range(n_sec):
        t = (i + 0.5) / n_sec
        p = along(t) + Vector((s * 0.004 * i, 0.012 + 0.008 * i, -0.03))
        d = Vector((s * (0.1 + 0.12 * t), 0.24 + 0.1 * t, -1.0))
        feather(f"wing_sec{i}_{sd}", root, p, d, face(t), 0.52 + 0.4 * t, 0.068, m["feather"] if i % 2 else
                m["feather_tip"], curve=-0.08, steps=3)
    # coverts: short, outermost, layered along the arm like scales
    n_cov = 5
    for i in range(n_cov):
        t = (i + 0.5) / n_cov
        p = along(t) + Vector((s * 0.012, -0.03, 0.02))
        d = Vector((s * (0.18 + 0.1 * t), 0.28, -1.0))
        feather(f"wing_cov{i}_{sd}", root, p, d, face(t) + Vector((0, -0.25, 0)), 0.25 + 0.08 * t, 0.07,
                m["feather"], curve=-0.1, steps=2, thick=0.008)
    sb.sphere(f"wing_knuckle_{sd}", root, radius=0.032, loc=tuple(W), material=m["gold"], segments=6, rings=4)

    hand = sb.empty(f"wing_hand_{sd}", root, loc=tuple(W))
    # primaries: the long flight feathers, fanned out and back, tips at the calves
    n_pri = 6
    for i in range(n_pri):
        t = i / (n_pri - 1)
        p = Vector((s * (0.005 - 0.01 * i), 0.015 + 0.04 * t, -0.02 - 0.06 * t))
        d = Vector((s * (0.2 + 0.06 * t), 0.2 + 0.36 * t, -1.0))
        ln = 1.14 + 0.18 * math.sin(math.pi * (0.25 + 0.6 * t))
        feather(f"wing_pri{i}_{sd}", hand, p, d, Vector((s * 0.6, 0.8, 0.0)), ln, 0.062,
                m["feather_tip"] if i % 2 else m["feather"], curve=-0.06, steps=3)
    # gilt alula on the wrist, pointing up: the top of the arch
    feather(f"wing_alula_{sd}", hand, (0, -0.01, 0.0), (s * 0.25, 0.35, 1.0), (s * 0.6, 0.8, 0), 0.2, 0.034,
            m["gold"], curve=-0.25, steps=2, thick=0.006)
    return root, hand


def build_spear(hand, m):
    """Tall winged spear along the hand joint's +Z (world-aligned at rest; grip at the origin)."""
    sb.cylinder("spear_haft", hand, r1=0.017, r2=0.016, depth=1.92, loc=(0, 0, -0.9), material=m["haft"], segments=6,
                bevel=0.0)
    sb.cylinder("spear_grip", hand, r1=0.021, depth=0.2, loc=(0, 0, -0.1), material=m["leather"], segments=6,
                bevel=0.0)
    for i, z in enumerate((-0.12, 0.1, 0.62)):
        sb.cylinder(f"spear_band{i}", hand, r1=0.024, depth=0.03, loc=(0, 0, z - 0.015), material=m["gold"],
                    segments=6, bevel=0.0)
    # butt spike
    sb.lathe("spear_butt", hand, [(0.0, -0.98), (0.022, -0.9), (0.025, -0.86)], segments=6, material=m["gold"])
    # socket, collar wings, leaf blade
    sb.lathe("spear_socket", hand, [(0.02, 1.0), (0.03, 1.06), (0.022, 1.12), (0.034, 1.15), (0.0, 1.17)], segments=6,
             material=m["gold"])
    for s in (-1, 1):
        feather(f"spear_wing_{s}", hand, (s * 0.02, 0, 1.12), (s * 1.0, 0.0, -0.55), (0, -1, 0), 0.16, 0.03,
                m["gold"], curve=0.0, steps=2, thick=0.005)
    sb.lathe("spear_head", hand, [(0.0, 1.14), (0.035, 1.18), (0.058, 1.28), (0.046, 1.4), (0.02, 1.5), (0.0, 1.56)],
             segments=4, material=m["steel"], scale=(1.0, 0.28, 1.0))
    sb.box("spear_fuller", hand, size=(0.012, 0.03, 0.24), loc=(0, 0, 1.31), material=m["gold"], bevel=0.0,
           taper=(0.3, 0.5))


def build_shield(temp, m):
    """Kite shield in `temp`'s frame: face toward -Y, sun emblem."""
    kite = [(-0.2, 0.2), (-0.21, 0.07), (-0.16, -0.14), (-0.08, -0.3), (0.0, -0.4), (0.08, -0.3), (0.16, -0.14),
            (0.21, 0.07), (0.2, 0.2), (0.1, 0.235), (0.0, 0.245), (-0.1, 0.235)]
    H.plate("shield_rim", temp, kite, 0.03, material=m["gold"], loc=(0, 0.01, 0))
    H.plate("shield_face", temp, [(x * 0.9, z * 0.9 + 0.005) for x, z in kite], 0.03, material=m["ivory"],
            loc=(0, 0.0, 0.0), bulge=0.035)
    # sun: a raised boss with sixteen rays
    star = []
    for i in range(16):
        a = math.pi * 2 * i / 16 + math.pi / 2
        r = (0.15 if i % 4 == 0 else 0.105) if i % 2 == 0 else 0.05
        star.append((math.cos(a) * r, math.sin(a) * r))
    H.plate("shield_sun", temp, star, 0.01, material=m["gold"], loc=(0, -0.032, 0.03), bulge=0.03)
    sb.lathe("shield_boss", temp, [(0.045, 0.0), (0.035, 0.03), (0.0, 0.045)], segments=8, material=m["gold"],
             loc=(0, -0.05, 0.03), rot=(90, 0, 0))
    # the lower point gets a gilt drop
    H.plate("shield_drop", temp, [(0.0, -0.14), (0.03, -0.2), (0.0, -0.3), (-0.03, -0.2)], 0.01, material=m["gold"],
            loc=(0, -0.034, 0.0), bulge=0.008)


# ----------------------------------------------------------------------------- build

def build():
    m = H.baked_mats()
    root = sb.root("SeraphSentinel")
    body = sb.empty("body", root)
    hips = sb.empty("hips", body, loc=(0, 0, 0.95))

    tL, sL, fL = build_leg(hips, 1, "L", m)
    tR, sR, fR = build_leg(hips, -1, "R", m)

    # tabard: front and back, two links each (follow-through chains)
    tab_f = [sb.empty("tabard_f0", hips, loc=(0, -0.168, 0.04))]
    tab_f.append(sb.empty("tabard_f1", tab_f[0], loc=(0, 0, -0.27)))
    tab_b = [sb.empty("tabard_b0", hips, loc=(0, 0.162, 0.04))]
    tab_b.append(sb.empty("tabard_b1", tab_b[0], loc=(0, 0, -0.29)))
    tcloth = sbmat.linen("Sentinel_TabardCloth", (0.66, 0.64, 0.58), weave=100.0, rough=0.93, stain=0.4,
                         stain_col=(0.45, 0.4, 0.31), grime_col=(0.13, 0.11, 0.09))
    for nm, ch, flip, l0, l1 in (("f", tab_f, False, 0.27, 0.3), ("b", tab_b, True, 0.29, 0.34)):
        panel(f"tabard_{nm}0_m", ch[0], 0.095, 0.105, l0, tcloth, folds=1.5, depth=0.012, flip=flip,
              z_top=0.02)
        _, hem = panel(f"tabard_{nm}1_m", ch[1], 0.105, 0.12, l1, tcloth, folds=1.5, depth=0.018, flip=flip,
                       point=0.08)
        sb.ptube(f"tabard_{nm}_hem", ch[1], [(x, y + (0.006 if flip else -0.006), z + 0.012) for x, y, z in hem],
                 [0.007] * len(hem), sides=3, material=m["gold"])
        if nm == "f":
            star = []
            for i in range(8):
                a = math.pi * 2 * i / 8 + math.pi / 2
                r = 0.045 if i % 2 == 0 else 0.016
                star.append((math.cos(a) * r, math.sin(a) * r))
            H.plate("tabard_sun", ch[0], star, 0.006, material=m["gold"], loc=(0, -0.018, -0.13), bulge=0.004)

    spine, chest = build_torso(hips, m)
    aR, oR = build_arm(chest, -1, "R", m, rest_arm=(-6, 4, 0), rest_fore=(-58, 0, 6))
    aL, oL = build_arm(chest, 1, "L", m, rest_arm=(-14, -10, -6), rest_fore=(-74, 0, 30))
    head, halo = build_head(chest, m)
    wL, whL = build_wing(chest, 1, "L", m)
    wR, whR = build_wing(chest, -1, "R", m)

    # right hand: world-aligned joint at the wrist (spear upright at rest)
    bpy.context.view_layer.update()
    hp = oR.matrix_world @ Vector((0, 0, -0.29))
    hand = place("hand_R", oR, tuple(hp), (0, 0, 0))
    gauntlet("gauntlet_R", hand, m, loc=(0, 0, 0.0))
    build_spear(hand, m)

    # left: gauntlet + shield on the forearm (no extra joint)
    bpy.context.view_layer.update()
    gp = oL.matrix_world @ Vector((0, 0, -0.29))
    t = place("_tmp_gl", oL, tuple(gp), (0, 0, 0))
    gauntlet("gauntlet_L", t, m)
    adopt(t, oL)
    sp = oL.matrix_world @ Vector((0.075, 0.0, -0.15))
    t = place("_tmp_shield", oL, (sp.x + 0.02, sp.y - 0.03, sp.z + 0.03), (4, 0, 16))
    build_shield(t, m)
    adopt(t, oL)

    H.merge_by_joint(root)
    H.report("seraph_sentinel")
    meshes = [o for o in sb.descendants(root) if o.type == "MESH"]
    print("MESHES", len(meshes), " ".join(f"{o.name}:{sum(len(p.vertices) - 2 for p in o.data.polygons)}"
                                          for o in meshes))

    J = dict(root=root, body=body, hips=hips, spine=spine, chest=chest, head=head, halo=halo, tL=tL, tR=tR, sL=sL,
             sR=sR, fL=fL, fR=fR, aL=aL, aR=aR, oL=oL, oR=oR, hand=hand, wL=wL, wR=wR, whL=whL, whR=whR,
             tab_f=tab_f, tab_b=tab_b)
    animate(J)
    return root


# ----------------------------------------------------------------------------- animation

def animate(J):
    ALL = A.joints(J["root"])
    hips, spine, chest, head, halo = J["hips"], J["spine"], J["chest"], J["head"], J["halo"]
    tL, tR, sL, sR, fL, fR = J["tL"], J["tR"], J["sL"], J["sR"], J["fL"], J["fR"]
    aL, aR, oL, oR, hand = J["aL"], J["aR"], J["oL"], J["oR"], J["hand"]
    wL, wR, whL, whR = J["wL"], J["wR"], J["whL"], J["whR"]
    tab_f, tab_b, body = J["tab_f"], J["tab_b"], J["body"]
    WTIP = {whL: (0.27, 0.45, -1.17), whR: (-0.27, 0.45, -1.17)}

    def secondary(c, floor=None, tab_freq=2.6, wing_freq=2.4):
        A.follow_through(c, tab_f, freq=tab_freq, damping=0.2, gravity=6.0, falloff=0.85, tip=(0, 0, -0.33),
                         floor=floor)
        A.follow_through(c, tab_b, freq=tab_freq, damping=0.2, gravity=6.0, falloff=0.85, tip=(0, 0, -0.38),
                         floor=floor)
        for wh in (whL, whR):
            A.follow_through(c, [wh], freq=wing_freq, damping=0.22, gravity=2.0, tip=WTIP[wh], max_angle=35,
                             floor=floor)

    def halo_spin(c, turns=1.0 / 12):
        c.key(halo, 0, rot=(0, 0, 0), ease="linear")
        c.key(halo, c.frames, rot=(0, 0, 360 * turns), ease="linear")

    def halo_spin_loop(c, steps=1):
        # loop-safe: spins `steps` quarter turns per cycle; seam is invisible (rays repeat every 90 deg)
        c.add(halo, lambda f: (0, 0, 90.0 * steps * f / c.frames), "rot")

    # ---------------------------------------------------------------- idle (loop): vigilant stillness
    c = A.Clip("idle", 90, joints=ALL)
    A.breathe(c, chest, amp=1.6, rise=0.006, swell=0.01, cycles=2, shoulders=[aL, aR], head=head)
    c.add(hips, lambda f: (0.012 * A.wave(c, f), 0, -0.004 * abs(A.wave(c, f))), "loc")   # weight shift
    c.add(hips, lambda f: (0, 1.2 * A.wave(c, f), 0), "rot")
    c.add(spine, lambda f: (0, -0.8 * A.wave(c, f, offset=-0.05), 0), "rot")
    A.noise(c, head, rot=(2.5, 2, 6), freq=0.35, seed=4)
    A.noise(c, hand, rot=(1.2, 0.6, 1.0), freq=0.3, seed=7)
    A.noise(c, oL, rot=(1.5, 0, 1.5), freq=0.3, seed=8)
    # wings: slow "breath" of the folded wings (rise a touch with each inhale)
    c.add(wL, lambda f: (-2.0 * A.wave(c, f, cycles=2, offset=-0.1), -1.5 * A.wave(c, f, cycles=2), 0), "rot")
    c.mirror(wL, phase=0.0)
    halo_spin_loop(c, 1)
    secondary(c)
    c.bake()

    # ---------------------------------------------------------------- walk (loop): measured march
    c = A.Clip("walk", WALK_FRAMES, joints=ALL)
    rig = {"hips": hips, "spine": spine, "chest": chest, "head": head, "thigh": (tL, tR), "shin": (sL, sR),
           "foot": (fL, fR), "arm": (aL, aR), "fore": (oL, oR)}
    A.walk(c, rig, stride=WALK_STRIDE, knee=58, stance=WALK_STANCE, arm=5, elbow=0, elbow_swing=4, arm_out=0,
           lean=5, twist=6, hip_yaw=6, hip_roll=3.5, heavy=0.35, sway=0.018)
    # spear rocks with the step, wings bounce on the contacts
    c.add(hand, lambda f: (2.5 * A.wave(c, f, offset=0.1), 0, 0), "rot")
    c.add(wL, lambda f: (-2.5 * A.wave(c, f, cycles=2, offset=-0.15), 0, 0), "rot")
    c.mirror(wL, phase=0.0)
    # tabard front kicks forward with whichever thigh is forward (keeps it off the knees)
    c.add(tab_f[0], lambda f: (0.8 * min(0.0, c.eval(tL, "rot", f)[0], c.eval(tR, "rot", f)[0]), 0, 0), "rot")
    c.add(tab_b[0], lambda f: (0.5 * max(0.0, c.eval(tL, "rot", f)[0], c.eval(tR, "rot", f)[0]), 0, 0), "rot")
    halo_spin_loop(c, 0)
    secondary(c)
    c.bake()
    print("WALK speed m/s =", round(A.stride_speed(THIGH_LEN + SHIN_LEN, WALK_STRIDE, WALK_FRAMES,
                                                   stance=WALK_STANCE), 3))

    # ---------------------------------------------------------------- attack: spear thrust
    antic = {
        hips: {"loc": (0, 0.07, -0.07), "rot": (0, 0, -8)},
        spine: {"rot": (-4, 0, -4)},
        chest: {"rot": (-6, 0, -10)},
        head: {"rot": (6, 0, 18)},
        tL: {"rot": (-24, 0, 4)}, sL: {"rot": (26, 0, 0)}, fL: {"rot": (-2, 0, 0)},
        tR: {"rot": (10, 0, -2)}, sR: {"rot": (24, 0, 0)}, fR: {"rot": (-30, 0, 0)},
        aR: {"rot": (24, 0, 18)}, oR: {"rot": (-14, 0, 0)}, hand: {"rot": (88, 0, 10)},
        aL: {"rot": (-22, 0, 6)}, oL: {"rot": (-6, 0, -6)},
        wL: {"rot": (-4, 0, -4)}, wR: {"rot": (-4, 0, 4)},
    }
    strike = {
        hips: {"loc": (0, -0.2, -0.11), "rot": (0, 0, 7)},
        spine: {"rot": (8, 0, 4)},
        chest: {"rot": (10, 0, 10)},
        head: {"rot": (-10, 0, -18)},
        tL: {"rot": (-46, 0, 4)}, sL: {"rot": (40, 0, 0)}, fL: {"rot": (6, 0, 0)},
        tR: {"rot": (28, 0, -2)}, sR: {"rot": (14, 0, 0)}, fR: {"rot": (-36, 0, 0)},
        aR: {"rot": (-62, 0, -22)}, oR: {"rot": (48, 0, 0)}, hand: {"rot": (78, 0, -6)},
        aL: {"rot": (6, 0, 12)}, oL: {"rot": (10, 0, -10)},
        wL: {"rot": (6, 4, -6)}, wR: {"rot": (6, -4, 6)},
    }
    follow = {j: {k: tuple(x * 0.93 for x in v) for k, v in d.items()} for j, d in strike.items()}

    c = A.Clip("attack", 36, joints=ALL)
    ev = A.attack(c, {"antic": antic, "strike": strike, "follow": follow}, antic=9, antic_hold=4, strike=3,
                  hold=5, recover=14, overshoot=0.1, push=0.08)
    A.jitter(c, hand, rot=(1.2, 0.8, 1.0), start=9, end=13)
    halo_spin(c, 1.0 / 12)
    secondary(c)
    c.bake()
    print("ATTACK impact frame", ev["impact"])

    # windup only (for state-driven use): ease into the antic pose and hold, trembling
    c = A.Clip("windup", 16, joints=ALL)
    for j, ch in antic.items():
        for k, v in ch.items():
            c.key(j, 0, **{k: (0, 0, 0)}, ease="sine_inout")
            c.key(j, 10, **{k: v}, ease="smooth")
            c.key(j, 16, **{k: tuple(x * 1.08 for x in v)})
    A.jitter(c, hand, rot=(1.2, 0.8, 1.0), start=9, end=16)
    halo_spin(c, 1.0 / 24)
    secondary(c)
    c.bake()

    # ---------------------------------------------------------------- hit: stagger behind the shield
    c = A.Clip("hit", 20, joints=ALL)
    A.hit_react(c, {hips: {"loc": (0, 0.1, -0.04), "rot": (-6, 0, 0)},
                    spine: {"rot": (-8, 0, 4)},
                    chest: {"rot": (-18, 4, 10), "scale": (1.02, 1.02, 0.97)},
                    head: {"rot": (-18, 0, -12)},
                    aL: {"rot": (-16, 0, 8)}, oL: {"rot": (-14, 0, 0)},
                    aR: {"rot": (12, 0, 10)}, hand: {"rot": (-10, 0, 6)},
                    tL: {"rot": (8, 0, 0)}, sL: {"rot": (10, 0, 0)},
                    wL: {"rot": (-6, -6, -14)}, wR: {"rot": (-6, 6, 14)},
                    whL: {"rot": (0, -10, -8)}, whR: {"rot": (0, 10, 8)}},
                start=0, rise=2, settle=13, wobble=1.0, stagger=0.6)
    halo_spin(c, 1.0 / 36)
    secondary(c)
    c.bake()

    # ---------------------------------------------------------------- death: to the knees, then forward
    c = A.Clip("death", 64, joints=ALL)
    K0, K1, K2, K3 = 4, 15, 24, 36       # recoil, knees hit, kneeling hold end, face hits the ground
    def P(f, poses, ease="smooth"):
        c.pose(f, poses, ease=ease)
    rest = {j: {"rot": (0, 0, 0), "loc": (0, 0, 0)} for j in (hips, spine, chest, head, tL, tR, sL, sR, fL, fR, aL,
                                                                 aR, oL, oR, hand, wL, wR, whL, whR, body)}
    P(0, rest, "sine_out")
    P(K0, {body: {"rot": (0, 0, 0), "loc": (0, 0, 0)}, hips: {"loc": (0, 0.06, -0.03), "rot": (-6, 0, 0)}, spine: {"rot": (-6, 0, 0)}, chest: {"rot": (-10, 0, 6)},
           head: {"rot": (-22, 0, 8)}, aR: {"rot": (14, 0, -10)}, aL: {"rot": (-10, 0, 14)}, hand: {"rot": (-6, 0, 0)},
           wL: {"rot": (-6, -8, -10)}, wR: {"rot": (-6, 8, 10)}}, "quad_in")
    kneel = {hips: {"loc": (0, 0.03, -0.47), "rot": (4, 0, 0)}, spine: {"rot": (8, 0, 0)}, chest: {"rot": (10, 0, -4)},
             head: {"rot": (26, 0, -6)},
             tL: {"rot": (-14, 0, 2)}, sL: {"rot": (96, 0, 0)}, fL: {"rot": (40, 0, 0)},
             tR: {"rot": (-6, 0, -2)}, sR: {"rot": (92, 0, 0)}, fR: {"rot": (44, 0, 0)},
             aR: {"rot": (6, 0, -16)}, oR: {"rot": (30, 0, 0)}, hand: {"rot": (-30, -42, 0)},
             aL: {"rot": (8, 0, 18)}, oL: {"rot": (34, 0, 0)},
             wL: {"rot": (-2, -4, -4)}, wR: {"rot": (-2, 4, 4)}, body: {"rot": (0, 0, 0), "loc": (0, 0, 0)}}
    P(K1, kneel, "quad_out")
    bow = {j: dict(v) for j, v in kneel.items()}
    bow[chest] = {"rot": (16, 0, -4)}
    bow[head] = {"rot": (34, 0, -8)}
    bow[spine] = {"rot": (12, 0, 0)}
    bow[hips] = {"loc": (0, 0.03, -0.48), "rot": (6, 0, 0)}
    P(K2, bow, "quad_in")
    # topple: the whole body pivots near the knees; shins stay flat on the ground behind
    fall = 74.0
    down = {j: dict(v) for j, v in bow.items()}
    down[body] = {"rot": (fall, 0, 3), "loc": (0, -0.04, 0.07)}
    down[tL] = {"rot": (-14, 0, 2)}
    down[tR] = {"rot": (-6, 0, -2)}
    down[sL] = {"rot": (96 - fall, 0, 0)}
    down[sR] = {"rot": (92 - fall, 0, 0)}
    down[spine] = {"rot": (8, 0, 0)}
    down[chest] = {"rot": (8, 0, -6)}
    down[head] = {"rot": (-6, 0, -34)}
    down[aR] = {"rot": (-30, 30, -30)}
    down[oR] = {"rot": (10, 0, 0)}
    down[hand] = {"rot": (-50, -70, 0)}
    down[aL] = {"rot": (-24, -20, 30)}
    down[oL] = {"rot": (20, 0, 0)}
    P(K3, down, "quad_out")
    settle = {j: dict(v) for j, v in down.items()}
    settle[body] = {"rot": (fall - 4, 0, 3), "loc": (0, -0.04, 0.07)}
    P(K3 + 3, settle, "quad_in")
    P(K3 + 7, down, "smooth")
    # wings: stay folded through the fall, then settle open and droop onto the ground
    c.key(wL, K3 - 4, rot=(-2, -4, -4))
    c.key(wR, K3 - 4, rot=(-2, 4, 4))
    c.key(wL, K3 + 6, rot=(-26, -24, -40), ease="back_out:1.6")
    c.key(wR, K3 + 6, rot=(-26, 24, 40), ease="back_out:1.6")
    c.key(wL, 64, rot=(-30, -30, -46))
    c.key(wR, 64, rot=(-30, 30, 46))
    c.key(whL, K3 - 2, rot=(0, 0, 0))
    c.key(whR, K3 - 2, rot=(0, 0, 0))
    c.key(whL, K3 + 10, rot=(0, -18, -14), ease="back_out:1.4")
    c.key(whR, K3 + 10, rot=(0, 18, 14), ease="back_out:1.4")
    c.key(whL, 64, rot=(0, -22, -16))
    c.key(whR, 64, rot=(0, 22, 16))
    # halo: flares, then sinks and goes out
    c.key(halo, 0, rot=(0, 0, 0), scale=(1, 1, 1), ease="sine_out")
    c.key(halo, K1, rot=(0, 0, 40), scale=(1.12, 1.12, 1.12), ease="sine_inout")
    c.key(halo, K3, rot=(0, 0, 160), scale=(0.7, 0.7, 0.7), ease="quad_in")
    c.key(halo, K3 + 10, rot=(0, 0, 220), scale=(0.02, 0.02, 0.02), ease="constant")
    secondary(c, floor=0.03, wing_freq=1.8)
    c.bake()
