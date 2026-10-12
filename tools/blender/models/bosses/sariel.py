"""Sariel, Herald of the Last Dawn: towering six-winged seraph (~4.3 m to the crown, ~4.8 m halo).

Ivory plate laced with gold filigree over long layered robes and sashes, a faceless veil crowned
with a rayed circlet, a great halo of three counter-rotating rings (eyes, inscriptions, rays)
and a spear of light in the right hand. Six wings in three tiers (raised / spread / trailing),
each built from ~130 layered feathers (primaries, secondaries, tertials, coverts, scapulars)
in several ivory / warm / gilt shades.

Joints used by Godot (scenes/bosses/sariel_model.gd):
  halo, halo_spin0..2 (procedural spin about local Godot Z; NOT keyed by any clip), spear_tip,
  wing<p><L|R>_mount (tier pose), _arm/_fore/_hand (beat chain), feather chunks
  wing<p><L|R>_<pri0..2|sec0..1|cov0..1|les0>_mesh (hidden one by one on dissolve).
Material names Sariel_Halo*/EyeIris/SpearLight/VeilGlow/WingGlow are swapped at runtime for
controllable glow materials.

Animations (every animated joint keyed in every clip so Godot can layer them with filtered Blend2):
  idle (54 f loop, staggered wingbeats; top pair's downstroke starts at frame 0), glide (54 f),
  raise, channel, summon, spread, kneel, descent (60 f looping pose clips with living motion).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

import sb  # noqa: E402
import sbanim as A  # noqa: E402
import _kit as kit  # noqa: E402
import sbmat  # noqa: E402

CATEGORY = "bosses"
# Procedural sbmat surfaces baked into one 2048 atlas (tools/blender/bake.py): filigreed ivory,
# engraved gold, linen weave, silk, feather barbs. Tight pack gap: ~800 feathers -> many islands.
BAKE = {"size": 2048, "samples": 16, "island_margin": 0.001}
FLAP = 54   # frames per wingbeat (1.8 s, = SarielModel.FLAP_PERIOD)
POSE = 60   # pose clip loop length

# Wing tiers. Mount frame: bone along +X (left wing), feathers trail along +Y, top surface +Z.
#   z: mount height (torso space), L: wing scale (m), tilt (X, feathers droop back-down),
#   elev (tip raised), sweep (+ = swept back), off: beat phase lag (cycles).
WINGS = [
    dict(z=0.95, L=2.0, tilt=45.0, elev=34.0, sweep=-40.0, off=0.0),
    dict(z=0.77, L=2.6, tilt=22.0, elev=8.0, sweep=0.0, off=0.08),
    dict(z=0.56, L=1.9, tilt=10.0, elev=-20.0, sweep=46.0, off=0.16),
]
SIDES = ((1, "L"), (-1, "R"))

# Absolute rest rotations (deg) of the posed joints.
REST = {
    "shoulder_L": (-10, -16, 0), "elbow_L": (-28, 0, 0), "hand_L": (-12, 0, 0),
    "shoulder_R": (-14, 12, 0), "elbow_R": (-78, 0, 0), "hand_R": (0, 0, 0),
    "head": (8, 0, 0),
}


def R(rot):
    return Euler([math.radians(a) for a in rot]).to_matrix()


def at(center, rot, off):
    return tuple(Vector(center) + R(rot) @ Vector(off))


def mesh_obj(name, parent, bm, mats, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    return ob


def spike(name, parent, length=0.3, width=0.03, thick=0.006, loc=(0, 0, 0), rot=(0, 0, 0), material=None,
          mid=0.3, smooth=False):
    """Cheap leaf-shaped ray along +Z (14 tris): rays, crown points, collar plates."""
    bm = bmesh.new()
    base = [bm.verts.new(v) for v in ((-width * 0.45, 0, 0), (0, thick, 0), (width * 0.45, 0, 0), (0, -thick, 0))]
    zm = length * mid
    midr = [bm.verts.new(v) for v in ((-width, 0, zm), (0, thick, zm), (width, 0, zm), (0, -thick, zm))]
    tip = bm.verts.new((0, 0, length))
    bm.faces.new(list(reversed(base)))
    for k in range(4):
        bm.faces.new((base[k], base[(k + 1) % 4], midr[(k + 1) % 4], midr[k]))
        bm.faces.new((midr[k], midr[(k + 1) % 4], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = mesh_obj(name, None, bm, [material] if material else [], smooth)
    return sb._finish(ob, parent, None, loc, rot, (1, 1, 1), 0.0, 0, smooth, name)


# ====================================================================== feathers

FLIGHT = [(0.0, 0.14), (0.16, 0.8), (0.55, 1.0), (0.86, 0.7), (1.0, 0.0)]       # 30 tris
COVERT = [(0.0, 0.4), (0.45, 1.0), (0.8, 0.78), (1.0, 0.0)]                     # 22 tris
SCALE = [(0.0, 0.55), (0.5, 1.0), (1.0, 0.0)]                                    # 14 tris


class Plume:
    """Many feathers in one bmesh (one mesh object per chunk joint). Coordinates are given in the
    LEFT wing frame; `s` = -1 mirrors to the right wing; `origin` = the chunk joint's position."""

    def __init__(self, s, origin, mats):
        self.bm = bmesh.new()
        self.s = s
        self.o = Vector(origin)
        self.mats = mats

    def _v(self, p):
        q = p - self.o
        return self.bm.verts.new((q.x * self.s, q.y, q.z))

    def add(self, base, theta, length, width, mi, prof=FLIGHT, pitch=4.0, curve=0.05, bend=0.0, asym=0.62,
            thick=None):
        th, ph = math.radians(theta), math.radians(pitch)
        d = Vector((math.sin(th) * math.cos(ph), math.cos(th) * math.cos(ph), -math.sin(ph)))
        w = Vector((math.cos(th), -math.sin(th), 0.0))
        n = w.cross(d).normalized()
        thick = thick if thick is not None else max(0.003, width * 0.1)
        rows = []
        for t, wf in prof:
            c = Vector(base) + d * (t * length) - n * (curve * t * t * length) + w * (bend * t * t * length)
            if wf <= 0.0:
                rows.append([self._v(c)])
                continue
            k = 1.0 - 0.6 * t
            rows.append([self._v(c - w * (width * wf)), self._v(c + n * thick * k),
                         self._v(c + w * (width * wf * asym)), self._v(c - n * thick * 0.5 * k)])
        faces = []
        for a, b in zip(rows[:-1], rows[1:]):
            for k in range(4):
                if len(b) == 1:
                    faces.append(self.bm.faces.new((a[k], a[(k + 1) % 4], b[0])))
                else:
                    faces.append(self.bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k])))
        faces.append(self.bm.faces.new(list(reversed(rows[0]))))
        for f in faces:
            f.material_index = mi

    def done(self, name, parent):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        return mesh_obj(name, parent, self.bm, self.mats)


def pick(rng, weights):
    r = rng.random() * sum(weights)
    for i, w in enumerate(weights):
        r -= w
        if r <= 0:
            return i
    return len(weights) - 1


