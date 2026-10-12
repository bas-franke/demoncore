"""Choir Wisp: a single note of the First Hymn given wings. A small sun of white light with one
slit eye between gold lids, crowned by a crisp rayed halo, borne on three pairs of tiny layered
seraph wings, trailing two ribbons of light.

SWARM FODDER (hundreds on screen): <= 1.5k tris, one mesh per joint, one material per wing.
Joints: bob (core) / halo (spin) / 6 wings (wing_{up,mid,low}_{L,R}) / ribbon0..1 (chain).
Anims: fly (loop, fast flutter), windup (draw back), attack (dart lunge), hit (flicker), death (burst).
"""
import importlib.util
import math
import os

import bmesh
from mathutils import Vector, Matrix

import sb
import sbanim as SA

_spec = importlib.util.spec_from_file_location("_angel", os.path.join(os.path.dirname(__file__), "_angel.py"))
A = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(A)

CATEGORY = "enemies"
CORE_Z = 0.72
CORE_R = 0.135

# wing pairs: name, attach (x, y, z) on the +X side, elevation deg, back-sweep deg, span, feathers
WINGS = (
    ("up", (0.08, 0.045, 0.08), 34.0, 6.0, 0.36, 4),
    ("mid", (0.105, 0.055, 0.0), 2.0, 18.0, 0.3, 3),
    ("low", (0.08, 0.05, -0.08), -30.0, 34.0, 0.22, 3),
)


# ----------------------------------------------------------------------------- geometry helpers

def _basis(d, n):
    """Rotation (deg) whose local Z = d (feather tip) and local Y = n (flat-face normal)."""
    z = Vector(d).normalized()
    y = Vector(n)
    y = (y - z * y.dot(z)).normalized()
    x = y.cross(z)
    m = Matrix(((x[0], y[0], z[0]), (x[1], y[1], z[1]), (x[2], y[2], z[2])))
    return tuple(math.degrees(a) for a in m.to_euler())


def wing(name, parent, s, loc, elev, sweep, span, n, m):
    """Tiny seraph wing on side s: a fan of `n` broad feathers lying in a plane tilted `elev`
    degrees up, swept `sweep` degrees back. The joint has ZERO rest rotation (flap = rot Y)."""
    j = sb.empty(name, parent, loc=(s * loc[0], loc[1], loc[2]))
    e = math.radians(elev)
    out = Vector((s * math.cos(e), 0.0, math.sin(e)))   # outward in the wing plane
    back = Vector((0.0, 1.0, 0.0))
    normal = Vector((-s * math.sin(e), 0.0, math.cos(e)))  # faces up (seen from the high camera)
    for i in range(n):
        t = i / max(n - 1, 1)
        a = math.radians(sweep - 10.0 + 48.0 * t)          # leading feather points out, last back
        d = out * math.cos(a) + back * math.sin(a)
        ln = span * (1.0 - 0.38 * t)
        p = out * (0.012 * i) + normal * (0.004 * (n - i))  # layered, leading feather on top
        vane(f"{name}_f{i}", j, ln, span * (0.13 - 0.02 * t), tuple(p), _basis(d, normal), m["feather"],
             curve=-0.1)
    return j


