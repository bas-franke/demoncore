"""Shared kit for ground foliage (underscore = not built by `all`).

Every foliage model is ONE joined mesh (one surface per material) under a root empty at the origin,
base at z=0, so res://scenes/world/foliage.gd can lift the mesh straight into a MultiMesh.
Foliage is drawn double-sided with a wind-sway shader whose bend weight grows with height, so:
  * blades / petals are single-sided ribbons (cheap), the shader renders both faces
  * keep the model's base at z=0; anything that must not sway (roots, litter) stays low
Colors are given as sRGB (`srgb()` converts to the linear base color Blender / glTF store).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import sb  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

CATEGORY = "foliage"


def srgb(r, g, b):
    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b))


def M(name, color_srgb, rough=0.85):
    return sb.mat(name, srgb(*color_srgb), rough, 0.0)


class Geo:
    """Raw multi-material mesh accumulator (fast: no bmesh ops, no modifiers)."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.fmat = []
        self.mats = []

    def mat_index(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def v(self, p):
        self.verts.append(tuple(p))
        return len(self.verts) - 1

    def face(self, idx, m):
        self.faces.append(tuple(idx))
        self.fmat.append(self.mat_index(m))

    # --------------------------------------------------------------- primitives

    def ribbon(self, m, pts, widths, side_dirs):
        """Flat strip through `pts`; half-width `widths[i]` along `side_dirs[i]`.
        A width of 0 collapses to a single vertex (pointed tip)."""
        rows = []
        for p, w, s in zip(pts, widths, side_dirs):
            p = Vector(p)
            s = Vector(s)
            if w <= 1e-5:
                rows.append([self.v(p)])
            else:
                rows.append([self.v(p - s * w), self.v(p + s * w)])
        for a, b in zip(rows[:-1], rows[1:]):
            if len(a) == 2 and len(b) == 2:
                self.face((a[0], a[1], b[1], b[0]), m)
            elif len(a) == 2:
                self.face((a[0], a[1], b[0]), m)
            elif len(b) == 2:
                self.face((a[0], b[1], b[0]), m)

    def tube(self, m, pts, radii, sides=4, cap=False):
        pts = [Vector(p) for p in pts]
        n = len(pts)
        rings = []
        prev = None
        for i, p in enumerate(pts):
            if i == 0:
                t = pts[1] - pts[0]
            elif i == n - 1:
                t = pts[-1] - pts[-2]
            else:
                t = (pts[i + 1] - pts[i - 1])
            t.normalize()
            if prev is None:
                ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
                side = t.cross(ref).normalized()
            else:
                side = (prev - t * prev.dot(t)).normalized()
            prev = side
            up = t.cross(side).normalized()
            r = radii[i]
            if r <= 1e-5:
                rings.append([self.v(p)])
                continue
            rings.append([self.v(p + (side * math.cos(2 * math.pi * k / sides)
                                      + up * math.sin(2 * math.pi * k / sides)) * r) for k in range(sides)])
        for a, b in zip(rings[:-1], rings[1:]):
            if len(a) > 1 and len(b) > 1:
                for k in range(sides):
                    self.face((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]), m)
            elif len(b) == 1:
                for k in range(sides):
                    self.face((a[k], a[(k + 1) % sides], b[0]), m)
            elif len(a) == 1:
                for k in range(sides):
                    self.face((a[0], b[(k + 1) % sides], b[k]), m)
        if cap and len(rings[-1]) > 2:
            self.face(tuple(rings[-1]), m)

    def lathe(self, m, profile, segs, xf, wobble=None):
        """Surface of revolution (profile [(r, z)] bottom->top) placed with matrix `xf`."""
        rows = []
        for i, (r, z) in enumerate(profile):
            if r <= 1e-6:
                rows.append([self.v(xf @ Vector((0, 0, z)))])
                continue
            row = []
            for k in range(segs):
                a = 2 * math.pi * k / segs
                rr = r * (wobble(a, i) if wobble else 1.0)
                row.append(self.v(xf @ Vector((math.cos(a) * rr, math.sin(a) * rr, z))))
            rows.append(row)
        for a, b in zip(rows[:-1], rows[1:]):
            if len(a) > 1 and len(b) > 1:
                for k in range(segs):
                    self.face((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]), m)
            elif len(b) == 1:
                for k in range(segs):
                    self.face((a[k], a[(k + 1) % segs], b[0]), m)
            elif len(a) == 1:
                for k in range(segs):
                    self.face((a[0], b[(k + 1) % segs], b[k]), m)

    # --------------------------------------------------------------- output

    def build(self, name, smooth=True):
        root = sb.root(name)
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        me.update()
        for m in self.mats:
            me.materials.append(m)
        for p, mi in zip(me.polygons, self.fmat):
            p.material_index = mi
            p.use_smooth = smooth
        obj = bpy.data.objects.new(name + "_mesh", me)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = root
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        print(f"TRIS {name} = {tris} verts={len(self.verts)}")
        return root


# ------------------------------------------------------------------- organic helpers

def bezier(p0, p1, p2, t):
    a = p0.lerp(p1, t)
    b = p1.lerp(p2, t)
    return a.lerp(b, t)


