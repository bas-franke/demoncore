"""Ophanim ("wheels"): a wheel within a wheel within a wheel. Three gyroscopically nested gold
rings with beveled, engraved bands (a channel of holy light runs along each rim, broken into
glyphs), their rims set with lidded eyes that blink. They gimbal around a radiant core with a
burning, heavy-lidded great eye. A small pair of wings springs from the outer wheel's axle hubs
(the winged wheel of the Thrones), and a crown-halo of light hovers over the top finial.

Gimbal (each ring turns on pins held by its parent):
    core (hover) -> outer (turns about Z) -> mid (pins at outer's +-X, turns about X)
                 -> inner (pins at mid's +-Y, turns about Y)
At rest the rings are mutually perpendicular. Aligned (windup / attack): outer Z 0, mid X +90,
inner Y -90 -> all three coplanar, facing forward (-Y) like a bullseye around the great eye.

Joints: core, aura (radiance + rays), great_eye, lid_up, lid_dn, crown, outer, mid, inner,
wing_L, wing_R, eye{ring}_{k} (scale Z = blink).
Anims: idle (loop: rings turn at 1 / -2 / 3 turns per 8 s, eyes blink, wings flutter),
windup (spin up, snap into alignment, eyes widen, core flares), attack (pulse + recoil, rings
spin back out), hit (rings jolt, eyes squeeze shut), death (rings stall, fall and settle flat,
light goes out)."""
import importlib.util
import math
import os

import bmesh
from mathutils import Euler, Matrix, Vector

import sb
import sbanim as A

_spec = importlib.util.spec_from_file_location("_angel", os.path.join(os.path.dirname(__file__), "_angel.py"))
AG = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(AG)

CATEGORY = "enemies"
CORE_Z = 0.55       # + EnemyData.hover 0.8 = 1.35 = muzzle_height (orbs leave the great eye)
HOVER = float(os.environ.get("OPHANIM_HOVER", "0.8"))   # the corpse falls this far below the model origin
RADII = (0.56, 0.43, 0.30)
SEGS = (32, 28, 22)
T = 0.028           # band radial half-thickness
W = 0.045           # band axial half-width
BEV = 0.007
GROOVE = (0.02, 0.008)   # half-width, depth
BAND_ROT = ((90, 0, 0), (0, 0, 0), (0, 90, 0))   # band local (XY plane, axis Z) -> ring joint
EYE_ANGLES = ((30, 60, 120, 150, 210, 240, 300, 330), (45, 135, 225, 315), (45, 135, 225, 315))
EYE_SIZE = (0.11, 0.1, 0.09)
EYE_TILT = 25.0     # eyes lean toward the band's +Z face (= forward when aligned)
CROWN_Z = RADII[0] + T + 0.095
GLYPHS = ("1110110111101101110111011110110",
          "1101111011011101111011011101",
          "1110111011011110111011")
ALIGN = {"outer": (0, 0, 0), "mid": (90, 0, 0), "inner": (0, -90, 0)}


def _deg(e):
    return tuple(math.degrees(a) for a in e)


def _rm(rot):
    return Euler([math.radians(a) for a in rot]).to_matrix()


# ----------------------------------------------------------------------------- geometry

def band(name, parent, radius, segs, glyphs, gold, dark, glow, rim, rot):
    """Beveled rim with an engraved channel round its outer face. The channel floor alternates
    holy light / dark gold per segment (`glyphs` bits) so it reads as a burning inscription."""
    t, w, b = T, W, BEV
    g, d = GROOVE
    prof = [(t - b, -w), (t, -w + b), (t, -g), (t - d, -g + 0.003), (t - d, g - 0.003), (t, g),
            (t, w - b), (t - b, w), (-t, w), (-t, -w)]
    # material per profile edge (edge k = prof[k] -> prof[k+1]): 0 gold, 1 dark, 2 glow / pattern
    emat = [0, 0, 1, "groove", 1, 0, 0, 0, 3, 0]   # 3 = inner face lit by the core
    bm = bmesh.new()
    rows = []
    for s in range(segs):
        a = 2 * math.pi * s / segs
        ca, sa = math.cos(a), math.sin(a)
        rows.append([bm.verts.new(((radius + dr) * ca, (radius + dr) * sa, dz)) for dr, dz in prof])
    n = len(prof)
    for s in range(segs):
        r0, r1 = rows[s], rows[(s + 1) % segs]
        for k in range(n):
            k1 = (k + 1) % n
            f = bm.faces.new((r0[k], r1[k], r1[k1], r0[k1]))
            m = emat[k]
            if m == "groove":
                m = 2 if glyphs[s % len(glyphs)] == "1" else 1
            f.material_index = m
            f.smooth = True
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(35):
            e.smooth = False
    obj = sb._new_mesh_obj(name, bm)
    obj = sb._finish(obj, parent, None, (0, 0, 0), rot, (1, 1, 1), 0.0, 0, False, name)
    for m in (gold, dark, glow, rim):
        obj.data.materials.append(m)
    return obj