def build_wing(p, s, nm, cfg, torso, M, J, chunks):
    L = cfg["L"]
    rng = random.Random(100 + p * 7)   # same feather layout on both sides
    tag = f"wing{p}{nm}"
    mount = sb.empty(f"{tag}_mount", torso, loc=(s * 0.15, 0.26, cfg["z"]),
                     rot=(cfg["tilt"], -s * cfg["elev"], s * cfg["sweep"]))
    a, b, c = 0.30 * L, 0.30 * L, 0.2 * L
    arm = sb.empty(f"{tag}_arm", mount)
    fore = sb.empty(f"{tag}_fore", arm, loc=(s * a, 0, 0))
    hand = sb.empty(f"{tag}_hand", fore, loc=(s * b, 0, 0))
    for j in (mount, arm, fore, hand):
        J[j.name] = j
    O = {"arm": Vector((0, 0, 0)), "fore": Vector((a, 0, 0)), "hand": Vector((a + b, 0, 0))}
    JO = {"arm": arm, "fore": fore, "hand": hand}

    def lp(jn, pts):
        o = O[jn]
        return [((x - o.x) * s, y - o.y, z - o.z) for x, y, z in pts]

    # ---- leading edge: ivory bone, gold filigree, knuckles.
    r = L / 2.2
    sb.ptube(f"{tag}_bone_a", arm, lp("arm", [(0, 0, 0), (0.25 * a, -0.025 * L, 0.012 * L),
                                             (0.6 * a, -0.035 * L, 0.018 * L), (a, 0, 0.005 * L)]),
             [0.075 * r, 0.068 * r, 0.058 * r, 0.05 * r], sides=6, material=M["plate"])
    sb.ptube(f"{tag}_bone_f", fore, lp("fore", [(a, 0, 0.005 * L), (a + 0.5 * b, -0.04 * L, 0.012 * L),
                                               (a + b, 0, 0)]), [0.05 * r, 0.042 * r, 0.036 * r], sides=6,
             material=M["plate"])
    sb.ptube(f"{tag}_bone_h", hand, lp("hand", [(a + b, 0, 0), (a + b + 0.5 * c, -0.012 * L, 0),
                                               (a + b + c, 0.02 * L, -0.005 * L)]), [0.036 * r, 0.026 * r, 0.01 * r],
             sides=5, material=M["plate"])
    kit.filigree(f"{tag}_gild_a", arm, lp("arm", [(0.05 * a, -0.02 * L, 0.03 * r), (0.5 * a, -0.05 * L, 0.06 * r),
                                                  (a, -0.012 * L, 0.05 * r)]), 0.008 * r, M["gold"], res=2)
    kit.filigree(f"{tag}_gild_f", fore, lp("fore", [(a, -0.012 * L, 0.05 * r), (a + 0.5 * b, -0.054 * L, 0.05 * r),
                                                    (a + b, -0.01 * L, 0.04 * r)]), 0.007 * r, M["gold"], res=2)
    for jn, x, rad in (("fore", a, 0.06), ("hand", a + b, 0.048)):
        kn = sb.sphere(f"{tag}_knuckle_{jn}", JO[jn], radius=rad * r, scale=(1, 1, 0.8), material=M["gold"],
                       segments=8, rings=4)
        kn.location = (0, -0.01 * L, 0.0)
    # scapular plate at the root: an ivory blade with gold spine and a sun boss.
    spike(f"{tag}_scap", arm, length=0.26 * L, width=0.05 * L, thick=0.02, loc=(0, 0.0, 0.03 * r),
          rot=(-90, 0, s * (-70)), material=M["plate"], smooth=True)
    sb.sphere(f"{tag}_boss", arm, radius=0.07 * r, scale=(1, 1, 0.6), loc=(s * 0.06 * L, -0.02 * L, 0.05 * r),
              material=M["sun"], segments=8, rings=4)

    mats_fl = [M["fea"], M["fea_w"], M["fea_s"], M["fea_p"]]
    mats_cv = [M["wglow"], M["fea_w"], M["fea_g"], M["fea_p"]]

    def chunk(jn, key):
        j = sb.empty(f"{tag}_{key}", JO[jn])
        J[j.name] = j
        pl = Plume(s, O[jn], mats_fl if key[:3] in ("pri", "sec") else mats_cv)
        chunks.append((pl, j))
        return pl, j

    def jit(v, amt):
        return v * (1.0 + rng.uniform(-amt, amt))

    # ---- primaries (hand): three chunks, inner -> outer.
    pri = [chunk("hand", f"pri{k}") for k in range(3)]
    n = 11
    for i in range(n):
        t = i / (n - 1)
        pl = pri[0 if i < 4 else (1 if i < 8 else 2)][0]
        base = (a + b + c * (0.04 + 0.92 * t), 0.004 * L, -0.002 * L * i)
        ln = L * (0.44 + 0.18 * t - 0.1 * t ** 6)
        pl.add(base, 16 + 64 * t ** 1.15 + rng.uniform(-1.5, 1.5), jit(ln, 0.03), 0.075 * L * (1 - 0.3 * t),
               pick(rng, [5, 2, 1.2, 1.5]), pitch=3 + 2 * t, curve=0.06, bend=-0.05 * t)
    # ---- secondaries (forearm).
    sec0 = chunk("fore", "sec0")[0]
    n = 13
    for i in range(n):
        t = i / (n - 1)
        base = (a + b * (0.02 + 0.97 * t), 0.008 * L, -0.0015 * L * (i % 2))
        ln = L * (0.38 + 0.025 * math.sin(i * 2.3) + 0.03 * t)
        sec0.add(base, 2 + 14 * t + rng.uniform(-1.5, 1.5), jit(ln, 0.03), 0.06 * L,
                 pick(rng, [5, 2, 1.2, 1.5]), pitch=4, curve=0.05)
    # ---- inner secondaries + tertials (arm).
    sec1 = chunk("arm", "sec1")[0]
    n = 10
    for i in range(n):
        t = i / (n - 1)
        base = (a * (0.04 + 0.96 * t), 0.008 * L, -0.0015 * L * (i % 2))
        ln = L * (0.26 + 0.09 * t + 0.02 * math.sin(i * 1.7))
        sec1.add(base, -16 + 18 * t + rng.uniform(-2, 2), jit(ln, 0.04), 0.065 * L,
                 pick(rng, [4, 2.5, 1.5, 1.2]), pitch=5, curve=0.05)
    # ---- coverts over the forearm: greater, median, lesser (marginal) rows.
    cov0 = chunk("fore", "cov0")[0]
    for row, (cnt, ln, wd, y, z, pitch, prof, wts) in enumerate((
            (12, 0.19, 0.046, -0.004, 0.016, 7, COVERT, [3, 2, 0.4, 1]),
            (11, 0.105, 0.036, -0.02, 0.026, 9, COVERT, [1.5, 2.5, 1.0, 1]),
            (11, 0.055, 0.025, -0.034, 0.034, 12, SCALE, [0.5, 1.5, 3.0, 0.5]))):
        for i in range(cnt):
            t = (i + 0.5 * (row % 2)) / cnt
            base = (a + b * t, y * L, z * L)
            cov0.add(base, 4 + 14 * t + rng.uniform(-2, 2), jit(ln * L, 0.06), wd * L, pick(rng, wts),
                     prof=prof, pitch=pitch, curve=0.06, asym=0.8)
    # ---- coverts over the hand: primary coverts, alula, marginals.
    cov1 = chunk("hand", "cov1")[0]
    for i in range(10):
        t = i / 9
        cov1.add((a + b + c * (0.03 + 0.9 * t), -0.002 * L, 0.016 * L), 16 + 60 * t ** 1.15, jit(0.2 * L, 0.05),
                 0.042 * L, pick(rng, [3, 2, 0.5, 1]), prof=COVERT, pitch=6, curve=0.05, asym=0.75)
    for i in range(3):
        cov1.add((a + b + 0.01 * L * i, -0.03 * L, 0.03 * L), 38 + 12 * i, (0.14 - 0.025 * i) * L, 0.028 * L,
                 2, prof=COVERT, pitch=8, curve=0.04, asym=0.7)
    for i in range(7):
        t = i / 6
        cov1.add((a + b + c * 0.9 * t, -0.022 * L, 0.03 * L), 20 + 50 * t, jit(0.07 * L, 0.08), 0.025 * L,
                 pick(rng, [0.5, 1.5, 3, 0.5]), prof=SCALE, pitch=10, curve=0.05, asym=0.85)
    # ---- arm coverts + scapulars.
    les0 = chunk("arm", "les0")[0]
    for row, (cnt, ln, wd, y, z, pitch, prof, wts) in enumerate((
            (10, 0.17, 0.045, -0.004, 0.016, 7, COVERT, [3, 2, 0.4, 1]),
            (8, 0.1, 0.04, -0.02, 0.026, 9, COVERT, [1.5, 2.5, 1.0, 1]),
            (9, 0.055, 0.028, -0.034, 0.034, 12, SCALE, [0.5, 1.5, 3.0, 0.5]))):
        for i in range(cnt):
            t = (i + 0.5 * (row % 2)) / cnt
            base = (a * (0.06 + 0.94 * t), y * L, z * L)
            les0.add(base, -10 + 14 * t + rng.uniform(-2, 2), jit(ln * L, 0.06), wd * L, pick(rng, wts),
                     prof=prof, pitch=pitch, curve=0.06, asym=0.8)
    for i in range(4):
        les0.add((0.015 * L * i, 0.0, 0.04 * L), -24 + 5 * i, jit(0.22 * L, 0.05), 0.05 * L, pick(rng, [3, 2, 0.6, 1]),
                 prof=COVERT, pitch=8, curve=0.05, asym=0.8)
    return mount, (arm, fore, hand), [pj for _, pj in pri]


