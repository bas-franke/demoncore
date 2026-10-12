"""Nhazgul, the Plague Hive (characters-new): a bloated, hunched brute of sick grey-green hide,
corroded verdigris plate split by plague-green fissures, waxy hive combs grown out of the back and
shoulders (their cells glow with larvae), a swollen belly sac, pustules, torn insect-veined wings
and a rust-eaten cleaver. Derived from vharok.py by _nhazgul_from_vharok.py: the same rig and
animation set (idle walk attack hit death cheer), re-themed materials plus the hive growths.

Rig: _demon_kit.humanoid (Godot needs "look" + "head") plus jaw, wing_L/R > wing_mid > wingtip,
loin_f0..2 / loin_b0..2, tasset_L/R, chain_L0..2 / chain_R0..2, sword (+ sword_tip marker).
"""
import math
import os
import random
import sys

import bmesh
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import sbanim as A  # noqa: E402
import _demon_kit as K  # noqa: E402
import sbmat  # noqa: E402
from _demon_kit import SIDES, sname  # noqa: E402

CATEGORY = "demons"
# Procedural sbmat surfaces (scarred skin, worn black iron, ridged horn, rag weave...) baked into one
# atlas (tools/blender/bake.py); the ember/eye glows stay flat emissive materials.
BAKE = {"size": 1024, "samples": 16}

LEG = 0.49 + 0.45          # thigh + shin (walk speed maths)
WALK_FRAMES = 16
WALK_STRIDE = 40.0
WALK_STANCE = 0.38
# Wing size (rest scale of the wing roots). The wings are Vharok's silhouette from the high game
# camera, so they are drawn larger than the body strictly needs (characters-polish).
WING_SCALE = 1.32


# ============================================================================ local mesh helpers

def setrot(j, rot):
    j.rotation_euler = Euler([math.radians(a) for a in rot])


def ell(radii, la, lo, flare=0.0, lat=(-90, 90), off=1.0):
    """Point + outward normal on a K.shell surface (same lat/lon/flare convention)."""
    rx, ry, rz = radii
    t = (lat[1] - la) / max(lat[1] - lat[0], 1e-6)
    f = (1.0 + flare * t) * off
    a, o = math.radians(la), math.radians(lo)
    p = Vector((rx * math.cos(a) * math.sin(o) * f, -ry * math.cos(a) * math.cos(o) * f, rz * math.sin(a) * off))
    n = Vector((p.x / (rx * rx), p.y / (ry * ry), p.z / (rz * rz))).normalized()
    return p, n


def xf(p, loc=(0, 0, 0), rot=(0, 0, 0)):
    return Euler([math.radians(a) for a in rot]).to_matrix() @ Vector(p) + Vector(loc)


def studs(name, parent, pts, material, r=0.012, h=0.01, segs=5):
    """Many small conical rivets in one mesh: pts = [(pos, normal)]."""
    bm = bmesh.new()
    for p, n in pts:
        p, n = Vector(p), Vector(n).normalized()
        t = n.cross(Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))).normalized()
        b = n.cross(t)
        ring = [bm.verts.new(p + (t * math.cos(2 * math.pi * k / segs) + b * math.sin(2 * math.pi * k / segs)) * r)
                for k in range(segs)]
        apex = bm.verts.new(p + n * h)
        for k in range(segs):
            bm.faces.new((ring[k], ring[(k + 1) % segs], apex))
    return K._obj(name, bm, parent, material, smooth=True, sharp=50)


def shell_studs(name, parent, radii, lat_edge, lons, material, loc=(0, 0, 0), rot=(0, 0, 0), flare=0.0,
                lat=(-90, 90), off=1.06, r=0.012, h=0.01):
    pts = []
    for lo in lons:
        p, n = ell(radii, lat_edge, lo, flare, lat, off)
        pts.append((xf(p, loc, rot), Euler([math.radians(a) for a in rot]).to_matrix() @ n))
    return studs(name, parent, pts, material, r, h)


def trimmed_shell(name, parent, radii, lat, lon, segs, thick, plate, trim, loc=(0, 0, 0), rot=(0, 0, 0),
                  flare=0.0, rim=0.022, rim_top=False, rivets=0, rivet_mat=None, rivet_r=0.011):
    """An armour plate (K.shell) with a bronze rim along its lower edge (and optionally top) + rivets."""
    K.shell(name, parent, radii, lat=lat, lon=lon, segs=segs, thick=thick, material=plate, loc=loc, rot=rot,
            flare=flare)
    span = lat[1] - lat[0]
    d = rim / max(radii[2], 0.01) * 57.0
    rr = tuple(x * 1.02 for x in radii)
    f_lo = flare
    K.shell(name + "_rim", parent, rr, lat=(lat[0], lat[0] + d), lon=lon, segs=(segs[0], 1), thick=thick * 0.7,
            material=trim, loc=loc, rot=rot, flare=f_lo)
    if rim_top:
        K.shell(name + "_rimt", parent, rr, lat=(lat[1] - d, lat[1]), lon=lon, segs=(segs[0], 1),
                thick=thick * 0.7, material=trim, loc=loc, rot=rot, flare=flare * d / span)
    if rivets:
        full = abs((lon[1] - lon[0]) - 360) < 1e-3
        n = rivets
        lons = [lon[0] + (lon[1] - lon[0]) * (i + (0.5 if full else 0.5)) / n for i in range(n)]
        la = lat[0] + d * 0.5
        shell_studs(name + "_rv", parent, radii, la, lons, rivet_mat or trim, loc, rot, flare=flare, lat=lat,
                    off=1.045 + thick / max(min(radii[0], radii[1]), 0.05), r=rivet_r, h=rivet_r * 0.8)