def shell(name, parent, r_out, r_in, half_angle, segs, material, steps=2):
    """Thick spherical cap around +Z (an eyelid), polar angle 0..half_angle."""
    bm = bmesh.new()
    angs = [half_angle * (i + 1) / steps for i in range(steps)]
    top_o = bm.verts.new((0, 0, r_out))
    top_i = bm.verts.new((0, 0, r_in))

    def ring_at(r, ang):
        a = math.radians(ang)
        return [bm.verts.new((r * math.sin(a) * math.cos(2 * math.pi * k / segs),
                              r * math.sin(a) * math.sin(2 * math.pi * k / segs), r * math.cos(a)))
                for k in range(segs)]
    outer = [ring_at(r_out, a) for a in angs]
    inner = [ring_at(r_in, a) for a in angs]
    for pole, rings in ((top_o, outer), (top_i, inner)):
        for k in range(segs):
            bm.faces.new((pole, rings[0][k], rings[0][(k + 1) % segs]))
        for lo, hi in zip(rings[:-1], rings[1:]):
            for k in range(segs):
                k1 = (k + 1) % segs
                bm.faces.new((lo[k], hi[k], hi[k1], lo[k1]))
    lo, hi = outer[-1], inner[-1]
    for k in range(segs):
        k1 = (k + 1) % segs
        bm.faces.new((lo[k], hi[k], hi[k1], lo[k1]))
    for f in bm.faces:
        f.smooth = True
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = sb._new_mesh_obj(name, bm)
    return sb._finish(obj, parent, material, (0, 0, 0), (0, 0, 0), (1, 1, 1), 0.0, 0, True, name)


def ring_eye(name, parent, pos, look, tangent, size, m, gold):
    """Lidded almond eye looking along `look`, long axis along `tangent` (parent space).
    Joint local: -Y = gaze, X = long axis, Z = lid axis (scale Z to blink)."""
    y = -look.normalized()
    x = (tangent - tangent.dot(y) * y).normalized()
    z = x.cross(y)
    mtx = Matrix((x, y, z)).transposed()
    j = sb.empty(name, parent, loc=tuple(pos), rot=_deg(mtx.to_euler()))
    AG.ellipsoid(name + "_ball", j, (size, size * 0.5, size * 0.56), material=m["eye"], seg=8, rings=4)
    sb.box(name + "_pupil", j, size=(size * 0.11, size * 0.08, size * 0.46), loc=(0, -size * 0.23, 0),
           material=m["pupil"], bevel=0.0)
    lid = sb.torus(name + "_lid", j, major=size * 0.52, minor=size * 0.11, loc=(0, -size * 0.02, 0),
                   rot=(90, 0, 0), material=gold, major_segments=8, minor_segments=3)
    lid.scale = (1.0, 0.62, 1.0)
    return j


# ----------------------------------------------------------------------------- model