# ====================================================================== build

def build():
    M = {}
    # Baked sbmat surfaces. Albedos sit well below white (linear ~0.5-0.66): under the arena's golden
    # key light + bloom the old 0.9+ flat whites clipped to a featureless glare; now feather barbs,
    # filigree and cloth weave keep form and shading. Glowing parts stay flat emissive materials
    # (sariel_model.gd swaps them by name).
    M["plate"] = sbmat.filigree_ivory("Sariel_IvoryPlate", tint=(0.6, 0.56, 0.47), inlay=(0.78, 0.55, 0.22),
                                      yellow=(0.5, 0.42, 0.28), grime=(0.13, 0.09, 0.045), scale=1.2,
                                      line_k=0.75)
    M["plate2"] = sbmat.aged_ivory("Sariel_IvoryPlateAged", tint=(0.52, 0.47, 0.37), scale=1.3)
    M["gold"] = sbmat.gold_filigree("Sariel_GoldFiligree", tint=(0.86, 0.62, 0.26), scale=2.0)
    M["dgold"] = sbmat.gold_filigree("Sariel_DarkGold", tint=(0.55, 0.38, 0.15), scale=2.0)
    M["robe"] = sbmat.linen("Sariel_RobeCloth", (0.6, 0.57, 0.5), weave=110.0, rough=0.88, stain=0.35,
                            stain_col=(0.42, 0.36, 0.27), grime_col=(0.14, 0.12, 0.09))
    M["robe2"] = sbmat.linen("Sariel_RobeLinenShade", (0.48, 0.44, 0.36), weave=110.0, rough=0.9, stain=0.35,
                             stain_col=(0.33, 0.28, 0.2), grime_col=(0.1, 0.085, 0.06))
    M["robe3"] = sbmat.silk("Sariel_SashSilkGold", (0.6, 0.4, 0.14), rough=0.55)
    M["veil"] = sbmat.silk("Sariel_VeilSilk", (0.64, 0.62, 0.57), rough=0.7, weave=200.0)
    pale = dict(barbs=45.0, vary=(0.86, 1.12), shade=0.55)
    M["fea"] = sbmat.feathers("Sariel_WingFeather", (0.64, 0.62, 0.56), sheen=(0.7, 0.66, 0.56),
                              edge_col=(0.5, 0.47, 0.4), shade_col=(0.3, 0.26, 0.2), **pale)
    M["fea_w"] = sbmat.feathers("Sariel_WingFeatherWarm", (0.62, 0.55, 0.43), sheen=(0.68, 0.58, 0.42),
                                edge_col=(0.48, 0.42, 0.32), shade_col=(0.28, 0.22, 0.15), **pale)
    M["fea_s"] = sbmat.feathers("Sariel_WingFeatherShade", (0.5, 0.46, 0.39), sheen=(0.56, 0.5, 0.4),
                                edge_col=(0.4, 0.36, 0.3), shade_col=(0.22, 0.18, 0.13), **pale)
    M["fea_p"] = sbmat.feathers("Sariel_WingFeatherPale", (0.7, 0.69, 0.65), sheen=(0.76, 0.73, 0.66),
                                edge_col=(0.56, 0.54, 0.48), shade_col=(0.34, 0.31, 0.25), **pale)
    M["fea_g"] = sbmat.feathers("Sariel_WingFeatherGilt", (0.62, 0.46, 0.2), sheen=(0.75, 0.55, 0.25),
                                edge_col=(0.5, 0.36, 0.15), shade_col=(0.24, 0.16, 0.06), **pale)
    M["wglow"] = sb.mat("Sariel_WingGlow", (0.95, 0.9, 0.78), 0.7, emission=(1.0, 0.85, 0.5), strength=0.25)
    M["sun"] = sb.mat("Sariel_SunGlowGold", (0.9, 0.7, 0.3), 0.3, emission=(1.0, 0.82, 0.45), strength=2.5)
    M["h0"] = sb.mat("Sariel_HaloInner", (1.0, 0.85, 0.5), 0.4, emission=(1.0, 0.85, 0.5), strength=5.0)
    M["h1"] = sb.mat("Sariel_HaloGold", (0.83, 0.66, 0.3), 0.4, emission=(0.95, 0.7, 0.3), strength=3.5)
    M["h2"] = sb.mat("Sariel_HaloOuter", (1.0, 0.97, 0.88), 0.4, emission=(1.0, 0.97, 0.88), strength=3.0)
    M["hd"] = sb.mat("Sariel_HaloDisc", (1.0, 0.85, 0.5), 0.4, emission=(1.0, 0.85, 0.5), strength=0.4)
    M["iris"] = sb.mat("Sariel_EyeIris", (1.0, 0.85, 0.5), 0.4, emission=(1.0, 0.85, 0.5), strength=5.0)
    M["sclera"] = sb.mat("Sariel_EyeScleraBone", (0.9, 0.88, 0.8), 0.3, emission=(1.0, 0.97, 0.88), strength=0.4)
    M["pupil"] = sb.mat("Sariel_PupilObsidian", (0.03, 0.025, 0.03), 0.2)
    M["spear"] = sb.mat("Sariel_SpearLight", (1.0, 0.97, 0.88), 0.4, emission=(1.0, 0.97, 0.88), strength=6.0)
    M["vglow"] = sb.mat("Sariel_VeilGlow", (1.0, 0.85, 0.5), 0.4, emission=(1.0, 0.85, 0.5), strength=1.5)

    root = sb.root("Sariel")
    body = sb.empty("body", root, loc=(0, 0, 0.3))
    J = {"body": body}
    chains = {}

    # ------------------------------------------------------------------ robes
    skirt = [(1.0, -0.28, 1.0), (0.98, -0.2, 1.0), (0.86, 0.15, 0.9), (0.69, 0.55, 0.7), (0.52, 0.95, 0.45),
             (0.4, 1.28, 0.2), (0.34, 1.47, 0.0)]
    kit.lathe("skirt", body, skirt, 48, material=M["robe"], folds=13, fold_amp=0.08, cap_top=False)
    kit.lathe("hem", body, [(1.012, -0.285, 1.0), (1.006, -0.23, 1.0), (1.0, -0.17, 1.0)], 48,
              material=M["gold"], folds=13, fold_amp=0.08, cap_top=False, cap_bottom=False)
    kit.lathe("hem2", body, [(0.985, -0.12, 1.0), (0.975, -0.09, 1.0)], 48, material=M["dgold"], folds=13,
              fold_amp=0.08, cap_top=False, cap_bottom=False)
    # embroidered wave band between the hems.
    pts = []
    for k in range(40):
        a = math.tau * k / 39
        zz = -0.15 + 0.035 * math.sin(a * 13)
        rr = 0.99 * (1.0 + 0.08 * 0.98 * math.sin(13 * a)) + 0.012
        pts.append((math.cos(a) * rr, math.sin(a) * rr, zz))
    kit.filigree("hem_wave", body, pts, 0.007, M["gold"], res=2)
    # faulds: ivory plates hanging from the waist, gold-edged, scrolled.
    for k in range(11):
        a = math.radians(-90 + (k - 5) * 24)
        rot = (18, 0, math.degrees(a) - 90)
        cc = (math.cos(a) * 0.45, math.sin(a) * 0.45, 1.2)
        ln = 0.5 if abs(k - 5) < 3 else 0.4
        sb.box(f"fauld{k}", body, size=(0.19, 0.026, ln), loc=cc, rot=rot, material=M["plate"], bevel=0.0,
               taper=(0.72, 1.0))
        sb.box(f"fauldtrim{k}", body, size=(0.195, 0.03, 0.025), loc=at(cc, rot, (0, 0.002, -ln * 0.5)),
               rot=rot, material=M["gold"], bevel=0.0)
        kit.filigree(f"fauldfil{k}", body, [at(cc, rot, (0, 0.016, ln * 0.45)), at(cc, rot, (0.035, 0.017, 0.08)),
                                           at(cc, rot, (-0.03, 0.017, -0.06)), at(cc, rot, (0.01, 0.017, -ln * 0.3)),
                                           at(cc, rot, (0.03, 0.016, -ln * 0.4))], 0.0055, M["gold"], res=2)

    # tabards (front/back) and sashes: 3-link cloth chains (follow-through).
    def cloth_chain(name, parent, loc, rot, ln, width, mat, trim=True, sun=False, links=3, thick=0.016,
                    taper=0.85):
        seg = ln / links
        j = sb.empty(name, parent, loc=loc, rot=rot)
        J[name] = j
        chain = [j]
        cur = j
        for k in range(links):
            w0 = width * (1.0 - (1 - taper) * k / links)
            w1 = width * (1.0 - (1 - taper) * (k + 1) / links)
            sb.box(f"{name}_cl{k}", cur, size=(w0, thick, seg + 0.04), loc=(0, 0, -seg * 0.5 + 0.01),
                   material=mat, bevel=0.0, taper=(w1 / w0, 1))
            if trim:
                for sx in (1, -1):
                    sb.box(f"{name}_tr{k}{sx}", cur, size=(0.02, thick + 0.006, seg + 0.03),
                           loc=(sx * (w0 + w1) * 0.25 * 0.94, 0, -seg * 0.5 + 0.01), rot=(0, -sx * math.degrees(
                               math.atan2((w0 - w1) * 0.5, seg)), 0), material=M["gold"], bevel=0.0)
            if k == links - 1:
                sb.box(f"{name}_hem", cur, size=(w1 + 0.01, thick + 0.008, 0.045), loc=(0, 0, -seg + 0.02),
                       material=M["gold"], bevel=0.0)
                sb.cylinder(f"{name}_tassel", cur, r1=0.025, r2=0.0, depth=0.12, loc=(0, 0, -seg - 0.05),
                            rot=(180, 0, 0), material=M["dgold"], segments=6, bevel=0.0)
            if k < links - 1:
                cur = sb.empty(f"{name}_{k + 1}", cur, loc=(0, 0, -seg))
                J[cur.name] = cur
                chain.append(cur)
        if sun:
            sj = sb.empty(f"{name}_sun", j, loc=(0, -thick, -0.36), rot=(90, 0, 0))
            sb.torus(f"{name}_sunring", sj, major=0.07, minor=0.012, material=M["sun"], major_segments=16,
                     minor_segments=3)
            sb.sphere(f"{name}_sungem", sj, radius=0.035, scale=(1, 1, 0.5), material=M["sun"], segments=8, rings=4)
            for r_ in range(12):
                ra = math.tau * r_ / 12
                ll = 0.1 if r_ % 2 else 0.055
                sb.box(f"{name}_sunray{r_}", sj, size=(0.012, ll, 0.008),
                       loc=(math.sin(ra) * (0.09 + ll * 0.5), math.cos(ra) * (0.09 + ll * 0.5), 0),
                       rot=(0, 0, -math.degrees(ra)), material=M["gold"], bevel=0.0)
            kit.filigree(f"{name}_fil", chain[1], [(0, -thick, -0.02), (0.07, -thick, -0.15), (-0.07, -thick, -0.3),
                                                   (0.0, -thick, -seg + 0.05)], 0.0065, M["gold"], res=2)
        chains[name] = chain
        return chain

    strips = []
    # front tabard / back tabard
    strips.append(cloth_chain("strip0", body, (0, -0.4, 1.36), (-22, 0, 0), 1.5, 0.36, M["robe"], sun=True))
    strips.append(cloth_chain("strip1", body, (0, 0.4, 1.36), (-20, 0, 180), 1.42, 0.38, M["robe"], sun=True))
    # sashes of varied length / colour
    for i, (ang, ln, w, mat) in enumerate(((-128, 1.25, 0.12, M["robe3"]), (-52, 1.05, 0.11, M["robe2"]),
                                           (-148, 0.95, 0.1, M["robe2"]), (-32, 1.3, 0.12, M["robe3"]),
                                           (150, 1.1, 0.11, M["robe2"]), (30, 1.15, 0.11, M["robe2"]))):
        a = math.radians(ang)
        strips.append(cloth_chain(f"strip{i + 2}", body, (math.cos(a) * 0.43, math.sin(a) * 0.43, 1.34),
                                  (24, 0, ang - 90), ln, w, mat, trim=False, thick=0.012, taper=0.8))
    # long back train falling from the shoulders (under the wings).

    # ------------------------------------------------------------------ torso
    torso = sb.empty("torso", body, loc=(0, 0, 1.45))
    J["torso"] = torso
    kit.lathe("belt", torso, [(0.34, -0.06), (0.37, -0.02), (0.37, 0.05), (0.345, 0.09)], 36, material=M["gold"],
              scale=(1, 0.8, 1))
    bk = sb.empty("buckle", torso, loc=(0, -0.3, 0.015), rot=(90, 0, 0))
    sb.torus("buckle_ring", bk, major=0.06, minor=0.014, material=M["gold"], major_segments=16, minor_segments=5)
    sb.sphere("buckle_gem", bk, radius=0.035, scale=(1, 1, 0.5), material=M["sun"], segments=10, rings=5)
    kit.lathe("abdomen", torso, [(0.31, 0.08), (0.335, 0.1), (0.315, 0.25), (0.34, 0.27), (0.325, 0.41),
                                 (0.35, 0.43), (0.345, 0.58)], 32, material=M["plate"], scale=(1, 0.78, 1))
    chest_prof = [(0.345, 0.55), (0.405, 0.68), (0.425, 0.8), (0.405, 0.92), (0.31, 1.0), (0.17, 1.045)]
    kit.lathe("chest", torso, chest_prof, 36, material=M["plate"], scale=(1, 0.72, 1), cap_bottom=False)

    def chest_pt(x, z, out=0.008, back=False):
        r = chest_prof[0][0]
        for (r0, z0), (r1, z1) in zip(chest_prof[:-1], chest_prof[1:]):
            if z0 <= z <= z1:
                r = r0 + (r1 - r0) * (z - z0) / (z1 - z0)
        y = 0.72 * math.sqrt(max(r * r - x * x, 0.0)) + out
        return (x, y if back else -y, z)

    def spiral(cx, cz, r0, turns, n, sgn, start=0.0):
        out = []
        for k in range(n):
            t = k / (n - 1)
            ang = start + sgn * turns * math.tau * t
            rr = r0 * (1.0 - 0.8 * t)
            out.append((cx + math.cos(ang) * rr, cz + math.sin(ang) * rr))
        return out

    kit.filigree("chest_ridge", torso, [chest_pt(0, z) for z in (0.58, 0.7, 0.86, 0.98)], 0.012, M["gold"])
    for s in (1, -1):
        kit.filigree(f"chest_scroll{s}", torso, [chest_pt(s * x, z) for x, z in
                     ((0.03, 0.6), (0.12, 0.7), (0.2, 0.8), (0.3, 0.9), (0.36, 0.95))], 0.008, M["gold"], res=2)
        sp = spiral(s * 0.3, 0.86, 0.06, 1.1, 9, s, math.radians(90 if s > 0 else 90))
        kit.filigree(f"chest_curl{s}", torso, [chest_pt(x, z) for x, z in sp], 0.006, M["gold"], res=2)
        kit.filigree(f"chest_scroll_b{s}", torso, [chest_pt(s * x, z) for x, z in
                     ((0.03, 0.7), (0.1, 0.8), (0.16, 0.9), (0.2, 0.97))], 0.007, M["gold"], res=2)
        sp = spiral(s * 0.17, 0.64, 0.05, 1.0, 8, -s, math.radians(-90))
        kit.filigree(f"chest_curl_b{s}", torso, [chest_pt(x, z) for x, z in sp], 0.006, M["gold"], res=2)
        kit.filigree(f"abd_line{s}", torso, [chest_pt(s * x, z, 0.0) for x, z in
                     ((0.05, 0.12), (0.12, 0.27), (0.1, 0.42), (0.04, 0.55))], 0.007, M["gold"], res=2)
        kit.filigree(f"abd_line2{s}", torso, [chest_pt(s * x, z, 0.0) for x, z in
                     ((0.22, 0.12), (0.26, 0.27), (0.23, 0.42), (0.28, 0.55))], 0.006, M["gold"], res=2)
    sunc = sb.empty("chest_sun", torso, loc=chest_pt(0, 0.8, 0.012), rot=(90, 0, 0))
    sb.torus("chest_sunring", sunc, major=0.075, minor=0.016, material=M["sun"], major_segments=20, minor_segments=4)
    sb.sphere("chest_gem", sunc, radius=0.04, scale=(1, 1, 0.5), material=M["sun"], segments=8, rings=4)
    for r in range(12):
        ra = math.tau * r / 12
        ln = 0.11 if r % 3 == 0 else 0.055
        sb.box(f"chest_ray{r}", sunc, size=(0.012, ln, 0.01),
               loc=(math.sin(ra) * (0.1 + ln * 0.5), math.cos(ra) * (0.1 + ln * 0.5), 0),
               rot=(0, 0, -math.degrees(ra)), material=M["gold"], bevel=0.0)
    kit.lathe("gorget", torso, [(0.21, 0.98), (0.235, 1.03), (0.185, 1.1), (0.13, 1.15)], 28, material=M["gold"],
              scale=(1, 0.9, 1))
    # standing collar: a fan of ivory and gold plates rising behind the head.
    for k in range(11):
        fa = (k - 5) * 15
        spike(f"collar{k}", torso, length=0.46 - 0.025 * abs(k - 5), width=0.05, thick=0.012,
              loc=(math.sin(math.radians(fa)) * 0.12, 0.13, 1.02), rot=(-24, fa, 0),
              material=M["plate"] if k % 2 == 0 else M["gold"], mid=0.4, smooth=True)
    # back plate where the wings root: a gilded reliquary spine.
    sb.box("wingroot", torso, size=(0.38, 0.12, 0.56), loc=(0, 0.24, 0.74), material=M["plate2"], bevel=0.03,
           taper=(0.7, 1))
    for k in range(4):
        sb.box(f"spine{k}", torso, size=(0.07, 0.05, 0.08), loc=(0, 0.31, 0.52 + k * 0.14), rot=(0, 45, 0),
               material=M["gold"], bevel=0.01)
    # pauldrons: three layered domes per side, gold rims, filigree curls, gilded crest.
    dome = [(0.0, 0.1), (0.14, 0.092), (0.24, 0.035), (0.272, -0.04), (0.28, -0.075)]

    def dome_pt(rr, ang, sc):
        z = dome[0][1]
        for (r0, z0), (r1, z1) in zip(dome[:-1], dome[1:]):
            if r0 <= rr <= r1:
                z = z0 + (z1 - z0) * (rr - r0) / (r1 - r0)
        return (math.cos(ang) * rr * sc, math.sin(ang) * rr * sc * 1.1, z * sc * 0.8 + 0.008)

    for s, nm in SIDES:
        for k in range(3):
            pj = sb.empty(f"pauld{nm}{k}", torso, loc=(s * (0.44 + 0.05 * k), 0, 0.97 - 0.1 * k),
                          rot=(0, s * (22 + 12 * k), 0))
            sc = 1.0 - 0.08 * k
            kit.lathe(f"pauldd{nm}{k}", pj, dome, 24, material=M["plate"], scale=(sc, sc * 1.1, sc * 0.8),
                      cap_bottom=False)
            sb.torus(f"pauldr{nm}{k}", pj, major=0.282 * sc, minor=0.014, loc=(0, 0, -0.075 * sc * 0.8),
                     material=M["gold"], major_segments=24, minor_segments=3)
            if k == 0:
                kit.filigree(f"pauldf{nm}", pj, [(0, -0.2, 0.0), (0, -0.12, 0.11), (0, 0.0, 0.15), (0, 0.12, 0.11),
                                                 (0, 0.2, 0.0)], 0.009, M["gold"])
                for q, a0 in enumerate((-1.2, 1.2)):
                    pts = []
                    for m in range(9):
                        t = m / 8
                        pts.append(dome_pt(0.2 - 0.14 * t, a0 + (1 if q else -1) * 2.4 * t * (1 if s > 0 else -1), sc))
                    kit.filigree(f"pauldcurl{nm}{q}", pj, pts, 0.006, M["gold"], res=2)
                for f in range(3):
                    spike(f"crest{nm}{f}", pj, length=0.3 - 0.05 * f, width=0.04, thick=0.008,
                          loc=(s * 0.02, 0.05 - 0.05 * f, 0.1), rot=(-10 - 15 * f, s * (10 + 15 * f), 0),
                          material=M["gold"])

    # ------------------------------------------------------------------ arms
    def arm(nm, s):
        sh = sb.empty(f"shoulder_{nm}", torso, loc=(s * 0.47, 0, 0.86))
        kit.lathe(f"rere{nm}", sh, [(0.09, -0.52), (0.105, -0.38), (0.115, -0.12), (0.1, -0.02)], 16,
                  material=M["plate"])
        sb.torus(f"rereb{nm}", sh, major=0.108, minor=0.011, loc=(0, 0, -0.38), material=M["gold"],
                 major_segments=14, minor_segments=3)
        # hanging sleeve of the under-robe
        kit.lathe(f"sleeve{nm}", sh, [(0.16, -0.5, 1.0), (0.14, -0.35, 0.6), (0.12, -0.15, 0.2)], 16,
                  material=M["robe"], folds=5, fold_amp=0.12, cap_top=False, cap_bottom=False)
        el = sb.empty(f"elbow_{nm}", sh, loc=(0, 0, -0.58))
        sb.sphere(f"couter{nm}", el, radius=0.1, scale=(1, 1, 0.9), material=M["plate"], segments=10, rings=5)
        cp = sb.empty(f"couterp{nm}", el, loc=(0, 0.06, 0.0), rot=(90, 0, 0))
        sb.torus(f"couterr{nm}", cp, major=0.05, minor=0.01, material=M["gold"], major_segments=14, minor_segments=4)
        kit.lathe(f"vamb{nm}", el, [(0.07, -0.47), (0.088, -0.38), (0.1, -0.14), (0.09, -0.04)], 16,
                  material=M["plate"])
        for z in (-0.12, -0.42):
            sb.torus(f"vambb{nm}{z}", el, major=0.095, minor=0.011, loc=(0, 0, z), material=M["gold"],
                     major_segments=14, minor_segments=3)
        kit.filigree(f"vambf{nm}", el, [(0, -0.083, -0.15), (0.03, -0.08, -0.22), (-0.03, -0.076, -0.3),
                                        (0, -0.075, -0.4)], 0.006, M["gold"])
        hd = sb.empty(f"hand_{nm}", el, loc=(0, 0, -0.5))
        kit.lathe(f"cuff{nm}", hd, [(0.07, 0.04), (0.11, -0.05), (0.1, -0.07)], 14, material=M["gold"],
                  cap_bottom=False, cap_top=False)
        sb.box(f"palm{nm}", hd, size=(0.08, 0.1, 0.13), loc=(0, 0, -0.1), material=M["plate"], bevel=0.0,
               taper=(1.0, 1.15))
        for f in range(4):
            fx = (f - 1.5) * 0.024
            sb.box(f"finger{nm}{f}", hd, size=(0.018, 0.022, 0.1 - 0.012 * abs(f - 1.5)),
                   loc=(fx, -0.01, -0.2), rot=(-25 if nm == "R" else -8, 0, 0), material=M["plate"], bevel=0.0)
        sb.box(f"thumb{nm}", hd, size=(0.02, 0.022, 0.07), loc=(-s * 0.04, -0.04, -0.12), rot=(-30, -s * 25, 0),
               material=M["plate"], bevel=0.0)
        return sh, el, hd

    shL, elL, hdL = arm("L", 1)
    shR, elR, hdR = arm("R", -1)
    J.update({"shoulder_L": shL, "elbow_L": elL, "hand_L": hdL, "shoulder_R": shR, "elbow_R": elR, "hand_R": hdR})

    # spear of light, held upright in the right hand.
    spear = sb.empty("spear", hdR, loc=(0, -0.02, -0.12))
    J["spear"] = spear
    sb.cylinder("spear_shaft", spear, r1=0.032, depth=3.74, loc=(0, 0, -1.52), material=M["spear"], segments=10,
                bevel=0.0)
    sb.cylinder("spear_butt", spear, r1=0.055, r2=0.0, depth=0.26, loc=(0, 0, -1.52), rot=(180, 0, 0),
                material=M["gold"], segments=8, bevel=0.0)
    kit.lathe("spear_pommel", spear, [(0.03, -1.53), (0.07, -1.48), (0.05, -1.41), (0.038, -1.35)], 12,
              material=M["gold"])
    for z in (-0.16, 0.14, 0.7, 1.35):
        sb.torus(f"spear_ring{z}", spear, major=0.04, minor=0.011, loc=(0, 0, z), material=M["gold"],
                 major_segments=12, minor_segments=4)
    kit.filigree("spear_wrap", spear, [(math.cos(k * 1.3) * 0.036, math.sin(k * 1.3) * 0.036, 0.75 + k * 0.05)
                                       for k in range(12)], 0.006, M["gold"], res=2)
    kit.lathe("spear_collar", spear, [(0.034, 1.98), (0.075, 2.05), (0.052, 2.12), (0.1, 2.2), (0.045, 2.28)], 14,
              material=M["gold"])
    sj = sb.empty("spear_sun", spear, loc=(0, 0, 2.17), rot=(90, 0, 0))
    sb.torus("spear_sunring", sj, major=0.13, minor=0.012, material=M["sun"], major_segments=20, minor_segments=4)
    for r in range(10):
        ra = math.tau * r / 10
        ll = 0.07 if r % 2 else 0.14
        sb.box(f"spear_rayb{r}", sj, size=(0.014, ll, 0.008),
               loc=(math.sin(ra) * (0.14 + ll * 0.5), math.cos(ra) * (0.14 + ll * 0.5), 0),
               rot=(0, 0, -math.degrees(ra)), material=M["gold"], bevel=0.0)
    for s in (1, -1):
        spike(f"spear_wing{s}", spear, length=0.42, width=0.05, thick=0.01, loc=(s * 0.04, 0, 2.22),
              rot=(0, s * 58, 0), material=M["gold"])
        spike(f"spear_wingb{s}", spear, length=0.26, width=0.035, thick=0.008, loc=(s * 0.04, 0, 2.18),
              rot=(0, s * 95, 0), material=M["dgold"])
    sb.blade("spear_head", spear, length=0.85, width=0.12, thickness=0.014, loc=(0, 0, 2.26), material=M["gold"])
    sb.blade("spear_core", spear, length=0.8, width=0.055, thickness=0.024, loc=(0, 0, 2.28), material=M["spear"])
    sb.empty("spear_tip", spear, loc=(0, 0, 3.1))

    # ------------------------------------------------------------------ head
    head = sb.empty("head", torso, loc=(0, 0, 1.12))
    J["head"] = head
    sb.cylinder("neck", head, r1=0.085, r2=0.075, depth=0.14, material=M["veil"], segments=12, bevel=0.0)
    veil = [(0.13, -0.02, 0.2), (0.15, 0.05, 0.5), (0.2, 0.15, 0.5), (0.215, 0.25, 0.2), (0.2, 0.34, 0.0),
            (0.15, 0.42, 0.0), (0.07, 0.48, 0.0), (0.0, 0.5, 0.0)]
    kit.lathe("veil", head, veil, 28, material=M["veil"], folds=9, fold_amp=0.06, scale=(0.86, 1.0, 1),
              cap_bottom=False)
    mantle = [(0.47, -0.27, 1.0), (0.38, -0.13, 0.7), (0.25, -0.02, 0.3), (0.16, 0.06, 0.0)]
    kit.lathe("mantle", head, mantle, 40, material=M["veil"], folds=15, fold_amp=0.05, scale=(1, 0.86, 1),
              cap_top=False, cap_bottom=False)
    kit.lathe("mantle_hem", head, [(0.478, -0.282, 1.0), (0.472, -0.255, 1.0)], 40, material=M["gold"], folds=15,
              fold_amp=0.05, scale=(1, 0.86, 1), cap_top=False, cap_bottom=False)
    sb.sphere("veil_glow", head, radius=0.11, loc=(0, -0.222, 0.2), scale=(0.75, 0.12, 1.0), material=M["vglow"],
              segments=14, rings=7)
    # front veil panel over the face (faceless) and a long back drape between the wing roots.

    cloth_chain("veil0", head, (0, 0.2, 0.3), (-24, 0, 180), 1.05, 0.3, M["veil"], trim=True, links=3,
                thick=0.012, taper=0.75)
    circ = sb.empty("circlet", head, loc=(0, 0, 0.33), rot=(-8, 0, 0))
    sb.torus("circlet_band", circ, major=0.19, minor=0.016, material=M["gold"], major_segments=28, minor_segments=5)
    sb.torus("circlet_band2", circ, major=0.188, minor=0.008, loc=(0, 0, 0.035), material=M["dgold"],
             major_segments=24, minor_segments=3)
    for i in range(15):
        a = -126 + i * 18
        ar = math.radians(a)
        ln = 0.14 + 0.3 * (1.0 - abs(i - 7) / 7.0) ** 1.6
        spike(f"circ_ray{i}", circ, length=ln, width=0.02 if i != 7 else 0.03, thick=0.006,
              loc=(math.sin(ar) * 0.195, -math.cos(ar) * 0.195, 0.0), rot=(16, 0, a),
              material=M["gold"] if i % 2 == 0 else M["dgold"], mid=0.15)

    sb.sphere("circ_gem", circ, radius=0.03, loc=(0, -0.205, 0.03), scale=(1, 0.6, 1.3), material=M["sun"],
              segments=10, rings=5)

    # ------------------------------------------------------------------ halo (procedurally spun in Godot)
    halo = sb.empty("halo", body, loc=(0, 0.62, 2.9), rot=(-22, 0, 0))
    tilts = [(0, 0, 0), (12, 0, 18), (-8, 0, -12)]
    spins = []
    for i in range(3):
        t = sb.empty(f"halo_tilt{i}", halo, rot=tilts[i])
        spins.append(sb.empty(f"halo_spin{i}", t))
    s0, s1, s2 = spins

    def eye(name, par, p, size, ring_mat):
        sb.sphere(f"{name}", par, radius=0.06 * size, loc=p, scale=(1.35, 0.5, 0.75), material=M["sclera"],
                  segments=8, rings=4)
        sb.cylinder(f"{name}_iris", par, r1=0.034 * size, depth=0.012, loc=(p[0], p[1] - 0.022 * size, p[2]),
                    rot=(90, 0, 0), material=M["iris"], segments=8, bevel=0.0)
        sb.box(f"{name}_pupil", par, size=(0.012 * size, 0.012, 0.05 * size), loc=(p[0], p[1] - 0.036 * size, p[2]),
               material=M["pupil"], bevel=0.0)
        lid = sb.torus(f"{name}_lid", par, major=0.078 * size, minor=0.009 * size, loc=p, rot=(90, 0, 0),
                       material=ring_mat, major_segments=12, minor_segments=3)
        lid.scale = (1.05, 0.55, 1.0)

    # inner ring: blazing band, eight eyes
    sb.torus("ring0", s0, major=0.56, minor=0.032, rot=(90, 0, 0), material=M["h0"], major_segments=56,
             minor_segments=5)
    sb.torus("ring0b", s0, major=0.49, minor=0.009, rot=(90, 0, 0), material=M["h1"], major_segments=40,
             minor_segments=3)
    sb.torus("ring0c", s0, major=0.63, minor=0.008, rot=(90, 0, 0), material=M["h1"], major_segments=48,
             minor_segments=3)
    for e in range(8):
        a = math.tau * e / 8
        eye(f"eye{e}", s0, (math.cos(a) * 0.56, -0.03, math.sin(a) * 0.56), 1.0, M["gold"])
        b_ = a + math.tau / 16
        spike(f"spike0_{e}", s0, length=0.12, width=0.02, thick=0.005,
              loc=(math.sin(b_) * 0.63, 0, math.cos(b_) * 0.63), rot=(0, math.degrees(b_), 0), material=M["h0"])
    # middle ring: two rails with an inscription of runes between, four crystal studs
    for nm_, rr in (("ring1a", 0.86), ("ring1b", 1.0)):
        sb.torus(nm_, s1, major=rr, minor=0.016, rot=(90, 0, 0), material=M["h1"], major_segments=64,
                 minor_segments=4)
    rng = random.Random(7)
    for k in range(40):
        a = math.tau * k / 40
        if k % 10 == 5:
            kit.crystal(f"stud{k}", s1, height=0.16, radius=0.045, sides=4, top=0.5,
                        loc=(math.sin(a) * 0.93, -0.02, math.cos(a) * 0.93), rot=(0, math.degrees(a), 0),
                        material=M["h0"], jitter=0.0, seed=k)
            continue
        glyph = sb.empty(f"rune{k}", s1, loc=(math.sin(a) * 0.93, 0, math.cos(a) * 0.93), rot=(0, math.degrees(a), 0))
        sb.box(f"rune{k}_a", glyph, size=(0.012, 0.014, 0.09), material=M["h1"], bevel=0.0)
        for q in range(rng.randint(1, 2)):
            sb.box(f"rune{k}_b{q}", glyph, size=(0.01, 0.014, 0.045), loc=(rng.choice((-0.018, 0.018)), 0,
                                                                            rng.uniform(-0.025, 0.025)),
                   rot=(0, rng.choice((-40, 40, 0, 90)), 0), material=M["h1"], bevel=0.0)
    # outer ring: thin ring of light with four great eyes and a sunburst of rays
    sb.torus("ring2", s2, major=1.25, minor=0.015, rot=(90, 0, 0), material=M["h2"], major_segments=72,
             minor_segments=4)

    for e in range(4):
        a = math.tau * e / 4 + math.pi / 4
        eye(f"eyeo{e}", s2, (math.cos(a) * 1.21, -0.03, math.sin(a) * 1.21), 1.25, M["h1"])
    for k in range(40):
        a = math.tau * k / 40
        if k % 10 == 5:
            continue
        ln = 0.22 if k % 2 == 0 else 0.12
        if k % 5 == 0:
            ln = 0.52
        spike(f"ray{k}", s2, length=ln, width=0.022 if ln < 0.3 else 0.036, thick=0.005,
              loc=(math.sin(a) * 1.26, 0, math.cos(a) * 1.26), rot=(0, math.degrees(a), 0), material=M["h2"],
              mid=0.12)
    sb.cylinder("halo_disc", halo, r1=1.12, depth=0.004, loc=(0, 0.06, 0), rot=(90, 0, 0), material=M["hd"],
                segments=48, bevel=0.0, smooth=False)

    # ------------------------------------------------------------------ wings
    wings = {}
    chunks = []
    for p, cfg in enumerate(WINGS):
        for s, nm in SIDES:
            wings[(p, s)] = build_wing(p, s, nm, cfg, torso, M, J, chunks)

    kit.merge_joint_meshes(root)
    for pl, j in chunks:
        pl.done(j.name + "_mesh", j)
    _animate(J, chains, wings, root)
    sb.tri_report("sariel")
    print("SARIEL TRIS", kit.tri_count())
    return root


