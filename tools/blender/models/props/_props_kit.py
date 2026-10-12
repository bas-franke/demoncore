"""Shared parts for the world props (underscore = not built by `all`).

Material NAMES are the contract with res://scripts/props.gd (Props.MATERIALS maps them to the static
lit + moss materials and texture-detail surfaces). Colors here are only for the Blender previews.
Every prop script makes variant roots v0..vN (sb.variants); Godot picks one per instance.
Objects whose name contains "_ns" don't cast shadows in Godot (small bits).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"

_SPEC = {
    "Prop_Stone": ((0.43, 0.41, 0.38), 0.9, 0.0),
    "Prop_StoneDark": ((0.25, 0.245, 0.24), 0.92, 0.0),
    "Prop_StoneLight": ((0.5, 0.47, 0.42), 0.85, 0.0),
    "Prop_Marble": ((0.64, 0.62, 0.58), 0.62, 0.0),
    "Prop_Iron": ((0.1, 0.095, 0.09), 0.5, 0.75),
    "Prop_Steel": ((0.36, 0.36, 0.37), 0.42, 0.6),
    "Prop_SteelDark": ((0.14, 0.14, 0.15), 0.55, 0.5),
    "Prop_Bronze": ((0.25, 0.3, 0.27), 0.6, 0.35),
    "Prop_Bark": ((0.085, 0.072, 0.064), 0.95, 0.0),
    "Prop_BarkPale": ((0.22, 0.2, 0.18), 0.95, 0.0),
    "Prop_Wood": ((0.2, 0.16, 0.12), 0.9, 0.0),
    "Prop_Bone": ((0.72, 0.68, 0.58), 0.65, 0.0),
    "Prop_Gold": ((0.83, 0.66, 0.3), 0.4, 0.9),
    "Prop_BannerCloth": ((0.32, 0.035, 0.035), 0.9, 0.0),
    "Prop_Wax": ((0.55, 0.5, 0.41), 0.55, 0.0),
    "Prop_Void": ((0.02, 0.02, 0.02), 1.0, 0.0),
    "Prop_ObsidianAltar": ((0.06, 0.055, 0.06), 0.6, 0.0),
    "Prop_Leaf": ((0.5, 0.33, 0.09), 0.7, 0.0),
    "Prop_LeafDark": ((0.36, 0.22, 0.06), 0.8, 0.0),
    "Prop_LeafFallen": ((0.6, 0.4, 0.12), 0.9, 0.0),
    "Prop_GrassDry": ((0.22, 0.19, 0.1), 0.95, 0.0),
    "Prop_GrassDark": ((0.085, 0.1, 0.05), 0.95, 0.0),
}
_EMIT = {
    "Prop_CandleFlame": ((1.0, 0.6, 0.22), (1.0, 0.6, 0.22), 4.0),
    "Prop_Ember": ((0.05, 0.03, 0.02), (1.0, 0.38, 0.08), 2.5),
    "Prop_HellRune": ((0.1, 0.02, 0.02), (1.0, 0.22, 0.05), 3.0),
    "Prop_HolyRune": ((0.3, 0.25, 0.15), (1.0, 0.85, 0.5), 2.2),
}


def M(name):
    if name in _EMIT:
        c, e, s = _EMIT[name]
        return sb.mat(name, c, 0.5, 0.0, e, s)
    c, r, m = _SPEC[name]
    return sb.mat(name, c, r, m)


def rng_for(seed):
    return random.Random(seed)


# ------------------------------------------------------------------ stone pieces

def drum(name, parent, rng, r=0.4, h=0.9, loc=(0, 0, 0), rot=(0, 0, 0), flutes=8, broken_top=0.0,
         broken_bottom=0.0, chips=2, mat="Prop_Stone", cracks=1):
    """Fluted column drum, base at z=0 (unless rotated). broken_* = fracture tilt depth (m)."""
    rings = max(2, int(h / 0.45))
    bm = sb.bm_column(r, h, segments=flutes * 4 if flutes else 12, rings=rings, flutes=flutes,
                      flute_depth=0.07)
    caps = []
    if broken_top > 0:
        side = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized()
        n = side * (broken_top / (2 * r)) + Vector((0, 0, 1))
        caps += sb.bm_cut(bm, (0, 0, h - broken_top * 0.5), n.normalized())
    if broken_bottom > 0:
        n = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized() * 0.7 + Vector((0, 0, -1.2))
        caps += sb.bm_cut(bm, (0, 0, broken_bottom * 0.5), n.normalized())
    caps = [f for f in caps if f.is_valid]
    if caps:
        sb.bm_roughen(bm, caps, rng, r * 0.14, 0.4)
    if chips:
        sb.bm_chip(bm, rng, chips, r * 0.3, rough=r * 0.05)
    if cracks:
        sb.bm_crack(bm, rng, cracks, depth=0.018, axis=(1, 0, 0.3))
    sb.bm_bevel(bm, 0.015, 40)
    sb.bm_noise(bm, r * 0.035, 2.2, seed=rng.randrange(9999))
    return sb.bm_obj(name, parent, bm, M(mat), loc, rot)


def lathe_obj(name, parent, rng, profile, segs=20, loc=(0, 0, 0), rot=(0, 0, 0), mat="Prop_Stone",
              noise=0.012, chips=1, wobble=None, sharp=35.0):
    bm = sb.bm_lathe(profile, segs, wobble=wobble)
    if chips:
        size = max(p[0] for p in profile)
        sb.bm_chip(bm, rng, chips, size * 0.25)
    sb.bm_noise(bm, noise, 2.5, seed=rng.randrange(9999))
    return sb.bm_obj(name, parent, bm, M(mat), loc, rot, sharp=sharp)


ATTIC_BASE = [(0.6, 0.0), (0.6, 0.06), (0.56, 0.1), (0.58, 0.15), (0.5, 0.2), (0.47, 0.24),
              (0.51, 0.28), (0.49, 0.32), (0.43, 0.34)]
CAPITAL = [(0.39, 0.0), (0.42, 0.05), (0.45, 0.08), (0.53, 0.16), (0.6, 0.24), (0.62, 0.27)]


def plinth(name, parent, rng, w=1.4, h=0.3, loc=(0, 0, 0), mat="Prop_Stone", chips=3):
    return sb.stone_block(name, parent, (w, w, h), M(mat), rng, loc=(loc[0], loc[1], loc[2] + h * 0.5),
                          chips=chips, cracks=1)


def rock(name, parent, rng, size, loc=(0, 0, 0), rot=(0, 0, 0), mat="Prop_Stone", subdiv=1, cuts=4):
    bm = sb.bm_rock(rng, size, cuts=cuts, subdiv=subdiv)
    return sb.bm_obj(name, parent, bm, M(mat), loc, rot, sharp=40)


def rubble(parent, rng, center, radius, count, smin=0.12, smax=0.4, mat="Prop_Stone", tag="rb",
           blocks=0.3):
    """Scatter of broken stones / masonry fragments. Pieces < 0.3 m get `_ns` (no shadow)."""
    out = []
    for i in range(count):
        a = rng.uniform(0, math.tau)
        d = math.sqrt(rng.random()) * radius
        s = rng.uniform(smin, smax)
        p = (center[0] + math.cos(a) * d, center[1] + math.sin(a) * d, center[2] - s * 0.08)
        nm = f"{tag}{i}" + ("_ns" if s < 0.3 else "")
        if rng.random() < blocks:
            sz = (s * rng.uniform(1.0, 1.8), s * rng.uniform(0.7, 1.1), s * rng.uniform(0.45, 0.7))
            out.append(sb.stone_block(nm, parent, sz, M(mat), rng, loc=(p[0], p[1], p[2] + sz[2] * 0.45),
                                      rot=(rng.uniform(-8, 8), rng.uniform(-8, 8), rng.uniform(0, 360)),
                                      chips=2, step=max(0.12, s * 0.5)))
        else:
            out.append(rock(nm, parent, rng, (s * rng.uniform(0.9, 1.4), s, s * rng.uniform(0.5, 0.8)), p,
                            (0, 0, rng.uniform(0, 360)), mat))
    return out


# ------------------------------------------------------------------ bones

def bone(name, parent, rng, a, b, r=0.03, mat="Prop_Bone"):
    a = Vector(a)
    b = Vector(b)
    d = b - a
    pts = [a, a + d * 0.15, a + d * 0.5, a + d * 0.85, b]
    rad = [r * 1.7, r * 1.0, r * 0.8, r * 1.0, r * 1.7]
    bm = sb.bm_limb(pts, rad, sides=5, samples=1, rng=rng, gnarl=0.08)
    sb.bm_noise(bm, r * 0.15, 8.0, seed=rng.randrange(999))
    return sb.bm_obj(name, parent, bm, M(mat), sharp=60)


def skull(name, parent, rng, loc=(0, 0, 0), rot=(0, 0, 0), s=1.0, mat="Prop_Bone"):
    """Human skull ~0.22 m long, facing -Y, resting on z=0."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.5)
    for v in bm.verts:
        v.co.x *= 0.15
        v.co.y *= 0.2
        v.co.z *= 0.16
        if v.co.y < -0.02 and v.co.z < 0.0:  # flatten face / cheekbones
            v.co.y *= 0.85
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0.01, 0.1))
    for sx in (-1, 1):
        sb.bm_dent(bm, (sx * 0.035, -0.095, 0.095), 0.04, 0.03)
    sb.bm_dent(bm, (0, -0.1, 0.06), 0.02, 0.015)
    jaw = sb.bm_box((0.1, 0.09, 0.05), (2, 2, 1))
    sb.bm_bevel(jaw, 0.012)
    sb.bm_xform(jaw, loc=(0, -0.06, 0.03), rot=(12, 0, 0))
    sb.bm_merge(bm, jaw)
    sb.bm_noise(bm, 0.004, 20.0, seed=rng.randrange(999))
    sb.bm_xform(bm, scale=(s, s, s))
    return sb.bm_obj(name, parent, bm, M(mat), loc, rot, sharp=55)