def fissure(name, parent, c, radii, start, heading, steps, material, seed, step=8.0, w=0.006, off=1.06,
            branches=1, turn=38.0):
    """Jagged glowing ember crack wandering over an ellipsoid (start = (lat, lon), heading in degrees in
    lat/lon space: 0 = toward +lon, 90 = up). Forks `branches` thinner cracks off its middle."""
    rng = random.Random(seed)

    def walk(la, lo, h, n, st):
        pts = [(la, lo)]
        for _ in range(n):
            h += rng.uniform(-turn, turn)
            la += math.sin(math.radians(h)) * st
            lo += math.cos(math.radians(h)) * st
            pts.append((la, lo))
        return pts

    def tube(nm, pts, ww):
        path = [K.on_ell(c, radii, a, b, off) for a, b in pts]
        n = len(path)
        rad = [0.002 + ww * 1.2 * math.sin(math.pi * (i + 0.6) / (n + 0.2)) for i in range(n)]
        K.loft(nm, parent, path, rad, material, segs=3, cap_round=1.0, ref=(0, 0, 1))

    main = walk(start[0], start[1], heading, steps, step)
    tube(name, main, w)
    for b in range(branches):
        k = rng.randint(max(1, steps // 3), max(2, steps - 2))
        la, lo = main[k]
        h = heading + rng.choice((-1, 1)) * rng.uniform(40, 75)
        tube(f"{name}_b{b}", walk(la, lo, h, max(2, steps // 2), step * 0.8), w * 0.6)


def ram_horn(name, parent, ctrl, r0, r1, material, n=6, segs=9, rib=0.1, flat=0.22, ref=(0, 0, 1)):
    """Ram horn: catmull path, alternating growth ridges (ribbed), flattened/triangular section."""
    path = K.catmull(ctrl, n)
    m = len(path)
    radii = []
    for i in range(m):
        v = i / (m - 1)
        r = max(0.003, r0 + (r1 - r0) * v ** 0.8)
        k = 1.0 + rib * (1.0 if i % 2 == 0 else -0.35) * (1.0 - v * 0.85)
        radii.append((r * k * (1 + flat), r * k * (1 - flat * 0.6)))
    tri = lambda u, v: 1.0 + 0.09 * math.cos(2 * math.pi * u * 3)  # noqa: E731
    return K.loft(name, parent, path, radii, material, segs, ref=ref, profile=tri, cap_round=1.4)


def spike(name, parent, base, tip, r, material, bend=(0, 0, 0), segs=4):
    b, t = Vector(base), Vector(tip)
    mid = b.lerp(t, 0.55) + Vector(bend)
    return K.horn(name, parent, [b, mid, t], r, 0.0015, material, segs=segs, n=2)


def strap(name, parent, pts, material, w=0.03, t=0.008, ref=(0, 0, 1)):
    return K.loft(name, parent, pts, [(w, t)] * len(pts), material, segs=4, ref=ref, cap_round=0.2)


def chain_links(name, parent, p0, p1, material, count, link=0.075, wire=0.012, mn=3):
    """`count` interlocking low-poly links from p0 toward p1 (6x4 sided)."""
    bm = bmesh.new()
    a, b = Vector(p0), Vector(p1)
    d = (b - a).normalized()
    nrm = Vector((1, 0, 0)) - d * d.x
    if nrm.length < 1e-3:
        nrm = Vector((0, 1, 0)) - d * d.y
    nrm.normalize()
    step = link * 0.74
    for i in range(count):
        n = nrm if i % 2 == 0 else d.cross(nrm)
        K._link_geo(bm, a + d * (step * i + link * 0.5), d, n, link, wire, maj=6, mn=mn)
    return K._obj(name, bm, parent, material, smooth=True)


# ============================================================================ build

def build():
    L = K.lin
    skin = sbmat.skin("Nhazgul_SkinBloated", L((0.2, 0.22, 0.13)), rough=0.5, scars=0.8, pores=70.0,
                      crease=L((0.06, 0.07, 0.03)), high=L((0.36, 0.38, 0.22)))
    plate = sbmat.worn_steel("Nhazgul_VerdigrisPlate", L((0.16, 0.24, 0.18)), roughness=0.45, rust=0.55,
                             edge_k=3.0, scratch_k=1.6, grime=1.0)
    obsid = sbmat.obsidian_ember("Nhazgul_ObsidianRot", tint=L((0.05, 0.06, 0.04)), strength=0.0)
    trim = sbmat.gold_filigree("Nhazgul_BronzeCorroded", tint=L((0.36, 0.42, 0.24)), scale=1.4)
    horn = sbmat.horn("Nhazgul_HornChitin", L((0.3, 0.3, 0.18)), rough=0.4, tip=L((0.08, 0.09, 0.05)))
    dhorn = sbmat.horn("Nhazgul_HornSpikeChitin", L((0.12, 0.13, 0.07)), rough=0.35, rings=30.0)
    claw = sbmat.horn("Nhazgul_ClawBlack", L((0.07, 0.08, 0.05)), rough=0.35, rings=45.0)
    teeth = sbmat.aged_ivory("Nhazgul_TeethYellow", L((0.62, 0.56, 0.3)), scale=2.0)
    ember = K.mat("Nhazgul_PlagueGlow", (0.25, 0.45, 0.05), 0.5, 0.0, (0.55, 1.0, 0.15), 9.0)
    core = K.mat("Nhazgul_PlagueCore", (0.4, 0.7, 0.1), 0.4, 0.0, (0.7, 1.0, 0.3), 12.0)
    eyes = K.mat("Nhazgul_EyeGlow", (0.7, 0.9, 0.2), 0.4, 0.0, (0.85, 1.0, 0.25), 16.0)
    cloth = sbmat.linen("Nhazgul_ClothRag", L((0.16, 0.17, 0.08)), weave=70.0, rough=0.9, stain=0.8,
                        stain_col=L((0.08, 0.09, 0.03)), grime_col=L((0.02, 0.025, 0.01)))
    cloth2 = sbmat.linen("Nhazgul_ClothBlackened", L((0.07, 0.075, 0.05)), weave=70.0, rough=0.92,
                         stain_col=L((0.1, 0.11, 0.05)), grime_col=L((0.02, 0.02, 0.01)))
    leather = sbmat.leather("Nhazgul_LeatherStrap", L((0.13, 0.11, 0.06)), scale=0.55)
    memb = sbmat.skin("Nhazgul_MembraneWing", L((0.3, 0.33, 0.18)), rough=0.4, veins=1.0, pores=40.0,
                      crease=L((0.08, 0.1, 0.04)))
    blade = sbmat.worn_steel("Nhazgul_BladeRust", L((0.2, 0.17, 0.13)), roughness=0.5, edge_k=2.0,
                             scratch_k=1.4, grime=1.0, rust=0.8)
    chainm = sbmat.worn_steel("Nhazgul_ChainIron", L((0.17, 0.18, 0.15)), roughness=0.5, scale=3.0,
                              rust=0.6, edge_k=2.4)
    hive = sbmat.aged_ivory("Nhazgul_HiveWax", L((0.62, 0.48, 0.18)), scale=3.0)
    larva = K.mat("Nhazgul_LarvaGlow", (0.6, 0.85, 0.2), 0.4, 0.0, (0.75, 1.0, 0.3), 7.0)

    R = K.humanoid("Nhazgul", hip_h=1.03, thigh=0.49, shin=0.45, hip_w=0.155, spine=0.26, chest=0.44,
                   neck=0.07, shoulder_w=0.37, shoulder_z=0.33, upper=0.37, fore=0.36, arm_out=18,
                   spine_rot=16, head_rot=-22)
    # brute guard stance baked into the rest pose (sword arm forward, elbows bent)
    setrot(R.arm[1], (6, -20, 4))
    setrot(R.fore[1], (-24, 0, 0))
    setrot(R.arm[-1], (-14, 14, 0))
    setrot(R.fore[-1], (-24, 0, 8))
    setrot(R.hand[-1], (36, 0, 0))

    # ---------------------------------------------------------------- pelvis, belt, chains, buckle
    H = R.hips
    K.loft("pelvis", H, [(0, 0.01, -0.17), (0, 0, -0.07), (0, 0, 0.04), (0, 0, 0.11)],
           [(0.16, 0.13), (0.235, 0.17), (0.25, 0.18), (0.235, 0.17)], skin, segs=12)
    bel = (0.27, 0.2, 0.075)
    K.shell("belt", H, bel, lat=(-40, 40), lon=(-180, 180), segs=(20, 2), thick=0.03, material=leather,
            loc=(0, 0, 0.035))
    for k, z in enumerate((-0.015, 0.085)):
        K.shell(f"belt_band{k}", H, (0.283, 0.212, 0.012), lat=(-60, 60), lon=(-180, 180), segs=(12, 1),
                thick=0.012, material=trim, loc=(0, 0, z))
    shell_studs("belt_rv", H, bel, 0, [a for a in range(-150, 181, 30) if abs(a) > 25], trim,
                loc=(0, 0, 0.035), off=1.13, r=0.013, h=0.012)
    # demon-face buckle: bronze plate, horns, ember eyes + fangs
    K.shell("buckle", H, (0.1, 0.06, 0.09), lat=(-70, 70), lon=(-75, 75), segs=(8, 4), thick=0.022,
            material=trim, loc=(0, -0.155, 0.03))
    for s in SIDES:
        sb.sphere(f"buckle_eye_{sname(s)}", H, 0.014, loc=(s * 0.03, -0.222, 0.05), scale=(1.4, 0.6, 0.8),
                  material=ember, segments=6, rings=3)
        spike(f"buckle_horn_{sname(s)}", H, (s * 0.05, -0.2, 0.08), (s * 0.11, -0.22, 0.14), 0.014, dhorn,
              bend=(s * 0.02, 0, -0.01))
        spike(f"buckle_fang_{sname(s)}", H, (s * 0.022, -0.215, 0.0), (s * 0.015, -0.225, -0.05), 0.008, teeth)
    # festoon chain slung over the belt + hip trophy ring
    pts = K.catmull([(0.24, -0.1, 0.0), (0.18, -0.2, -0.09), (0.03, -0.235, -0.12), (-0.12, -0.215, -0.07),
                     (-0.22, -0.13, 0.0)], 2)
    for i in range(0, len(pts) - 1, 2):
        chain_links(f"belt_chain{i}", H, pts[i], pts[min(i + 2, len(pts) - 1)], chainm, 2, link=0.07, wire=0.01)

    # ---------------------------------------------------------------- loincloths (follow-through chains)
    loin_f = [sb.empty("loin_f0", H, loc=(0, -0.2, -0.02), rot=(-4, 0, 0))]
    loin_b = [sb.empty("loin_b0", H, loc=(0, 0.19, 0.0), rot=(6, 0, 0))]
    for i in range(1, 3):
        loin_f.append(sb.empty(f"loin_f{i}", loin_f[-1], loc=(0, 0, -0.2)))
        loin_b.append(sb.empty(f"loin_b{i}", loin_b[-1], loc=(0, 0, -0.24)))
    for i, j in enumerate(loin_f):
        last = i == 2
        K.panel(f"loin_f{i}_m", j, 0.26 - i * 0.025, 0.24 - i * 0.03, 0.22 + (0.06 if last else 0), cloth,
                segs=(5, 2), cup=0.03, flare=0.0, rag=0.45 if last else 0.0, seed=3, thick=0.012, wave=0.012)
    K.panel("loin_f0_over", loin_f[0], 0.18, 0.15, 0.14, cloth2, segs=(4, 1), cup=0.03, rag=0.3, seed=9,
            thick=0.01, loc=(0, -0.012, 0.02))
    for i, j in enumerate(loin_b):
        last = i == 2
        K.panel(f"loin_b{i}_m", j, 0.32 - i * 0.02, 0.3 - i * 0.025, 0.26 + (0.08 if last else 0), cloth2,
                segs=(5, 2), cup=0.04, flare=0.0, rag=0.5 if last else 0.0, seed=8, thick=0.012, rot=(0, 0, 180),
                wave=0.015)

    # ---------------------------------------------------------------- tassets (follow the thighs)
    tasset = {}
    for s in SIDES:
        n = sname(s)
        tj = sb.empty(f"tasset_{n}", H, loc=(s * 0.25, -0.04, 0.01), rot=(0, s * 14, s * 78))
        tasset[s] = tj
        for k in range(3):
            K.panel(f"tasset_{n}{k}", tj, 0.21 - k * 0.018, 0.2 - k * 0.012, 0.16, plate, segs=(2, 2), cup=0.06,
                    flare=0.04, thick=0.02, loc=(0, -0.006 * k, -k * 0.105), sharp=35)
            K.panel(f"tasset_{n}{k}_rim", tj, 0.2 - k * 0.018, 0.2 - k * 0.012, 0.022, trim, segs=(3, 1),
                    cup=0.06, thick=0.022, loc=(0, -0.008 - 0.006 * k, -k * 0.105 - 0.14), sharp=35)
        studs(f"tasset_{n}_rv", tj, [((x, -0.035, -0.02), (0, -1, 0)) for x in (-0.07, 0.0, 0.07)], trim,
              r=0.011, h=0.01)

    # ---------------------------------------------------------------- legs
    for s in SIDES:
        n = sname(s)
        T, S, F = R.thigh[s], R.shin[s], R.foot[s]
        K.loft(f"thigh_{n}", T, [(0, 0, 0.07), (0, -0.01, -0.07), (0, 0, -0.24), (0, 0.01, -0.4), (0, 0, -0.49)],
               [0.135, (0.15, 0.145), (0.135, 0.13), (0.1, 0.1), 0.085], skin, segs=12)
        cu = (0.152, 0.148, 0.2)
        trimmed_shell(f"cuisse_{n}", T, cu, (-55, 70), (-85, 85), (6, 3), 0.022, plate, trim, loc=(0, 0, -0.17),
                      rivets=4)
        trimmed_shell(f"cuisse_low_{n}", T, (0.13, 0.13, 0.1), (-60, 40), (-80, 80), (8, 2), 0.02, plate, trim,
                      loc=(0, -0.015, -0.36), flare=0.06)
        fissure(f"cuisse_crack_{n}", T, (0, 0, -0.17), cu, (40, s * -40), -70, 6, ember, seed=4 + s, w=0.005,
                off=1.17)
        # knee cop + spike
        K.shell(f"knee_{n}", S, (0.1, 0.09, 0.1), lat=(-45, 85), lon=(-100, 100), segs=(6, 3), thick=0.022,
                material=obsid, loc=(0, -0.035, 0.0), flare=0.08)
        spike(f"knee_spike_{n}", S, (0, -0.11, 0.02), (s * 0.02, -0.21, 0.1), 0.028, dhorn, bend=(0, 0.01, -0.03))
        K.loft(f"shin_{n}", S, [(0, 0, 0.02), (0, 0.02, -0.14), (0, 0, -0.33), (0, 0, -0.45)],
               [0.088, (0.095, 0.1), 0.07, 0.06], skin, segs=10)
        gr = (0.102, 0.108, 0.22)
        trimmed_shell(f"greave_{n}", S, gr, (-75, 72), (-100, 100), (8, 4), 0.024, plate, trim,
                      loc=(0, -0.012, -0.22), flare=0.07, rivets=4)
        K.loft(f"greave_ridge_{n}", S, [K.on_ell((0, -0.012, -0.22), gr, la, 0, 1.15) for la in (-60, -25, 15, 55)],
               [0.01, 0.016, 0.016, 0.008], obsid, segs=4)
        fissure(f"greave_crack_{n}", S, (0, -0.012, -0.22), gr, (50, s * 40), -95, 6, ember, seed=7 + s, w=0.0045,
                off=1.16)
        # sabaton: layered lames, toe claws, heel spur
        K.loft(f"foot_{n}", F, [(0, 0.07, -0.005), (0, 0.0, -0.008), (0, -0.1, -0.02), (0, -0.18, -0.03)],
               [(0.065, 0.045), (0.08, 0.055), (0.08, 0.035), (0.065, 0.022)], skin, segs=8)
        for k in range(2):
            K.shell(f"sabaton_{n}{k}", F, (0.085 - k * 0.006, 0.075, 0.05), lat=(-10, 80), lon=(-110, 110),
                    segs=(6, 2), thick=0.016, material=plate, loc=(0, -0.03 - k * 0.075, -0.02 - k * 0.012),
                    rot=(-12 - k * 8, 0, 0))
        for i, x in enumerate((-0.05, 0.0, 0.05)):
            K.horn(f"toe_{n}{i}", F, [(x, -0.16, -0.02), (x * 1.2, -0.22, -0.02), (x * 1.3, -0.27, -0.045)],
                   0.019, 0.0015, claw, segs=5, n=2)
        spike(f"spur_{n}", F, (0, 0.06, -0.01), (0, 0.15, -0.055), 0.02, claw)

    # ---------------------------------------------------------------- abdomen + faulds
    SP = R.spine
    K.loft("belly", SP, [(0, 0, -0.08), (0, -0.01, 0.06), (0, 0, 0.2), (0, 0, 0.3)],
           [(0.22, 0.16), (0.245, 0.17), (0.28, 0.18), (0.3, 0.19)], skin, segs=12)
    for k, z in enumerate((0.0, 0.085, 0.17)):
        trimmed_shell(f"fauld{k}", SP, (0.255 + k * 0.014, 0.19 + k * 0.007, 0.075), (-55, 25), (-125, 125),
                      (10, 2), 0.02, plate, trim, loc=(0, 0, z), flare=0.12, rim=0.016, rivets=5 if k == 0 else 0)

    # ---------------------------------------------------------------- chest: torso, layered breastplate, core
    C = R.chest
    K.loft("torso", C, [(0, 0, -0.08), (0, -0.01, 0.08), (0, 0, 0.22), (0, 0.01, 0.34), (0, 0.03, 0.44)],
           [(0.29, 0.19), (0.34, 0.21), (0.38, 0.23), (0.37, 0.21), (0.2, 0.15)], skin, segs=14)
    bp_c, bp_r = (0, -0.005, 0.18), (0.355, 0.245, 0.31)
    K.shell("breastplate", C, bp_r, lat=(-55, 64), lon=(-84, 84), segs=(12, 6), thick=0.035, material=plate,
            loc=bp_c, flare=0.05)
    K.shell("breast_rim", C, tuple(x * 1.02 for x in bp_r), lat=(-55, -49), lon=(-84, 84), segs=(12, 1),
            thick=0.025, material=trim, loc=bp_c, flare=0.05)
    # obsidian pectoral slabs overlapping the plate, each with bronze lower rim + rivets
    for s in SIDES:
        pc = (s * 0.13, -0.075, 0.25)
        trimmed_shell(f"pec_{sname(s)}", C, (0.22, 0.2, 0.17), (-35, 70), (-60 + s * 10, 60 + s * 10), (6, 3),
                      0.026, obsid, trim, loc=pc, rot=(0, 0, s * 18), flare=0.08, rivets=3, rim=0.018)
        fissure(f"pec_crack_{sname(s)}", C, bp_c, bp_r, (8, s * 8), 90 - s * 70, 6, ember, seed=20 + s,
                w=0.007, off=1.2, branches=2)
        fissure(f"rib_crack_{sname(s)}", C, bp_c, bp_r, (-20, s * 30), -60 - s * 30 + (180 if s < 0 else 0), 5,
                ember, seed=30 + s, w=0.005, off=1.13)
    # ember heart: glowing core set in a bronze ring, cracks radiate from it
    sb.sphere("heart_core", C, 0.05, loc=(0, -0.265, 0.18), scale=(1.0, 0.55, 1.25), material=ember,
              segments=10, rings=6)
    K.shell("heart_ring", C, (0.075, 0.05, 0.09), lat=(-80, 80), lon=(-180, 180), segs=(12, 1), thick=0.02,
            material=trim, loc=(0, -0.255, 0.18), rot=(90, 0, 0))
    fissure("heart_crack_d", C, bp_c, bp_r, (-12, 0), -90, 5, ember, seed=41, w=0.007, off=1.12)
    K.loft("sternum_ridge", C, [K.on_ell(bp_c, bp_r, la, 0, 1.14) for la in (12, 30, 48, 60)],
           [0.016, 0.02, 0.016, 0.008], obsid, segs=4)
    K.shell("backplate", C, (0.35, 0.24, 0.31), lat=(-50, 62), lon=(100, 260), segs=(10, 5), thick=0.03,
            material=plate, loc=(0, 0.01, 0.18))
    fissure("back_crack", C, (0, 0.01, 0.18), (0.35, 0.24, 0.31), (30, 160), -80, 6, ember, seed=51, w=0.006,
            off=1.12)
    # high gorget with a crown of spines protecting the neck
    trimmed_shell("gorget", C, (0.22, 0.19, 0.1), (-30, 55), (-180, 180), (14, 2), 0.03, obsid, trim,
                  loc=(0, 0.0, 0.41), flare=0.25, rivets=8)
    for k in range(5):
        a = math.radians(110 + k * 35)
        bx, by = 0.17 * math.sin(a), -0.15 * math.cos(a)
        h = 0.14 + 0.06 * (2 - abs(k - 2))
        spike(f"gorget_spine{k}", C, (bx, by, 0.44), (bx * 1.35, by * 1.5 + 0.04, 0.44 + h), 0.026, dhorn,
              bend=(0, 0.03, 0))
    for k in range(4):
        z = 0.02 + k * 0.09
        h = 0.1 + 0.05 * (1.5 - abs(k - 1.5))
        spike(f"spine_spike{k}", C, (0, 0.215, z), (0, 0.24 + h, z + h * 0.7), 0.026, dhorn, bend=(0, 0, -0.02))
    # leather harness straps from the breastplate up over each shoulder, bronze buckles
    for s in SIDES:
        strap(f"harness_{sname(s)}", C, [(s * 0.2, -0.24, 0.3), (s * 0.24, -0.17, 0.44), (s * 0.24, 0.0, 0.5),
                                         (s * 0.22, 0.18, 0.42), (s * 0.18, 0.25, 0.25)], leather, w=0.032, t=0.01)
        sb.box(f"harness_buckle_{sname(s)}", C, size=(0.06, 0.02, 0.05), loc=(s * 0.21, -0.245, 0.33),
               rot=(-18, 0, s * -8), material=trim, bevel=0.0)

    # ---------------------------------------------------------------- arms: huge layered pauldrons, vambraces, shackles
    chains = {}
    for s in SIDES:
        Am, Fo, Ha = R.arm[s], R.fore[s], R.hand[s]
        n = sname(s)
        K.loft(f"upperarm_{n}", Am, [(0, 0, 0.08), (s * 0.012, 0, -0.06), (0, -0.01, -0.2), (0, 0, -0.37)],
               [0.12, (0.13, 0.12), (0.115, 0.115), 0.09], skin, segs=12)
        trimmed_shell(f"paul_dome_{n}", Am, (0.215, 0.225, 0.17), (5, 90), (-180, 180), (12, 3), 0.032, obsid,
                      trim, loc=(s * 0.035, 0, 0.03), rot=(0, -s * 20, 0), flare=0.1, rivets=10, rim=0.02)
        for k in range(2):
            trimmed_shell(f"paul_lame_{n}{k}", Am, (0.22 + k * 0.012, 0.23 + k * 0.01, 0.085), (-50, 25),
                          (s * 90 - 100, s * 90 + 100), (8, 2), 0.022, plate, trim,
                          loc=(s * (0.055 + k * 0.03), 0, -0.03 - k * 0.09), rot=(0, -s * (24 + k * 9), 0),
                          flare=0.18, rim=0.016)
        fissure(f"paul_crack_{n}", Am, (s * 0.035, 0, 0.03), (0.215, 0.225, 0.17), (60, s * 20), 0 if s > 0 else 180,
                6, ember, seed=60 + s, w=0.006, off=1.18, branches=2)
        for k, (y, h) in enumerate(((-0.08, 0.17), (0.0, 0.28), (0.08, 0.2))):
            ram_horn(f"paul_spike_{n}{k}", Am, [(s * 0.08, y, 0.13), (s * 0.14, y * 1.1, 0.13 + h * 0.6),
                                                (s * 0.25, y * 1.4, 0.13 + h)], 0.036, 0.003, dhorn, n=2, segs=5,
                     rib=0.12, flat=0.0, ref=(0, 1, 0))
        # forearm + vambrace with outer blade-fins, cuff, shackle
        K.loft(f"forearm_{n}", Fo, [(0, 0, 0.03), (0, -0.01, -0.1), (0, 0, -0.35)], [0.09, (0.1, 0.092), 0.068],
               skin, segs=10)
        trimmed_shell(f"vambrace_{n}", Fo, (0.108, 0.108, 0.17), (-70, 75), (-180, 180), (10, 3), 0.022, plate,
                      trim, loc=(0, 0, -0.17), rim=0.014)
        K.shell(f"cuff_{n}", Fo, (0.115, 0.115, 0.07), lat=(-20, 60), lon=(-180, 180), segs=(10, 2), thick=0.016,
                material=obsid, loc=(0, 0, -0.05), flare=-0.2)
        for k in range(2):
            z = -0.09 - k * 0.1
            spike(f"vam_fin_{n}{k}", Fo, (s * 0.09, 0.03, z), (s * (0.17 - k * 0.02), 0.07, z + 0.08), 0.02, dhorn,
                  bend=(s * 0.01, 0, -0.02))
        fissure(f"vam_crack_{n}", Fo, (0, 0, -0.17), (0.108, 0.108, 0.17), (50, s * 70), -90, 5, ember, seed=70 + s,
                w=0.0045, off=1.14)
        # iron shackle at the wrist + broken chain (3 joints, follow-through)
        K.shell(f"shackle_{n}", Fo, (0.098, 0.098, 0.035), lat=(-60, 60), lon=(-180, 180), segs=(10, 2),
                thick=0.02, material=chainm, loc=(0, 0, -0.32))
        studs(f"shackle_rv_{n}", Fo, [((math.sin(a) * 0.112, -math.cos(a) * 0.112, -0.32),
                                       (math.sin(a), -math.cos(a), 0)) for a in (0.0, 2.1, 4.2)], chainm,
              r=0.013, h=0.01)
        cj = [sb.empty(f"chain_{n}0", Fo, loc=(s * 0.03, 0.09, -0.31))]
        for i in range(1, 3):
            cj.append(sb.empty(f"chain_{n}{i}", cj[-1], loc=(0, 0, -0.15)))
        for i, j in enumerate(cj):
            chain_links(f"chain_{n}{i}_m", j, (0, 0, 0.02), (0, 0, -1), chainm, 2, link=0.08,
                        wire=0.012)
        chains[s] = cj
        K.claw_hand(f"hand_{n}", Ha, skin, claw, size=1.42, claw_len=0.085, curl=38 if s > 0 else 72)

    # ---------------------------------------------------------------- the greatsword (right hand)
    Hr = R.hand[-1]
    sw = sb.empty("sword", Hr, loc=(0, -0.055, -0.115), rot=(103, 0, -14))
    K.loft("sword_grip", sw, [(0, 0, -0.16), (0, 0, 0.21)], [0.024, 0.024], leather, segs=8,
           profile=lambda u, v: 1.0 + 0.12 * math.cos(v * math.pi * 14))
    K.loft("sword_grip_ring", sw, [(0, 0, -0.17), (0, 0, -0.15)], [0.03, 0.03], trim, segs=8)
    sb.sphere("sword_pommel", sw, 0.045, loc=(0, 0, -0.21), scale=(1, 0.8, 1.25), material=trim, segments=8,
              rings=5)
    spike("sword_pommel_spike", sw, (0, 0, -0.25), (0, 0, -0.33), 0.018, dhorn)
    sb.box("sword_guard", sw, size=(0.42, 0.08, 0.075), loc=(0, 0, 0.245), material=plate, bevel=0.012,
           taper=(0.72, 0.8))
    sb.sphere("sword_eye", sw, 0.03, loc=(0, -0.04, 0.25), scale=(1.4, 0.5, 0.9), material=core, segments=8,
              rings=4)
    for side_y in (-1, 1):
        K.shell(f"sword_eye_lid{side_y}", sw, (0.045, 0.03, 0.035), lat=(-60, 60), lon=(-80, 80), segs=(6, 2),
                thick=0.008, material=trim, loc=(0, -0.038 * side_y, 0.25), rot=(0, 0, 0 if side_y > 0 else 180))
    for s in SIDES:
        ram_horn(f"guard_hook_{sname(s)}", sw, [(s * 0.17, 0, 0.26), (s * 0.27, 0, 0.3), (s * 0.3, 0, 0.42),
                                                (s * 0.25, 0, 0.5)], 0.03, 0.003, horn, n=2, segs=6, rib=0.14,
                 flat=0.0, ref=(0, 1, 0))
    bl = [(0, 0, 0.27), (0, 0, 0.55), (0, 0, 0.9), (0, 0, 1.2), (0, 0, 1.4), (0, 0, 1.52)]
    bw = [(0.125, 0.024), (0.12, 0.024), (0.11, 0.022), (0.095, 0.018), (0.06, 0.012), (0.006, 0.005)]
    K.loft("sword_blade", sw, bl, bw, blade, segs=4, ref=(1, 0, 0), sharp=30, cap_round=0.2)
    # serrated teeth on both edges, bigger toward the guard (hooked back toward the hilt)
    for k, z in enumerate((0.42, 0.66, 0.9, 1.13)):
        for s in SIDES:
            if s < 0 and k % 2:
                continue
            ln = 0.13 - k * 0.016
            wz = 0.12 - z * 0.04
            spike(f"blade_tooth_{k}{sname(s)}", sw, (s * (wz - 0.03), 0, z + 0.03), (s * (wz + ln), 0, z - ln * 0.7),
                  0.034, blade, bend=(0, 0, 0.025))
    # ember fuller: jagged glowing seam on both faces
    for side_y in (-1, 1):
        rng = random.Random(5 + side_y)
        pts = [(rng.uniform(-0.02, 0.02) if 0 < i < 9 else 0.0, side_y * 0.019, 0.3 + i * 0.105) for i in range(10)]
        K.loft(f"sword_fuller{side_y}", sw, pts, [0.005 + 0.007 * math.sin(math.pi * (i + 0.5) / 10)
                                                   for i in range(10)], ember, segs=3, ref=(0, 1, 0))
    sb.empty("sword_tip", sw, loc=(0, 0, 1.52))

    # ---------------------------------------------------------------- neck + head (jaw is its own joint)
    K.loft("neck_m", R.neck, [(0, 0.03, -0.08), (0, 0.0, 0.03), (0, -0.03, 0.12)],
           [(0.15, 0.13), (0.12, 0.11), (0.1, 0.1)], skin, segs=10)
    Hd = R.head
    K.loft("cranium", Hd, [(0, 0.08, 0.05), (0, 0.06, 0.13), (0, -0.01, 0.2), (0, -0.075, 0.21), (0, -0.13, 0.17)],
           [(0.075, 0.075), (0.125, 0.115), (0.13, 0.12), (0.115, 0.095), (0.075, 0.055)], skin, segs=12)
    # heavy brow ridge with spurs, glowing deep-set eyes
    K.loft("brow", Hd, [(-0.13, -0.1, 0.175), (-0.06, -0.165, 0.17), (0.0, -0.17, 0.162), (0.06, -0.165, 0.17),
                        (0.13, -0.1, 0.175)], [0.026, 0.034, 0.03, 0.034, 0.026], skin, segs=7, ref=(0, 0, 1))
    K.loft("muzzle", Hd, [(0, -0.05, 0.12), (0, -0.15, 0.11), (0, -0.215, 0.09)],
           [(0.09, 0.065), (0.075, 0.055), (0.055, 0.04)], skin, segs=10)
    sb.torus("nose_ring", Hd, major=0.022, minor=0.0055, loc=(0, -0.235, 0.07), rot=(0, 90, 0), material=trim,
             major_segments=10, minor_segments=4)
    for s in SIDES:
        n = sname(s)
        sb.sphere(f"eye_{n}", Hd, 0.021, loc=(s * 0.058, -0.168, 0.148), rot=(0, 0, s * 25), scale=(1.7, 0.6, 0.65),
                  material=eyes, segments=8, rings=4)
        spike(f"brow_spur_{n}", Hd, (s * 0.1, -0.13, 0.19), (s * 0.17, -0.12, 0.25), 0.016, dhorn)
        for k in range(2):
            spike(f"cheek_spike_{n}{k}", Hd, (s * 0.095, -0.07 + k * 0.045, 0.1),
                  (s * 0.165, -0.03 + k * 0.05, 0.085 - k * 0.012), 0.013, dhorn)
        # upper fangs
        for k, (x, y) in enumerate(((0.045, -0.2), (0.025, -0.215))):
            spike(f"fang_up_{n}{k}", Hd, (s * x, y, 0.075), (s * x * 0.95, y - 0.008, 0.03 + k * 0.01),
                  0.011 - k * 0.003, teeth)
        # great ram horn: up and back from the crown, curling out, down and forward round the ear
        ctrl = [(s * 0.07, -0.04, 0.2), (s * 0.15, 0.02, 0.29), (s * 0.27, 0.12, 0.28), (s * 0.37, 0.15, 0.14),
                (s * 0.38, 0.06, 0.0), (s * 0.33, -0.08, -0.03), (s * 0.31, -0.17, 0.06), (s * 0.34, -0.21, 0.17)]
        # (Nhazgul) long jointed antennae sweeping up and back, and short hooked mandible-horns.
        ctrl = [(s * 0.06, -0.06, 0.2), (s * 0.12, -0.04, 0.36), (s * 0.2, 0.05, 0.52), (s * 0.3, 0.2, 0.62),
                (s * 0.42, 0.36, 0.64), (s * 0.5, 0.5, 0.6)]
        ram_horn(f"ram_horn_{n}", Hd, ctrl, 0.03, 0.005, horn, n=6, segs=6, rib=0.18, flat=0.0)
        K.horn(f"mandible_{n}", Hd, [(s * 0.08, -0.17, 0.08), (s * 0.13, -0.24, 0.06), (s * 0.08, -0.3, 0.02)],
               0.022, 0.002, horn, segs=6, n=2)
    # glowing maw (visible when the jaw drops) + jaw joint
    sb.sphere("maw_glow", Hd, 0.05, loc=(0, -0.15, 0.06), scale=(1.0, 1.4, 0.45), material=core, segments=8, rings=4)
    jaw = sb.empty("jaw", Hd, loc=(0, -0.02, 0.07))
    K.loft("jaw_m", jaw, [(0, 0.02, -0.01), (0, -0.09, -0.035), (0, -0.19, -0.025)],
           [(0.105, 0.055), (0.085, 0.045), (0.055, 0.03)], skin, segs=10)
    for s in SIDES:
        n = sname(s)
        # lower tusks curving up past the lip
        K.horn(f"tusk_{n}", jaw, [(s * 0.05, -0.15, -0.01), (s * 0.068, -0.19, 0.03), (s * 0.06, -0.2, 0.09)],
               0.016, 0.0015, teeth, segs=6, n=2)
        for k in range(2):
            spike(f"fang_lo_{n}{k}", jaw, (s * (0.012 + k * 0.016), -0.195 + k * 0.01, -0.005),
                  (s * (0.012 + k * 0.016), -0.2 + k * 0.01, 0.03), 0.008, teeth)

    # ---------------------------------------------------------------- torn membrane wings: wing > wing_mid > wingtip
    wings = {}
    for s in SIDES:
        n = sname(s)
        W = sb.empty(f"wing_{n}", C, loc=(s * 0.14, 0.22, 0.32))
        W.scale = (WING_SCALE,) * 3
        W1 = sb.empty(f"wing_mid_{n}", W, loc=(s * 0.28, 0.17, 0.25))
        W2 = sb.empty(f"wingtip_{n}", W1, loc=(s * 0.22, 0.05, 0.18), rot=(24, 0, 0))
        wings[s] = (W, W1, W2)
        K.loft(f"wing_bone0_{n}", W, [(0, 0, 0), (s * 0.15, 0.1, 0.13), (s * 0.28, 0.17, 0.25)], [0.045, 0.036, 0.03],
               dhorn, segs=7)
        K.loft(f"wing_bone1_{n}", W1, [(0, 0, 0), (s * 0.11, 0.03, 0.09), (s * 0.22, 0.05, 0.18)], [0.032, 0.026, 0.024],
               dhorn, segs=7)
        spike(f"wing_elbow_spike_{n}", W1, (0, 0.02, 0), (s * -0.04, 0.12, -0.06), 0.022, dhorn)
        fingers = [(s * 0.36, 0.12, 0.14), (s * 0.48, 0.2, -0.22), (s * 0.4, 0.25, -0.6), (s * 0.18, 0.22, -0.84)]
        for i, f in enumerate(fingers):
            mid = (f[0] * 0.5, f[1] * 0.5, f[2] * 0.5 + 0.06)
            K.loft(f"wing_finger_{n}{i}", W2, [(0, 0, 0), mid, f], [0.02, 0.013, 0.004], dhorn, segs=5, cap_round=1.5)
            K.horn(f"wing_talon_{n}{i}", W2, [f, (f[0] * 1.08, f[1] * 1.05, f[2] - 0.05)], 0.008, 0.001, claw, segs=4,
                   n=1)
        K.horn(f"wing_claw_{n}", W2, [(0, 0, 0.02), (s * 0.02, -0.03, 0.09), (s * 0.0, -0.08, 0.14)], 0.024, 0.002,
               claw, segs=5, n=2)
        body_pt = (-s * 0.46, -0.17, -0.82)
        K.membrane(f"wing_web_{n}", W2, (0, 0, 0), fingers + [body_pt], memb, sag=0.32, nu=5, nw=3, thick=0.012,
                   holes=0.3, seed=11 if s > 0 else 23)

    # ---------------------------------------------------------------- the hive (characters-new)
    # Waxy comb masses grown out of the back and shoulders, each studded with glowing larval cells.
    for k, (loc, rad) in enumerate((((0.0, 0.31, 0.32), 0.3), ((-0.24, 0.27, 0.46), 0.2), ((0.23, 0.28, 0.44), 0.21),
                                    ((0.08, 0.36, 0.12), 0.17), ((-0.13, 0.34, 0.15), 0.15), ((0.0, 0.26, 0.62), 0.16))):
        sb.sphere(f"hive_comb{k}", C, rad, loc=loc, scale=(1.0, 0.8, 1.15), material=hive, segments=10, rings=6)
        for c in range(6):
            a = math.radians(c * 60 + k * 17)
            p = (loc[0] + math.cos(a) * rad * 0.55, loc[1] + rad * 0.72, loc[2] + math.sin(a) * rad * 0.6)
            sb.sphere(f"hive_cell{k}_{c}", C, rad * 0.16, loc=p, scale=(1.0, 0.5, 1.0), material=larva,
                      segments=6, rings=3)
    for s in SIDES:
        n = sname(s)
        sb.sphere(f"hive_shoulder_{n}", C, 0.11, loc=(s * 0.36, 0.08, 0.5), scale=(1.0, 0.9, 0.8), material=hive,
                  segments=8, rings=5)
        for c in range(3):
            sb.sphere(f"hive_shoulder_cell_{n}{c}", C, 0.02, loc=(s * (0.33 + c * 0.03), 0.0, 0.53 + c * 0.02),
                      material=larva, segments=6, rings=3)
    # Swollen belly sac with glowing veins, and pustules on the arms and thighs.
    sb.sphere("belly_sac", SP, 0.2, loc=(0, -0.17, 0.08), scale=(1.15, 0.8, 1.0), material=skin, segments=12, rings=8)
    for v in range(4):
        sb.sphere(f"belly_vein{v}", SP, 0.018, loc=(-0.09 + v * 0.06, -0.33, 0.04 + 0.03 * (v % 2)),
                  scale=(1.0, 0.4, 2.2), material=ember, segments=6, rings=3)
    for s in SIDES:
        n = sname(s)
        for c in range(3):
            sb.sphere(f"pustule_arm_{n}{c}", R.arm[s], 0.028 - c * 0.004, loc=(s * 0.06, -0.04, -0.08 - c * 0.08),
                      material=larva, segments=6, rings=4)
            sb.sphere(f"pustule_leg_{n}{c}", R.thigh[s], 0.026, loc=(s * 0.08, -0.07, -0.12 - c * 0.1),
                      material=larva, segments=6, rings=4)

    animate(R, dict(loin_f=loin_f, loin_b=loin_b, tasset=tasset, chains=chains, wings=wings, jaw=jaw, sword=sw))
    K.finalize(R.root)
    return R.root


# ============================================================================ animation

def animate(R, X):
    ALL = [j for j in A.joints(R.root) if j.name != "look"]   # "look" is driven by Godot, never keyed
    hips, spine, chest, neck, head = R.hips, R.spine, R.chest, R.neck, R.head
    thL, thR, shL, shR, ftL, ftR = R.thigh[1], R.thigh[-1], R.shin[1], R.shin[-1], R.foot[1], R.foot[-1]
    aL, aR, oL, oR, hL, hR = R.arm[1], R.arm[-1], R.fore[1], R.fore[-1], R.hand[1], R.hand[-1]
    jaw, sword = X["jaw"], X["sword"]
    wL, wR = list(X["wings"][1]), list(X["wings"][-1])
    loin_f, loin_b = X["loin_f"], X["loin_b"]
    tL, tR = X["tasset"][1], X["tasset"][-1]
    cL, cR = X["chains"][1], X["chains"][-1]
    rig = {"hips": hips, "spine": spine, "chest": chest, "head": head, "thigh": (thL, thR), "shin": (shL, shR),
           "foot": (ftL, ftR), "arm": (aL, None), "fore": (oL, None)}

    # wide, sunk brute stance (additive, so every keyed pose sits on top of it)
    STANCE_LEGS = {thL: (-12, -5, 0), thR: (-10, 5, 0), shL: (24, 0, 0), shR: (20, 0, 0),
                   ftL: (-12, 5, 0), ftR: (-10, -5, 0)}

    def stance(c, legs=True, upper=True):
        if legs:
            for j, r in STANCE_LEGS.items():
                c.add(j, (lambda f, r=r: r), "rot")
            # keep the soles on the ground with bent knees
            drop = (0.49 * math.cos(math.radians(12)) + 0.45 * math.cos(math.radians(12))) - LEG
            c.add(hips, lambda f: (0, 0.02, drop - 0.005), "loc")
        if upper:
            c.add(spine, lambda f: (4, 0, 0), "rot")

    def tassets_follow(c, k=0.55):
        c.add(tL, lambda f: (c.eval(thL, "rot", f)[0] * k, 0, 0), "rot")
        c.add(tR, lambda f: (c.eval(thR, "rot", f)[0] * k, 0, 0), "rot")

    def loin_push(c, k=0.75):
        # the front cloth is pushed forward by whichever thigh is further forward (no leg clipping)
        c.add(loin_f[0], lambda f: (min(0.0, c.eval(thL, "rot", f)[0], c.eval(thR, "rot", f)[0]) * k, 0, 0), "rot")
        c.add(loin_b[0], lambda f: (max(0.0, c.eval(thL, "rot", f)[0], c.eval(thR, "rot", f)[0]) * k * 0.5, 0, 0),
              "rot")

    def secondary(c, floor=None, wing_g=2.5, wing_freq=2.6):
        A.follow_through(c, loin_f, freq=2.4, damping=0.16, gravity=7.0, falloff=0.85, floor=floor,
                         tip=(0, 0, -0.26))
        A.follow_through(c, loin_b, freq=2.0, damping=0.14, gravity=7.0, falloff=0.85, floor=floor,
                         tip=(0, 0, -0.32))
        for ch in (cL, cR):
            A.follow_through(c, ch, freq=1.8, damping=0.1, gravity=9.0, falloff=0.9, floor=floor, tip=(0, 0, -0.14))
        for wc in (wL, wR):
            A.follow_through(c, wc, freq=wing_freq, damping=0.2, gravity=wing_g, falloff=0.8, max_angle=40,
                             tip=_tip_vec(wc))

    def _wing_fold(c, f, amt=1.0, ease="smooth"):
        c.pose(f, {wL[0]: {"rot": (0, 10 * amt, 26 * amt)}, wL[1]: {"rot": (0, -8 * amt, 18 * amt)},
                   wL[2]: {"rot": (0, -6 * amt, 10 * amt)}}, mirror=True, ease=ease)

    # ------------------------------------------------------------------ idle (loop, 3 s)
    c = A.Clip("idle", 90, joints=ALL)
    stance(c)
    A.breathe(c, chest, amp=3.6, rise=0.016, swell=0.026, cycles=2, inhale=0.4, shoulders=[aL, aR], head=head)
    c.add(hips, lambda f: (0.016 * A.wave(c, f), 0, -0.008 * abs(A.wave(c, f))), "loc")   # slow weight shift
    c.add(hips, lambda f: (0, 1.6 * A.wave(c, f), 0.8 * A.wave(c, f, offset=0.2)), "rot")
    c.add(spine, lambda f: (0, -1.2 * A.wave(c, f), 0), "rot")
    c.add(jaw, lambda f: (2.5 + 2.5 * A.wave(c, f, cycles=2, offset=-0.12), 0, 0), "rot")   # heavy breathing
    A.noise(c, head, rot=(2.5, 4, 2), freq=0.35, seed=1)
    A.noise(c, aR, rot=(2, 1, 1.5), freq=0.3, seed=3)
    A.noise(c, aL, rot=(2, 1, 2), freq=0.3, seed=4)
    c.add(oL, lambda f: (-3 * A.wave(c, f, cycles=2, offset=0.1), 0, 0), "rot")
    c.add(hL, lambda f: (4 * A.wave(c, f, cycles=2, offset=0.3), 0, 0), "rot")     # claws flex
    c.add(sword, lambda f: (2.0 * A.wave(c, f, offset=0.3), 0, 1.2 * A.wave(c, f, cycles=2)), "rot")
    # wings: slow menacing stretch (open a little, settle back) + drift
    c.add(wL[0], lambda f: (0, -11 * max(0.0, A.wave(c, f, offset=0.1)) ** 2, -9 * max(0.0, A.wave(c, f, offset=0.1)) ** 2),
          "rot")
    c.add(wL[1], lambda f: (0, -5 * max(0.0, A.wave(c, f, offset=0.05)) ** 2, -4 * max(0.0, A.wave(c, f)) ** 2), "rot")
    A.noise(c, wL[2], rot=(2, 4, 3), freq=0.6, seed=7)
    c.mirror(wL[0], wR[0], phase=0.0)
    c.mirror(wL[1], wR[1], phase=0.0)
    c.mirror(wL[2], wR[2], phase=0.5)
    tassets_follow(c)
    secondary(c)
    c.bake()

    # ------------------------------------------------------------------ walk (loop: heavy loping charge)
    c = A.Clip("walk", WALK_FRAMES, joints=ALL)
    A.walk(c, rig, stride=WALK_STRIDE, knee=78, load=10, stance=WALK_STANCE, arm=30, elbow=22, elbow_swing=22,
           lean=12, twist=12, hip_roll=5, hip_yaw=8, heavy=0.7, heel=12, toe_off=26, sway=0.03, head_stab=0.85)
    c.add(spine, lambda f: (6, 0, 0), "rot")
    c.add(aR, lambda f: (-16 + 7 * A.wave(c, f, offset=0.5 - 0.1), 0, 4), "rot")      # sword arm carried, small swing
    c.add(oR, lambda f: (-6 - 4 * A.wave(c, f, cycles=2, offset=0.2), 0, 0), "rot")
    c.add(sword, lambda f: (-34 + 4 * A.wave(c, f, cycles=2, offset=0.35), 0, 0), "rot")  # tip up off the ground
    c.add(jaw, lambda f: (6 + 2 * A.wave(c, f, cycles=2), 0, 0), "rot")
    _wing_fold(c, 0, 0.9)
    c.add(wL[0], lambda f: (0, 3 * A.wave(c, f, cycles=2, offset=0.15), 0), "rot")
    c.add(wR[0], lambda f: (0, -3 * A.wave(c, f, cycles=2, offset=0.15), 0), "rot")
    tassets_follow(c, 0.6)
    loin_push(c)
    secondary(c, wing_g=3.5)
    c.bake()
    print("VHAROK walk stride_speed m/s =", round(A.stride_speed(LEG, WALK_STRIDE, WALK_FRAMES,
                                                                 stance=WALK_STANCE), 2))

    # ------------------------------------------------------------------ attack (overhead cleave)
    c = A.Clip("attack", 42, joints=ALL)
    stance(c)
    antic = {aR: {"rot": (-150, -10, -20)}, oR: {"rot": (-55, 0, 0)}, hR: {"rot": (-20, 0, 0)},
             sword: {"rot": (-40, 0, 10)},
             chest: {"rot": (-14, 6, 22)}, spine: {"rot": (-10, 0, 10)}, hips: {"loc": (0, 0.07, 0.02), "rot": (0, 0, 8)},
             neck: {"rot": (-10, 0, -10)}, head: {"rot": (0, 0, -6)}, jaw: {"rot": (12, 0, 0)},
             aL: {"rot": (-55, 0, 18)}, oL: {"rot": (-40, 0, 0)},
             thL: {"rot": (-14, 0, 0)}, shL: {"rot": (10, 0, 0)}, ftL: {"rot": (4, 0, 0)},
             thR: {"rot": (10, 0, 0)}, shR: {"rot": (12, 0, 0)}, ftR: {"rot": (-22, 0, 0)},
             wL[0]: {"rot": (0, -22, -20)}, wR[0]: {"rot": (0, 22, 20)}, wL[1]: {"rot": (0, -14, -10)},
             wR[1]: {"rot": (0, 14, 10)}}
    strike = {aR: {"rot": (-40, 6, 14)}, oR: {"rot": (-6, 0, 0)}, hR: {"rot": (14, 0, 0)},
              sword: {"rot": (30, 0, 0)},
              chest: {"rot": (26, -4, -24)}, spine: {"rot": (14, 0, -10)}, hips: {"loc": (0, -0.18, -0.16), "rot": (0, 0, -8)},
              neck: {"rot": (-14, 0, 12)}, head: {"rot": (-8, 0, 6)}, jaw: {"rot": (26, 0, 0)},
              aL: {"rot": (34, 0, -24)}, oL: {"rot": (-30, 0, 0)},
              thL: {"rot": (-50, 0, 0)}, shL: {"rot": (62, 0, 0)}, ftL: {"rot": (-12, 0, 0)},
              thR: {"rot": (26, 0, 0)}, shR: {"rot": (30, 0, 0)}, ftR: {"rot": (-50, 0, 0)},
              wL[0]: {"rot": (0, 14, 22)}, wR[0]: {"rot": (0, -14, -22)}, wL[1]: {"rot": (0, 10, 12)},
              wR[1]: {"rot": (0, -10, -12)}}
    follow = {j: {k: tuple(x * 0.93 for x in v) for k, v in d.items()} for j, d in strike.items()}
    ev = A.attack(c, {"antic": antic, "strike": strike, "follow": follow}, start=0, antic=13, antic_hold=5,
                  strike=3, hold=5, recover=16, overshoot=0.1, push=0.08)
    A.jitter(c, aR, rot=(1.5, 1.0, 1.5), start=12, end=18)
    A.jitter(c, chest, rot=(0.8, 0.5, 0.8), start=12, end=18)
    imp = ev["impact"]
    c.add(chest, lambda f: (0, 0, 0) if f < imp else (2.5 * math.exp(-(f - imp) / 3.0) * math.sin((f - imp) * 1.7), 0, 0),
          "rot")   # impact shudder
    tassets_follow(c)
    loin_push(c, 0.6)
    secondary(c)
    c.bake()
    print("VHAROK attack impact frame", imp)

    # ------------------------------------------------------------------ hit (recoil)
    c = A.Clip("hit", 22, joints=ALL)
    stance(c)
    A.hit_react(c, {hips: {"loc": (0, 0.13, -0.05), "rot": (-7, 0, 4)}, spine: {"rot": (-15, 0, 6)},
                    chest: {"rot": (-18, 5, 11), "scale": (1.04, 1.04, 0.96)}, neck: {"rot": (-12, 0, 0)},
                    head: {"rot": (-26, 10, -14)}, jaw: {"rot": (26, 0, 0)},
                    aL: {"rot": (-28, 0, -26)}, oL: {"rot": (-30, 0, 0)}, aR: {"rot": (-18, 0, 22)},
                    sword: {"rot": (-14, 0, 0)},
                    wL[0]: {"rot": (0, -24, -22)}, wR[0]: {"rot": (0, 24, 22)}, wL[1]: {"rot": (0, -16, -14)},
                    wR[1]: {"rot": (0, 16, 14)}, thL: {"rot": (-6, 0, 0)}, shL: {"rot": (10, 0, 0)}},
                start=0, rise=2, settle=14, wobble=1.0, stagger=0.8)
    tassets_follow(c)
    secondary(c)
    c.bake()

    # ------------------------------------------------------------------ death (stagger, knees, crash face-down)
    c = A.Clip("death", 64, joints=ALL)
    stance(c, legs=False)
    buckle = {hips: {"loc": (0, 0.06, -0.34)}, thL: {"rot": (-62, -6, 0)}, shL: {"rot": (110, 0, 0)},
              ftL: {"rot": (-40, 0, 0)}, thR: {"rot": (-30, 6, 0)}, shR: {"rot": (100, 0, 0)}, ftR: {"rot": (-60, 0, 0)},
              spine: {"rot": (20, 0, 4)}, chest: {"rot": (8, 0, 0)}, head: {"rot": (26, 0, 6)}, jaw: {"rot": (20, 0, 0)},
              aL: {"rot": (-14, 0, 10)}, aR: {"rot": (-6, 0, -6)}, oR: {"rot": (14, 0, 0)}, sword: {"rot": (34, 0, 0)},
              wL[0]: {"rot": (0, 10, 24)}, wR[0]: {"rot": (0, -10, -24)}}
    limp = {hips: {"loc": (0, 0.04, -0.3)}, thL: {"rot": (-30, 0, 4)}, shL: {"rot": (60, 0, 0)}, ftL: {"rot": (-30, 0, 0)},
            thR: {"rot": (-14, 0, -6)}, shR: {"rot": (40, 0, 0)}, ftR: {"rot": (-40, 0, 0)},
            spine: {"rot": (-6, 0, 0)}, chest: {"rot": (-4, 0, 0)}, head: {"rot": (-30, 0, 30)}, jaw: {"rot": (28, 0, 0)},
            aL: {"rot": (-70, 0, 55)}, oL: {"rot": (-10, 0, 0)}, aR: {"rot": (-80, 0, -40)}, oR: {"rot": (10, 0, 0)},
            hR: {"rot": (20, 0, 0)}, sword: {"rot": (60, 0, 20)},
            wL[0]: {"rot": (-20, 40, -10)}, wR[0]: {"rot": (-20, -40, 10)}, wL[1]: {"rot": (0, 20, 0)},
            wR[1]: {"rot": (0, -20, 0)}, wL[2]: {"rot": (0, 18, 0)}, wR[2]: {"rot": (0, -18, 0)}}
    imp = A.death(c, R.body, fall=(78, 0, -10), drop=(0, -0.1, 0.1), stagger=6, buckle=11, topple=11, bounce=0.07,
                  recoil={chest: {"rot": (-14, 0, 8)}, head: {"rot": (-22, 0, 0)}, aL: {"rot": (-20, 0, -20)}},
                  buckle_pose=buckle, limp_pose=limp)
    tassets_follow(c, 0.4)
    secondary(c, floor=0.03, wing_g=6.0, wing_freq=1.6)
    c.bake()
    print("VHAROK death impact frame", imp)

    # ------------------------------------------------------------------ cheer (gather -> ROAR, wings flared, sword raised)
    c = A.Clip("cheer", 78, joints=ALL)
    stance(c)
    gather = {hips: {"loc": (0, 0.03, -0.12)}, spine: {"rot": (22, 0, 0)}, chest: {"rot": (10, 0, 0)},
              neck: {"rot": (14, 0, 0)}, head: {"rot": (12, 0, 0)}, jaw: {"rot": (0, 0, 0)},
              thL: {"rot": (-26, 0, 0)}, shL: {"rot": (48, 0, 0)}, ftL: {"rot": (-22, 0, 0)},
              thR: {"rot": (-22, 0, 0)}, shR: {"rot": (44, 0, 0)}, ftR: {"rot": (-22, 0, 0)},
              aL: {"rot": (-20, 0, 14)}, oL: {"rot": (-50, 0, 0)}, hL: {"rot": (-30, 0, 0)},
              aR: {"rot": (-12, 0, -10)}, oR: {"rot": (-30, 0, 0)}, sword: {"rot": (14, 0, 0)},
              wL[0]: {"rot": (0, 16, 30)}, wR[0]: {"rot": (0, -16, -30)}, wL[1]: {"rot": (0, -8, 22)},
              wR[1]: {"rot": (0, 8, -22)}, wL[2]: {"rot": (0, -6, 12)}, wR[2]: {"rot": (0, 6, -12)}}
    roar = {hips: {"loc": (0, 0.03, 0.02)}, spine: {"rot": (-16, 0, 0)}, chest: {"rot": (-16, 0, 0)},
            neck: {"rot": (-24, 0, 0)}, head: {"rot": (-22, 0, 0)}, jaw: {"rot": (38, 0, 0)},
            thL: {"rot": (-4, -6, 0)}, shL: {"rot": (8, 0, 0)}, ftL: {"rot": (-4, 6, 0)},
            thR: {"rot": (-4, 6, 0)}, shR: {"rot": (8, 0, 0)}, ftR: {"rot": (-4, -6, 0)},
            aL: {"rot": (-40, 0, 0), "loc": (0, 0, 0.02)}, oL: {"rot": (-48, 0, 0)}, hL: {"rot": (-20, 0, 0)},
            aR: {"rot": (-2, 126, 0)}, oR: {"rot": (14, 0, -8)}, hR: {"rot": (-36, 0, 0)}, sword: {"rot": (66, 0, 0)},
            wL[0]: {"rot": (0, -36, -30)}, wR[0]: {"rot": (0, 36, 30)}, wL[1]: {"rot": (0, -24, -22)},
            wR[1]: {"rot": (0, 24, 22)}, wL[2]: {"rot": (0, -14, -16)}, wR[2]: {"rot": (0, 14, 16)}}
    # arms flung out wide on the roar: arm_L outward via its Y axis
    roar[aL]["rot"] = (-20, -118, -4)
    roar[oL]["rot"] = (8, 0, 0)
    keys_j = list(dict.fromkeys(list(gather) + list(roar)))

    def g(pose, j, ch, s=1.0):
        v = pose.get(j, {}).get(ch)
        return None if v is None else tuple(x * s for x in v)

    for j in keys_j:
        for ch in ("rot", "loc"):
            if g(gather, j, ch) is None and g(roar, j, ch) is None:
                continue
            z = (0, 0, 0)
            ga = g(gather, j, ch) or z
            ro = g(roar, j, ch) or z
            c.key(j, 0, **{ch: z}, ease="sine_inout")
            c.key(j, 14, **{ch: ga}, ease="sine_inout")
            c.key(j, 20, **{ch: tuple(x * 1.06 for x in ga)}, ease="expo_out")          # coiled moving hold
            c.key(j, 26, **{ch: tuple(x * 1.08 for x in ro)}, ease="sine_inout")       # explode into the roar
            c.key(j, 52, **{ch: ro}, ease="quad_inout")
            c.key(j, 76, **{ch: z}, ease="smooth")
    A.jitter(c, chest, rot=(1.6, 1.2, 1.4), freq=11, start=26, end=54, seed=2)
    A.jitter(c, head, rot=(2.5, 2, 2.5), freq=13, start=26, end=54, seed=3)
    A.jitter(c, aR, rot=(1.5, 1, 1.5), freq=9, start=26, end=54, seed=4)
    A.jitter(c, wL[2], rot=(0, 4, 3), freq=10, start=26, end=54, seed=5)
    A.jitter(c, wR[2], rot=(0, 4, 3), freq=10, start=26, end=54, seed=6)
    tassets_follow(c)
    secondary(c)
    c.bake()


def _tip_vec(wc):
    """Local end vector of a wing chain's last link (roughly toward the outer finger tips)."""
    return Vector((0.4 if wc[0].name.endswith("_L") else -0.4, 0.2, -0.3))