def blade(g, m, rng, base, height, width, lean, heading, curl=0.0, segs=4, droop=0.0, twist=0.0):
    """One grass blade: curved tapered ribbon. `lean` 0..1 = how far it tips over (fraction of
    height reached horizontally), `heading` = radians of the lean direction, `droop` bends the
    tip back down (broken / heavy blades), `twist` rotates the flat face along the blade."""
    base = Vector(base)
    d = Vector((math.cos(heading), math.sin(heading), 0.0))
    tip = base + d * (height * lean) + Vector((0, 0, height * (1.0 - 0.45 * lean * lean) - droop))
    mid = base + d * (height * lean * 0.25) + Vector((0, 0, height * 0.62))
    side0 = Vector((-d.y, d.x, 0.0))
    pts, ws, sides = [], [], []
    for i in range(segs + 1):
        t = i / segs
        pts.append(bezier(base, mid, tip, t))
        w = width * (1.0 - t ** 1.5) * (0.75 + 0.25 * math.sin(min(1.0, t * 3.0) * math.pi * 0.5))
        ws.append(w if i < segs else 0.0)
        a = twist * t + curl * t
        sides.append((side0 * math.cos(a) + d * math.sin(a)).normalized())
    g.ribbon(m, pts, ws, sides)


def leaf_shape(g, m, center, length, width, heading, tilt=0.0, fold=0.25, curl=0.0, pitch=0.0):
    """Flat-ish leaf (pointed oval) lying around `center`, midrib along `heading`; `fold` lifts the
    two halves into a shallow V, `curl` lifts the tip, `pitch` raises the whole leaf (radians)."""
    c = Vector(center)
    d = Vector((math.cos(heading) * math.cos(pitch), math.sin(heading) * math.cos(pitch), math.sin(pitch)))
    s = Vector((-math.sin(heading), math.cos(heading), 0.0))
    up = d.cross(s).normalized()
    if up.z < 0:
        up = -up
    rot = Matrix.Rotation(tilt, 3, d)
    s = rot @ s
    up = rot @ up
    n = 3
    rows = []
    for i in range(n + 1):
        t = i / n
        p = c + d * (length * (t - 0.5)) + up * (curl * length * t * t)
        w = width * math.sin(math.pi * min(0.999, max(0.001, t ** 0.85)))
        if i == 0 or i == n:
            rows.append([g.v(p)])
        else:
            rows.append([g.v(p - s * w + up * fold * w), g.v(p + up * 0.0), g.v(p + s * w + up * fold * w)])
    # fan between rows (left half + right half)
    for a, b in zip(rows[:-1], rows[1:]):
        if len(a) == 1:
            g.face((a[0], b[1], b[0]), m)
            g.face((a[0], b[2], b[1]), m)
        elif len(b) == 1:
            g.face((a[0], a[1], b[0]), m)
            g.face((a[1], a[2], b[0]), m)
        else:
            g.face((a[0], a[1], b[1], b[0]), m)
            g.face((a[1], a[2], b[2], b[1]), m)


def scatter_disc(rng, radius, n, min_d=0.0):
    """`n` points in a disc (rough Poisson by rejection)."""
    pts = []
    tries = 0
    while len(pts) < n and tries < n * 40:
        tries += 1
        a = rng.uniform(0, math.tau)
        r = math.sqrt(rng.random()) * radius
        p = Vector((math.cos(a) * r, math.sin(a) * r, 0.0))
        if all((p - q).length >= min_d for q in pts):
            pts.append(p)
    return pts


def grass_clump(g, rng, mats, n=22, h=(0.25, 0.55), w=(0.012, 0.022), radius=0.12, lean=(0.15, 0.6),
                droop_chance=0.0, seeds=0, seed_mat=None, seed_h=1.25, segs=3):
    """Tussock: blades rooted in a small disc, leaning outward (taller ones near the centre).
    `mats` = list of (material, weight). `seeds` = seed stalks with spindle heads."""
    tot = sum(wt for _, wt in mats)
    for i in range(n):
        a = rng.uniform(0, math.tau)
        r = math.sqrt(rng.random()) * radius
        base = Vector((math.cos(a) * r, math.sin(a) * r, 0.0))
        k = 1.0 - r / max(radius, 1e-4)
        height = rng.uniform(*h) * (0.7 + 0.45 * k)
        heading = a + rng.uniform(-0.6, 0.6)
        ln = rng.uniform(*lean) * (1.2 - 0.5 * k)
        droop = 0.0
        if rng.random() < droop_chance:
            ln = min(0.95, ln + 0.35)
            droop = height * rng.uniform(0.25, 0.6)
        x = rng.uniform(0, tot)
        m = mats[-1][0]
        for mm, wt in mats:
            x -= wt
            if x <= 0:
                m = mm
                break
        blade(g, m, rng, base, height, rng.uniform(*w), ln, heading, curl=rng.uniform(-0.6, 0.6),
              segs=segs, droop=droop, twist=rng.uniform(-0.8, 0.8))
    for i in range(seeds):
        a = rng.uniform(0, math.tau)
        base = Vector((math.cos(a) * radius * 0.4, math.sin(a) * radius * 0.4, 0.0))
        height = h[1] * seed_h * rng.uniform(0.9, 1.2)
        d = Vector((math.cos(a), math.sin(a), 0.0))
        top = base + d * height * rng.uniform(0.15, 0.35) + Vector((0, 0, height))
        mid = base + d * height * 0.05 + Vector((0, 0, height * 0.6))
        pts = [bezier(base, mid, top, t / 4) for t in range(5)]
        sd = Vector((-d.y, d.x, 0.0))
        g.ribbon(seed_mat, pts, [0.006, 0.005, 0.0045, 0.004, 0.0035], [sd] * 5)
        # spindle seed head: two crossed ribbons continuing the stalk
        tan = (pts[-1] - pts[-2]).normalized()
        hl = rng.uniform(0.09, 0.14)
        head = [pts[-1] + tan * hl * t / 3 for t in range(4)]
        side = tan.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        side.normalize()
        side2 = tan.cross(side).normalized()
        wd = [0.01, 0.018, 0.012, 0.0]
        g.ribbon(seed_mat, head, wd, [side] * 4)
        g.ribbon(seed_mat, head, wd, [side2] * 4)
