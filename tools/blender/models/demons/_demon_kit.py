"""Shared kit for the five playable demons (underscore = not built by `all`).

Adds organic/armor/cloth primitives on top of sb.py, a humanoid joint rig, a pose-function
animation baker, and the standard demon animation set (idle, walk, attack, hit, death, cheer).

Rig joint names (Godot relies on "look" and "head"):
  root > body > hips > thigh_L/R > shin_L/R > foot_L/R
                     > spine > chest > neck > look (never keyed: Godot turns it for look_yaw) > head
                                     > arm_L/R > fore_L/R > hand_L/R
  Side L = +X (the character's left; it faces -Y), R = -X.
"""
import math
import random
import bpy
import bmesh
from mathutils import Vector
import sb

SIDES = (1, -1)


def sname(s):
    return "L" if s > 0 else "R"


def lin(c):
    """sRGB (0..1) tuple -> linear (what Blender's base colour expects)."""
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def mat(name, srgb, roughness=0.7, metallic=0.0, emission=None, strength=0.0):
    return sb.mat(name, lin(srgb), roughness, metallic,
                  lin(emission) if emission is not None else None, strength)


def smooth01(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3.0 - 2.0 * x)


def env(t, a, b, c=None, d=None):
    """Envelope: rises a->b, (optionally) falls c->d."""
    up = smooth01((t - a) / max(b - a, 1e-6))
    if c is None:
        return up
    return up * (1.0 - smooth01((t - c) / max(d - c, 1e-6)))


# ----------------------------------------------------------------------------- mesh helpers

def _obj(name, bm, parent, material, loc=(0, 0, 0), rot=(0, 0, 0), smooth=True, sharp=None):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = sb._new_mesh_obj(name, bm)
    sb._finish(obj, parent, material, loc, rot, (1, 1, 1), 0.0, 0, smooth, name)
    if sharp is not None and hasattr(obj.data, "set_sharp_from_angle"):
        obj.data.set_sharp_from_angle(angle=math.radians(sharp))
    return obj


def catmull(points, n=4):
    """Smooth path through control points (n samples per segment)."""
    pts = [Vector(p) for p in points]
    if len(pts) < 3:
        return pts
    out = []
    ext = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return out