def build():
    m = AG.mats()
    gold = sb.mat("Ophanim_GoldRing", (0.9, 0.67, 0.29), roughness=0.24, metallic=1.0)
    dark = sb.mat("Ophanim_GoldEngraved", (0.42, 0.29, 0.11), roughness=0.5, metallic=1.0)
    glow = m["halo"]
    rim = sb.mat("Ophanim_RimLight", (1.0, 0.8, 0.45), roughness=0.4, emission=(1.0, 0.74, 0.36), strength=1.5)

    root = sb.root("Ophanim")
    core = sb.empty("core", root, loc=(0, 0, CORE_Z))

    # --- radiant core: a sun disc of light with a corona of rays behind the great eye
    aura = sb.empty("aura", core, loc=(0, 0.035, 0))
    AG.ellipsoid("aura_sun", aura, (0.23, 0.17, 0.23), material=m["light"], seg=12, rings=6)
    for i in range(10):
        a = 2 * math.pi * (i + 0.25) / 10
        dv = (math.cos(a), 0.0, math.sin(a))
        AG.spike(f"aura_ray{i}", aura, (dv[0] * 0.1, 0.01, dv[2] * 0.1), dv, 0.15 if i % 2 == 0 else 0.09,
                 0.032, 0.012, material=m["halo"], up=(0, -1, 0))

    # --- the great eye: white-hot globe, burning ember iris, slit pupil, heavy gold lids
    great = sb.empty("great_eye", core, loc=(0, -0.03, 0), rot=(-25, 0, 0))
    sb.sphere("great_ball", great, radius=0.095, material=m["eye"], segments=12, rings=8)
    sb.torus("great_iris", great, major=0.045, minor=0.013, loc=(0, -0.084, 0), rot=(90, 0, 0),
             material=m["ember"], major_segments=12, minor_segments=3)
    sb.box("great_pupil", great, size=(0.017, 0.012, 0.064), loc=(0, -0.093, 0), material=m["pupil"],
           bevel=0.0)
    lid_up = sb.empty("lid_up", great, rot=(-42, 0, 0))
    shell("lid_up_shell", lid_up, 0.114, 0.107, 93, 12, gold)
    lid_dn = sb.empty("lid_dn", great, rot=(180 + 42, 0, 0))
    shell("lid_dn_shell", lid_dn, 0.105, 0.099, 93, 12, dark)

    # --- the three wheels
    outer = sb.empty("outer", core)
    mid = sb.empty("mid", outer)
    inner = sb.empty("inner", mid)
    rings = (outer, mid, inner)
    eyes = []
    for i, (rj, r) in enumerate(zip(rings, RADII)):
        band(f"band{i}", rj, r, SEGS[i], GLYPHS[i], gold, dark, glow, rim, BAND_ROT[i])
        B = _rm(BAND_ROT[i])
        for k, deg in enumerate(EYE_ANGLES[i]):
            a = math.radians(deg)
            rad = Vector((math.cos(a), math.sin(a), 0))
            pos = rad * (r + T + 0.002)
            look = rad * math.cos(math.radians(EYE_TILT)) + Vector((0, 0, math.sin(math.radians(EYE_TILT))))
            tan = Vector((-math.sin(a), math.cos(a), 0))
            eyes.append(ring_eye(f"eye{i}_{k}", rj, B @ pos, B @ look, B @ tan, EYE_SIZE[i], m, gold))

    # axle pins + hub bosses: mid hangs in outer on +-X, inner hangs in mid on +-Y
    for s in (-1, 1):
        sd = "L" if s > 0 else "R"
        AG.seg(f"pin_mid_{sd}", outer, (s * (RADII[1] + T * 0.5), 0, 0), (s * (RADII[0] - T * 0.5), 0, 0),
               0.011, material=m["gold_dark"], segments=6)
        sb.sphere(f"hub_mid_{sd}", outer, radius=0.021, loc=(s * (RADII[1] + T + 0.017), 0, 0),
                  material=gold, segments=6, rings=4)
        AG.seg(f"pin_in_{sd}", mid, (0, s * (RADII[2] + T * 0.5), 0), (0, s * (RADII[1] - T * 0.5), 0),
               0.01, material=m["gold_dark"], segments=6)
        sb.sphere(f"hub_in_{sd}", mid, radius=0.019, loc=(0, s * (RADII[2] + T + 0.015), 0),
                  material=gold, segments=6, rings=4)
        # outer hub where the wing springs from
        sb.sphere(f"hub_out_{sd}", outer, radius=0.026, loc=(s * (RADII[0] + T + 0.012), 0, 0),
                  material=gold, segments=6, rings=4)
    # top finial (points up at the crown) and the pendant spike underneath
    AG.spike("finial", outer, (0, 0, RADII[0] + T - 0.005), (0, 0, 1), 0.075, 0.03, 0.03, material=gold)
    AG.spike("pendant", outer, (0, 0, -RADII[0] - T + 0.005), (0, 0, -1), 0.13, 0.032, 0.032, material=gold)

    # --- winged wheel: a small fan of feathers on each outer axle hub, spread in the ring plane
    wings = {}
    for s in (1, -1):
        sd = "L" if s > 0 else "R"
        wj = sb.empty(f"wing_{sd}", outer, loc=(s * (RADII[0] + T + 0.02), 0, 0.0))
        for k, (ang, ln) in enumerate(((22, 0.27), (48, 0.25), (74, 0.21), (100, 0.16))):
            AG.feather(f"wing_{sd}_f{k}", wj, length=ln, width=0.034, thickness=0.006,
                       loc=(0, 0.004 * k, 0), rot=(0, s * ang, 0),
                       material=m["feather"] if k % 2 == 0 else m["feather_tip"], curve=0.16, steps=3)
        wings[sd] = wj

    # --- crown-halo of light above the top finial
    crown = sb.empty("crown", core, loc=(0, 0, CROWN_Z))
    AG.ring("crown_band", crown, 0.15, 0.015, material=gold, seg=20, mseg=4)
    AG.ring("crown_light", crown, 0.127, 0.007, material=m["light"], seg=20, mseg=3)
    for i in range(8):
        a = 2 * math.pi * i / 8
        ca, sa = math.cos(a), math.sin(a)
        AG.spike(f"crown_ray{i}", crown, (ca * 0.15, sa * 0.15, 0.008), (ca * 0.3, sa * 0.3, 1),
                 0.12 if i % 2 == 0 else 0.07, 0.03, 0.012, material=m["halo"], up=(-sa, ca, 0))

    AG.merge_by_joint(root)
    AG.report("ophanim")
    _animate(root, core, aura, great, lid_up, lid_dn, outer, mid, inner, eyes, wings, crown)
    return root