def bone_scatter(parent, rng, center, radius, n, tag="bn", r=0.028):
    for i in range(n):
        a = rng.uniform(0, math.tau)
        d = math.sqrt(rng.random()) * radius
        c = Vector((center[0] + math.cos(a) * d, center[1] + math.sin(a) * d, r * 1.4 + (i % 3) * r * 1.2))
        l = rng.uniform(0.28, 0.5)
        ang = rng.uniform(0, math.tau)
        off = Vector((math.cos(ang), math.sin(ang), rng.uniform(-0.15, 0.15))) * l * 0.5
        bone(f"{tag}{i}_ns", parent, rng, c - off, c + off, r)


# ------------------------------------------------------------------ candles

def candles(parent, rng, n=6, loc=(0, 0, 0), radius=0.3, tag="cd", puddle=True):
    """Cluster of melted candles with emissive flame tips (Prop_CandleFlame)."""
    x0, y0, z0 = loc
    if puddle:
        lathe_obj(f"{tag}_wax_ns", parent, rng, [(radius * 0.85, 0.0), (radius * 0.8, 0.012),
                  (radius * 0.4, 0.02), (0.0, 0.022)], 12, (x0, y0, z0), mat="Prop_Wax", chips=0,
                  noise=0.006, wobble=lambda a, t: 1.0 + 0.15 * math.sin(a * 3 + 1.3) * math.sin(a * 5))
    for i in range(n):
        a = rng.uniform(0, math.tau)
        d = math.sqrt(rng.random()) * radius * 0.85
        r = rng.uniform(0.025, 0.055)
        h = rng.uniform(0.06, 0.42)
        px, py = x0 + math.cos(a) * d, y0 + math.sin(a) * d
        prof = [(r * 1.45, 0.0), (r * 1.15, 0.02), (r, 0.05), (r, h * 0.7), (r * 1.02, h - 0.012),
                (r * 0.75, h), (0.0, h - 0.008)]
        drip = rng.uniform(0.0, math.tau)
        lathe_obj(f"{tag}{i}_ns", parent, rng, prof, 7, (px, py, z0), mat="Prop_Wax", chips=0, noise=0.002,
                  wobble=lambda aa, t, dr=drip: 1.0 + 0.18 * max(0.0, math.cos(aa - dr)) * (1.0 - t), sharp=0)
        if rng.random() < 0.85:
            fl = sb.bm_lathe([(0.0, 0.0), (0.014, 0.018), (0.012, 0.045), (0.0, 0.085)], 5)
            sb.bm_obj(f"{tag}{i}f_ns", parent, fl, M("Prop_CandleFlame"), (px, py, z0 + h - 0.004), sharp=0)


