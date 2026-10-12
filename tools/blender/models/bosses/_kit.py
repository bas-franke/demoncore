"""Extra modeling helpers for the boss / pickup models (kept out of sb.py to avoid edit clashes).

Import from a model script with:
    import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bosses"))
    import _kit as kit
"""
import math
import bpy
import bmesh
from mathutils import Euler, Matrix, Vector
import sb


def _obj(name, bm, parent, material, loc, rot, smooth, scale=(1, 1, 1)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return sb._finish(ob, parent, material, loc, rot, scale, 0.0, 0, smooth, name)


def lathe(name, parent, profile, segments=24, loc=(0, 0, 0), rot=(0, 0, 0), material=None,
          folds=0, fold_amp=0.0, cap_bottom=True, cap_top=True, smooth=True, scale=(1, 1, 1),
          phase=0.0):
    """Surface of revolution around local Z. profile = [(r, z) or (r, z, fold_weight)] bottom->top.
    `folds` radial sine folds of relative amplitude fold_amp * fold_weight (cloth, fluting)."""
    bm = bmesh.new()
    rings = []
    for p in profile:
        r, z = p[0], p[1]
        fw = p[2] if len(p) > 2 else 1.0
        ring = []
        for i in range(segments):
            a = math.tau * i / segments
            rr = r * (1.0 + fold_amp * fw * math.sin(folds * a + phase)) if folds else r
            ring.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z)))
        rings.append(ring)
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap_bottom and profile[0][0] > 1e-4:
        bm.faces.new(list(reversed(rings[0])))
    if cap_top and profile[-1][0] > 1e-4:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm, parent, material, loc, rot, smooth, scale)


FEATHER_ROWS = [(0.0, 0.14), (0.12, 0.75), (0.38, 1.0), (0.66, 0.86), (0.88, 0.48), (1.0, 0.03)]


def feather(name, parent, length=0.5, width=0.08, thickness=0.012, loc=(0, 0, 0), rot=(0, 0, 0),
            material=None, curve=0.08, asym=0.75):
    """Low-poly feather (44 tris) along +Z, flat in X, raised rachis ridge on +-Y; tip curls to +Y.
    The -X vane is `asym` x narrower (real flight feathers are asymmetric)."""
    bm = bmesh.new()
    rows = []
    for t, wf in FEATHER_ROWS:
        w = width * wf
        z = t * length
        y = curve * t * t * length
        rows.append([bm.verts.new((-w * asym, y, z)), bm.verts.new((0, y + thickness, z)),
                     bm.verts.new((w, y, z)), bm.verts.new((0, y - thickness, z))])
    for a, b in zip(rows[:-1], rows[1:]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm, parent, material, loc, rot, True)


def filigree(name, parent, points, radius=0.012, material=None, res=3, radii=None):
    """Thin, cheap tube along a smooth curve through `points` (gold filigree, wire, trim)."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 0
    cu.resolution_u = res
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for i, (bp, p) in enumerate(zip(sp.bezier_points, points)):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
        bp.radius = radii[i] if radii else 1.0
    ob = bpy.data.objects.new(name + "_curve", cu)
    bpy.context.scene.collection.objects.link(ob)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    mo = bpy.context.active_object
    return sb._finish(mo, parent, material, (0, 0, 0), (0, 0, 0), (1, 1, 1), 0.0, 0, True, name)


def crystal(name, parent, height=0.3, radius=0.07, sides=5, top=0.72, loc=(0, 0, 0), rot=(0, 0, 0),
            material=None, jitter=0.18, seed=1, scale=(1, 1, 1), cap=0.0):
    """Faceted bipyramid crystal along +Z (flat shaded). `top` = fraction of height above the girdle.
    `cap` > 0 makes a flat-ish terminated top (hexagonal prism look)."""
    import random
    rnd = random.Random(seed)
    bm = bmesh.new()
    zb = -height * (1.0 - top)
    zt = height * top
    girdle = []
    upper = []
    for i in range(sides):
        a = math.tau * i / sides + rnd.uniform(-0.2, 0.2)
        r = radius * (1.0 + rnd.uniform(-jitter, jitter))
        girdle.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0.0)))
        if cap > 0.0:
            r2 = r * 0.92
            upper.append(bm.verts.new((math.cos(a) * r2, math.sin(a) * r2, zt * (1.0 - cap))))
    vb = bm.verts.new((rnd.uniform(-0.15, 0.15) * radius, rnd.uniform(-0.15, 0.15) * radius, zb))
    vt = bm.verts.new((rnd.uniform(-0.25, 0.25) * radius, rnd.uniform(-0.25, 0.25) * radius, zt))
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((girdle[j], girdle[i], vb))
        if cap > 0.0:
            bm.faces.new((girdle[i], girdle[j], upper[j], upper[i]))
            bm.faces.new((upper[i], upper[j], vt))
        else:
            bm.faces.new((girdle[i], girdle[j], vt))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm, parent, material, loc, rot, False, scale)


def keep_world_rot(chain_rots, world_rot=(0, 0, 0)):
    """Local XYZ euler (deg) for a child under a chain of joint rotations (deg, each XYZ) so the
    child ends up with `world_rot` relative to the chain's base frame (e.g. a spear kept upright)."""
    m = Matrix.Identity(3)
    for r in chain_rots:
        m = m @ Euler([math.radians(a) for a in r]).to_matrix()
    loc = m.inverted() @ Euler([math.radians(a) for a in world_rot]).to_matrix()
    return tuple(math.degrees(a) for a in loc.to_euler("XYZ"))


def merge_joint_meshes(root, keep=()):
    """For every joint (EMPTY) under `root`, joins its direct MESH children into one mesh object
    (modifiers applied first). Names in `keep` stay separate. Cuts the node / draw-call count."""
    groups = []
    stack = [root]
    while stack:
        o = stack.pop()
        stack.extend(o.children)
        if o.type == "EMPTY":
            meshes = [c for c in o.children if c.type == "MESH" and c.name not in keep]
            if len(meshes) > 1:
                groups.append((o, meshes))
    for joint, meshes in groups:
        for x in bpy.context.selected_objects:
            x.select_set(False)
        for m in meshes:
            m.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.convert(target="MESH")
        bpy.ops.object.join()
        j = bpy.context.active_object
        j.name = joint.name + "_mesh"
        j.data.name = j.name


def tri_count(root=None):
    n = 0
    dg = bpy.context.evaluated_depsgraph_get()
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            me = o.evaluated_get(dg).to_mesh()
            n += sum(len(p.vertices) - 2 for p in me.polygons)
            o.evaluated_get(dg).to_mesh_clear()
    return n