def loft(name, parent, centers, radii, material=None, segs=12, loc=(0, 0, 0), rot=(0, 0, 0),
         caps=(True, True), ref=(1, 0, 0), profile=None, subdiv=0, sharp=None, cap_round=0.5):
    """Skinned tube through `centers` with per-ring radius (r or (rx, ry)). Organic limbs, torsos,
    horns, tails. `profile(u, v)` (u around 0..1, v along 0..1) multiplies the radius (muscles, ridges)."""
    bm = bmesh.new()
    cs = [Vector(c) for c in centers]
    n = len(cs)
    refv = Vector(ref)
    rings = []
    frames = []
    for i, c in enumerate(cs):
        if i == 0:
            t = cs[1] - c
        elif i == n - 1:
            t = c - cs[i - 1]
        else:
            t = cs[i + 1] - cs[i - 1]
        t.normalize()
        u = refv - t * refv.dot(t)
        if u.length < 1e-4:
            u = Vector((0, 1, 0)) - t * t.y
        u.normalize()
        v = t.cross(u)
        r = radii[i]
        rx, ry = (r, r) if isinstance(r, (int, float)) else r
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            pf = profile(k / segs, i / max(n - 1, 1)) if profile else 1.0
            ring.append(bm.verts.new(c + u * (math.cos(a) * rx * pf) + v * (math.sin(a) * ry * pf)))
        rings.append(ring)
        frames.append((t, min(rx, ry)))
    for a, b in zip(rings[:-1], rings[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    if caps[0]:
        t, r = frames[0]
        pole = bm.verts.new(cs[0] - t * r * cap_round)
        for k in range(segs):
            bm.faces.new((rings[0][(k + 1) % segs], rings[0][k], pole))
    if caps[1]:
        t, r = frames[-1]
        pole = bm.verts.new(cs[-1] + t * r * cap_round)
        for k in range(segs):
            bm.faces.new((rings[-1][k], rings[-1][(k + 1) % segs], pole))
    o = _obj(name, bm, parent, material, loc, rot, True, sharp)
    if subdiv:
        s = o.modifiers.new("Subsurf", "SUBSURF")
        s.levels = subdiv
        s.render_levels = subdiv
    return o


def horn(name, parent, ctrl, r0, r1, material, segs=8, n=4, ridges=0.0, loc=(0, 0, 0), ref=(0, 1, 0)):
    """Tapered horn along smooth control points; `ridges` adds ram-horn growth rings."""
    path = catmull(ctrl, n)
    m = len(path)
    radii = []
    for i in range(m):
        v = i / (m - 1)
        r = r0 + (r1 - r0) * (v ** 0.9)
        if ridges and i % 2 == 1 and v < 0.9:
            r *= 1.0 + ridges
        radii.append(max(r, 0.002))
    return loft(name, parent, path, radii, material, segs, loc, ref=ref, caps=(True, True), cap_round=1.2)


def shell(name, parent, radii, lat=(0, 90), lon=(-180, 180), segs=(16, 5), thick=0.02, material=None,
          loc=(0, 0, 0), rot=(0, 0, 0), flare=0.0, sharp=40):
    """Thick ellipsoid patch (pauldron lames, helmets, breastplates, greaves).
    lat -90..90 (bottom..top), lon around Z with 0 = front (-Y), +90 = +X. `flare` widens the lower edge."""
    rx, ry, rz = radii
    nu, nv = segs
    full = abs((lon[1] - lon[0]) - 360) < 1e-3
    bm = bmesh.new()
    cols = nu if full else nu + 1
    grid = []
    for j in range(nv + 1):
        la = math.radians(lat[0] + (lat[1] - lat[0]) * j / nv)
        f = 1.0 + flare * (1.0 - j / nv)
        row = []
        for i in range(cols):
            lo = math.radians(lon[0] + (lon[1] - lon[0]) * i / nu)
            row.append(bm.verts.new((rx * math.cos(la) * math.sin(lo) * f,
                                     -ry * math.cos(la) * math.cos(lo) * f,
                                     rz * math.sin(la))))
        grid.append(row)
    for j in range(nv):
        for i in range(nu):
            i2 = (i + 1) % cols
            q = [grid[j][i], grid[j][i2], grid[j + 1][i2], grid[j + 1][i]]
            try:
                bm.faces.new(q)
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if thick > 0:
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    return _obj(name, bm, parent, material, loc, rot, True, sharp)


def panel(name, parent, top_w, bot_w, length, material=None, segs=(6, 6), cup=0.0, flare=0.0,
          rag=0.0, seed=0, thick=0.012, loc=(0, 0, 0), rot=(0, 0, 0), wave=0.0, point=0.0, sharp=None):
    """Hanging cloth / plate panel: top edge centred on the origin, hangs along -Z, faces -Y.
    cup > 0 bends the side edges back (+Y, wraps a body); flare pushes the hem forward (-Y);
    rag tears the hem into uneven tongues; point makes the hem pointed in the middle."""
    nx, ny = segs
    rng = random.Random(seed)
    lens = []
    for i in range(nx + 1):
        r = rng.random() if i % 2 else rng.random() * 0.35
        lens.append(length * (1.0 - rag * r))
    bm = bmesh.new()
    grid = []
    for j in range(ny + 1):
        v = j / ny
        row = []
        for i in range(nx + 1):
            u = i / nx - 0.5
            w = top_w + (bot_w - top_w) * v
            L = lens[i] + length * point * (1.0 - abs(2 * u))
            z = -L * v
            y = cup * (2 * u) ** 2 - flare * v * v + wave * math.sin(u * math.pi * 3 + seed) * v
            row.append(bm.verts.new((u * w, y, z)))
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if thick > 0:
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    return _obj(name, bm, parent, material, loc, rot, True, sharp)


def _link_geo(bm, p, t, n, length, wire, maj=8, mn=4):
    b = t.cross(n)
    a = length * 0.5
    c = length * 0.3
    rings = []
    for i in range(maj):
        th = 2 * math.pi * i / maj
        cen = p + t * (math.cos(th) * a) + n * (math.sin(th) * c)
        tan = (t * (-math.sin(th) * a) + n * (math.cos(th) * c)).normalized()
        out = tan.cross(b).normalized()
        ring = []
        for k in range(mn):
            ph = 2 * math.pi * k / mn
            ring.append(bm.verts.new(cen + out * (math.cos(ph) * wire) + b * (math.sin(ph) * wire)))
        rings.append(ring)
    for i in range(maj):
        r0, r1 = rings[i], rings[(i + 1) % maj]
        for k in range(mn):
            bm.faces.new((r0[k], r0[(k + 1) % mn], r1[(k + 1) % mn], r1[k]))


def chain(name, parent, points, material, link=0.075, wire=0.011, smooth_n=3, loc=(0, 0, 0)):
    """Interlocking iron links along a (smoothed) path."""
    path = catmull(points, smooth_n) if len(points) > 2 else [Vector(p) for p in points]
    # resample evenly
    samples = []
    step = link * 0.78
    acc = 0.0
    for a, b in zip(path[:-1], path[1:]):
        seg = (b - a)
        L = seg.length
        d = step - acc if samples else 0.0
        while d <= L:
            samples.append((a + seg * (d / L), seg.normalized()))
            d += step
        acc = L - (d - step)
    bm = bmesh.new()
    up = Vector((0, 0, 1))
    for i, (p, t) in enumerate(samples):
        n = up - t * up.dot(t)
        if n.length < 1e-3:
            n = Vector((1, 0, 0)) - t * t.x
        n.normalize()
        if i % 2:
            n = t.cross(n)
        _link_geo(bm, p, t, n, link, wire)
    return _obj(name, bm, parent, material, loc, (0, 0, 0), True, None)


def ring_chain(name, parent, center, rx, ry, material, link=0.07, wire=0.011, tilt=(0, 0, 0), count=None):
    """Closed loop of links (around a torso / wrist)."""
    from mathutils import Euler
    e = Euler([math.radians(a) for a in tilt]).to_matrix()
    n = count or max(8, int(2 * math.pi * max(rx, ry) / (link * 0.78)))
    pts = []
    for i in range(n + 1):
        a = 2 * math.pi * i / n
        pts.append(Vector(center) + e @ Vector((math.cos(a) * rx, math.sin(a) * ry, 0)))
    return chain(name, parent, pts, material, link, wire, smooth_n=1)


def membrane(name, parent, root, tips, material, sag=0.35, nu=6, nw=4, thick=0.01, holes=0.0, seed=1,
             mids=None):
    """Leathery wing membrane: fan from `root` to each finger tip, the trailing edge between tips
    scalloped toward the root by `sag`. `mids` = optional per-finger knuckle offsets (bend)."""
    rng = random.Random(seed)
    root = Vector(root)
    tips = [Vector(t) for t in tips]
    bm = bmesh.new()
    grid = []
    nf = len(tips)
    for f in range(nf - 1):
        for w_i in range(nw + (1 if f == nf - 2 else 0)):
            w = w_i / nw
            col = []
            for u_i in range(nu + 1):
                u = u_i / nu
                a = root.lerp(tips[f], u)
                b = root.lerp(tips[f + 1], u)
                p = a.lerp(b, w)
                s = sag * math.sin(math.pi * w) * u ** 2
                p = p.lerp(root, s)
                col.append(bm.verts.new(p))
            grid.append(col)
    for c0, c1 in zip(grid[:-1], grid[1:]):
        for u_i in range(nu):
            if holes and u_i >= nu - 2 and rng.random() < holes:
                continue
            bm.faces.new((c0[u_i], c1[u_i], c1[u_i + 1], c0[u_i + 1]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if thick > 0:
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    return _obj(name, bm, parent, material, (0, 0, 0), (0, 0, 0), True, None)


def claw_hand(prefix, hand, skin, claw, size=1.0, claw_len=0.09, fingers=4, spread=1.0, curl=25, thumb=True,
              bony=False):
    """Palm + segmented clawed fingers hanging from the hand joint (fingers point down, -Z, palm faces in)."""
    k = size
    r_palm = (0.045 * k, 0.03 * k) if not bony else (0.03 * k, 0.018 * k)
    loft(prefix + "_palm", hand, [(0, 0, 0.01), (0, -0.004, -0.05 * k), (0, -0.006, -0.095 * k)],
         [(r_palm[0] * 0.8, r_palm[1]), (r_palm[0] * 1.08, r_palm[1] * 1.05), (r_palm[0], r_palm[1] * 0.9)],
         skin, segs=8)
    for i in range(fingers):
        x = (i - (fingers - 1) / 2) * 0.026 * k * spread
        base = Vector((x, -0.008, -0.09 * k))
        c = math.radians(curl)
        L1 = (0.045 if not bony else 0.06) * k
        p1 = base + Vector((x * 0.25, -math.sin(c) * L1, -math.cos(c) * L1))
        p2 = p1 + Vector((x * 0.15, -math.sin(2 * c) * L1 * 0.8, -math.cos(2 * c) * L1 * 0.8))
        rr = (0.011 if not bony else 0.007) * k
        loft(f"{prefix}_f{i}", hand, [base, p1, p2], [rr, rr * 0.9, rr * 0.8], skin, segs=6)
        tipdir = (p2 - p1).normalized()
        tip = p2 + tipdir * claw_len * k + Vector((0, -claw_len * 0.45 * k, 0))
        horn(f"{prefix}_c{i}", hand, [p2, p2 + tipdir * claw_len * 0.5 * k + Vector((0, -0.01 * k, 0)), tip],
             rr * 0.95, 0.001, claw, segs=5, n=2)
    if thumb:
        s = 1 if hand.name.endswith("L") else -1
        b = Vector((-s * 0.04 * k, -0.02 * k, -0.04 * k))
        p = b + Vector((-s * 0.012 * k, -0.04 * k, -0.035 * k))
        loft(prefix + "_th", hand, [b, p], [0.012 * k, 0.01 * k], skin, segs=6)
        horn(prefix + "_thc", hand, [p, p + Vector((0, -0.03 * k, -0.03 * k))], 0.009 * k, 0.001, claw, segs=5, n=2)


def on_ell(c, radii, lat, lon, off=1.0):
    la, lo = math.radians(lat), math.radians(lon)
    rx, ry, rz = radii
    return Vector(c) + Vector((rx * math.cos(la) * math.sin(lo) * off, -ry * math.cos(la) * math.cos(lo) * off,
                               rz * math.sin(la) * off))


def crack(name, parent, c, radii, pts, material, r=0.008, off=1.0):
    """Glowing seam lying on an ellipsoid surface (same centre/radii as a shell()); pts = [(lat, lon)]."""
    path = catmull([on_ell(c, radii, la, lo, off) for la, lo in pts], 2)
    n = len(path)
    radii_ = [0.0025 + r * math.sin(math.pi * (i + 0.5) / n) for i in range(n)]
    return loft(name, parent, path, radii_, material, segs=4, cap_round=1.0)


# ----------------------------------------------------------------------------- rig

class Rig:
    pass


def humanoid(name, hip_h=1.0, thigh=0.46, shin=0.44, hip_w=0.12, spine=0.24, chest=0.4, neck=0.1,
             shoulder_w=0.3, shoulder_z=0.32, upper=0.34, fore=0.32, arm_out=10, legs=True,
             spine_rot=0.0, head_rot=0.0):
    R = Rig()
    R.root = sb.root(name)
    R.body = sb.empty("body", R.root)
    R.hips = sb.empty("hips", R.body, loc=(0, 0, hip_h))
    R.hip_h, R.thigh_len, R.shin_len = hip_h, thigh, shin
    R.thigh, R.shin, R.foot = {}, {}, {}
    R.arm, R.fore, R.hand = {}, {}, {}
    if legs:
        for s in SIDES:
            R.thigh[s] = sb.empty(f"thigh_{sname(s)}", R.hips, loc=(s * hip_w, 0, -0.03))
            R.shin[s] = sb.empty(f"shin_{sname(s)}", R.thigh[s], loc=(0, 0, -thigh))
            R.foot[s] = sb.empty(f"foot_{sname(s)}", R.shin[s], loc=(0, 0, -shin))
    R.spine = sb.empty("spine", R.hips, loc=(0, 0, 0.06), rot=(spine_rot, 0, 0))
    R.chest = sb.empty("chest", R.spine, loc=(0, 0, spine))
    R.neck = sb.empty("neck", R.chest, loc=(0, 0, chest))
    R.look = sb.empty("look", R.neck, loc=(0, 0, neck))
    R.head = sb.empty("head", R.look, rot=(head_rot, 0, 0))
    R.upper_len, R.fore_len = upper, fore
    for s in SIDES:
        R.arm[s] = sb.empty(f"arm_{sname(s)}", R.chest, loc=(s * shoulder_w, 0, shoulder_z), rot=(0, -s * arm_out, 0))
        R.fore[s] = sb.empty(f"fore_{sname(s)}", R.arm[s], loc=(0, 0, -upper), rot=(-8, 0, 0))
        R.hand[s] = sb.empty(f"hand_{sname(s)}", R.fore[s], loc=(0, 0, -fore))
    R.extra = []      # extra animated joints (wings, cape, skirt, props)
    R.skirts = []     # (joint, angle_deg) hanging panels around the hips
    R.capes = []      # cape segment joints, top to bottom
    R.wings = []      # (side, wing joint, wingtip joint)
    return R


def skirt(R, parent, name, angles, radii, z, length, top_w, bot_w, material, rag=0.3, flare=0.08, cup=0.03,
          seed=1, thick=0.012, segs=(4, 6), point=0.0, lengths=None):
    """Ring of hanging panels (robe / skirt / tassets). angles in degrees, 0 = front (-Y), 90 = +X.
    Each panel gets its own joint (animated by standard_anims)."""
    rx, ry = radii
    out = []
    for i, a in enumerate(angles):
        ar = math.radians(a)
        j = sb.empty(f"{name}{i}", parent, loc=(math.sin(ar) * rx, -math.cos(ar) * ry, z), rot=(0, 0, a))
        L = lengths[i] if lengths else length
        panel(f"{name}{i}_m", j, top_w, bot_w, L, material, segs=segs, cup=cup, flare=flare, rag=rag,
              seed=seed + i * 7, thick=thick, point=point)
        R.skirts.append((j, a))
        R.extra.append(j)
        out.append(j)
    return out


def cape(R, parent, loc, widths, length, material, rag=0.35, seed=5, cup=0.08, thick=0.014, tilt=8):
    """Segmented cape hanging down the back (len(widths)-1 segments, each its own joint)."""
    n = len(widths) - 1
    seg = length / n
    p = parent
    for i in range(n):
        j = sb.empty(f"cape{i}", p, loc=loc if i == 0 else (0, 0, -seg), rot=(tilt if i == 0 else 3, 0, 0))
        last = i == n - 1
        panel(f"cape{i}_m", j, widths[i], widths[i + 1], seg + (0.0 if last else 0.02), material, segs=(6, 3),
              cup=-cup, flare=0.0, rag=rag if last else 0.0, seed=seed, thick=thick, rot=(0, 0, 180))
        R.capes.append(j)
        R.extra.append(j)
        p = j
    return R.capes


def wing_joints(R, parent, s, loc, tip, rot=(0, 0, 0)):
    n = sname(s)
    W = sb.empty(f"wing_{n}", parent, loc=loc, rot=rot)
    W2 = sb.empty(f"wingtip_{n}", W, loc=tip)
    R.wings.append((s, W, W2))
    R.extra += [W, W2]
    return W, W2


def feather(name, parent, base, direction, length, width, material, curve=0.0, roll=0.0):
    """sb.blade pointing along `direction` (flat side kept in the plane of direction and parent X)."""
    d = Vector(direction).normalized()
    q = Vector((0, 0, 1)).rotation_difference(d)
    if roll:
        from mathutils import Quaternion
        q = Quaternion(d, math.radians(roll)) @ q
    e = q.to_euler("XYZ")
    return sb.blade(name, parent, length=length, width=width, thickness=0.006, loc=base,
                    rot=tuple(math.degrees(a) for a in e), material=material, curve=curve)


def joints(R):
    js = [R.body, R.hips, R.spine, R.chest, R.neck, R.head]
    for d in (R.thigh, R.shin, R.foot, R.arm, R.fore, R.hand):
        js += list(d.values())
    return js + list(R.extra)


# ----------------------------------------------------------------------------- animation

class Pose(dict):
    def add(self, j, rot=(0, 0, 0), loc=(0, 0, 0), w=1.0):
        if j is None or w == 0.0:
            return
        r, l = self.get(j, ((0, 0, 0), (0, 0, 0)))
        self[j] = (tuple(a + b * w for a, b in zip(r, rot)), tuple(a + b * w for a, b in zip(l, loc)))


def bake(name, js, frames, fn, step=2):
    """Sample pose function fn(t in 0..1) -> Pose into an animation keyed on every joint in js."""
    fr = list(range(0, frames + 1, step))
    if fr[-1] != frames:
        fr.append(frames)
    keys = {j: [] for j in js}
    for f in fr:
        P = fn(f / frames)
        for j in js:
            r, l = P.get(j, ((0, 0, 0), (0, 0, 0)))
            keys[j].append((f, sb.offset(j, rot=r, loc=l)))
    sb.anim(name, keys)


def standard_anims(R, cfg, extra=None):
    """idle / walk / attack / hit / death / cheer. `extra(name, t, P, cfg)` adds per-demon joints."""
    c = dict(stride=26, knee=42, arm=20, bob=0.04, lean=5, sway=3, twist=7, hover=0.0,
             attack="cleave", side=-1, heavy=1.0, idle_frames=60, walk_frames=30)
    c.update(cfg)
    js = joints(R)
    legs = bool(R.thigh)
    hov = c["hover"]

    def ex(name, t, P):
        secondary(R, name, t, P, c)
        if extra:
            extra(name, t, P, c)
        return P

    # ---------------- idle
    def idle(t):
        P = Pose()
        b = math.sin(2 * math.pi * t)
        b2 = math.sin(2 * math.pi * t * 2 + 0.7)
        P.add(R.body, loc=(0, 0, hov + 0.035 * b * (1 if hov else 0)))
        P.add(R.hips, loc=(0, 0, -0.006 * (1 - b) * (0 if hov else 1)))
        P.add(R.spine, rot=(-1.2 * b, 0, 0.6 * b2))
        P.add(R.chest, rot=(-1.5 * b, 0, 0))
        P.add(R.neck, rot=(1.6 * b, 1.5 * math.sin(2 * math.pi * t + 1.3), 0))
        for s in SIDES:
            P.add(R.arm.get(s), rot=(2.0 * math.sin(2 * math.pi * t + 0.6), s * -1.8 * b, 0))
            P.add(R.fore.get(s), rot=(-2.5 * b, 0, 0))
            P.add(R.hand.get(s), rot=(-3 * math.sin(2 * math.pi * t + 1.0), 0, 0))
            if legs:
                P.add(R.shin[s], rot=(1.2 * (1 - b), 0, 0))
                P.add(R.thigh[s], rot=(-0.6 * (1 - b), 0, 0))
                P.add(R.foot[s], rot=(-0.6 * (1 - b), 0, 0))
        return ex("idle", t, P)

    # ---------------- walk
    def walk(t):
        P = Pose()
        ph = 2 * math.pi * t
        s_ = math.sin(ph)
        h = c["heavy"]
        if legs:
            P.add(R.hips, loc=(0, 0, c["bob"] * (0.4 - abs(math.cos(ph)))),
                  rot=(0, c["twist"] * s_ * 0.6, c["sway"] * math.cos(ph) * 0.5))
            for s in SIDES:
                phi = ph if s > 0 else ph + math.pi
                ang = -c["stride"] * math.sin(phi)
                swing = max(0.0, math.cos(phi))
                knee = c["knee"] * swing ** 1.2 + 5 + 8 * max(0.0, -math.sin(phi)) * 0.5
                P.add(R.thigh[s], rot=(ang - knee * 0.25, 0, 0))
                P.add(R.shin[s], rot=(knee, 0, 0))
                P.add(R.foot[s], rot=(-(ang - knee * 0.25 + knee) * 0.7 + 10 * max(0.0, math.sin(phi)) * 0, 0, 0))
        else:
            P.add(R.body, loc=(0, 0, hov + 0.03 * math.sin(2 * ph)))
        P.add(R.spine, rot=(c["lean"] + 2 * h * abs(math.cos(ph)), -c["twist"] * s_, -c["sway"] * math.cos(ph) * 0.4))
        P.add(R.neck, rot=(-c["lean"] * 0.7, c["twist"] * s_ * 0.6, 0))
        for s in SIDES:
            phi = ph if s > 0 else ph + math.pi
            P.add(R.arm.get(s), rot=(c["arm"] * math.sin(phi), 0, 0))
            P.add(R.fore.get(s), rot=(-8 - 10 * max(0.0, -math.sin(phi)), 0, 0))
        return ex("walk", t, P)

    # ---------------- attack (one-shot)
    def attack(t):
        P = Pose()
        sd = c["side"]
        wind = env(t, 0.0, 0.32, 0.36, 0.5)
        hit = env(t, 0.34, 0.5, 0.62, 1.0)
        style = c["attack"]
        if style == "cleave":       # overhead heavy chop with the weapon arm
            P.add(R.spine, rot=(-10, sd * -14, 0), w=wind)
            P.add(R.spine, rot=(22, sd * 18, 0), w=hit)
            P.add(R.hips, loc=(0, 0, -0.06), w=hit)
            P.add(R.arm[sd], rot=(-165, sd * 12, 0), w=wind)
            P.add(R.fore[sd], rot=(-40, 0, 0), w=wind)
            P.add(R.arm[sd], rot=(-55, sd * -10, 0), w=hit)
            P.add(R.fore[sd], rot=(-5, 0, 0), w=hit)
            P.add(R.arm[-sd], rot=(-40, sd * 15, 0), w=wind)
            P.add(R.arm[-sd], rot=(25, 0, 0), w=hit)
            P.add(R.neck, rot=(-8, 0, 0), w=wind)
            if legs:
                for s in SIDES:
                    P.add(R.thigh[s], rot=(-14, 0, 0), w=hit)
                    P.add(R.shin[s], rot=(24, 0, 0), w=hit)
                    P.add(R.foot[s], rot=(-10, 0, 0), w=hit)
        elif style == "sweep":      # horizontal sweep across the body (hook / scythe)
            P.add(R.spine, rot=(4, sd * -35, 0), w=wind)
            P.add(R.spine, rot=(12, sd * 40, 0), w=hit)
            P.add(R.arm[sd], rot=(-60, 0, sd * 0), w=wind)
            P.add(R.arm[sd], rot=(-15, sd * 65, 0), w=wind)
            P.add(R.arm[sd], rot=(-80, sd * -55, 0), w=hit)
            P.add(R.fore[sd], rot=(-30, 0, 0), w=wind)
            P.add(R.arm[-sd], rot=(20, sd * -20, 0), w=hit)
        else:                       # "cast": both hands thrust forward
            P.add(R.spine, rot=(-6, sd * -10, 0), w=wind)
            P.add(R.spine, rot=(12, sd * 8, 0), w=hit)
            P.add(R.arm[sd], rot=(-30, sd * 30, 0), w=wind)
            P.add(R.fore[sd], rot=(-70, 0, 0), w=wind)
            P.add(R.arm[sd], rot=(-85, sd * -8, 0), w=hit)
            P.add(R.fore[sd], rot=(8, 0, 0), w=hit)
            P.add(R.hand[sd], rot=(40, 0, 0), w=hit)
            P.add(R.arm[-sd], rot=(-20, sd * -25, 0), w=wind + hit)
            P.add(R.fore[-sd], rot=(-35, 0, 0), w=wind + hit)
        P.add(R.body, loc=(0, 0, hov))
        return ex("attack", t, P)

    # ---------------- hit (one-shot recoil)
    def hit(t):
        P = Pose()
        k = env(t, 0.0, 0.18, 0.3, 1.0)
        P.add(R.body, loc=(0, 0.07 * k, hov))
        P.add(R.spine, rot=(-14 * k, 0, 4 * k))
        P.add(R.chest, rot=(-6 * k, 0, 0))
        P.add(R.neck, rot=(-14 * k, 0, -5 * k))
        for s in SIDES:
            P.add(R.arm.get(s), rot=(-18 * k, s * -16 * k, 0))
            P.add(R.fore.get(s), rot=(-25 * k, 0, 0))
            if legs:
                P.add(R.thigh[s], rot=(-6 * k, 0, 0))
                P.add(R.shin[s], rot=(10 * k, 0, 0))
        return ex("hit", t, P)

    # ---------------- death (one-shot: stagger, kneel, slump)
    def death(t):
        P = Pose()
        st = env(t, 0.0, 0.12, 0.12, 0.3)
        kn = env(t, 0.12, 0.45)
        sl = env(t, 0.4, 0.8)
        P.add(R.spine, rot=(-14 * st, 0, 5 * st))
        P.add(R.neck, rot=(-20 * st, 0, 0))
        if legs:
            a = 62.0
            hip_new = 0.08 + R.thigh_len * math.cos(math.radians(a))
            P.add(R.body, loc=(0, 0, (hip_new - R.hip_h) * kn))
            for s in SIDES:
                P.add(R.thigh[s], rot=(-a, 0, s * 4), w=kn)
                P.add(R.shin[s], rot=(a + 85, 0, 0), w=kn)
                P.add(R.foot[s], rot=(-20, 0, 0), w=kn)
        else:
            P.add(R.body, loc=(0, 0, hov * (1 - kn) - 0.35 * kn))
        P.add(R.spine, rot=(18, 0, 0), w=kn)
        P.add(R.spine, rot=(32, 0, 6), w=sl)
        P.add(R.chest, rot=(10, 0, 0), w=sl)
        P.add(R.neck, rot=(30, 10, 8), w=sl)
        for s in SIDES:
            P.add(R.arm.get(s), rot=(-10, s * 6, 0), w=kn)
            P.add(R.arm.get(s), rot=(-15, s * 8, 0), w=sl)
            P.add(R.fore.get(s), rot=(6, 0, 0), w=kn + sl)
            P.add(R.hand.get(s), rot=(10, 0, 0), w=sl)
        return ex("death", t, P)

    # ---------------- cheer (menacing roar for the select screen)
    def cheer(t):
        P = Pose()
        cr = env(t, 0.0, 0.18, 0.2, 0.36)
        ro = env(t, 0.24, 0.42, 0.78, 1.0)
        shake = math.sin(t * 90) * 1.2 * ro
        if legs:
            for s in SIDES:
                P.add(R.thigh[s], rot=(-24, 0, 0), w=cr)
                P.add(R.shin[s], rot=(44, 0, 0), w=cr)
                P.add(R.foot[s], rot=(-20, 0, 0), w=cr)
            P.add(R.body, loc=(0, 0, -0.1 * cr))
        else:
            P.add(R.body, loc=(0, 0, hov - 0.08 * cr + 0.12 * ro))
        P.add(R.spine, rot=(22, 0, 0), w=cr)
        P.add(R.neck, rot=(16, 0, 0), w=cr)
        P.add(R.spine, rot=(-16, 0, shake), w=ro)
        P.add(R.chest, rot=(-8, 0, 0), w=ro)
        P.add(R.neck, rot=(-26, 0, shake * 2), w=ro)
        for s in SIDES:
            P.add(R.arm.get(s), rot=(-20, s * 10, 0), w=cr)
            P.add(R.fore.get(s), rot=(-30, 0, 0), w=cr)
            P.add(R.arm.get(s), rot=(-35, s * -62, 0), w=ro)
            P.add(R.fore.get(s), rot=(-45, 0, 0), w=ro)
            P.add(R.hand.get(s), rot=(-20, 0, 0), w=ro)
        return ex("cheer", t, P)

    bake("idle", js, c["idle_frames"], idle, 3)
    bake("walk", js, c["walk_frames"], walk, 2)
    bake("attack", js, 20, attack, 1)
    bake("hit", js, 12, hit, 1)
    bake("death", js, 42, death, 2)
    bake("cheer", js, 54, cheer, 2)


def secondary(R, name, t, P, c):
    """Skirt panels, cape segments and wings for every standard animation."""
    ph = 2 * math.pi * t
    wa = c.get("wing_amp", 1.0)
    if name == "idle":
        for j, a in R.skirts:
            P.add(j, rot=(1.5 * math.sin(ph + math.radians(a) * 2), 0, 0))
        for i, j in enumerate(R.capes):
            P.add(j, rot=(2.0 * math.sin(ph - i * 0.9) * (1 + i * 0.3), 0, 1.0 * math.sin(ph * 2 - i)))
        for s, W, W2 in R.wings:
            b = math.sin(ph)
            P.add(W, rot=(0, -s * 4 * b * wa, s * 3 * b * wa))
            P.add(W2, rot=(0, -s * 4 * math.sin(ph - 0.6) * wa, 0))
    elif name == "walk":
        for j, a in R.skirts:
            ca = math.cos(math.radians(a))
            P.add(j, rot=(ca * c.get("skirt_trail", 10) + 7 * math.sin(ph + math.radians(a)) * abs(math.sin(math.radians(a))) + 3 * math.sin(2 * ph), 0, 0))
        for i, j in enumerate(R.capes):
            P.add(j, rot=((22 if i == 0 else 6) + 4 * math.sin(2 * ph - i * 1.1) * (1 + i * 0.4), 0, 2 * math.sin(ph - i)))
        for s, W, W2 in R.wings:
            P.add(W, rot=(-4, -s * 3 * math.sin(2 * ph) * wa, s * 12 * wa))
            P.add(W2, rot=(0, s * 6 * wa, s * 6 * wa))
    elif name == "attack":
        k = env(t, 0.0, 0.32, 0.5, 1.0)
        h = env(t, 0.34, 0.5, 0.62, 1.0)
        for j, a in R.skirts:
            P.add(j, rot=(-6 * h + 4 * math.cos(math.radians(a)) * h, 0, 0))
        for i, j in enumerate(R.capes):
            P.add(j, rot=(10 * h - 4 * k, 0, 0))
        for s, W, W2 in R.wings:
            P.add(W, rot=(0, -s * 18 * k * wa, -s * 12 * k * wa))
    elif name == "hit":
        k = env(t, 0.0, 0.18, 0.3, 1.0)
        lag = env(t, 0.1, 0.3, 0.4, 1.0)
        for j, a in R.skirts:
            P.add(j, rot=(-math.cos(math.radians(a)) * 12 * lag, 0, 0))
        for i, j in enumerate(R.capes):
            P.add(j, rot=(-10 * lag, 0, 0))
        for s, W, W2 in R.wings:
            P.add(W, rot=(0, -s * 22 * k * wa, -s * 8 * k * wa))
            P.add(W2, rot=(0, -s * 12 * k * wa, 0))
    elif name == "death":
        kn = env(t, 0.12, 0.6)
        for j, a in R.skirts:
            P.add(j, rot=(-c.get("skirt_pool", 30) * kn, 0, 0))
        for i, j in enumerate(R.capes):
            P.add(j, rot=((-15 if i == 0 else 10) * kn, 0, 0))
        for s, W, W2 in R.wings:
            P.add(W, rot=(10 * kn, s * 30 * kn, s * 30 * kn))
            P.add(W2, rot=(0, s * 30 * kn, s * 20 * kn))
    elif name == "cheer":
        cr = env(t, 0.0, 0.18, 0.2, 0.36)
        ro = env(t, 0.24, 0.42, 0.78, 1.0)
        for j, a in R.skirts:
            P.add(j, rot=(-12 * ro + 3 * math.sin(t * 60 + a) * ro, 0, 0))
        for i, j in enumerate(R.capes):
            P.add(j, rot=((25 if i == 0 else 8) * ro + 4 * math.sin(t * 40 - i) * ro, 0, 0))
        for s, W, W2 in R.wings:
            P.add(W, rot=(0, s * 10 * cr * wa, s * 15 * cr * wa))
            P.add(W, rot=(0, -s * 24 * ro * wa, -s * 22 * ro * wa))
            P.add(W2, rot=(0, -s * 18 * ro * wa, -s * 10 * ro * wa))


# ----------------------------------------------------------------------------- finish

def finalize(root):
    """Apply modifiers and merge the meshes under each joint into one object (fewer nodes in Godot).
    Prints the triangle count."""
    sc = bpy.context.scene
    vl = bpy.context.view_layer
    vl.update()
    meshes = [o for o in sc.objects if o.type == "MESH"]
    for o in sc.objects:
        o.select_set(False)
    for o in meshes:
        o.select_set(True)
    if meshes:
        vl.objects.active = meshes[0]
        bpy.ops.object.convert(target="MESH")
    groups = {}
    for o in [o for o in sc.objects if o.type == "MESH"]:
        groups.setdefault(o.parent, []).append(o)
    for parent, objs in groups.items():
        if len(objs) < 2:
            objs[0].name = (parent.name if parent else "mesh") + "_m"
            continue
        for o in sc.objects:
            o.select_set(False)
        for o in objs:
            o.select_set(True)
        vl.objects.active = objs[0]
        bpy.ops.object.join()
        objs[0].name = (parent.name if parent else "mesh") + "_m"
    tris = 0
    for o in sc.objects:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
    print(f"DEMON {root.name} tris={tris} meshes={len([o for o in sc.objects if o.type == 'MESH'])}")
    return tris