# ------------------------------------------------------------------ masonry

def wall(parent, rng, x0, x1, top, th=0.6, course=0.5, y=0.0, mat="Prop_Stone", tag="w",
         opening=None, axis="x", step=0.45, jitter=0.03, blen=(0.55, 1.05)):
    """Coursed ashlar wall from x0 to x1 (along X, or along Y if axis == "y"), base z=0.
    `top(x) -> height` gives the ruined profile; `opening(z) -> (x_left, x_right) | None` leaves a hole."""
    z = 0.0
    row = 0
    n = 0
    while True:
        x = x0 - (rng.uniform(0.2, 0.5) if row % 2 else 0.0)
        made = False
        holes = opening(z + course * 0.5) if opening is not None else None
        if holes is not None and not isinstance(holes, list):
            holes = [holes]
        holes = [hh for hh in (holes or []) if hh is not None]
        while x < x1 - 0.05:
            ln = rng.uniform(*blen)
            a, b = max(x, x0), min(x + ln, x1)
            x += ln
            hole = next((hh for hh in holes if b > hh[0] and a < hh[1]), None)
            if hole is not None:
                if a < hole[0] - 0.15:
                    b = hole[0]
                    x = hole[1]
                else:
                    a = hole[1]
                    x = max(x, hole[1])
                    if b <= a:
                        continue
            if b - a < 0.2:
                continue
            cx = (a + b) * 0.5
            h_here = min(top(a), top(cx), top(b))
            if z + course * 0.35 > h_here:
                continue
            made = True
            hh = course - 0.02
            broken = z + course > h_here
            sz = (b - a - 0.02, th + rng.uniform(-0.04, 0.04), hh)
            loc = (cx, y + rng.uniform(-jitter, jitter), z + hh * 0.5)
            rot = (rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1.5, 1.5))
            if axis == "y":
                loc = (y + rng.uniform(-jitter, jitter), cx, z + hh * 0.5)
                sz = (sz[1], sz[0], sz[2])
            sb.stone_block(f"{tag}{n}", parent, sz, M(mat), rng, loc=loc, rot=rot,
                           chips=3 if broken else rng.choice((0, 1, 1, 2)), step=step,
                           chip_depth=0.25 if broken else 0.12, noise=0.012)
            n += 1
        z += course
        row += 1
        if not made and z > 0.5:
            break
        if z > 20:
            break
    return n