# ----------------------------------------------------------------------------- animation

def _blink(c, e, f0, close=2, open_=4, depth=0.06):
    c.key(e, f0, scale=(1, 1, 1), ease="quad_in")
    c.key(e, f0 + close, scale=(1, 1, depth), ease="quad_out")
    c.key(e, f0 + close + open_, scale=(1, 1, 1))


def _animate(root, core, aura, great, lid_up, lid_dn, outer, mid, inner, eyes, wings, crown):
    js = A.joints(root)
    wl, wr = wings["L"], wings["R"]

    # ------------------------------------------------------------------ idle (8 s loop)
    F = 240
    c = A.Clip("idle", F, joints=js)
    c.add(core, lambda f: (0, 0, 0.035 * A.wave(c, f, cycles=2)), "loc")
    A.noise(c, core, rot=(3, 2, 3), freq=0.25, seed=3)
    c.add(outer, lambda f: (0, 0, 360.0 * f / F))
    c.add(mid, lambda f: (-720.0 * f / F, 0, 0))
    c.add(inner, lambda f: (0, 1080.0 * f / F, 0))
    c.add(aura, lambda f: (0, -360.0 * f / F, 0))
    c.add(aura, lambda f: (0.05 * A.wave(c, f, cycles=4),) * 3, "scale")
    c.add(crown, lambda f: (0, 0, -360.0 * f / F))
    c.add(crown, lambda f: (0, 0, 0.015 * A.wave(c, f, cycles=2, offset=0.15)), "loc")
    for sd, s in (("L", 1), ("R", -1)):
        w = wings[sd]
        c.add(w, lambda f, s=s: (0, s * 9 * A.wave(c, f, cycles=6), 0))
    # blinks scattered over the loop (each eye once or twice), the great eye once
    rng = [17, 131, 52, 199, 88, 163, 30, 214, 109, 70, 182, 9, 146, 95, 226, 60]
    for i, e in enumerate(eyes):
        _blink(c, e, rng[i % len(rng)])
        if i % 3 == 0:
            _blink(c, e, (rng[i % len(rng)] + 113) % (F - 8))
        A.noise(c, e, rot=(8, 0, 6), freq=0.2, seed=10 + i)
    for f0 in (118,):
        c.key(lid_up, f0, rot=(0, 0, 0), ease="quad_in")
        c.key(lid_up, f0 + 3, rot=(44, 0, 0), ease="quad_out")
        c.key(lid_up, f0 + 8, rot=(0, 0, 0))
        c.key(lid_dn, f0, rot=(0, 0, 0), ease="quad_in")
        c.key(lid_dn, f0 + 3, rot=(-44, 0, 0), ease="quad_out")
        c.key(lid_dn, f0 + 8, rot=(0, 0, 0))
    A.noise(c, great, rot=(5, 0, 7), freq=0.3, seed=7)
    c.bake()

    # ------------------------------------------------------------------ windup (spin up -> align)
    F = 30
    c = A.Clip("windup", F, joints=js)
    spin = {outer: (0, 0, 720), mid: (90 + 720, 0, 0), inner: (0, -90 - 720, 0)}
    fast = {outer: (0, 0, 540), mid: (600, 0, 0), inner: (0, -620, 0)}
    for j in rings_of(outer, mid, inner):
        c.key(j, 0, rot=(0, 0, 0), ease="quad_in")
        c.key(j, 15, rot=fast[j], ease="back_out:1.2")
        c.key(j, 22, rot=spin[j])
        c.key(j, F, rot=spin[j])
    c.key(core, 0, loc=(0, 0, 0))
    c.key(core, 16, loc=(0, 0.05, 0.03), rot=(-6, 0, 0))
    c.key(core, F, loc=(0, 0.06, 0.04), rot=(-8, 0, 0))
    A.jitter(c, core, rot=(1.2, 1.2, 1.2), start=20, end=F, fade=3)
    c.key(aura, 0, scale=1.0, rot=(0, 0, 0), ease="cubic_in")
    c.key(aura, 22, scale=1.75, rot=(0, -300, 0), ease="sine_out")
    c.key(aura, F, scale=1.9, rot=(0, -360, 0))
    c.add(aura, lambda f: ((0.08 * A.wave(c, f, cycles=4) * f / F),) * 3, "scale")
    c.key(great, 0, scale=1.0)
    c.key(great, 20, scale=1.22, ease="back_out")
    c.key(great, F, scale=1.25)
    c.key(lid_up, 0, rot=(0, 0, 0))
    c.key(lid_up, 18, rot=(-22, 0, 0), ease="back_out")
    c.key(lid_up, F, rot=(-24, 0, 0))
    c.key(lid_dn, 0, rot=(0, 0, 0))
    c.key(lid_dn, 18, rot=(22, 0, 0), ease="back_out")
    c.key(lid_dn, F, rot=(24, 0, 0))
    for i, e in enumerate(eyes):
        c.key(e, 0, scale=1.0)
        c.key(e, 14 + (i % 4), scale=(1.1, 1.1, 0.25), ease="back_out:2.5")
        c.key(e, 22 + (i % 3), scale=1.45)
        c.key(e, F, scale=1.4)
    for sd, s in (("L", 1), ("R", -1)):
        c.key(wings[sd], 0, rot=(0, 0, 0))
        c.key(wings[sd], 20, rot=(0, -s * 18, 0), ease="back_out")
        c.key(wings[sd], F, rot=(0, -s * 20, 0))
    c.key(crown, 0, rot=(0, 0, 0), loc=(0, 0, 0), ease="quad_in")
    c.key(crown, F, rot=(0, 0, -400), loc=(0, 0, 0.04))
    c.bake()

    # ------------------------------------------------------------------ attack (pulse, recoil, spin out)
    F = 20
    c = A.Clip("attack", F, joints=js)
    start = {outer: (0, 0, 0), mid: (90, 0, 0), inner: (0, -90, 0)}
    out = {outer: (0, 0, 360), mid: (360, 0, 0), inner: (0, -360, 0)}
    for j in rings_of(outer, mid, inner):
        c.key(j, 0, rot=start[j])
        c.key(j, 7, rot=start[j], ease="quad_in")
        c.key(j, F, rot=out[j])
    c.key(outer, 0, scale=1.0, ease="expo_out")
    c.key(outer, 2, scale=1.1, ease="quad_out")
    c.key(outer, 8, scale=1.0)
    c.key(core, 0, loc=(0, 0.06, 0.04), rot=(-8, 0, 0), ease="expo_out")
    c.key(core, 3, loc=(0, 0.17, 0.06), rot=(14, 0, 0), ease="back_out")
    c.key(core, 11, loc=(0, 0.04, 0.02), rot=(-3, 0, 0))
    c.key(core, F, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key(aura, 0, scale=1.9, rot=(0, 0, 0), ease="expo_out")
    c.key(aura, 2, scale=2.7, rot=(0, -40, 0), ease="quad_out")
    c.key(aura, 9, scale=1.2, rot=(0, -80, 0))
    c.key(aura, F, scale=1.0, rot=(0, -100, 0))
    c.key(great, 0, scale=1.25, ease="expo_out")
    c.key(great, 2, scale=1.45)
    c.key(great, 10, scale=1.0)
    c.key(lid_up, 0, rot=(-24, 0, 0))
    c.key(lid_up, 3, rot=(-30, 0, 0))
    c.key(lid_up, 12, rot=(0, 0, 0))
    c.key(lid_dn, 0, rot=(24, 0, 0))
    c.key(lid_dn, 3, rot=(30, 0, 0))
    c.key(lid_dn, 12, rot=(0, 0, 0))
    for i, e in enumerate(eyes):
        c.key(e, 0, scale=1.4, ease="expo_out")
        c.key(e, 2, scale=1.6)
        c.key(e, 12 + (i % 3), scale=1.0)
    for sd, s in (("L", 1), ("R", -1)):
        c.key(wings[sd], 0, rot=(0, -s * 20, 0), ease="expo_out")
        c.key(wings[sd], 3, rot=(0, s * 14, 0))
        c.key(wings[sd], F, rot=(0, 0, 0))
    c.key(crown, 0, rot=(0, 0, 0), loc=(0, 0, 0.04), ease="expo_out")
    c.key(crown, 3, rot=(0, 0, -50), loc=(0, 0, 0.08))
    c.key(crown, F, rot=(0, 0, -90), loc=(0, 0, 0))
    c.events["impact"] = 2
    c.bake()

    # ------------------------------------------------------------------ hit (rings jolt)
    F = 14
    c = A.Clip("hit", F, joints=js)
    A.hit_react(c, {core: {"loc": (0, 0.07, 0.03), "rot": (-12, 6, 9)},
                    outer: {"rot": (14, 0, 26)},
                    mid: {"rot": (-30, 12, 0)},
                    inner: {"rot": (0, 38, -10)},
                    crown: {"rot": (10, -8, 20), "loc": (0, 0.02, 0.03)}},
                rise=2, settle=10, stagger=0.7)
    A.hit_react(c, {wl: {"rot": (0, -22, 0)}, wr: {"rot": (0, 22, 0)}, aura: {"scale": 0.7}}, rise=2,
                settle=9)
    c.key(lid_up, 0, rot=(0, 0, 0), ease="expo_out")
    c.key(lid_up, 2, rot=(44, 0, 0))
    c.key(lid_up, 6, rot=(40, 0, 0), ease="quad_inout")
    c.key(lid_up, 12, rot=(0, 0, 0))
    c.key(lid_dn, 0, rot=(0, 0, 0), ease="expo_out")
    c.key(lid_dn, 2, rot=(-44, 0, 0))
    c.key(lid_dn, 6, rot=(-40, 0, 0), ease="quad_inout")
    c.key(lid_dn, 12, rot=(0, 0, 0))
    for i, e in enumerate(eyes):
        c.key(e, 0, scale=1.0, ease="expo_out")
        c.key(e, 2, scale=(1.05, 1, 0.08))
        c.key(e, 5 + (i % 3), scale=(1, 1, 0.12), ease="back_out")
        c.key(e, 11 + (i % 3), scale=1.0)
    c.bake()

    # ------------------------------------------------------------------ death (stall, fall, settle flat)
    F = 46
    c = A.Clip("death", F, joints=js)
    drop = -(CORE_Z + HOVER - W - 0.004)
    # stall + shudder, light flares then dies
    c.key(core, 0, loc=(0, 0, 0), ease="sine_out")
    c.key(core, 7, loc=(0, 0.04, 0.06), rot=(-10, 0, 6), ease="quad_in")
    c.key(core, 24, loc=(0.02, 0.06, drop), rot=(0, 0, 0), ease="quad_out")
    c.key(core, 28, loc=(0.02, 0.06, drop + 0.035), ease="quad_in")
    c.key(core, 32, loc=(0.02, 0.06, drop), ease="quad_out")
    c.key(core, 34, loc=(0.02, 0.06, drop + 0.008), ease="quad_in")
    c.key(core, 36, loc=(0.02, 0.06, drop))
    A.jitter(c, core, rot=(4, 4, 4), start=0, end=10, fade=2)
    # rings: lurch, then topple flat (outer X -90 with mid/inner aligned = all lie on the ground),
    # with a coin-like wobble as they settle and a little scatter
    flat = {outer: (-90, 0, 70), mid: (90 - 6, 0, 0), inner: (5, -90 + 4, 0)}
    lurch = {outer: (-15, 0, 50), mid: (40, 10, 0), inner: (0, -60, 20)}
    for j in rings_of(outer, mid, inner):
        c.key(j, 0, rot=(0, 0, 0), ease="sine_out")
        c.key(j, 8, rot=lurch[j], ease="quad_in")
        c.key(j, 24, rot=flat[j], ease="quad_out")
    c.key(outer, 24, rot=flat[outer], loc=(0, 0, 0), ease="sine_inout")
    c.key(outer, 28, rot=(-90 + 7, 4, 78), ease="sine_inout")
    c.key(outer, 32, rot=(-90 - 4, -3, 86), ease="sine_inout")
    c.key(outer, 36, rot=(-90 + 1.5, 1.5, 92), ease="sine_inout")
    c.key(outer, 40, rot=(-90, 0, 95))
    c.key(mid, 24, rot=flat[mid], loc=(0, 0, 0), ease="quad_out")
    # (outer frame once flat: local X / Z are horizontal; mid frame ~ world axes)
    c.key(mid, 30, rot=(90 + 3, 0, 0), loc=(0.045, 0, -0.03), ease="sine_inout")
    c.key(mid, 40, rot=(90, 0, 0), loc=(0.05, 0, -0.035))
    c.key(inner, 24, rot=flat[inner], loc=(0, 0, 0), ease="quad_out")
    c.key(inner, 31, rot=(-2, -90 - 2, 0), loc=(-0.035, 0.04, 0), ease="sine_inout")
    c.key(inner, 40, rot=(0, -90, 0), loc=(-0.04, 0.05, 0))
    c.key(aura, 0, scale=1.0, ease="quad_out")
    c.key(aura, 6, scale=2.3, ease="quad_in")
    c.key(aura, 14, scale=0.02)
    c.key(aura, F, scale=0.02)
    c.key(great, 0, scale=1.0, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key(great, 6, scale=1.35, ease="quad_in")
    c.key(great, 22, scale=0.75, loc=(0, 0, 0.035), rot=(-35, 0, 0))
    c.key(great, F, scale=0.75, loc=(0, 0, 0.035), rot=(-35, 0, 0))
    c.key(lid_up, 0, rot=(0, 0, 0))
    c.key(lid_up, 6, rot=(-24, 0, 0), ease="quad_in")
    c.key(lid_up, 12, rot=(46, 0, 0))
    c.key(lid_dn, 0, rot=(0, 0, 0))
    c.key(lid_dn, 6, rot=(24, 0, 0), ease="quad_in")
    c.key(lid_dn, 12, rot=(-46, 0, 0))
    for i, e in enumerate(eyes):
        c.key(e, 0, scale=1.0)
        c.key(e, 5, scale=1.4, ease="quad_in")
        c.key(e, 10 + (i * 5) % 12, scale=(1, 1, 0.05))
    for sd, s in (("L", 1), ("R", -1)):
        c.key(wings[sd], 0, rot=(0, 0, 0))
        c.key(wings[sd], 7, rot=(0, -s * 25, 0), ease="quad_in")
        c.key(wings[sd], 24, rot=(0, s * 55, 0), ease="back_out")
        c.key(wings[sd], 34, rot=(0, s * 62, 0))
    # the crown falls a beat behind and clatters down beside the rings
    c.key(crown, 0, rot=(0, 0, 0), loc=(0, 0, 0))
    c.key(crown, 10, rot=(5, 0, -40), loc=(0, 0, 0.06), ease="quad_in")
    c.key(crown, 27, rot=(16, -10, -90), loc=(0.18, -0.12, -CROWN_Z + 0.02), ease="quad_out")
    c.key(crown, 31, rot=(10, -6, -100), loc=(0.2, -0.13, -CROWN_Z + 0.05), ease="quad_in")
    c.key(crown, 35, rot=(4, -3, -105), loc=(0.21, -0.14, -CROWN_Z + 0.015), ease="quad_out")
    c.key(crown, F, rot=(4, -3, -105), loc=(0.21, -0.14, -CROWN_Z + 0.015))
    c.bake()


def rings_of(*rs):
    return rs