# ====================================================================== animation

def _wrap(d):
    return (d + 180.0) % 360.0 - 180.0


def _animate(J, chains, wings, root):
    # Posed rest: arms / head from REST, spear kept upright in the world.
    for n, r in REST.items():
        J[n].rotation_euler = Euler([math.radians(a) for a in r])
    spear_rest = Euler(J["spear"].rotation_euler)

    def spear_abs(arm, world=(0, 0, 0)):
        m = R(arm["shoulder_R"]) @ R(arm["elbow_R"]) @ R(arm["hand_R"])
        loc = m.inverted() @ R(world)
        return loc.to_euler("XYZ", spear_rest)

    e = spear_abs(REST)
    J["spear"].rotation_euler = e
    spear_rest = Euler(e)
    SPEAR_REST = tuple(math.degrees(a) for a in spear_rest)

    keyed = list(J.values())
    chain_list = list(chains.values())

    def new(name, frames):
        c = A.Clip(name, frames, loop=True, joints=keyed)
        # A whisper of motion on every joint: the glTF exporter drops constant channels, and every
        # clip must carry rot + loc tracks for every joint so Godot's filtered blends layer cleanly.
        for k, j in enumerate(keyed):
            c.add(j, lambda f, k=k: (0.03 * math.sin(math.tau * f / frames + k), 0, 0), "rot")
            c.add(j, lambda f, k=k: (0, 0, 0.0002 * math.sin(math.tau * f / frames + k)), "loc")
        return c

    def arms(c, pose, frame=0, world=(0, 0, 0), ease="smooth"):
        """Key absolute arm/head rotations (missing = REST) and the spear (kept at `world`)."""
        full = dict(REST)
        full.update({k: v for k, v in pose.items() if k in REST})
        for n in REST:
            c.key(J[n], frame, rot=tuple(full[n][i] - REST[n][i] for i in range(3)), ease=ease)
        sp = spear_abs(full, world)
        c.key(J["spear"], frame, rot=tuple(_wrap(math.degrees(sp[i]) - SPEAR_REST[i]) for i in range(3)),
              ease=ease)

    def wing_mounts(c, poses, frame=0):
        """poses[p] = (dtilt, delev, dsweep) for the left wing; mirrored to the right."""
        for (p, s), (mount, chain, pri) in wings.items():
            dt, de, ds = poses[p]
            c.key(mount, frame, rot=(dt, -s * de, s * ds))

    def wing_chain(c, poses, frame=0):
        """poses[p] = [(rx, ry, rz) arm, fore, hand] offsets for the left wing (ry + = down)."""
        for (p, s), (mount, chain, pri) in wings.items():
            for j, r in zip(chain, poses[p]):
                c.key(j, frame, rot=(r[0], s * r[1], s * r[2]))

    def beat(c, amp, bias, down=0.4, lag=0.07, flex=24.0, sweep=12.0, twist=8.0, spread=9.0, fold=6.0,
             lift=0.05, pitch=1.5, scale=(1.0, 1.0, 1.0)):
        stroke = A.cyc(c, [(0.0, -1.0, "sine_inout"), (down, 1.0, "sine_inout"), (1.0, -1.0)])
        opn = A.cyc(c, [(0.0, 1.0), (down * 0.85, 1.0), (down + (1 - down) * 0.3, 0.0), (0.92, 0.0), (1.0, 1.0)])
        for (p, s), (mount, chain, pri) in wings.items():
            off = -WINGS[p]["off"]
            k = scale[p]
            for i, j in enumerate(chain):
                def fn(f, i=i, off=off, s=s, k=k):
                    ph = A.phase(c, f, 1, off - lag * i)
                    st = stroke(ph)
                    o = opn(A.phase(c, f, 1, off - lag * i * 0.5))
                    if i == 0:
                        v = (-twist * (1 - o), k * amp * st + bias, 0.0)
                    else:
                        ang = k * amp * 0.35 * st * (0.8 ** (i - 1))
                        v = (0.0, ang + flex * (1 - o) * (1.0 if i == 1 else -0.5), sweep * (1 - o))
                    return (v[0], s * v[1], s * v[2])
                c.add(j, fn, "rot")
            for q, pj in enumerate(pri):
                fs = (0.35, 0.7, 1.0)[q]

                def ff(f, fs=fs, off=off, s=s):
                    o = opn(A.phase(c, f, 1, off - lag))
                    return (0.0, 0.0, -s * fs * (spread * o - fold * (1 - o)))
                c.add(pj, ff, "rot")
        lift_c = A.cyc(c, [(0.0, -0.4), (down + 0.08, 1.0), (1.0, -0.4)])
        c.add(J["body"], lambda f: (0, 0, lift * lift_c(A.phase(c, f, 1, 0))), "loc")
        c.add(J["body"], lambda f: (pitch * stroke(A.phase(c, f, 1, -0.12)), 0, 0), "rot")

    def living(c, seed=0, amp=1.0):
        A.noise(c, J["head"], rot=(2.0 * amp, 3.0 * amp, 1.5 * amp), freq=0.35, seed=seed + 1)
        A.noise(c, J["torso"], rot=(1.0 * amp, 1.2 * amp, 0.8 * amp), freq=0.3, seed=seed + 2)
        for k, n in enumerate(("shoulder_L", "elbow_L", "shoulder_R")):
            A.noise(c, J[n], rot=(2.0 * amp, 1.2 * amp, 1.0 * amp), freq=0.35, seed=seed + 3 + k)
        A.breathe(c, J["torso"], amp=1.2 * amp, rise=0.006 * amp, swell=0.0, cycles=1)

    def cloth(c, wind=None, floor=None, gravity=6.0, freq=1.5, damping=0.12):
        for ch in chain_list:
            A.follow_through(c, ch, freq=freq, damping=damping, gravity=gravity, falloff=0.85, wind=wind,
                             floor=floor)

    # ---- idle: majestic hover, staggered beats, robes and veil trailing the bob.
    c = new("idle", FLAP)
    arms(c, {})
    beat(c, amp=22.0, bias=2.0, lift=0.06, scale=(0.8, 1.0, 0.75))
    living(c, 0)
    cloth(c)
    c.bake()

    # ---- glide: wings held wider and swept, shallow beats, leaning into the motion, robes streaming.
    c = new("glide", FLAP)
    arms(c, {"shoulder_L": (12, -14, 0), "elbow_L": (-16, 0, 0), "shoulder_R": (4, 12, 0)})
    c.key(J["body"], 0, rot=(9, 0, 0))
    c.key(J["head"], 0, rot=(-8, 0, 0))
    wing_chain(c, {0: [(6, -6, 12), (0, 4, 0), (0, 0, 0)], 1: [(6, -4, 14), (0, 3, 0), (0, 0, 0)],
                   2: [(4, -2, 14), (0, 2, 0), (0, 0, 0)]})
    beat(c, amp=12.0, bias=0.0, flex=14.0, sweep=8.0, lift=0.035, pitch=1.0)
    living(c, 10, 0.7)
    cloth(c, wind=(0, 9.0, 1.0))
    c.bake()

    # ---- raise: the spear lifted high overhead, wings rising behind it.
    c = new("raise", POSE)
    arms(c, {"shoulder_R": (-160, -22, 0), "elbow_R": (-12, 0, 0), "head": (-14, 0, 0),
             "shoulder_L": (-24, -34, 0), "elbow_L": (-22, 0, 0)}, world=(6, 0, 0))
    c.key(J["torso"], 0, rot=(-7, 0, 0))
    wing_mounts(c, {0: (6, 18, -6), 1: (4, 20, -4), 2: (2, 16, -6)})
    A.jitter(c, J["shoulder_R"], rot=(0.8, 0.5, 0.5), freq=7.0, seed=3)
    living(c, 20, 0.5)
    cloth(c)
    c.bake(step=2)

    # ---- channel: arms thrust forward, palms out, spear levelled; leaning back against the light.
    c = new("channel", POSE)
    arms(c, {"shoulder_L": (-82, -22, 0), "elbow_L": (-8, 0, 0), "hand_L": (-55, 0, 0), "head": (-6, 0, 0),
             "shoulder_R": (-72, 22, 0), "elbow_R": (-24, 0, 0)}, world=(80, 0, 0))
    c.key(J["torso"], 0, rot=(-10, 0, 0))
    A.jitter(c, J["torso"], rot=(0.6, 0.4, 0.4), freq=6.0, seed=4)
    A.jitter(c, J["shoulder_L"], rot=(1.0, 0.8, 0.6), freq=8.0, seed=5)
    A.jitter(c, J["shoulder_R"], rot=(0.8, 0.6, 0.6), freq=8.0, seed=6)
    living(c, 30, 0.4)
    cloth(c, wind=(0, 3.0, 2.0))
    c.bake(step=2)

    # ---- summon: arms flung open and up, face lifted, wings flared.
    c = new("summon", POSE)
    arms(c, {"shoulder_L": (-34, -96, 0), "elbow_L": (-14, 0, 0), "hand_L": (-30, 0, 0),
             "shoulder_R": (-34, 92, 0), "elbow_R": (-20, 0, 0), "head": (-18, 0, 0)})
    c.key(J["torso"], 0, rot=(-8, 0, 0))
    wing_mounts(c, {0: (8, 14, -10), 1: (6, 10, -12), 2: (6, 14, -16)})
    living(c, 40, 0.6)
    cloth(c)
    c.bake(step=2)

    # ---- spread (enraged): every wing flung wide and high, primaries fanned open, chest thrown out.
    c = new("spread", POSE)
    c.key(J["torso"], 0, rot=(-6, 0, 0))
    wing_mounts(c, {0: (4, 24, -8), 1: (8, 20, -12), 2: (10, 34, -30)})
    for (p, s), (mount, chain, pri) in wings.items():
        for q, pj in enumerate(pri):
            c.key(pj, 0, rot=(0, 0, -s * (8, 16, 24)[q]))
    A.noise(c, J["torso"], rot=(1.2, 0.8, 0.6), freq=0.4, seed=50)
    A.breathe(c, J["torso"], amp=2.0, rise=0.01, swell=0.0, cycles=1)
    cloth(c)
    c.bake(step=2)

    # ---- kneel (death): sinks and bows, braced on the spear; wings droop, fold and tremble.
    c = new("kneel", POSE)
    arms(c, {"shoulder_R": (-36, 14, 0), "elbow_R": (-40, 0, 0), "head": (38, 0, 0),
             "shoulder_L": (16, -8, 0), "elbow_L": (-10, 0, 0), "hand_L": (14, 0, 0)}, world=(-8, 0, 0))
    c.key(J["body"], 0, rot=(12, 0, 0), loc=(0, 0.05, -0.5))
    c.key(J["torso"], 0, rot=(22, 0, 0))
    wing_mounts(c, {0: (-70, -46, 34), 1: (-56, -36, 26), 2: (-34, -22, 12)})
    wing_chain(c, {p: [(0, 14, 6), (0, 22, 10), (0, 14, 8)] for p in range(3)})
    for (p, s), (mount, chain, pri) in wings.items():
        for q, pj in enumerate(pri):
            c.key(pj, 0, rot=(0, 0, s * (4, 8, 12)[q]))
        for k, j in enumerate(chain):
            A.jitter(c, j, rot=(0.4, 1.2, 0.6), freq=7.0, seed=60 + p * 6 + k + (3 if s < 0 else 0))
    A.jitter(c, J["torso"], rot=(0.5, 0.3, 0.3), freq=5.0, seed=70)
    cloth(c, floor=0.03, gravity=8.0)
    c.bake(step=2)

    # ---- descent: wings raised high like a stooping eagle, robes and veil streaming upward.
    c = new("descent", POSE)
    arms(c, {"shoulder_L": (-8, -30, 0), "elbow_L": (-14, 0, 0), "shoulder_R": (-8, 26, 0),
             "elbow_R": (-32, 0, 0), "head": (-4, 0, 0)})
    c.key(J["body"], 0, rot=(-4, 0, 0))
    wing_mounts(c, {0: (10, 34, 6), 1: (14, 44, 6), 2: (16, 52, -6)})
    wing_chain(c, {p: [(0, -6, 4), (0, 10, 8), (0, 6, 4)] for p in range(3)})
    for (p, s), (mount, chain, pri) in wings.items():
        A.noise(c, chain[2], rot=(1.0, 4.0, 2.0), freq=2.0, seed=80 + p + (3 if s < 0 else 0))
    living(c, 90, 0.5)
    cloth(c, wind=(0, 2.0, 14.0))
    c.bake(step=2)