def voussoir_arc(parent, rng, center, r_in, r_out, a0, a1, count, depth=0.6, y=0.0, mat="Prop_Stone",
                 tag="vs", keep=None):
    """Ring of wedge stones between angles a0..a1 (deg) in the XZ plane. `keep(i) -> bool`."""
    da = (a1 - a0) / count
    for i in range(count):
        if keep is not None and not keep(i):
            continue
        bm = sb.bm_box((1, depth, 1), (2, 2, 2))
        sb.bm_arc(bm, center, r_in, r_out, a0 + da * i + 0.4 * (1 if da > 0 else -1), a0 + da * (i + 1))
        bmesh.ops.translate(bm, verts=bm.verts, vec=(0, y, 0))
        sb.bm_chip(bm, rng, rng.choice((0, 1, 1)), 0.1)
        sb.bm_bevel(bm, 0.025)
        sb.bm_noise(bm, 0.012, 2.0, seed=rng.randrange(9999))
        sb.bm_obj(f"{tag}{i}", parent, bm, M(mat))


def pointed_arch(parent, rng, span, spring, th=0.5, depth=0.6, count=5, y=0.0, mat="Prop_Stone", tag="ar",
                 keep_left=None, keep_right=None, key=True):
    """Equilateral gothic arch springing at z=`spring` from x = +-span/2."""
    s = span
    voussoir_arc(parent, rng, (s * 0.5, 0, spring), s, s + th, 180, 120, count, depth, y, mat, tag + "L",
                 keep_left)
    voussoir_arc(parent, rng, (-s * 0.5, 0, spring), s, s + th, 0, 60, count, depth, y, mat, tag + "R",
                 keep_right)
    if key:
        apex = spring + s * math.sin(math.radians(60))
        sb.stone_block(tag + "key", parent, (0.32, depth + 0.04, th * 1.15), M(mat), rng,
                       loc=(0, y, apex + th * 0.5), chips=1, step=0.2)


def pointed_hole(z, span, spring, base=0.0, cx=0.0):
    """Horizontal extent (xl, xr) of a pointed-arch opening at height z, or None."""
    if z < base:
        return None
    if z <= spring:
        hw = span * 0.5
    else:
        dz = z - spring
        if dz >= span * 0.866:
            return None
        hw = math.sqrt(span * span - dz * dz) - span * 0.5
        if hw <= 0.05:
            return None
    return (cx - hw, cx + hw)


# ------------------------------------------------------------------ trees

def _rotate_towards(d, rng, spread, up_bias):
    import mathutils
    axis = d.orthogonal().normalized()
    q = mathutils.Quaternion(d, rng.uniform(0, math.tau))
    axis.rotate(q)
    nd = d.copy()
    nd.rotate(mathutils.Quaternion(axis, math.radians(spread)))
    nd.z += up_bias
    return nd.normalized()