def vane(name, parent, length, width, loc, rot, material, curve=0.08, thick=0.004):
    """Flat feather with a rounded, slightly asymmetric tip (tip at +Z, flat face +-Y, curls to
    +Y). 4 rows -> 28 tris."""
    prof = ((0.0, 0.28, 0.28), (0.35, 0.95, 0.8), (0.75, 1.0, 0.7), (1.0, 0.35, 0.12))
    bm = bmesh.new()
    rows = []
    for t, wl, wr in prof:
        z = t * length
        y = curve * t * t * length
        a, b = -width * wl, width * wr
        rows.append([bm.verts.new((a, y - thick, z)), bm.verts.new((b, y - thick, z)),
                     bm.verts.new((b, y + thick, z)), bm.verts.new((a, y + thick, z))])
    for r0, r1 in zip(rows[:-1], rows[1:]):
        for k in range(4):
            bm.faces.new((r0[k], r0[(k + 1) % 4], r1[(k + 1) % 4], r1[k]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = sb._new_mesh_obj(name, bm)
    return sb._finish(obj, parent, material, loc, rot, (1, 1, 1), 0.0, 0, False, name)


EYE_TILT = 26.0  # the eye looks forward and up, toward the high camera


def _tilt(p):
    a = math.radians(EYE_TILT)
    x, y, z = p
    return (x, y * math.cos(a) + z * math.sin(a), -y * math.sin(a) + z * math.cos(a))


def almond_lid(name, parent, s, m):
    """One gold eyelid: a thin arc hugging the front of the core (s = +1 upper, -1 lower)."""
    pts, rad = [], []
    for k in range(7):
        u = -1.0 + 2.0 * k / 6
        x = 0.07 * u
        z = s * 0.038 * (1.0 - u * u)
        y = -math.sqrt(max(CORE_R ** 2 - x * x - z * z, 0.0)) - 0.004
        pts.append(_tilt((x, y, z)))
        rad.append(0.007 * (0.35 + 0.65 * (1.0 - u * u)))
    return sb.ptube(name, parent, pts, rad, sides=4, material=m["gold"], smooth=True, caps=False)


def halo(name, parent, loc, radius, m, rays=12):
    """Thin glowing ring with fine alternating rays (cheap: 3-sided ring). Returns spin joint."""
    mount = sb.empty(name + "_mount", parent, loc=loc, rot=(-14, 0, 0))  # tipped back: a crown
    spin = sb.empty(name, mount)
    minor = radius * 0.085
    A.ring(name + "_ring", spin, radius, minor, material=m["halo"], seg=28, mseg=3)
    for i in range(rays):
        a = 2 * math.pi * i / rays
        ln = radius * (0.62 if i % 2 == 0 else 0.3)
        ca, sa = math.cos(a), math.sin(a)
        r0 = radius + minor
        A.spike(f"{name}_ray{i}", spin, (ca * r0, sa * r0, 0), (ca, sa, 0), ln, minor * 1.7, minor * 0.7,
                material=m["halo"])
    return spin


def ribbon_strip(name, parent, length, w0, w1, side, m):
    """Flat glowing ribbon segment trailing back (+Y), faces up, drifting to `side`."""
    bm = bmesh.new()
    rows = []
    steps = 2
    for i in range(steps + 1):
        t = i / steps
        w = w0 + (w1 - w0) * t
        y = length * t
        x = side * 0.02 * t
        z = -0.3 * length * t
        rows.append([bm.verts.new((x - w, y, z - 0.003)), bm.verts.new((x + w, y, z - 0.003)),
                     bm.verts.new((x + w, y, z + 0.003)), bm.verts.new((x - w, y, z + 0.003))])
    for a, b in zip(rows[:-1], rows[1:]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = sb._new_mesh_obj(name, bm)
    return sb._finish(obj, parent, m["halo"], (0, 0, 0), (0, 0, 0), (1, 1, 1), 0.0, 0, False, name)


# ----------------------------------------------------------------------------- build

def build():
    m = A.mats()
    m["feather"] = sb.mat("Wisp_WingFeather", (0.95, 0.93, 0.87), roughness=0.7)
    m["halo"] = sb.mat("Wisp_HaloLight", (1.0, 0.88, 0.58), roughness=0.4,
                       emission=(1.0, 0.82, 0.45), strength=6.0)
    m["light"] = sb.mat("Wisp_CoreLight", (1.0, 0.97, 0.9), roughness=0.4,
                        emission=(1.0, 0.95, 0.84), strength=8.0)
    root = sb.root("ChoirWisp")
    bob = sb.empty("bob", root, loc=(0, 0, CORE_Z))

    # core: a small sun with one slit eye between gold lids
    sb.sphere("core", bob, radius=CORE_R, material=m["light"], segments=12, rings=8)
    A.ellipsoid("pupil", bob, (0.022, 0.02, 0.058), loc=_tilt((0, -CORE_R + 0.004, 0)),
                rot=(-EYE_TILT, 0, 0), material=m["pupil"],
                seg=6, rings=4)
    almond_lid("lid_up", bob, 1, m)
    almond_lid("lid_dn", bob, -1, m)
    # gold collar the wings grow from (a thin band around the back of the core)
    A.ring("collar", bob, CORE_R * 0.98, 0.008, loc=(0, 0.035, 0), rot=(90, 0, 0), material=m["gold"],
           seg=16, mseg=3)

    hal = halo("halo", bob, (0, 0.05, 0.25), 0.135, m, rays=12)

    wings = {}
    for key, loc, elev, sweep, span, n in WINGS:
        for s, side in ((1, "L"), (-1, "R")):
            wings[(key, side)] = wing(f"wing_{key}_{side}", bob, s, loc, elev, sweep, span, n, m)

    rib = []
    prev = bob
    for i, (ln, w0, w1) in enumerate(((0.16, 0.017, 0.011), (0.16, 0.011, 0.002))):
        j = sb.empty(f"ribbon{i}", prev, loc=(0, CORE_R * 0.6, -0.08) if i == 0 else (0, ln, -0.3 * ln))
        ribbon_strip(f"ribbon{i}_a", j, ln, w0, w1, 1, m)
        ribbon_strip(f"ribbon{i}_b", j, ln, w0 * 0.8, w1 * 0.8, -1, m)
        rib.append(j)
        prev = j

    def K(c, j, f, rot=(0, 0, 0), loc=(0, 0, 0), scale=1.0, ease="smooth"):
        """Keys ALL channels (a channel keyed only once would hold that value for the whole clip)."""
        c.key(j, f, rot=rot, loc=loc, scale=scale, ease=ease)

    def W(c, f, jl, rot=(0, 0, 0), loc=(0, 0, 0), scale=1.0, ease="smooth"):
        c.pose(f, {jl: {"rot": rot, "loc": loc, "scale": scale}}, mirror=True, ease=ease)

    J = SA.joints(root)
    up_L, mid_L, low_L = wings[("up", "L")], wings[("mid", "L")], wings[("low", "L")]
    pairs = ((up_L, 34.0, 0.0), (mid_L, 30.0, 0.12), (low_L, 24.0, 0.24))

    def flutter(c, cycles, amp_k=1.0, bias=0.0):
        stroke = SA.cyc(c, [(0.0, -1.0, "sine_inout"), (0.4, 1.0, "sine_inout"), (1.0, -1.0)])
        for jl, amp, off in pairs:
            jr = SA.other(jl)

            def fn(f, amp=amp, off=off):
                st = stroke(SA.phase(c, f, cycles, -off))
                return (0.0, amp * amp_k * st + bias, 8.0 * (1 - st) * 0.5)   # Y = flap, Z = sweep on the upstroke
            c.add(jl, fn, "rot")
            c.add(jr, (lambda f, fn=fn: SA.mirror_value("rot", fn(f))), "rot")

    # ---- fly: 24 f, 4 fast beats, upper/mid/lower pairs ripple; halo turns 60 deg (6-fold)
    c = SA.Clip("fly", 24, joints=J)
    flutter(c, 4)
    c.add(bob, lambda f: (0, 0, 0.012 * SA.wave(c, f, 4, 0.1) + 0.025 * SA.wave(c, f, 1)), "loc")
    c.add(bob, lambda f: (3.0 * SA.wave(c, f, 4, 0.3), 4.0 * SA.wave(c, f, 1, 0.25), 0), "rot")
    c.add(hal, lambda f: (4.0 * SA.wave(c, f, 1), 3.0 * SA.wave(c, f, 1, 0.25), 60.0 * f / c.frames), "rot")
    c.add(rib[0], lambda f: (10.0 * SA.wave(c, f, 2), 0, 14.0 * SA.wave(c, f, 1)), "rot")
    SA.overlap(c, rib, delay=3.5, decay=1.2)
    c.bake()

    # ---- windup: draws back and up, wings raised and quivering, core swells, halo spins up
    c = SA.Clip("windup", 12, joints=J)
    K(c, bob, 0)
    K(c, bob, 9, rot=(-22, 0, 0), loc=(0, 0.1, 0.05), scale=1.12, ease="sine_out")
    K(c, bob, 12, rot=(-25, 0, 0), loc=(0, 0.11, 0.055), scale=1.16)
    for jl, amp, off in pairs:
        W(c, 0, jl, rot=(0, 0, 0))
        W(c, 8, jl, rot=(0, -amp * 1.3, 18), ease="back_out")
        W(c, 12, jl, rot=(0, -amp * 1.4, 22))
    for jl in (up_L, mid_L, low_L):
        SA.jitter(c, jl, rot=(0, 7, 3), freq=14.0, start=6, end=12, fade=2)
        SA.jitter(c, SA.other(jl), rot=(0, 7, 3), freq=14.0, start=6, end=12, fade=2)
    K(c, hal, 0)
    K(c, hal, 12, rot=(0, 0, 150), scale=1.2, ease="quad_in")
    K(c, rib[0], 0)
    K(c, rib[0], 10, rot=(-10, 0, 0))
    SA.overlap(c, rib, delay=2.0, decay=0.9)
    c.bake()

    # ---- attack: dart lunge (impact ~f4), wings slam back, ribbons stream, recover
    c = SA.Clip("attack", 16, joints=J)
    K(c, bob, 0, rot=(-25, 0, 0), loc=(0, 0.11, 0.055), scale=1.16, ease="quad_in")
    K(c, bob, 3, rot=(28, 0, 0), loc=(0, -0.34, -0.07), scale=(0.85, 1.25, 0.85), ease="expo_out")
    K(c, bob, 7, rot=(18, 0, 0), loc=(0, -0.38, -0.08), scale=1.05, ease="sine_inout")
    K(c, bob, 16)
    for jl, amp, off in pairs:
        W(c, 0, jl, rot=(0, -amp * 1.4, 22), ease="quad_in")
        W(c, 3, jl, rot=(0, amp * 1.1, 70), ease="sine_out")
        W(c, 8, jl, rot=(0, amp * 0.6, 40))
        W(c, 16, jl, rot=(0, 0, 0))
    K(c, hal, 0, rot=(0, 0, 0), scale=1.2, ease="expo_out")
    K(c, hal, 4, rot=(-30, 0, 120), loc=(0, 0.06, -0.02), scale=1.35, ease="sine_out")
    K(c, hal, 16, rot=(0, 0, 240))
    K(c, rib[0], 0, rot=(-10, 0, 0))
    K(c, rib[0], 3, rot=(18, 0, 0), ease="sine_out")
    K(c, rib[0], 16)
    SA.overlap(c, rib, delay=2.0, decay=1.0, motion_only=False)
    c.events["impact"] = 4
    c.bake()

    # ---- hit: knocked back, light flickers (snap scale pulses), wings flare
    c = SA.Clip("hit", 10, joints=J)
    K(c, bob, 0)
    K(c, bob, 1, rot=(-22, 0, 9), loc=(0, 0.08, 0.03), scale=1.3, ease="constant")
    K(c, bob, 2, rot=(-20, 0, 8), loc=(0, 0.08, 0.03), scale=0.78, ease="constant")
    K(c, bob, 3, rot=(-16, 0, 6), loc=(0, 0.07, 0.025), scale=1.18, ease="constant")
    K(c, bob, 4, rot=(-12, 0, 4), loc=(0, 0.05, 0.02), scale=0.9, ease="sine_out")
    K(c, bob, 10)
    K(c, hal, 0)
    K(c, hal, 1, rot=(18, 0, 30), scale=0.75, ease="constant")
    K(c, hal, 2, rot=(18, 0, 30), scale=1.3, ease="constant")
    K(c, hal, 3, rot=(12, 0, 40), scale=0.9, ease="sine_out")
    K(c, hal, 10, rot=(0, 0, 60))
    for jl, amp, off in pairs:
        W(c, 0, jl, rot=(0, 0, 0))
        W(c, 2, jl, rot=(0, -amp * 1.5, -10), ease="sine_out")
        W(c, 10, jl, rot=(0, 0, 0))
    K(c, rib[0], 0)
    K(c, rib[0], 2, rot=(-8, 0, 25), ease="sine_out")
    K(c, rib[0], 10)
    SA.overlap(c, rib, delay=1.5, decay=0.9)
    c.bake()

    # ---- death: brief contraction, then the light bursts: wings fling out and vanish, halo widens away
    c = SA.Clip("death", 12, joints=J)
    K(c, bob, 0, ease="expo_out")
    K(c, bob, 2, rot=(-8, 0, 0), loc=(0, 0, 0.03), scale=0.72, ease="expo_out")
    K(c, bob, 4, loc=(0, 0, 0.06), scale=1.7, ease="quad_in")
    K(c, bob, 10, loc=(0, 0, 0.1), scale=0.01)
    for jl, amp, off in pairs:
        W(c, 0, jl, ease="expo_out")
        W(c, 2, jl, rot=(0, -amp * 1.6, 25), ease="expo_out")
        W(c, 4, jl, rot=(0, -amp * 0.3, -15), loc=(0.08, 0, 0.02), scale=1.15, ease="sine_in")
        W(c, 8, jl, rot=(0, -amp * 0.2, -25), loc=(0.2, 0, 0.05), scale=0.02)
    K(c, hal, 0, ease="expo_out")
    K(c, hal, 2, scale=0.8, ease="expo_out")
    K(c, hal, 5, rot=(0, 0, 90), loc=(0, 0, 0.04), scale=1.3, ease="sine_out")
    K(c, hal, 9, rot=(0, 0, 160), loc=(0, 0, 0.12), scale=(3.0, 3.0, 0.4))
    K(c, rib[0], 0)
    K(c, rib[0], 4, rot=(-12, 0, 0), scale=1.2, ease="sine_out")
    K(c, rib[0], 9, rot=(-20, 0, 0), scale=0.02)
    SA.overlap(c, rib, delay=1.5, decay=0.9)
    c.bake()

    A.finish(root, "choir_wisp")
    return root







