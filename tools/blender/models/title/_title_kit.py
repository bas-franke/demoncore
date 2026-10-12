"""Shared parts for the title-screen vista (underscore = not built by `all`).

Everything here is built at REAL scale (tens to hundreds of meters): the title scene places the
models directly. Material names map to Art surface presets via keywords (marble/rock/gold/steel).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import sb  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "title"

_SPEC = {
    "Title_Marble": ((0.66, 0.63, 0.57), 0.62, 0.0),
    "Title_MarbleDark": ((0.4, 0.385, 0.36), 0.7, 0.0),
    "Title_StoneRock": ((0.17, 0.16, 0.15), 0.95, 0.0),
    "Title_AshRock": ((0.13, 0.12, 0.115), 0.97, 0.0),
    "Title_Gold": ((0.83, 0.66, 0.3), 0.38, 0.9),
    "Title_SteelBlade": ((0.3, 0.3, 0.31), 0.45, 0.7),
}
_EMIT = {
    "Title_HolyGlass": ((0.6, 0.5, 0.3), (1.0, 0.78, 0.42), 4.0),
    "Title_HolyCrack": ((0.4, 0.33, 0.2), (1.0, 0.78, 0.4), 3.0),
    "Title_Ember": ((0.05, 0.02, 0.01), (1.0, 0.16, 0.03), 2.2),
}


def M(name):
    if name in _EMIT:
        c, e, s = _EMIT[name]
        return sb.mat(name, c, 0.5, 0.0, e, s)
    c, r, m = _SPEC[name]
    return sb.mat(name, c, r, m)


def rng_for(seed):
    return random.Random(seed)


def block(name, parent, rng, size, loc=(0, 0, 0), rot=(0, 0, 0), mat="Title_Marble", chips=2,
          cracks=0, step=None, taper=None):
    """Weathered masonry block at big scale (coarse slicing keeps tris low)."""
    if step is None:
        step = max(0.6, max(size) / 5.0)
    return sb.stone_block(name, parent, size, M(mat), rng, loc, rot, chips=chips, cracks=cracks,
                          step=step, taper=taper)


def rock(name, parent, rng, size, loc=(0, 0, 0), rot=(0, 0, 0), mat="Title_StoneRock", subdiv=1,
         cuts=5, flat_bottom=True):
    bm = sb.bm_rock(rng, size, cuts=cuts, subdiv=subdiv, flat_bottom=flat_bottom)
    return sb.bm_obj(name, parent, bm, M(mat), loc, rot, sharp=40)


def arc_piece(name, parent, center, r_in, r_out, a0, a1, depth, y=0.0, mat="Title_Marble",
              rng=None, slices=6):
    """Curved voussoir / ring segment in the XZ plane (angles in degrees), `depth` along Y."""
    bm = sb.bm_box((1.0, depth, 1.0), (slices, 1, 1))
    sb.bm_arc(bm, (center[0], 0.0, center[1]), r_in, r_out, a0, a1)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, y, 0))
    if rng is not None:
        sb.bm_noise(bm, (r_out - r_in) * 0.05, 0.6, seed=rng.randrange(9999))
    return sb.bm_obj(name, parent, bm, M(mat))


def pointed_arch(parent, rng, cx, spring, span, th, depth, y=0.0, mat="Title_Marble", tag="pa",
                 pieces=3, drop=()):
    """Equilateral gothic arch (two arcs of radius = span) springing at z=`spring`.
    `drop` = indices of missing voussoirs (0..2*pieces-1, left half first)."""
    out = []
    idx = 0
    for side in (-1, 1):
        # left half: centered on the right springer, angles 180 -> 120
        c = (cx - side * span * 0.5, spring)
        a_start, a_end = (180.0, 120.0) if side < 0 else (0.0, 60.0)
        for k in range(pieces):
            if idx not in drop:
                a0 = a_start + (a_end - a_start) * k / pieces
                a1 = a_start + (a_end - a_start) * (k + 1) / pieces
                lo, hi = min(a0, a1), max(a0, a1)
                out.append(arc_piece(f"{tag}{idx}", parent, c, span, span + th, lo + 0.4, hi - 0.4,
                                     depth, y, mat, rng, 3))
            idx += 1
    return out


def spire(name, parent, rng, base_r, height, loc=(0, 0, 0), rot=(0, 0, 0), sides=8, broken=0.0,
          mat="Title_Marble"):
    """Octagonal spire cone with a crocketed silhouette; `broken` cuts the tip at that fraction."""
    prof = []
    n = 10
    for i in range(n + 1):
        t = i / n
        r = base_r * (1.0 - t) ** 1.15
        if 0 < i < n and i % 2 == 0:
            r *= 1.12  # crocket bands
        prof.append((max(r, 0.0), height * t))
    bm = sb.bm_lathe(prof, sides)
    if broken > 0.0:
        n_ = Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), 1.0)).normalized()
        caps = sb.bm_cut(bm, (0, 0, height * broken), n_)
        caps = [f for f in caps if f.is_valid]
        if caps:
            sb.bm_roughen(bm, caps, rng, base_r * 0.12, 0.35)
    sb.bm_noise(bm, base_r * 0.03, 0.5, seed=rng.randrange(9999))
    return sb.bm_obj(name, parent, bm, M(mat), loc, rot, sharp=30)


def column(name, parent, rng, r, h, loc=(0, 0, 0), rot=(0, 0, 0), flutes=8, broken_top=0.0,
           mat="Title_Marble"):
    rings = max(2, min(10, int(h / max(r, 0.1))))
    bm = sb.bm_column(r, h, segments=flutes * 3 if flutes else 12, rings=rings, flutes=flutes,
                      flute_depth=0.08)
    if broken_top > 0:
        side = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized()
        nrm = side * (broken_top / (2 * r)) + Vector((0, 0, 1))
        caps = sb.bm_cut(bm, (0, 0, h - broken_top * 0.5), nrm.normalized())
        caps = [f for f in caps if f.is_valid]
        if caps:
            sb.bm_roughen(bm, caps, rng, r * 0.15, 0.4)
    sb.bm_noise(bm, r * 0.04, 1.5 / max(r, 0.2), seed=rng.randrange(9999))
    return sb.bm_obj(name, parent, bm, M(mat), loc, rot)


def sword(name, parent, rng, length, width, loc, rot, mat_blade="Title_SteelBlade",
          mat_hilt="Title_MarbleDark", broken=False):
    """Great sword along local +Z (point at z=0, pommel at the top). For blades stuck in the ground."""
    L = length * (0.6 if broken else 1.0)
    outline = [(-width * 0.5, L * 0.12), (0.0, 0.0), (width * 0.5, L * 0.12), (width * 0.45, L),
               (-width * 0.45, L)]
    if broken:
        outline = [(-width * 0.5, L * 0.15), (-width * 0.1, 0.0), (width * 0.3, L * 0.07),
                   (width * 0.5, L * 0.18), (width * 0.45, L), (-width * 0.45, L)]
    root = sb.empty(name, parent, loc, rot)
    pts = [(x, 0.0, z) for x, z in outline]
    n = len(pts)
    t = width * 0.09
    verts = [(x, -t, z) for x, _, z in pts] + [(x, t, z) for x, _, z in pts]
    faces = [list(reversed(range(n))), list(range(n, 2 * n))]
    for k in range(n):
        j = (k + 1) % n
        faces.append([k, j, n + j, n + k])
    # front/back faces are in the XZ plane: rebuild via mesh_from (normals recalculated)
    sb.mesh_from(name + "_blade", root, verts, faces, M(mat_blade))
    g = width * 1.9
    sb.box(name + "_guard", root, (g, width * 0.35, width * 0.28), loc=(0, 0, L + width * 0.14),
           material=M(mat_hilt), bevel=0.0)
    sb.cylinder(name + "_grip", root, width * 0.16, width * 0.14, length * 0.2, loc=(0, 0, L + width * 0.28),
                material=M(mat_hilt), segments=6, bevel=0.0, smooth=False)
    sb.sphere(name + "_pommel", root, width * 0.26, loc=(0, 0, L + width * 0.28 + length * 0.2),
              material=M(mat_hilt), segments=8, rings=5)
    return root


def scale_bm(bm, s):
    sb.bm_xform(bm, scale=(s, s, s))
    return bm