def branch(parent, rng, start, d, length, r, depth, ends, tag, mat="Prop_Bark", segs=4, droop=0.0,
           kids=(2, 3), spread=(25, 55), sides=None):
    """Recursive gnarled branch. Appends tip positions to `ends`."""
    pts = [Vector(start)]
    p = Vector(start)
    cur = Vector(d)
    for i in range(segs):
        cur = _rotate_towards(cur, rng, rng.uniform(5, 22), -droop * 0.1)
        p = p + cur * (length / segs)
        pts.append(p.copy())
    radii = [r * (1.0 - 0.55 * i / segs) for i in range(segs + 1)]
    sd = sides or (7 if r > 0.12 else 5 if r > 0.04 else 4)
    bm = sb.bm_limb(pts, radii, sd, 2 if r > 0.06 else 1, rng, 0.1 if r > 0.05 else 0.0)
    sb.bm_obj(f"{tag}" + ("_ns" if r < 0.05 else ""), parent, bm, M(mat), sharp=60)
    if depth <= 0 or r < 0.02:
        ends.append(pts[-1])
        return
    n = rng.randint(*kids)
    for k in range(n):
        idx = rng.randint(max(1, segs // 2), segs)
        nd = _rotate_towards((pts[idx] - pts[idx - 1]).normalized(), rng, rng.uniform(*spread), 0.15)
        branch(parent, rng, pts[idx], nd, length * rng.uniform(0.5, 0.72), radii[idx] * rng.uniform(0.55, 0.7),
               depth - 1, ends, f"{tag}_{k}", mat, max(2, segs - 1), droop, kids, spread)


def tree(parent, rng, height=5.0, r=0.32, depth=3, mat="Prop_Bark", tag="t", lean=0.12, kids=(2, 3)):
    """Twisted dead tree: trunk, 2-4 main limbs (recursive), flared roots. Returns branch tips."""
    ends = []
    pts = [Vector((0, 0, -0.2))]
    p = Vector((0, 0, -0.2))
    d = Vector((rng.uniform(-lean, lean), rng.uniform(-lean, lean), 1)).normalized()
    n = 5
    for i in range(n):
        d = _rotate_towards(d, rng, rng.uniform(6, 18), 0.08)
        p = p + d * (height * 0.55 / n)
        pts.append(p.copy())
    radii = [r * 1.25] + [r * (1.0 - 0.5 * i / n) for i in range(1, n + 1)]
    bm = sb.bm_limb(pts, radii, 9, 2, rng, 0.12)
    sb.bm_noise(bm, r * 0.12, 3.0, seed=rng.randrange(999))
    sb.bm_obj(f"{tag}trunk", parent, bm, M(mat), sharp=70)
    top_r = radii[-1]
    for k in range(rng.randint(2, 3)):
        at = rng.randint(3, n)
        nd = _rotate_towards(d, rng, rng.uniform(20, 50), 0.1)
        branch(parent, rng, pts[at], nd, height * rng.uniform(0.32, 0.45), radii[at] * 0.72, depth - 1, ends,
               f"{tag}b{k}", mat, 4, 0.0, kids)
    branch(parent, rng, pts[-1], d, height * 0.35, top_r * 0.9, depth - 1, ends, f"{tag}top", mat, 3, 0.0, kids)
    for k in range(rng.randint(4, 5)):
        a = k / 5 * math.tau + rng.uniform(-0.4, 0.4)
        rr = rng.uniform(0.6, 1.1)
        rp = [Vector((math.cos(a) * 0.1, math.sin(a) * 0.1, 0.45)), Vector((math.cos(a) * 0.45, math.sin(a) * 0.45, 0.18)),
              Vector((math.cos(a) * rr, math.sin(a) * rr, -0.02)), Vector((math.cos(a) * (rr + 0.4), math.sin(a) * (rr + 0.4), -0.12))]
        bm = sb.bm_limb(rp, [r * 0.75, r * 0.55, r * 0.3, r * 0.14], 6, 2, rng, 0.1)
        sb.bm_obj(f"{tag}root{k}", parent, bm, M(mat), sharp=70)
    return ends


def socket(parent, name, loc=(0, 0, 0)):
    """Attachment point read by props.gd (fires, lights, candles, sigils): an empty named socket_<name>."""
    return sb.empty("socket_" + name, parent, loc=loc)
