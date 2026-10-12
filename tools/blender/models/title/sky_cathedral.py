"""The shattered Cathedral of Heaven: broken fragments of a colossal gothic nave hanging in the sky,
torn out of the ground with rock still clinging beneath. ~140 m across. Seen from far below.

Top-level layout: root "SkyCathedral" -> empties "frag_<name>" (one joined mesh each); the title
scene bobs/rotates every node whose name starts with "frag_" independently.
Glowing gold glass ("Title_HolyGlass") fills the windows: Heaven's light still burns inside.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _title_kit as K  # noqa: E402
import sb  # noqa: E402

CATEGORY = "title"


def frag(root, name, loc, rot=(0, 0, 0)):
    return sb.empty("frag_" + name, root, loc, rot)


def underside(f, rng, w, d, depth, tag, loc=(0, 0, 0)):
    """Inverted torn-earth cone hanging beneath a floor slab."""
    bm = sb.bm_rock(rng, (w, d, depth * 2.0), cuts=6, subdiv=2, flat_bottom=True)
    sb.bm_xform(bm, rot=(180, 0, 0))
    lo, hi = sb.bm_bounds(bm)
    import bmesh
    bmesh.ops.translate(bm, verts=bm.verts, vec=(loc[0], loc[1], loc[2] - hi.z))
    # stretch the lower half into a ragged point
    for v in bm.verts:
        t = (loc[2] - v.co.z) / max(depth, 0.1)
        if t > 0.3:
            k = 1.0 - min(0.6, (t - 0.3) * 0.6)
            v.co.x = loc[0] + (v.co.x - loc[0]) * k
            v.co.y = loc[1] + (v.co.y - loc[1]) * k
    sb.bm_obj(tag, f, bm, K.M("Title_StoneRock"), sharp=40)
    # dangling shards
    for i in range(5):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.15, 0.4)
        K.rock(f"{tag}_dang{i}", f, rng, (w * r * 0.4, d * r * 0.4, depth * rng.uniform(0.3, 0.6)),
               loc=(loc[0] + math.cos(a) * w * r, loc[1] + math.sin(a) * d * r,
                    loc[2] - depth * rng.uniform(0.35, 0.7)), rot=(180, rng.uniform(-15, 15), 0))


def nave(root, rng):
    """Central fragment: three bays of arcade + clerestory with lancets, broken on the right."""
    f = frag(root, "nave", (0, 0, 0), (0, 0, 4))
    W, D = 54.0, 22.0
    K.block("floor", f, rng, (W, D, 3.0), loc=(0, 0, -1.5), mat="Title_MarbleDark", chips=4)
    underside(f, rng, W * 0.95, D * 1.1, 34.0, "under", (0, 0, -3.0))
    bay = 14.0
    pier_h = 18.0
    for row, y in (("f", -D * 0.32), ("b", D * 0.32)):
        for i, x in enumerate((-21.0, -7.0, 7.0, 21.0)):
            h = pier_h
            broken = 0.0
            if x > 15:  # right end shattered
                h = pier_h * (0.45 if row == "f" else 0.7)
                broken = 2.0
            K.column(f"pier{row}{i}", f, rng, 1.5, h, loc=(x, y, 0), flutes=6, broken_top=broken)
            K.block(f"base{row}{i}", f, rng, (4.0, 4.0, 1.6), loc=(x, y, 0.8), chips=2)
            if h >= pier_h:
                K.block(f"cap{row}{i}", f, rng, (4.2, 4.2, 1.2), loc=(x, y, h + 0.6), chips=1)
        # arches between piers (right bay collapsed)
        for i, cx in enumerate((-14.0, 0.0)):
            K.pointed_arch(f, rng, cx, pier_h + 1.2, bay - 1.0, 1.8, 3.0, y=y, tag=f"arc{row}{i}_",
                           drop=((5,) if (row == "f" and i == 1) else ()))
        K.pointed_arch(f, rng, 14.0, pier_h + 1.2, bay - 1.0, 1.8, 3.0, y=y, tag=f"arc{row}2_",
                       drop=(2, 3, 4, 5) if row == "f" else (4, 5))
        # clerestory wall over the two intact bays with three lancets each
        wall_z0 = pier_h + 1.2 + (bay - 1.0) * math.sin(math.radians(60)) + 1.5
        wall_h = 16.0
        for i, cx in enumerate((-14.0, 0.0)):
            if row == "f" and i == 1:
                wall_h_i = wall_h * 0.6
            else:
                wall_h_i = wall_h
            for k in (-1, 0, 1):
                lx = cx + k * 4.2
                # glowing lancet glass, set slightly back
                K.pointed_arch(f, rng, lx, wall_z0 + wall_h_i * 0.62, 2.4, 0.5, 1.6, y=y,
                               tag=f"lan{row}{i}{k}_", pieces=2)
                sb.box(f"glass{row}{i}{k}", f, (2.2, 0.3, wall_h_i * 0.55), loc=(lx, y + 0.4, wall_z0
                       + 1.2 + wall_h_i * 0.275), material=K.M("Title_HolyGlass"), bevel=0.0)
                sb.box(f"glasstop{row}{i}{k}", f, (1.3, 0.3, 1.6), loc=(lx, y + 0.4, wall_z0 + wall_h_i * 0.62
                       + 1.0), material=K.M("Title_HolyGlass"), bevel=0.0)
            # wall slabs between lancets
            for k in (-1.5, -0.5, 0.5, 1.5):
                K.block(f"mull{row}{i}{k}", f, rng, (2.0, 2.4, wall_h_i), loc=(cx + k * 4.2, y, wall_z0
                        + wall_h_i * 0.5), chips=2, cracks=1)
            K.block(f"sill{row}{i}", f, rng, (bay, 2.6, 1.4), loc=(cx, y, wall_z0 + 0.7), chips=2)
            K.block(f"cornice{row}{i}", f, rng, (bay + 0.6, 3.0, 1.2), loc=(cx, y, wall_z0 + wall_h_i + 0.6),
                    chips=3)
            # pinnacles on the cornice
            for k in (-0.5, 0.5):
                K.spire(f"pin{row}{i}{k}", f, rng, 0.9, 7.0, loc=(cx + k * bay, y, wall_z0 + wall_h_i + 1.2),
                        sides=6, broken=0.0 if rng.random() < 0.6 else 0.6)
    # roof: two broken pitched slabs over the left bay (ridge along X)
    roof_z = pier_h + 1.2 + (bay - 1.0) * math.sin(math.radians(60)) + 1.5 + 16.0 + 1.2
    for s in (-1, 1):
        K.block(f"roof{s}", f, rng, (bay * 2.0, D * 0.42, 1.0), loc=(-7.0, s * D * 0.18, roof_z + 4.0),
                rot=(-s * 34, 0, 0), chips=4, step=3.0)
    # flying buttresses on the front
    for i, x in enumerate((-21.0, -7.0)):
        K.block(f"butpier{i}", f, rng, (2.6, 3.0, 26.0), loc=(x, -D * 0.5 - 6.0, 13.0), chips=2, taper=(0.8, 0.8))
        K.spire(f"butpin{i}", f, rng, 1.3, 8.0, loc=(x, -D * 0.5 - 6.0, 26.0), sides=6)
        # flyer arc in the YZ plane: an empty turned 90 deg about Z maps local X -> world Y
        e = sb.empty(f"flyrot{i}", f, (x, 0, 0), (0, 0, 90))
        K.arc_piece(f"fly{i}", e, (-D * 0.5 + 4.0, 16.0), 10.0, 11.6, 95.0, 172.0, 1.6, 0.0, rng=rng)
    # loose masonry on the floor
    for i in range(10):
        K.block(f"loose{i}", f, rng, (rng.uniform(1.5, 3.5), rng.uniform(1.2, 2.5), rng.uniform(0.8, 1.6)),
                loc=(rng.uniform(10, 26), rng.uniform(-9, 9), 0.6), rot=(rng.uniform(-20, 20), rng.uniform(-20, 20),
                                                                         rng.uniform(0, 360)))
    sb.join_meshes(f, "nave_mesh")



def tower(root, rng):
    """Broken bell tower with a snapped spire, tilted and drifting to the left."""
    f = frag(root, "tower", (-52, 14, 6), (8, -14, -10))
    K.block("tfloor", f, rng, (13.0, 13.0, 2.5), loc=(0, 0, -1.25), mat="Title_MarbleDark")
    underside(f, rng, 13.0, 13.0, 22.0, "tunder", (0, 0, -2.5))
    H = 34.0
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.block(f"corner{sx}{sy}", f, rng, (2.6, 2.6, H), loc=(sx * 4.6, sy * 4.6, H * 0.5), chips=3,
                    cracks=1)
            K.spire(f"tpin{sx}{sy}", f, rng, 1.2, 9.0, loc=(sx * 4.6, sy * 4.6, H), sides=6,
                    broken=0.55 if (sx + sy) == 0 else 0.0)
    for side, (x, y, sx, sy) in enumerate(((0, -4.6, 7.0, 2.0), (0, 4.6, 7.0, 2.0), (-4.6, 0, 2.0, 7.0),
                                           (4.6, 0, 2.0, 7.0))):
        K.block(f"twall_lo{side}", f, rng, (sx, sy, H * 0.45), loc=(x, y, H * 0.225), chips=2)
        K.block(f"twall_hi{side}", f, rng, (sx, sy, H * 0.12), loc=(x, y, H * 0.94), chips=2)
        gsize = (sx * 0.55, 0.4, H * 0.36) if sx > sy else (0.4, sy * 0.55, H * 0.36)
        sb.box(f"tglass{side}", f, gsize, loc=(x * 0.92, y * 0.92, H * 0.66),
               material=K.M("Title_HolyGlass"), bevel=0.0)
        if sx > sy:
            K.pointed_arch(f, rng, 0.0, H * 0.78, 4.2, 0.9, sy, y=y, tag=f"tarch{side}_", pieces=2)
    K.spire("tspire", f, rng, 6.4, 38.0, loc=(0, 0, H + 0.5), sides=8, broken=0.72)
    # the snapped-off spire tip floats nearby
    K.spire("ttip", f, rng, 2.3, 12.0, loc=(6.0, -3.0, H + 38.0 * 0.8), rot=(24, -30, 0), sides=8)
    sb.join_meshes(f, "tower_mesh")


def rose(root, rng):
    """Shattered rose window: a stone ring with tracery and glowing glass, a quarter missing."""
    f = frag(root, "rose", (50, 6, 26), (12, 0, -22))  # ring lies in the XZ plane = faces the viewer
    R = 13.0
    # ring built in XZ (arc_piece), rotated by the frag so it faces the viewer
    pieces = 14
    for i in range(pieces):
        if i in (3, 4, 5):
            continue
        a0 = i * 360.0 / pieces
        K.arc_piece(f"ring{i}", f, (0.0, 0.0), R, R + 2.2, a0 + 0.6, a0 + 360.0 / pieces - 0.6, 3.0,
                    rng=rng, slices=4)
    K.arc_piece("inner", f, (0.0, 0.0), 3.0, 4.2, 0.0, 359.0, 2.0, rng=rng, slices=16)
    for i in range(12):
        a = math.radians(i * 30.0 + 15.0)
        if 75 < math.degrees(a) < 170:
            continue
        p0 = (math.cos(a) * 4.2, 0.0, math.sin(a) * 4.2)
        p1 = (math.cos(a) * R, 0.0, math.sin(a) * R)
        sb.ptube(f"spoke{i}", f, [p0, p1], [0.55, 0.45], sides=5, material=K.M("Title_Marble"))
    # glowing glass behind (a disc with a missing wedge)
    import bmesh
    bm = bmesh.new()
    seg = 36
    verts = [bm.verts.new((0, 0.9, 0))]
    for i in range(seg + 1):
        a = math.radians(i * 360.0 / seg)
        if 70 < math.degrees(a) < 175:
            continue
        verts.append(bm.verts.new((math.cos(a) * R, 0.9, math.sin(a) * R)))
    for a, b in zip(verts[1:-1], verts[2:]):
        try:
            bm.faces.new((verts[0], a, b))
        except ValueError:
            pass
    sb.bm_obj("roseglass", f, bm, K.M("Title_HolyGlass"), sharp=None)
    sb.join_meshes(f, "rose_mesh")


def debris(root, rng):
    """Floating chunks: masonry, drums, a broken arch, rocks (each its own drifting fragment)."""
    spots = [(-24, -14, 52), (18, -8, 50), (36, -18, -14), (-38, -10, -18), (66, 10, -4), (-70, 4, 30),
             (8, -22, -30), (-8, 18, 64), (82, 20, 40), (-86, 20, -10), (28, -26, 26), (-18, -28, 16),
             (54, -20, 58), (-58, -16, 60)]
    for i, (x, y, z) in enumerate(spots):
        f = frag(root, f"debris{i}", (x, y, z), (rng.uniform(-40, 40), rng.uniform(-40, 40), rng.uniform(0, 360)))
        kind = i % 4
        s = rng.uniform(0.7, 1.5)
        if kind == 0:
            K.block(f"d{i}", f, rng, (5.0 * s, 3.0 * s, 2.4 * s), chips=3, cracks=1)
            K.rock(f"d{i}r", f, rng, (4.0 * s, 2.6 * s, 3.0 * s), loc=(0, 0, -2.6 * s), rot=(180, 0, 0),
                   flat_bottom=True)
        elif kind == 1:
            K.column(f"d{i}", f, rng, 1.4 * s, 6.0 * s, loc=(0, 0, -3.0 * s), flutes=6, broken_top=1.5 * s)
        elif kind == 2:
            K.pointed_arch(f, rng, 0.0, 0.0, 8.0 * s, 1.4 * s, 2.4 * s, tag=f"d{i}a", pieces=2, drop=(3,))
        else:
            K.rock(f"d{i}", f, rng, (5.0 * s, 4.0 * s, 4.0 * s), subdiv=2, mat="Title_StoneRock")
            K.block(f"d{i}b", f, rng, (3.4 * s, 3.4 * s, 1.0 * s), loc=(0, 0, 3.2 * s), chips=2)
        sb.join_meshes(f, f"debris{i}_mesh")


def build():
    root = sb.root("SkyCathedral")
    rng = K.rng_for(77)
    nave(root, rng)
    tower(root, rng)
    rose(root, rng)
    debris(root, rng)
    sb.tri_count(root)
    return root
