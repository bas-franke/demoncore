"""Lilaeth, the Fallen Seraph: tall and slender, pale, in a fitted black bodice and long flowing
robe panels (torn hems, crimson silk showing through the front slit); vast ragged black feathered
wings whose torn tips still smoulder; a woven crown of thorns, a gold mask with burning eye slits
and a cracked, burning halo. Ash-silver hair.

Rig: the shared demon humanoid (_demon_kit.humanoid) + wings (wing_X > wing_mid_X > wingtip_X >
pfan0..2_X primary fans), 10 robe-panel chains (robe<a>_<k>), hair / front-lock chains, halo >
halo_spin, cast_fx (hellfire in the right hand) and sweep_fx (cast arc). All animation is authored
with sbanim (keys + generators + follow_through on robe, hair and locks).
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
# Procedural sbmat surfaces (porcelain skin, worn black steel, gilt, robe weave, silk, feather
# barbs...) baked into one atlas (tools/blender/bake.py); glows stay flat emissive materials.
BAKE = {"size": 1024, "samples": 16}

LEG = 0.5 + 0.47          # thigh + shin
WALK_SPEED = 7.2          # m/s the walk cycle is authored for (6.0 base + 1.2 perk)


# ============================================================================ local mesh helpers

def _axes(d, n):
    z = Vector(d).normalized()
    x = Vector(n).cross(z)
    if x.length < 1e-4:
        x = Vector((1, 0, 0)).cross(z)
    x.normalize()
    return x, z.cross(x), z


def plume(name, parent, base, d, length, width, mats, n=(0, 1, 0), bend=0.05, sweep=0.0, rows=7,
          torn=False, singe=0, rng=None, notch=0.25, asym=0.35, thick=0.0045, cup=0.18):
    """Single feather built in the parent's space: vane with a raised rachis, rounded tip,
    asymmetric (narrow leading edge), random torn notches; torn=True leaves a ragged, ripped end.
    singe = number of tip segments using mats[1] (smouldering ember edge)."""
    rng = rng or random.Random(name)
    x, y, z = _axes(d, n)
    base = Vector(base)
    bm = bmesh.new()
    rings = []
    tear = rng.choice((-1, 1))
    for i in range(rows + 1):
        t = i / rows
        if t < 0.16:
            prof = 0.3 + 0.7 * (t / 0.16) ** 0.7
        elif t < 0.68:
            prof = 1.0
        else:
            prof = math.sqrt(max(0.0, 1.0 - ((t - 0.68) / 0.32) ** 2))
        wl = width * prof * (1 - asym * 0.5)
        wr = width * prof * (1 + asym * 0.5)
        cx = 0.0
        if 0 < i < rows and rng.random() < notch:
            if rng.random() < 0.5:
                wl *= rng.uniform(0.25, 0.6)
            else:
                wr *= rng.uniform(0.25, 0.6)
        if i == rows:
            if torn:
                wl, wr = width * rng.uniform(0.15, 0.4), width * rng.uniform(0.05, 0.25)
                cx = tear * width * 0.35
            else:
                wl = wr = 0.0012
        elif torn and i == rows - 1:
            cx = -tear * width * 0.15
        c = base + z * (length * t) + y * (bend * length * t * t) + x * (sweep * length * t * t + cx)
        e = y * (-cup * width * prof)
        th = thick * (1.0 - 0.6 * t)
        rings.append([bm.verts.new(c - x * wl + e), bm.verts.new(c + y * th), bm.verts.new(c + x * wr + e)])
    ember = []
    for i, (a, b) in enumerate(zip(rings[:-1], rings[1:])):
        for k in range(3):
            bm.faces.new((a[k], a[(k + 1) % 3], b[(k + 1) % 3], b[k]))
            ember.append(bool(singe and i >= rows - singe))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    ember += [False, bool(singe)]
    o = K._obj(name, bm, parent, mats[0])
    if singe:
        o.data.materials.append(mats[1])
        for p, e_ in zip(o.data.polygons, ember):
            p.material_index = 1 if e_ else 0
    return o


def cloth_seg(name, parent, seg_len, v0, v1, top_w, bot_w, mat, nx=5, ny=2, folds=1.5, fold_amp=0.03,
              phase=0.0, flare=0.06, cup=0.03, rag=0.0, seed=0, thick=0.008, overlap=0.008, mat2=None):
    """One segment of a hanging cloth chain (top edge at the joint, hangs along -Z, faces -Y).
    v0..v1 = this segment's span along the whole panel (0 top .. 1 hem) so folds, flare and
    widths continue seamlessly from segment to segment. rag > 0 tears the hem into tongues."""
    rng = random.Random(seed)
    lens = []
    for i in range(nx + 1):
        r = rng.random() if i % 2 else rng.random() * 0.3
        lens.append(seg_len * (1.0 - rag * r) if rag else seg_len + overlap)
    bm = bmesh.new()
    grid = []
    for j in range(ny + 1):
        a = j / ny
        row = []
        for i in range(nx + 1):
            u = i / nx - 0.5
            L = lens[i] * a
            v = v0 + (v1 - v0) * min(1.0, L / seg_len)
            w = top_w + (bot_w - top_w) * v
            y = (fold_amp * (0.25 + v) * math.sin(2 * math.pi * (u * folds) + phase)
                 + cup * (2 * u) ** 2 - flare * v * v)
            row.append(bm.verts.new((u * w, y, -L)))
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if thick > 0:
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    o = K._obj(name, bm, parent, mat)
    if mat2 is not None:   # inner face of the cloth (seen when it flares / flutters)
        o.data.materials.append(mat2)
        for p in o.data.polygons:
            p.material_index = 1 if p.normal.y > 0.3 else 0
    return o


def chain_panel(R, prefix, parent, loc, rot, length, nseg, top_w, bot_w, mat, rag=0.4, seed=1, **kw):
    """Hanging cloth chain: nseg joints, each with its own segment mesh (for follow_through)."""
    seg = length / nseg
    js = []
    p = parent
    for k in range(nseg):
        j = sb.empty(f"{prefix}_{k}", p, loc=loc if k == 0 else (0, 0, -seg), rot=rot if k == 0 else (0, 0, 0))
        R.extra.append(j)
        js.append(j)
        cloth_seg(f"{prefix}_{k}_m", j, seg, k / nseg, (k + 1) / nseg, top_w, bot_w, mat,
                  rag=rag if k == nseg - 1 else 0.0, seed=seed + k, **kw)
        p = j
    return js


# ============================================================================ build

def build():
    L = K.lin
    skin = sbmat.skin("Lilaeth_Skin", L((0.74, 0.68, 0.66)), rough=0.48, pores=140.0,
                      crease=L((0.42, 0.33, 0.34)), high=L((0.84, 0.79, 0.77)), veins=0.25,
                      vein_col=L((0.5, 0.42, 0.5)))
    armor = sbmat.worn_steel("Lilaeth_ArmorSteel", L((0.12, 0.11, 0.125)), roughness=0.3, edge_k=3.5,
                             scratch_k=2.0, grime=0.7)
    gilt = sbmat.gold_filigree("Lilaeth_Gold", tint=L((0.76, 0.56, 0.27)), scale=1.6)
    robe = sbmat.linen("Lilaeth_RobeCloth", L((0.085, 0.064, 0.082)), weave=90.0, rough=0.82, stain=0.4,
                       stain_col=L((0.17, 0.13, 0.15)), grime_col=L((0.02, 0.015, 0.02)))
    lining = sbmat.silk("Lilaeth_SilkCloth", L((0.4, 0.035, 0.05)), rough=0.5)
    hair = sbmat.hair("Lilaeth_HairSilk", L((0.66, 0.64, 0.66)), rough=0.45)
    feath = sbmat.feathers("Lilaeth_WingFeather", L((0.06, 0.054, 0.068)), barbs=60.0)
    # Smouldering feather edges: bright enough to trace the wing outline from the high game camera
    # (characters-polish; was 1.3, which vanished against dark ground).
    ember = K.mat("Lilaeth_FeatherEmber", (0.2, 0.03, 0.02), 0.6, 0.0, (1.0, 0.2, 0.05), 3.2)
    thorn = sbmat.horn("Lilaeth_ThornBranch", L((0.12, 0.09, 0.08)), rough=0.6, rings=35.0)
    claw = sbmat.horn("Lilaeth_Claw", L((0.07, 0.055, 0.07)), rough=0.3, rings=45.0)
    fire = K.mat("Lilaeth_HellfireGlow", (0.4, 0.05, 0.04), 0.5, 0.0, (1.0, 0.18, 0.08), 8.0)
    halo_m = K.mat("Lilaeth_HaloGlow", (0.7, 0.42, 0.14), 0.4, 0.5, (1.0, 0.5, 0.16), 7.0)
    char = K.mat("Lilaeth_HaloCharGold", (0.2, 0.13, 0.06), 0.45, 1.0)
    eyes = K.mat("Lilaeth_EyeGlow", (0.6, 0.1, 0.08), 0.5, 0.0, (1.0, 0.25, 0.15), 14.0)
    gem = K.mat("Lilaeth_EmberGem", (0.5, 0.04, 0.03), 0.15, 0.0, (1.0, 0.12, 0.06), 4.0)
    lips = K.mat("Lilaeth_LipSkin", (0.3, 0.06, 0.07), 0.45)
    FM = (feath, ember)

    R = K.humanoid("Lilaeth", hip_h=1.06, thigh=0.5, shin=0.47, hip_w=0.09, spine=0.22, chest=0.36,
                   neck=0.1, shoulder_w=0.19, shoulder_z=0.3, upper=0.31, fore=0.29, arm_out=8,
                   spine_rot=-2, head_rot=4)
    rng = random.Random(7)
    H, SP, C, Hd = R.hips, R.spine, R.chest, R.head

    # ------------------------------------------------------------------ hips, girdle, robe chains
    K.loft("pelvis", H, [(0, 0, -0.14), (0, 0, -0.05), (0, 0, 0.06), (0, 0, 0.12)],
           [(0.12, 0.1), (0.165, 0.12), (0.155, 0.112), (0.135, 0.098)], armor, segs=12)
    K.shell("girdle_belt", H, (0.172, 0.132, 0.045), lat=(-40, 40), lon=(-180, 180), segs=(14, 2), thick=0.016,
            material=gilt, loc=(0, 0, 0.05))
    # girdle clasp + hanging chain medallion
    sb.sphere("girdle_gem", H, 0.026, loc=(0, -0.142, 0.05), scale=(1, 0.5, 1.25), material=gem, segments=8, rings=6)
    K.loft("girdle_clasp", H, [(0.035 * math.sin(a), -0.137 - 0.004 * math.cos(a), 0.05 + 0.04 * math.cos(a))
                               for a in [k * math.pi / 6 for k in range(13)]], [0.006] * 13, gilt, segs=4, caps=(False, False))
    gpath = K.catmull([(-0.15, -0.07, 0.03), (-0.08, -0.16, -0.06), (0.0, -0.175, -0.09),
                       (0.08, -0.16, -0.06), (0.15, -0.07, 0.03)], 5)
    K.loft("girdle_chain", H, gpath, [0.0045 + 0.0025 * (i % 2) for i in range(len(gpath))], gilt, segs=4)
    sb.sphere("girdle_drop", H, 0.016, loc=(0, -0.175, -0.115), scale=(1, 0.6, 1.5), material=gem, segments=6, rings=4)

    robes = []
    spec = [  # angle, length, top_w, bot_w, tilt
        (-34, 0.95, 0.13, 0.26, -3), (34, 0.95, 0.13, 0.26, -3),
        (-62, 0.98, 0.16, 0.3, -5), (62, 0.98, 0.16, 0.3, -5),
        (-102, 1.0, 0.16, 0.32, -6), (102, 1.0, 0.16, 0.32, -6),
        (-142, 1.05, 0.16, 0.34, -6), (142, 1.05, 0.16, 0.34, -6),
        (180, 1.12, 0.18, 0.38, -7),
    ]
    for i, (a, L, tw, bw, tilt) in enumerate(spec):
        ar = math.radians(a)
        loc = (math.sin(ar) * 0.172, -math.cos(ar) * 0.135, 0.035)
        js = chain_panel(R, f"robe{i}", H, loc, (tilt, 0, a), L, 3, tw, bw, robe, rag=0.42, seed=11 + i * 5,
                         folds=1.5 + 0.5 * (i % 2), fold_amp=0.04, phase=i * 1.7, flare=0.06, cup=0.035, mat2=lining,
                         nx=5, ny=2)
        robes.append((js, a))
    # crimson silk under-panel in the front slit
    ln = chain_panel(R, "robe_silk", H, (0, -0.118, 0.02), (-2, 0, 0), 0.88, 3, 0.13, 0.2, lining, rag=0.3,
                     seed=77, folds=2.0, fold_amp=0.018, flare=0.03, cup=0.04, nx=4, ny=2)
    robes.append((ln, 0))

    # ------------------------------------------------------------------ legs: black greaves, pointed sabatons
    for s in SIDES:
        T, S_, F = R.thigh[s], R.shin[s], R.foot[s]
        n = sname(s)
        K.loft(f"thigh_{n}", T, [(0, 0, 0.05), (0, -0.005, -0.12), (0, 0, -0.32), (0, 0, -0.5)],
               [0.08, 0.082, 0.066, 0.054], armor, segs=8)
        K.shell(f"knee_{n}", S_, (0.06, 0.058, 0.066), lat=(-40, 90), lon=(-100, 100), segs=(6, 3), thick=0.014,
                material=armor, loc=(0, -0.03, 0.0), flare=0.15)
        K.loft(f"shin_{n}", S_, [(0, 0, 0.02), (0, 0.01, -0.15), (0, 0, -0.35), (0, 0, -0.47)],
               [0.056, 0.058, 0.042, 0.037], armor, segs=8)
        K.loft(f"greave_trim_{n}", S_, [(0, -0.062, -0.06), (0, -0.07, -0.2), (0, -0.055, -0.38)],
               [0.006, 0.008, 0.005], gilt, segs=4)
        K.loft(f"foot_{n}", F, [(0, 0.04, 0.0), (0, -0.04, -0.02), (0, -0.14, -0.04), (0, -0.22, -0.045)],
               [(0.042, 0.038), (0.047, 0.038), (0.037, 0.02), (0.005, 0.005)], armor, segs=8, sharp=40)

    # ------------------------------------------------------------------ torso: bodice, gilt filigree, hellfire seams
    K.loft("waist", SP, [(0, 0, -0.08), (0, 0, 0.08), (0, 0, 0.24)], [(0.13, 0.095), (0.118, 0.088), (0.15, 0.105)],
           armor, segs=12)
    for k, z in enumerate((0.0, 0.12)):
        K.shell(f"corset{k}", SP, (0.138 + k * 0.007, 0.104, 0.065), lat=(-50, 25), lon=(-110, 110), segs=(9, 2),
                thick=0.01, material=armor, loc=(0, 0, z), flare=0.08)
        K.loft(f"corset_lace{k}", SP, [K.on_ell((0, 0, z), (0.14 + k * 0.007, 0.106, 0.055), 18, lo, 1.04)
                                       for lo in (-100, -60, -25, 0, 25, 60, 100)], [0.004] * 7, gilt, segs=4)
    K.loft("torso", C, [(0, 0, -0.06), (0, 0, 0.1), (0, 0, 0.24), (0, 0.01, 0.33), (0, 0.01, 0.4)],
           [(0.14, 0.095), (0.17, 0.11), (0.18, 0.115), (0.17, 0.105), (0.09, 0.075)], skin, segs=14)
    bp_c, bp_r = (0, 0.0, 0.16), (0.196, 0.138, 0.235)
    K.shell("breastplate", C, bp_r, lat=(-62, 58), lon=(-95, 95), segs=(12, 6), thick=0.02, material=armor,
            loc=bp_c, flare=0.03)
    K.shell("backplate", C, bp_r, lat=(-60, 45), lon=(95, 265), segs=(10, 5), thick=0.018, material=armor, loc=bp_c)
    K.loft("bp_trim_top", C, [K.on_ell(bp_c, bp_r, 58 - 10 * abs(math.sin(math.radians(lo))), lo, 1.08)
                              for lo in (-92, -60, -30, 0, 30, 60, 92)], [0.007] * 7, gilt, segs=4, ref=(0, 0, 1))
    K.loft("bp_trim_mid", C, [K.on_ell(bp_c, bp_r, la, 0, 1.1) for la in (55, 30, 0, -30, -58)], [0.006] * 5, gilt, segs=4)
    for s in SIDES:   # filigree scrolls on the bodice
        K.loft(f"bp_scroll_{sname(s)}", C, K.catmull([K.on_ell(bp_c, bp_r, la, s * lo, 1.09) for la, lo in
                                                      ((45, 12), (30, 30), (12, 38), (0, 28), (6, 18))], 2),
               [0.004] * 9, gilt, segs=4)
    K.crack("bp_crack1", C, bp_c, bp_r, [(30, -8), (20, -18), (8, -22), (-6, -34)], fire, r=0.0035, off=1.1)
    K.crack("bp_crack2", C, bp_c, bp_r, [(-14, 6), (-26, 16), (-40, 14)], fire, r=0.003, off=1.1)
    # heart clasp: gold ring + ember gem at the sternum
    K.loft("heart_ring", C, [(0.03 * math.sin(a), -0.15, 0.24 + 0.034 * math.cos(a)) for a in
                             [k * math.pi / 6 for k in range(13)]], [0.006] * 13, gilt, segs=4, caps=(False, False))
    sb.sphere("heart_gem", C, 0.02, loc=(0, -0.152, 0.24), scale=(1, 0.6, 1.3), material=gem, segments=8, rings=6)
    # gorget collar + choker
    K.shell("collar", C, (0.115, 0.095, 0.11), lat=(-20, 60), lon=(80, 280), segs=(10, 3), thick=0.014, material=armor,
            loc=(0, 0.0, 0.37), flare=0.3)
    K.loft("collar_trim", C, [K.on_ell((0, 0, 0.37), (0.115, 0.095, 0.11), 60, lo, 1.05) for lo in range(85, 280, 30)],
           [0.005] * 7, gilt, segs=4)
    # feather mantle around the shoulders/upper back (frames the head from above)
    for k in range(16):
        a = math.radians(-118 + k * (236 / 15) + 180)        # around the back
        base = Vector((math.sin(a) * 0.15, -math.cos(a) * 0.11, 0.36))
        out = Vector((math.sin(a), -math.cos(a), 0))
        plume(f"mantle{k}", C, base, out * 0.9 + Vector((0, 0.15, -1.0)), 0.22 + 0.05 * rng.random(), 0.045,
              FM, n=(0, 0, 1) if False else -out, bend=0.08, rows=4, rng=rng, notch=0.2)
    for k in range(10):
        a = math.radians(-100 + k * (200 / 9) + 180)
        base = Vector((math.sin(a) * 0.12, -math.cos(a) * 0.1, 0.4))
        out = Vector((math.sin(a), -math.cos(a), 0))
        plume(f"mantle_up{k}", C, base, out * 0.8 + Vector((0, 0.1, -0.6)), 0.16, 0.035, FM, n=-out, bend=0.1,
              rows=3, rng=rng)

    # ------------------------------------------------------------------ arms: pale, gold armlets, black bracers, clawed hands
    for s in SIDES:
        Ar, Fo, Ha = R.arm[s], R.fore[s], R.hand[s]
        n = sname(s)
        K.loft(f"upperarm_{n}", Ar, [(0, 0, 0.05), (0, 0, -0.08), (0, 0, -0.31)], [0.056, 0.052, 0.041], skin, segs=10)
        K.shell(f"pauldron_{n}", Ar, (0.075, 0.08, 0.06), lat=(0, 90), lon=(-180, 180), segs=(9, 2), thick=0.012,
                material=armor, loc=(s * 0.015, 0, 0.02), rot=(0, -s * 18, 0), flare=0.15)
        K.loft(f"pauldron_trim_{n}", Ar, [(s * 0.015 + s * 0.084 * math.sin(math.radians(a)), -0.09 * math.cos(math.radians(a)),
                                           0.02 - 0.01 * abs(math.sin(math.radians(a)))) for a in range(-150, 151, 30)],
               [0.005] * 11, gilt, segs=4, ref=(0, 0, 1))
        sb.sphere(f"shoulder_gem_{n}", Ar, 0.016, loc=(s * 0.07, -0.04, 0.035), scale=(1, 0.6, 1), material=gem,
                  segments=6, rings=4)
        for k in range(5):   # black feathers spilling from the shoulder
            plume(f"shoulder_feather_{n}{k}", Ar, (s * (0.04 + k * 0.014), -0.04 + k * 0.022, 0.03),
                  (s * (0.45 + k * 0.1), 0.2, -1.0), 0.17 + 0.025 * k, 0.034, FM, n=(0, -1, 0) if k < 2 else (s, 0, 0),
                  bend=0.08, rows=4, rng=rng)
        for zz in (-0.13, -0.17):   # armlets
            K.loft(f"armlet{int(-zz * 100)}_{n}", Ar, [(0.047 * math.cos(a), 0.047 * math.sin(a), zz)
                                                     for a in [k * math.pi / 4 for k in range(9)]],
                   [0.006] * 9, gilt, segs=4, caps=(False, False))
        K.loft(f"forearm_{n}", Fo, [(0, 0, 0.02), (0, -0.005, -0.08), (0, 0, -0.29)], [0.043, 0.045, 0.032], skin, segs=10)
        K.shell(f"gauntlet_{n}", Fo, (0.052, 0.052, 0.14), lat=(-75, 60), lon=(-180, 180), segs=(8, 2), thick=0.011,
                material=armor, loc=(0, 0, -0.17), flare=-0.15)
        K.loft(f"gauntlet_trim_{n}", Fo, [(0.056 * math.cos(a), 0.056 * math.sin(a), -0.065) for a in
                                          [k * math.pi / 6 for k in range(13)]], [0.005] * 13, gilt, segs=4, caps=(False, False))
        K.horn(f"gauntlet_fin_{n}", Fo, [(s * 0.045, 0.01, -0.06), (s * 0.075, 0.035, 0.0), (s * 0.085, 0.06, 0.07)],
               0.012, 0.002, gilt, segs=4, n=2)
        # slender hand: palm + 4 long jointed fingers with black claws + thumb
        K.loft(f"palm_{n}", Ha, [(0, 0, 0.01), (0, -0.004, -0.045), (0, -0.006, -0.085)],
               [(0.032, 0.02), (0.037, 0.021), (0.033, 0.018)], skin, segs=8)
        for i in range(4):
            x = (i - 1.5) * 0.019
            curl = math.radians(18 + 8 * i if s > 0 else 30 + 6 * i)
            L1 = 0.042 - 0.004 * abs(i - 1.2)
            p0 = Vector((x, -0.006, -0.08))
            p1 = p0 + Vector((x * 0.2, -math.sin(curl) * L1, -math.cos(curl) * L1))
            p2 = p1 + Vector((x * 0.1, -math.sin(2 * curl) * L1 * 0.85, -math.cos(2 * curl) * L1 * 0.85))
            K.loft(f"finger_{n}{i}", Ha, [p0, p1, p2], [0.0085, 0.0075, 0.0065], skin, segs=5)
            dd = (p2 - p1).normalized()
            K.horn(f"nail_{n}{i}", Ha, [p2, p2 + dd * 0.025, p2 + dd * 0.05 + Vector((0, -0.012, 0))], 0.0065, 0.0008,
                   claw, segs=4, n=1)
        tb =Vector((s * 0.028, -0.016, -0.03))
        tp = tb + Vector((s * 0.008, -0.03, -0.03))
        K.loft(f"thumb_{n}", Ha, [tb, tp], [0.009, 0.0075], skin, segs=5)
        K.horn(f"thumbnail_{n}", Ha, [tp, tp + Vector((0, -0.02, -0.025))], 0.006, 0.001, claw, segs=4, n=2)

    # hellfire in the casting (right) hand: its own joint (scale-animated)
    cast = sb.empty("cast_fx", R.hand[-1], loc=(0, -0.06, -0.11))
    R.extra.append(cast)
    sb.sphere("cast_core", cast, 0.03, scale=(1, 1, 1.25), material=fire, segments=10, rings=6)
    for k in range(3):
        a = k * 2 * math.pi / 3
        K.horn(f"cast_tongue{k}", cast, [(0.02 * math.cos(a), 0.02 * math.sin(a), 0.0),
                                         (0.03 * math.cos(a + 0.6), 0.03 * math.sin(a + 0.6), 0.04),
                                         (0.012 * math.cos(a + 1.2), 0.012 * math.sin(a + 1.2), 0.085)],
               0.012, 0.001, fire, segs=4, n=2)

    # ------------------------------------------------------------------ neck, face, gold mask
    K.loft("neck_m", R.neck, [(0, 0.0, -0.05), (0, 0.0, 0.05), (0, -0.01, 0.12)], [0.045, 0.04, 0.042], skin, segs=10)
    K.loft("face", Hd, [(0, 0.02, -0.005), (0, -0.032, 0.04), (0, -0.04, 0.1), (0, -0.03, 0.17), (0, -0.01, 0.22),
                        (0, 0.01, 0.245)],
           [(0.03, 0.035), (0.055, 0.07), (0.075, 0.088), (0.082, 0.092), (0.075, 0.082), (0.045, 0.045)],
           skin, segs=12, subdiv=1)
    K.loft("nose", Hd, [(0, -0.118, 0.13), (0, -0.13, 0.095), (0, -0.126, 0.083)], [0.008, 0.01, 0.007], skin, segs=5)
    K.loft("lips", Hd, [(-0.016, -0.112, 0.06), (0, -0.118, 0.058), (0.016, -0.112, 0.06)], [0.004, 0.006, 0.004],
           lips, segs=5)
    mc, mr = (0, -0.035, 0.125), (0.087, 0.1, 0.07)
    K.shell("mask_gold", Hd, mr, lat=(-28, 62), lon=(-78, 78), segs=(10, 4), thick=0.006, material=gilt, loc=mc)
    K.horn("mask_crest", Hd, [K.on_ell(mc, mr, 40, 0, 1.03), K.on_ell(mc, mr, 62, 0, 1.08),
                              K.on_ell(mc, mr, 80, 0, 1.0) + Vector((0, 0, 0.03))], 0.012, 0.002, gilt, segs=4, n=2)
    for s in SIDES:
        n = sname(s)
        e = K.on_ell(mc, mr, 10, s * 28, 1.06)
        sb.sphere(f"eye_{n}", Hd, 0.015, loc=tuple(e), rot=(0, 0, s * 25), scale=(1.6, 0.5, 0.5), material=eyes,
                  segments=8, rings=4)
        # burning tear tracks running from the slits
        K.crack(f"tear_{n}", Hd, mc, mr, [(0, s * 30), (-14, s * 33), (-28, s * 30)], fire, r=0.0022, off=1.05)
        # mask wing-flares at the temples
        K.horn(f"mask_flare_{n}", Hd, [K.on_ell(mc, mr, 20, s * 70, 1.02), K.on_ell(mc, mr, 35, s * 92, 1.15),
                                       K.on_ell(mc, mr, 55, s * 105, 1.35)], 0.01, 0.0015, gilt, segs=4, n=2)

    # ------------------------------------------------------------------ ash-silver hair (cap, strands, chains)
    K.shell("hair_cap", Hd, (0.092, 0.1, 0.1), lat=(-15, 90), lon=(-180, 180), segs=(12, 4), thick=0.012,
            material=hair, loc=(0, 0.008, 0.15))
    hc, hr = (0, 0.008, 0.15), (0.092, 0.1, 0.1)
    for i in range(8):     # strands swept back over the cap from a centre parting
        sd = 1 if i < 4 else -1
        k = i % 4
        lo0 = sd * (8 + 22 * k)
        pts = [K.on_ell(hc, hr, la, lo0 + sd * (la - 30) * (0.25 + 0.15 * k), 1.08) for la in (30, 60, 80)]
        pts += [K.on_ell(hc, hr, 40, 180 - sd * (20 + 25 * k), 1.08), K.on_ell(hc, hr, -5, 180 - sd * (25 + 28 * k), 1.06)]
        K.loft(f"hair_strand{i}", Hd, K.catmull(pts, 2), [0.011] * 8 + [0.005], hair, segs=4)
    hair_chain = chain_panel(R, "hair", Hd, (0, 0.085, 0.15), (16, 0, 0), 0.66, 3, 0.16, 0.2, hair, rag=0.5, seed=31,
                             folds=4.0, fold_amp=0.012, flare=-0.02, cup=-0.06, nx=7, ny=2, thick=0.012)
    locks = []
    for s in SIDES:
        locks.append(chain_panel(R, f"lock_{sname(s)}", Hd, (s * 0.085, -0.035, 0.15), (-12, s * -10, s * -8), 0.4, 3,
                                 0.035, 0.022, hair, rag=0.3, seed=41 + s, folds=1.0, fold_amp=0.006, flare=0.0,
                                 cup=-0.012, nx=2, ny=2, thick=0.012))

    # ------------------------------------------------------------------ crown of thorns: two woven vines + thorns
    for v in range(2):
        vine = []
        for k in range(25):
            a = k * 2 * math.pi / 24
            r = 0.104 + 0.006 * math.sin(a * 6 + v * math.pi)
            vine.append((math.sin(a) * r, -math.cos(a) * r * 1.06 + 0.008, 0.205 + 0.011 * math.sin(a * 6 + v * math.pi)))
        K.loft(f"crown_vine{v}", Hd, vine, [0.0075] * len(vine), thorn, segs=4, caps=(False, False))
    for k in range(17):
        a = k * 2 * math.pi / 17 + 0.1
        big = k in (0, 4, 8, 13)
        h = (0.13 if big else 0.05 + rng.random() * 0.035) * (1.25 if k == 0 else 1.0)
        base = Vector((math.sin(a) * 0.106, -math.cos(a) * 0.112 + 0.008, 0.21))
        out = Vector((math.sin(a), -math.cos(a), 0))
        tilt = 0.25 if big else 0.6
        K.horn(f"thorn{k}", Hd, [base, base + out * h * tilt * 0.6 + Vector((0, 0, h * 0.55)),
                                 base + out * h * tilt + Vector((0, 0, h))],
               0.011 if big else 0.007, 0.0012, thorn, segs=4 if big else 3, n=2)
        if k % 3 == 1:   # side barbs
            K.horn(f"barb{k}", Hd, [base + Vector((0, 0, 0.005)), base + out * 0.03 + Vector((0, 0, -0.012))],
                   0.004, 0.0008, thorn, segs=4, n=1)

    # ------------------------------------------------------------------ cracked burning halo
    halo = sb.empty("halo", Hd, loc=(0, 0.14, 0.36), rot=(-60, 0, 0))
    spin = sb.empty("halo_spin", halo)
    R.extra += [halo, spin]
    rad = 0.25
    gaps = (0, 3)    # two big breaks
    for seg in range(7):
        a0 = seg * 360 / 7 + rng.uniform(-3, 3)
        a1 = a0 + 360 / 7 - (18 if seg in gaps else rng.uniform(2.5, 5))
        pts = [(math.cos(math.radians(a)) * rad, math.sin(math.radians(a)) * rad, rng.uniform(-0.006, 0.006))
               for a in (a0, (a0 + a1) / 2, a1)]
        path = K.catmull(pts, 3)
        K.loft(f"halo_seg{seg}", spin, path, [0.012, 0.016, 0.017, 0.017, 0.016, 0.013, 0.008], halo_m,
               segs=6, ref=(0, 0, 1), cap_round=0.6)
        # charred gold plating over the ring, leaving glowing seams
        for p in range(1):
            b0 = a0 + (a1 - a0) * rng.uniform(0.15, 0.5)
            b1 = b0 + (a1 - a0) * 0.28
            arc = [(math.cos(math.radians(b)) * rad, math.sin(math.radians(b)) * rad, 0.0)
                   for b in (b0, (b0 + b1) / 2, b1)]
            K.loft(f"halo_plate{seg}{p}", spin, arc, [(0.0175, 0.019), (0.019, 0.02), (0.0175, 0.019)], char,
                   segs=6, ref=(0, 0, 1), cap_round=0.3)
        # radiating rays (some snapped short)
        am = math.radians((a0 + a1) / 2)
        L = 0.11 if seg % 2 == 0 else 0.07
        if seg in (2, 5):
            L *= 0.45
        d = Vector((math.cos(am), math.sin(am), 0))
        K.horn(f"halo_ray{seg}", spin, [d * (rad + 0.012), d * (rad + L * 0.5), d * (rad + L)], 0.011, 0.0015,
               halo_m, segs=4, n=1)
    for k in range(7):  # fragments drifting from the breaks
        a = math.radians([4, 10, 18, 158, 164, 171, 240][k])
        r2 = rad + rng.uniform(0.03, 0.08)
        sb.box(f"halo_frag{k}", spin, size=(0.022, 0.012, 0.018),
               loc=(math.cos(a) * r2, math.sin(a) * r2, rng.uniform(-0.04, 0.04)),
               rot=(rng.uniform(0, 90), rng.uniform(0, 90), 0), material=halo_m if k % 2 else char, bevel=0.0)

    # ------------------------------------------------------------------ great tattered wings
    W0, W1, W2, FAN = {}, {}, {}, {}
    for s in SIDES:
        n = sname(s)
        r = random.Random(100 + s)
        w0 = sb.empty(f"wing_{n}", C, loc=(s * 0.07, 0.15, 0.25))
        elbow = Vector((s * 0.34, 0.1, 0.3))
        w1 = sb.empty(f"wing_mid_{n}", w0, loc=tuple(elbow))
        wrist = Vector((s * 0.42, 0.05, 0.12))
        w2 = sb.empty(f"wingtip_{n}", w1, loc=tuple(wrist))
        hand_end = Vector((s * 0.26, 0.02, -0.04))
        fans = [sb.empty(f"pfan{k}_{n}", w2, loc=tuple(hand_end * (0.12 + 0.4 * k))) for k in range(3)]
        R.wings.append((s, w0, w2))
        R.extra += [w0, w1, w2] + fans
        W0[s], W1[s], W2[s], FAN[s] = w0, w1, w2, fans
        # leading-edge "bones" covered in feathers
        K.loft(f"wing_arm_{n}", w0, K.catmull([(0, 0, 0), (s * 0.18, 0.06, 0.2), tuple(elbow)], 2),
               [0.034, 0.032, 0.03, 0.027, 0.024], feath, segs=6)
        K.loft(f"wing_fore_{n}", w1, K.catmull([(0, 0, 0), wrist * 0.5 + Vector((0, 0, 0.04)), tuple(wrist)], 2),
               [0.024, 0.023, 0.021, 0.019, 0.016], feath, segs=6)
        K.loft(f"wing_hand_{n}", w2, [(0, 0, 0), tuple(hand_end * 0.5), tuple(hand_end)], [0.022, 0.017, 0.01], feath, segs=6)
        nb = (0, 1, 0)
        # tertials / scapulars along the upper arm (drape over the back)
        for i in range(7):
            u = 0.15 + 0.85 * i / 6
            b = Vector((0, 0, 0)).lerp(elbow, u) + Vector((0, 0.02, -0.03))
            L = (0.5 + 0.18 * u) * r.uniform(0.88, 1.06)
            plume(f"tert_{n}{i}", w0, b, (s * (0.05 + 0.15 * u), 0.12, -1.0), L, 0.075, FM, n=nb, bend=0.05,
                  rows=6, rng=r, torn=r.random() < 0.3, singe=1 if r.random() < 0.25 else 0)
        # secondaries along the forearm (trailing edge)
        for i in range(10):
            u = i / 9
            b = wrist * (0.04 + 0.94 * u) + Vector((0, 0.012, -0.03))
            L = (0.72 + 0.1 * math.sin(math.pi * u)) * r.uniform(0.86, 1.06)
            torn = r.random() < 0.3
            if torn:
                L *= r.uniform(0.6, 0.82)
            plume(f"sec_{n}{i}", w1, b, (s * (0.1 + 0.32 * u), 0.08, -1.0), L, 0.088, FM, n=nb, bend=0.06,
                  sweep=0.03 * s, rows=7, rng=r, torn=torn, singe=1 if r.random() < 0.55 else 0)
        # primaries fanning from the hand (3 fan joints so they can spread / fold)
        npri = 11
        for i in range(npri):
            u = i / (npri - 1)
            fj = fans[min(2, int(u * 3 - 1e-6))]
            hb = hand_end * (0.05 + 0.95 * u) - Vector(fj.location)
            ang = math.radians(-82 + 92 * u)
            d = (s * math.cos(ang), 0.06 + 0.06 * u, math.sin(ang))
            L = (0.76 + 0.34 * math.sin(math.pi * (0.2 + 0.62 * u))) * r.uniform(0.9, 1.05)
            torn = r.random() < 0.28
            if torn:
                L *= r.uniform(0.58, 0.8)
            plume(f"pri_{n}{i}", fj, hb, d, L, 0.085 - 0.012 * u, FM, n=nb, bend=0.07, sweep=-0.04 * s * (1 - u),
                  rows=7, rng=r, torn=torn, singe=1)
        # coverts: greater (front + back faces), lesser along the leading edge, primary coverts, alula
        for i in range(9):
            u = i / 8
            b = wrist * (0.03 + 0.95 * u)
            plume(f"gcov_{n}{i}", w1, b + Vector((0, -0.018, -0.01)), (s * (0.15 + 0.3 * u), 0.02, -1.0),
                  0.3 * r.uniform(0.9, 1.1), 0.075, FM, n=nb, bend=0.03, rows=3, rng=r)
            plume(f"gcovb_{n}{i}", w1, b + Vector((0, 0.03, -0.01)), (s * (0.12 + 0.3 * u), 0.08, -1.0),
                  0.34 * r.uniform(0.9, 1.1), 0.075, FM, n=nb, bend=0.04, rows=3, rng=r)
        for i in range(8):
            u = i / 7
            b = Vector((0, 0, 0)).lerp(elbow, 0.2 + 0.8 * u)
            plume(f"scap_{n}{i}", w0, b + Vector((0, -0.02, -0.015)), (s * (0.2 + 0.3 * u), 0.0, -1.0),
                  0.26 * r.uniform(0.9, 1.1), 0.065, FM, n=nb, bend=0.03, rows=3, rng=r)
            plume(f"scapb_{n}{i}", w0, b + Vector((0, 0.035, -0.015)), (s * (0.15 + 0.3 * u), 0.1, -1.0),
                  0.3 * r.uniform(0.9, 1.1), 0.065, FM, n=nb, bend=0.03, rows=3, rng=r)
        for i in range(10):
            u = i / 9
            on_arm = u < 0.5
            jt = w0 if on_arm else w1
            b = elbow * (0.3 + 1.4 * u) if on_arm else wrist * ((u - 0.5) * 2 * 0.95)
            plume(f"lcov_{n}{i}", jt, b + Vector((0, (-0.02 if i % 2 else 0.03), 0.015)),
                  (s * 0.4, 0.05 if i % 2 else 0.15, -1.0), 0.15 * r.uniform(0.85, 1.15), 0.05, FM, n=nb, bend=0.03,
                  rows=3, rng=r)
        for i in range(6):
            u = i / 5
            b = hand_end * (0.05 + 0.8 * u)
            ang = math.radians(-70 + 70 * u)
            plume(f"pcov_{n}{i}", w2, b + Vector((0, -0.015, 0)), (s * math.cos(ang), 0.06, math.sin(ang)),
                  0.32 * r.uniform(0.9, 1.08), 0.07, FM, n=nb, bend=0.03, rows=3, rng=r)
            plume(f"pcovb_{n}{i}", w2, b + Vector((0, 0.025, 0)), (s * math.cos(ang), 0.1, math.sin(ang)),
                  0.28 * r.uniform(0.9, 1.08), 0.07, FM, n=nb, bend=0.03, rows=3, rng=r)
        for i in range(3):   # alula: small spikes at the wrist pointing out-up
            plume(f"alula_{n}{i}", w2, (s * 0.01 * i, -0.01, 0.01), (s * 1.0, -0.05, 0.25 + 0.2 * i), 0.13 - 0.02 * i,
                  0.03, FM, n=(0, 0, 1), bend=0.05, rows=3, rng=r)
        # a few loose, broken feathers hanging from the forearm (tattered silhouette)
        for i in range(3):
            b = wrist * (0.25 + 0.3 * i) + Vector((0, 0.03, -0.05))
            plume(f"loose_{n}{i}", w1, b, (s * 0.25, 0.25, -1.0), 0.86 + 0.08 * i, 0.05, FM, n=nb, bend=0.1,
                  rows=6, rng=r, torn=True, singe=1, notch=0.5)

    # sweeping hellfire arc (cast VFX, hidden except around the impact)
    sweep = sb.empty("sweep_fx", R.body, loc=(0, -0.2, 1.25))
    R.extra.append(sweep)
    arc = [(math.cos(math.radians(a)) * 0.95, math.sin(math.radians(a)) * 0.95 - 0.25, 0.04 * math.sin(math.radians(a * 2)))
           for a in range(200, 341, 10)]
    sb.ptube("sweep_arc", sweep, arc, [0.004 + 0.045 * math.sin(math.pi * i / (len(arc) - 1)) ** 1.5 for i in range(len(arc))],
             sides=4, material=fire)

    animate(R, dict(W0=W0, W1=W1, W2=W2, FAN=FAN, robes=robes, hair=hair_chain, locks=locks, halo=halo,
                    spin=spin, cast=cast, sweep=sweep))
    K.finalize(R.root)
    return R.root


# ============================================================================ animation

def animate(R, X):
    W0, W1, W2, FAN = X["W0"], X["W1"], X["W2"], X["FAN"]
    halo, spin, cast, sweep = X["halo"], X["spin"], X["cast"], X["sweep"]
    ALL = [j for j in A.joints(R.root, include_root=False) if j.name != "look"]
    L, Rr = 1, -1
    HIDE = (0.001, 0.001, 0.001)
    arm, fore, hand, thigh, shin, foot = R.arm, R.fore, R.hand, R.thigh, R.shin, R.foot
    rig = {"hips": R.hips, "spine": R.spine, "chest": R.chest, "head": R.head,
           "thigh": (thigh[L], thigh[Rr]), "shin": (shin[L], shin[Rr]), "foot": (foot[L], foot[Rr]),
           "arm": (arm[L], arm[Rr]), "fore": (fore[L], fore[Rr])}

    def mir(d):
        """Adds mirrored R entries for every *_L joint in a pose dict (for A.attack / hit_react)."""
        out = {}
        for j, ch in d.items():
            out[j] = ch
            if j.name.endswith("_L"):
                o = A.other(j)
                if o is not None and o not in d:
                    out[o] = {k: A.mirror_value(k, A._v3(v, 1.0 if k == "scale" else 0.0)) for k, v in ch.items()}
        return out

    def add2(c, jl, fn, ch="rot"):
        """Additive layer on a left joint and its mirror."""
        c.add(jl, fn, ch)
        c.add(A.other(jl), (lambda f: A.mirror_value(ch, fn(f))), ch)

    def wings(rot0=(0, 0, 0), rot1=(0, 0, 0), rot2=(0, 0, 0), fan=((0, 0, 0), (0, 0, 0), (0, 0, 0))):
        d = {W0[L]: {"rot": rot0}, W1[L]: {"rot": rot1}, W2[L]: {"rot": rot2}}
        for k in range(3):
            d[FAN[L][k]] = {"rot": fan[k]}
        return d

    # rest-of-wing poses (offsets from the modelled half-open spread)
    WING_IDLE = wings((0, 5, 10), (0, 3, 6), (0, 4, 4), ((0, 4, 0), (0, 0, 0), (0, -3, 0)))
    WING_GLIDE = wings((-4, -2, 20), (0, -2, 12), (0, 6, 8), ((0, 8, 4), (0, 3, 2), (0, -2, 0)))
    WING_SPREAD = wings((0, -26, -6), (0, -10, -4), (0, -10, -6), ((0, 16, 0), (0, 2, 0), (0, -14, 0)))
    WING_WRAP = wings((0, 14, -36), (0, 10, -30), (0, 16, -20), ((0, 12, 6), (0, 4, 3), (0, -2, 0)))

    def secondary(c, wind=None, floor=None, robe_freq=1.6, hair_freq=1.4, gravity=6.0):
        for js, a in X["robes"]:
            A.follow_through(c, js, freq=robe_freq, damping=0.12, gravity=gravity, falloff=0.85, wind=wind,
                             floor=floor, max_angle=70)
        A.follow_through(c, X["hair"], freq=hair_freq, damping=0.12, gravity=gravity, falloff=0.85, wind=wind,
                         floor=floor, max_angle=80)
        for lk in X["locks"]:
            A.follow_through(c, lk, freq=1.8, damping=0.15, gravity=gravity, falloff=0.85, wind=wind, floor=floor,
                             max_angle=60)

    def halo_life(c, spin_amp=8.0):
        c.add(spin, lambda f: (0, 0, spin_amp * A.wave(c, f, 1)), "rot")
        c.add(halo, lambda f: (0, 0, 0.012 * A.wave(c, f, 2)), "loc")
        A.noise(c, halo, rot=(2.5, 2.5, 0), freq=0.4, seed=9)

    def flame(c, base=0.7, amp=0.12):
        c.add(cast, lambda f: tuple((base - 1.0) + amp * (A.wave(c, f, 7) * 0.6 + A.wave(c, f, 11, 0.3) * 0.4) * k
                                    for k in (1.0, 1.0, 1.4)), "scale")

    # ------------------------------------------------------------------ idle (loop, 4 s)
    c = A.Clip("idle", 120, joints=ALL)
    c.key(sweep, 0, scale=HIDE)
    c.pose(0, {R.hips: {"loc": (0.018, 0, -0.004), "rot": (0, -2.5, 3)},
               thigh[L]: {"rot": (0, 2.5, -3)}, thigh[Rr]: {"rot": (-5, 2.5, -3)}, shin[Rr]: {"rot": (10, 0, 0)},
               foot[Rr]: {"rot": (-5, 0, 0)}, foot[L]: {"rot": (0, 0, 0)},
               R.spine: {"rot": (-1, 2, -2)}, R.chest: {"rot": (-2, 1.5, -2)}, R.head: {"rot": (7, -2, 4)},
               arm[L]: {"rot": (3, -4, 4)}, fore[L]: {"rot": (-12, 0, 0)}, hand[L]: {"rot": (-8, 0, 10)},
               arm[Rr]: {"rot": (-18, 6, -10)}, fore[Rr]: {"rot": (-62, 0, 10)}, hand[Rr]: {"rot": (25, 0, 0)}})
    c.pose(0, WING_IDLE, mirror=True)
    # wing settle: a slow lift-and-ruffle at ~2/3 of the loop (keys on the L side, mirrored R)
    settle = {W0[L]: (0, -9, 4), W1[L]: (0, -6, -2), W2[L]: (0, -5, 0)}
    for j, v in settle.items():
        base = WING_IDLE[j]["rot"]
        c.key(j, 0, rot=base)
        c.key(j, 68, rot=base, ease="sine_inout")
        c.key(j, 78, rot=tuple(b + x for b, x in zip(base, v)), ease="sine_inout")
        c.key(j, 86, rot=tuple(b + x * 0.35 for b, x in zip(base, v)), ease="sine_inout")
        c.key(j, 100, rot=base, ease="sine_inout")
        o = A.other(j)
        for f in (0, 68, 78, 86, 100):
            c.key(o, f, rot=A.mirror_value("rot", c.tracks[(j, "rot")].keys[float(f)][0]),
                  ease=c.tracks[(j, "rot")].keys[float(f)][1])
    for k in range(3):   # feathers spread on the lift, shiver, settle
        fj = FAN[L][k]
        base = WING_IDLE[fj]["rot"]
        sp = (0, (6, 2, -8)[k], 0)
        for f, w in ((0, 0), (70, 0), (80, 1), (90, 0.2), (104, 0)):
            c.key(fj, f, rot=tuple(b + x * w for b, x in zip(base, sp)), ease="sine_inout")
            c.key(A.other(fj), f, rot=A.mirror_value("rot", tuple(b + x * w for b, x in zip(base, sp))), ease="sine_inout")
        A.jitter(c, fj, rot=(0.6, 1.5, 1.0), freq=10, seed=20 + k, start=80, end=92)
        A.jitter(c, A.other(fj), rot=(0.6, 1.5, 1.0), freq=10, seed=30 + k, start=81, end=93)
    # breathing wings: slow rise/fall with lag toward the tips
    add2(c, W0[L], lambda f: (0, 2.5 * A.wave(c, f, 3), 1.5 * A.wave(c, f, 3, 0.1)))
    add2(c, W1[L], lambda f: (0, 2.0 * A.wave(c, f, 3, -0.08), 1.0 * A.wave(c, f, 3, 0.0)))
    add2(c, W2[L], lambda f: (0, 2.5 * A.wave(c, f, 3, -0.16), 0))
    A.breathe(c, R.chest, amp=1.8, rise=0.006, swell=0.012, cycles=3, shoulders=[arm[L], arm[Rr]], head=R.head)
    c.add(R.hips, lambda f: (0.006 * A.wave(c, f, 1), 0, 0), "loc")
    A.noise(c, R.head, rot=(2, 4, 2), freq=0.3, seed=1)
    A.noise(c, arm[Rr], rot=(2, 1, 2), freq=0.35, seed=2)
    A.noise(c, hand[Rr], rot=(4, 3, 3), freq=0.5, seed=3)
    A.noise(c, arm[L], rot=(1.5, 1, 1), freq=0.3, seed=4)
    halo_life(c)
    flame(c)
    secondary(c, wind=(0.3, 0.8, 0))
    c.bake()

    # ------------------------------------------------------------------ walk / glide-run (loop)
    stride, stance = 40.0, 0.44
    reach = LEG * (math.sin(math.radians(stride)) + math.sin(math.radians(stride * 0.8)))
    wf = max(8, round(reach * A.FPS / (stance * WALK_SPEED)))
    c = A.Clip("walk", wf, joints=ALL)
    c.key(sweep, 0, scale=HIDE)
    A.walk(c, rig, stride=stride, knee=78, load=10, stance=stance, sway=0.012, hip_roll=3, hip_yaw=6, twist=7,
           lean=11, arm=14, elbow=22, elbow_swing=14, arm_out=7, head_stab=0.85, heel=12, toe_off=26, heavy=0.0)
    c.pose(0, WING_GLIDE, mirror=True)
    c.key(hand[Rr], 0, rot=(15, 0, 0))
    c.key(fore[Rr], 0, rot=(-14, 0, 0))
    # wings ride the stride: gentle lift on each step, tips trailing
    add2(c, W0[L], lambda f: (0, 2.5 * A.wave(c, f, 2, -0.1), 1.5 * A.wave(c, f, 1)))
    add2(c, W1[L], lambda f: (0, 2.5 * A.wave(c, f, 2, -0.2), 0))
    add2(c, W2[L], lambda f: (0, 3.0 * A.wave(c, f, 2, -0.3), 0))
    for k in range(3):
        add2(c, FAN[L][k], (lambda f, k=k: (0, 1.5 * A.wave(c, f, 2, -0.3 - 0.06 * k), 0)))
    # front robe panels ride the thighs (knees push the cloth), back panels are kicked by the back-swing
    for js, a in X["robes"]:
        ca = math.cos(math.radians(a))
        side = thigh[L] if math.sin(math.radians(a)) > 0.01 else (thigh[Rr] if math.sin(math.radians(a)) < -0.01 else None)
        wfw = max(0.0, ca) * 0.85
        wbk = max(0.0, -ca) * 0.4
        if side is None:
            c.add(js[0], (lambda f, a1=wfw * 0.6, a2=wbk: (
                a1 * min(0.0, c.eval(thigh[L], "rot", f)[0], c.eval(thigh[Rr], "rot", f)[0])
                + a2 * max(0.0, c.eval(thigh[L], "rot", f)[0], c.eval(thigh[Rr], "rot", f)[0]), 0, 0)))
            continue
        c.add(js[0], (lambda f, t=side, a1=wfw, a2=wbk: (a1 * min(0.0, c.eval(t, "rot", f)[0])
                                                          + a2 * max(0.0, c.eval(t, "rot", f)[0]), 0, 0)))
    c.add(halo, lambda f: (4, 0, 0))
    c.add(spin, lambda f: (0, 0, 3 * A.wave(c, f, 1)), "rot")
    flame(c, 0.6, 0.1)
    secondary(c, wind=(0, 7.0, 0), robe_freq=1.8, hair_freq=1.6)
    c.bake()
    print(f"LILAETH walk frames={wf} speed={A.stride_speed(LEG, stride, wf, stance=stance):.2f} m/s")

    # ------------------------------------------------------------------ attack: sweeping hellfire cast
    c = A.Clip("attack", 44, joints=ALL)
    antic = {
        R.hips: {"loc": (0, 0.03, -0.035), "rot": (0, 0, -8)},
        thigh[L]: {"rot": (-14, 0, 8)}, shin[L]: {"rot": (26, 0, 0)}, foot[L]: {"rot": (-12, 0, 0)},
        thigh[Rr]: {"rot": (-12, 0, 8)}, shin[Rr]: {"rot": (22, 0, 0)}, foot[Rr]: {"rot": (-10, 0, 0)},
        R.spine: {"rot": (-6, -4, -12)}, R.chest: {"rot": (-6, -6, -22)}, R.head: {"rot": (2, 4, 22)},
        arm[Rr]: {"rot": (-10, 82, -38)}, fore[Rr]: {"rot": (-48, 0, 0)}, hand[Rr]: {"rot": (20, 0, -20)},
        arm[L]: {"rot": (-55, -22, -10)}, fore[L]: {"rot": (-40, 0, 0)}, hand[L]: {"rot": (-10, 0, 0)},
        W0[L]: {"rot": (0, -18, -2)}, W1[L]: {"rot": (0, -8, 2)}, W2[L]: {"rot": (0, -6, 4)},
        FAN[L][0]: {"rot": (0, 10, 0)}, FAN[L][2]: {"rot": (0, -10, 0)},
        halo: {"rot": (-6, 0, 0)},
    }
    strike = {
        R.hips: {"loc": (0, -0.02, -0.05), "rot": (0, 0, 10)},
        thigh[L]: {"rot": (-18, 0, -10)}, shin[L]: {"rot": (30, 0, 0)}, foot[L]: {"rot": (-12, 0, 0)},
        thigh[Rr]: {"rot": (-14, 0, -10)}, shin[Rr]: {"rot": (28, 0, 0)}, foot[Rr]: {"rot": (-14, 0, 0)},
        R.spine: {"rot": (10, 3, 12)}, R.chest: {"rot": (8, 6, 26)}, R.head: {"rot": (-4, -3, -18)},
        arm[Rr]: {"rot": (-14, 78, 112)}, fore[Rr]: {"rot": (-4, 0, 0)}, hand[Rr]: {"rot": (-10, 0, 10)},
        arm[L]: {"rot": (18, -48, 10)}, fore[L]: {"rot": (-22, 0, 0)}, hand[L]: {"rot": (10, 0, 0)},
        W0[L]: {"rot": (0, 18, -22)}, W1[L]: {"rot": (0, 10, -14)}, W2[L]: {"rot": (0, 8, -8)},
        FAN[L][0]: {"rot": (0, -4, 0)}, FAN[L][2]: {"rot": (0, 6, 0)},
        halo: {"rot": (8, 0, 0)},
    }
    follow = {j: {k: tuple(x * 0.9 for x in v) for k, v in d.items()} for j, d in strike.items()}
    ev = A.attack(c, {"antic": mir(antic), "strike": mir(strike), "follow": mir(follow)}, start=0, antic=13,
                  antic_hold=5, strike=3, hold=5, recover=16, overshoot=0.12, push=0.08)
    imp = ev["impact"]
    A.jitter(c, arm[Rr], rot=(1.5, 1.0, 1.5), start=12, end=19)
    A.jitter(c, FAN[L][2], rot=(1, 2, 1), start=12, end=19, seed=5)
    # hellfire gathers in the hand during the windup, is flung out on the strike
    c.key(cast, 0, scale=(0.7, 0.7, 0.7))
    c.key(cast, 13, scale=(1.5, 1.5, 1.7), ease="sine_inout")
    c.key(cast, imp - 1, scale=(1.8, 1.8, 2.0), ease="quad_in")
    c.key(cast, imp, scale=(0.05, 0.05, 0.05), ease="constant")
    c.key(cast, imp + 6, scale=(0.05, 0.05, 0.05), ease="sine_out")
    c.key(cast, 44, scale=(0.7, 0.7, 0.7))
    c.key(sweep, 0, scale=HIDE, ease="constant")
    c.key(sweep, imp - 1, scale=(0.75, 0.75, 0.75), rot=(0, 0, -25), ease="expo_out")
    c.key(sweep, imp + 3, scale=(1.05, 1.05, 1.0), rot=(0, 0, 18), ease="constant")
    c.key(sweep, imp + 4, scale=HIDE, rot=(0, 0, 0))
    halo_life(c, 4)
    secondary(c, robe_freq=1.8)
    c.bake()
    print("LILAETH attack impact frame", imp)

    # ------------------------------------------------------------------ hit: recoil + wing flinch
    c = A.Clip("hit", 22, joints=ALL)
    c.key(sweep, 0, scale=HIDE)
    c.pose(0, WING_IDLE, mirror=True)
    A.hit_react(c, {R.hips: {"loc": (0, 0.06, -0.025), "rot": (-6, 0, 0)}, R.spine: {"rot": (-9, 0, 4)},
                    R.chest: {"rot": (-13, 3, 8), "scale": (1.02, 1.02, 0.97)}, R.head: {"rot": (-18, 0, -12)},
                    halo: {"rot": (14, 0, 6)}},
                start=0, rise=2, settle=14, wobble=1.0, stagger=1.0)
    A.hit_react(c, mir({arm[L]: {"rot": (-28, -16, 0)}, arm[Rr]: {"rot": (-22, 14, 0)},
                        fore[L]: {"rot": (-30, 0, 0)}, fore[Rr]: {"rot": (-24, 0, 0)}}),
                start=1, rise=2, settle=13, wobble=1.0, stagger=0.0)
    A.hit_react(c, mir({W0[L]: {"rot": (0, -16, -16)}, W1[L]: {"rot": (0, -14, -12)}, W2[L]: {"rot": (0, -10, -8)},
                        FAN[L][0]: {"rot": (0, 8, 0)}, FAN[L][2]: {"rot": (0, -8, 0)}}),
                start=1, rise=3, settle=16, wobble=1.2, stagger=0.5)
    c.add(cast, lambda f: (-0.3 * A._response(f, 2, 10, 0.5),) * 3, "scale")
    c.key(cast, 0, scale=(0.7, 0.7, 0.7))
    secondary(c, robe_freq=2.0)
    c.bake()

    # ------------------------------------------------------------------ death: wings flare, kneel, fall, crumple
    c = A.Clip("death", 66, joints=ALL)
    c.key(sweep, 0, scale=HIDE)
    buckle = {R.hips: {"loc": (0, 0.05, -0.5)},
              thigh[L]: {"rot": (-14, 0, 6)}, shin[L]: {"rot": (100, 0, 0)}, foot[L]: {"rot": (55, 0, 0)},
              thigh[Rr]: {"rot": (-24, 0, -6)}, shin[Rr]: {"rot": (106, 0, 0)}, foot[Rr]: {"rot": (55, 0, 0)},
              R.spine: {"rot": (16, 0, 4)}, R.chest: {"rot": (10, 0, 0)}, R.head: {"rot": (28, 0, 10)},
              arm[L]: {"rot": (-14, -8, 0)}, arm[Rr]: {"rot": (-20, 10, 0)},
              fore[L]: {"rot": (-14, 0, 0)}, fore[Rr]: {"rot": (-20, 0, 0)}}
    limp = {R.hips: {"loc": (0, 0.0, -0.36)},
            thigh[L]: {"rot": (6, 0, 10)}, shin[L]: {"rot": (14, 0, 0)}, foot[L]: {"rot": (50, 0, 0)},
            thigh[Rr]: {"rot": (-4, 0, -6)}, shin[Rr]: {"rot": (30, 0, 0)}, foot[Rr]: {"rot": (45, 0, 0)},
            R.spine: {"rot": (-4, 0, 6)}, R.chest: {"rot": (-6, 0, 0)}, R.head: {"rot": (-30, 0, 38)},
            arm[L]: {"rot": (-150, -30, 0)}, fore[L]: {"rot": (-10, 0, 0)}, hand[L]: {"rot": (20, 0, 0)},
            arm[Rr]: {"rot": (-60, 70, 0)}, fore[Rr]: {"rot": (-30, 0, 0)}, hand[Rr]: {"rot": (20, 0, 0)}}
    imp = A.death(c, R.body, fall=(80, 0, -8), drop=(0, 0.0, 0.22), stagger=6, buckle=10, topple=12, bounce=0.05,
                  recoil={R.chest: {"rot": (-14, 0, 6)}, R.head: {"rot": (-22, 0, 0)}},
                  buckle_pose=buckle, limp_pose=limp)
    # wings: flare open in agony, droop as she kneels, then crumple over her and onto the ground
    flare_ = wings((0, -24, 4), (0, -12, -4), (0, -10, -6), ((0, 14, 0), (0, 2, 0), (0, -16, 0)))
    droop = wings((0, 22, 14), (0, 16, 18), (0, 14, 10), ((0, -6, 4), (0, -2, 2), (0, 4, 0)))
    crumple = wings((0, 10, -30), (0, 30, 24), (0, 30, 20), ((0, -14, 8), (0, -6, 6), (0, 10, 4)))
    c.pose(0, WING_IDLE, mirror=True, ease="expo_out")
    c.pose(5, flare_, mirror=True, ease="sine_inout")
    c.pose(16, droop, mirror=True, ease="quad_in")
    c.pose(imp, crumple, mirror=True, ease="back_out:1.6")
    c.pose(imp + 8, wings(*[tuple(x * 1.05 for x in crumple[j]["rot"]) for j in (W0[L], W1[L], W2[L])],
                          fan=tuple(crumple[FAN[L][k]]["rot"] for k in range(3))), mirror=True, ease="constant")
    # the halo gutters: jolts, tilts and sinks as she falls
    c.key(halo, 0, rot=(0, 0, 0), loc=(0, 0, 0), scale=(1, 1, 1), ease="expo_out")
    c.key(halo, 5, rot=(16, 0, 10), loc=(0, 0.02, 0.03), scale=(1.15, 1.15, 1.15), ease="sine_inout")
    c.key(halo, imp, rot=(40, 0, 25), loc=(0, 0.06, -0.08), scale=(0.9, 0.9, 0.9), ease="bounce_out")
    c.key(halo, imp + 12, rot=(50, 0, 30), loc=(0, 0.08, -0.12), scale=(0.75, 0.75, 0.75), ease="constant")
    c.key(spin, 0, rot=(0, 0, 0))
    c.key(spin, imp + 10, rot=(0, 0, -70), ease="sine_out")
    c.key(cast, 0, scale=(0.7, 0.7, 0.7))
    c.key(cast, 8, scale=(0.3, 0.3, 0.3), ease="sine_out")
    c.key(cast, 22, scale=HIDE)
    secondary(c, floor=0.03, robe_freq=2.2)
    c.bake()
    print("LILAETH death impact frame", imp)

    # ------------------------------------------------------------------ cheer: regal rise, wings unfurled
    c = A.Clip("cheer", 72, joints=ALL)
    c.key(sweep, 0, scale=HIDE)
    gather = {R.hips: {"loc": (0, 0.01, -0.045)},
              thigh[L]: {"rot": (-14, 0, 0)}, shin[L]: {"rot": (28, 0, 0)}, foot[L]: {"rot": (-14, 0, 0)},
              thigh[Rr]: {"rot": (-14, 0, 0)}, shin[Rr]: {"rot": (28, 0, 0)}, foot[Rr]: {"rot": (-14, 0, 0)},
              R.spine: {"rot": (14, 0, 0)}, R.chest: {"rot": (8, 0, 0)}, R.head: {"rot": (22, 0, 0)},
              arm[L]: {"rot": (-40, -2, 30)}, fore[L]: {"rot": (-80, 0, 0)}, hand[L]: {"rot": (10, 0, 0)},
              arm[Rr]: {"rot": (-40, 2, -30)}, fore[Rr]: {"rot": (-80, 0, 0)}, hand[Rr]: {"rot": (10, 0, 0)}}
    rise = {R.hips: {"loc": (0, 0, 0.012)},
            thigh[L]: {"rot": (0, 0, 0)}, shin[L]: {"rot": (0, 0, 0)}, foot[L]: {"rot": (6, 0, 0)},
            thigh[Rr]: {"rot": (0, 0, 0)}, shin[Rr]: {"rot": (0, 0, 0)}, foot[Rr]: {"rot": (6, 0, 0)},
            R.spine: {"rot": (-8, 0, 0)}, R.chest: {"rot": (-8, 0, 0)}, R.head: {"rot": (-20, 0, 0)},
            arm[L]: {"rot": (-25, -128, 0)}, fore[L]: {"rot": (-14, 0, 0)}, hand[L]: {"rot": (-20, 0, -10)},
            arm[Rr]: {"rot": (-25, 128, 0)}, fore[Rr]: {"rot": (-14, 0, 0)}, hand[Rr]: {"rot": (-20, 0, 10)}}
    rest = {j: {k: (0, 0, 0) for k in v} for j, v in gather.items()}
    c.pose(0, rest, ease="sine_inout")
    c.pose(0, WING_IDLE, mirror=True, ease="sine_inout")
    c.pose(12, gather, ease="sine_inout")
    c.pose(12, WING_WRAP, mirror=True, ease="expo_out")
    c.pose(15, gather, ease="expo_out")
    c.pose(24, rise, ease="sine_inout")
    c.pose(24, WING_SPREAD, mirror=True, ease="sine_inout")
    c.pose(46, {j: {k: tuple(x * 1.04 for x in v) for k, v in d.items()} for j, d in rise.items()}, ease="sine_inout")
    # one slow, regal downbeat while the arms are up
    c.pose(34, wings((0, -8, -6), (0, 2, -6), (0, 6, -2), ((0, 8, 0), (0, 0, 0), (0, -6, 0))), mirror=True,
           ease="sine_inout")
    c.pose(46, WING_SPREAD, mirror=True, ease="sine_inout")
    c.pose(70, rest, ease="sine_inout")
    c.pose(70, WING_IDLE, mirror=True)
    c.pose(72, rest)
    A.jitter(c, FAN[L][2], rot=(1, 2, 1), start=24, end=46, seed=7)
    A.jitter(c, FAN[Rr][2], rot=(1, 2, 1), start=24, end=46, seed=8)
    c.key(halo, 0, scale=(1, 1, 1), loc=(0, 0, 0), ease="sine_inout")
    c.key(halo, 15, scale=(0.9, 0.9, 0.9), loc=(0, 0, -0.01), ease="back_out:2.0")
    c.key(halo, 26, scale=(1.35, 1.35, 1.35), loc=(0, 0.02, 0.07), ease="sine_inout")
    c.key(halo, 50, scale=(1.3, 1.3, 1.3), loc=(0, 0.02, 0.07), ease="sine_inout")
    c.key(halo, 72, scale=(1, 1, 1), loc=(0, 0, 0))
    c.key(spin, 0, rot=(0, 0, 0), ease="sine_inout")
    c.key(spin, 72, rot=(0, 0, 360))
    c.key(cast, 0, scale=(0.7, 0.7, 0.7), ease="sine_inout")
    c.key(cast, 24, scale=(1.4, 1.4, 1.6), ease="sine_inout")
    c.key(cast, 50, scale=(1.3, 1.3, 1.5), ease="sine_inout")
    c.key(cast, 72, scale=(0.7, 0.7, 0.7))
    secondary(c, wind=(0, 1.5, 0), robe_freq=1.7)
    c.bake()
