"""SINBOUND Blender modeling kit (bpy, Blender 5.x).

Every model script in tools/blender/models/<category>/<name>.py defines:

    CATEGORY = "enemies"            # output folder under res://assets/models/
    def build():                    # create the model in the (already empty) scene
        root = sb.root("ChoirWisp")  # top-level empty; everything is parented under it
        ...
        sb.anim(...)                 # optional named animations (idle, walk, attack, hit, death...)
        return root

and is exported by build.py to res://assets/models/<CATEGORY>/<name>.glb.

Conventions (Godot side relies on them):
  * Units = meters; +Y up in Godot (export_yup). Model FORWARD = Blender -Y.
    (Blender +Z up, character faces -Y; feet at Z=0.) NOTE: glTF export maps Blender -Y to
    Godot +Z, so the Godot side turns imported models by PI about Y to face Godot's forward (-Z)
    (EnemyModel.use_glb, DemonModel.build, SarielModel, Reliquary do this).
  * Animated joints are EMPTY objects in a parent hierarchy; meshes are children of joints.
    Animations key joint loc/rot/scale. Each animation is an NLA track named exactly
    "idle", "walk", "attack", "windup", "hit", "death", ... (exported with NLA_TRACKS mode,
    so all objects' tracks with the same name merge into one Godot animation).
  * Loop animations: name them as-is; Godot side loops idle/walk/fly automatically.
  * Materials: Principled BSDF only (base color, roughness, metallic, emission). Godot converts
    them to the game's lit shader at runtime (GlbModel), so keep materials simple and named.
"""
import math
import bpy
import bmesh
from mathutils import Vector, Euler

# ----------------------------------------------------------------------------- scene

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.objects, bpy.data.actions,
                 bpy.data.curves):
        for item in list(coll):
            coll.remove(item)
    sc = bpy.context.scene
    sc.render.fps = 30
    sc.frame_start = 0
    sc.frame_end = 60


def _link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def root(name):
    """Top-level empty that owns the whole model."""
    return empty(name, None)


def empty(name, parent, loc=(0, 0, 0), rot=(0, 0, 0)):
    """A joint. `rot` in degrees (XYZ)."""
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.1
    _link(e)
    if parent is not None:
        e.parent = parent
    e.location = loc
    e.rotation_euler = Euler([math.radians(a) for a in rot])
    return e


# ----------------------------------------------------------------------------- materials

def mat(name, color, roughness=0.7, metallic=0.0, emission=None, strength=0.0):
    """Principled material. `color` = (r, g, b) 0..1 (sRGB-ish), emission color + strength."""
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None and strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return m


# ----------------------------------------------------------------------------- meshes

def _finish(obj, parent, material, loc, rot, scale, bevel, subdiv, smooth, name):
    obj.name = name
    if parent is not None:
        obj.parent = parent
    obj.location = loc
    obj.rotation_euler = Euler([math.radians(a) for a in rot])
    obj.scale = scale
    if material is not None:
        obj.data.materials.clear()
        obj.data.materials.append(material)
    if bevel > 0.0:
        b = obj.modifiers.new("Bevel", "BEVEL")
        b.width = bevel
        b.segments = 2
        b.limit_method = "ANGLE"
    if subdiv > 0:
        s = obj.modifiers.new("Subsurf", "SUBSURF")
        s.levels = subdiv
        s.render_levels = subdiv
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    return obj


def _new_mesh_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return _link(bpy.data.objects.new(name, me))


def box(name, parent, size=(1, 1, 1), loc=(0, 0, 0), rot=(0, 0, 0), material=None,
        bevel=0.02, subdiv=0, taper=None):
    """Box with `size` (x, y, z). `taper` = (sx, sy) scales the top face (wedges, plates)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
        if taper is not None and v.co.z > 0:
            v.co.x *= taper[0]
            v.co.y *= taper[1]
    obj = _new_mesh_obj(name, bm)
    return _finish(obj, parent, material, loc, rot, (1, 1, 1), bevel, subdiv, subdiv > 0, name)


def sphere(name, parent, radius=0.5, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1),
           material=None, segments=24, rings=12):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    obj = _new_mesh_obj(name, bm)
    return _finish(obj, parent, material, loc, rot, scale, 0.0, 0, True, name)


def cylinder(name, parent, r1=0.5, r2=None, depth=1.0, loc=(0, 0, 0), rot=(0, 0, 0),
             scale=(1, 1, 1), material=None, segments=16, bevel=0.01, smooth=True):
    """Cylinder/cone along local Z, base at z=0 (grows +Z). r2 = top radius (cone if 0)."""
    if r2 is None:
        r2 = r1
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=r1, radius2=r2, depth=depth)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, depth * 0.5))
    obj = _new_mesh_obj(name, bm)
    o = _finish(obj, parent, material, loc, rot, scale, bevel, 0, smooth, name)
    if smooth:
        o.data.shade_auto_smooth() if hasattr(o.data, "shade_auto_smooth") else None
    return o


def torus(name, parent, major=0.5, minor=0.05, loc=(0, 0, 0), rot=(0, 0, 0), material=None,
          major_segments=32, minor_segments=8):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=major_segments, minor_segments=minor_segments)
    obj = bpy.context.active_object
    return _finish(obj, parent, material, loc, rot, (1, 1, 1), 0.0, 0, True, name)


def tube(name, parent, points, radii, material=None, segments=10, loc=(0, 0, 0)):
    """Tapered tube along a polyline (horns, tails, chains of bone, tentacles, spears).
    `points` = list of (x, y, z) in parent space, `radii` = one radius per point."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 1.0
    cu.bevel_resolution = max(1, segments // 4)
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for bp, p, r in zip(sp.bezier_points, points, radii):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
        bp.radius = r
    ob = _link(bpy.data.objects.new(name + "_curve", cu))
    # convert to mesh so it exports as geometry
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    mo = bpy.context.active_object
    return _finish(mo, parent, material, loc, (0, 0, 0), (1, 1, 1), 0.0, 0, True, name)


def blade(name, parent, length=1.0, width=0.12, thickness=0.02, loc=(0, 0, 0), rot=(0, 0, 0),
          material=None, curve=0.0):
    """Flat tapered blade/feather along +Z (tip at z=length). `curve` bends the tip along +Y."""
    bm = bmesh.new()
    steps = 6
    prev = None
    rows = []
    for i in range(steps + 1):
        t = i / steps
        w = width * (1.0 - t ** 1.6) + 0.002
        z = t * length
        y = curve * t * t * length
        row = [bm.verts.new((-w, y - thickness, z)), bm.verts.new((w, y - thickness, z)),
               bm.verts.new((w, y + thickness, z)), bm.verts.new((-w, y + thickness, z))]
        rows.append(row)
    for a, b in zip(rows[:-1], rows[1:]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = _new_mesh_obj(name, bm)
    return _finish(obj, parent, material, loc, rot, (1, 1, 1), 0.0, 0, True, name)


def mirror_x(obj):
    """Add a mirror modifier across the parent's X (for symmetric pieces modeled on one side)."""
    m = obj.modifiers.new("Mirror", "MIRROR")
    m.use_axis[0] = True
    return obj


def displace(obj, strength=0.03, scale=0.6):
    """Organic lumpiness / weathering via a cloud-texture displace."""
    tex = bpy.data.textures.new(obj.name + "_noise", "CLOUDS")
    tex.noise_scale = scale
    d = obj.modifiers.new("Displace", "DISPLACE")
    d.texture = tex
    d.strength = strength
    return obj


# ----------------------------------------------------------------------------- animation

def anim(name, keys, frames=30):
    """Create one named animation.

    keys = { joint_object: [(frame, {"rot": (x,y,z deg), "loc": (x,y,z), "scale": (x,y,z)}), ...], ... }
    Any channel left out of a key is not keyed. Frames are at 30 fps.
    For looping clips make the last key equal the first.
    """
    for obj, klist in keys.items():
        if obj.animation_data is None:
            obj.animation_data_create()
        rest_rot = obj.rotation_euler.copy()
        rest_loc = obj.location.copy()
        rest_scale = obj.scale.copy()
        act = bpy.data.actions.new(f"{obj.name}_{name}")
        obj.animation_data.action = act
        for frame, ch in klist:
            if "rot" in ch:
                obj.rotation_euler = Euler([math.radians(a) for a in ch["rot"]])
                obj.keyframe_insert("rotation_euler", frame=frame)
            if "loc" in ch:
                obj.location = ch["loc"]
                obj.keyframe_insert("location", frame=frame)
            if "scale" in ch:
                obj.scale = ch["scale"]
                obj.keyframe_insert("scale", frame=frame)
        track = obj.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, int(act.frame_range[0]), act)
        strip.name = name
        obj.animation_data.action = None
        obj.rotation_euler = rest_rot
        obj.location = rest_loc
        obj.scale = rest_scale


def rest(obj):
    """Current rest transform as a key dict (handy for loop start/end keys)."""
    return {"rot": tuple(math.degrees(a) for a in obj.rotation_euler),
            "loc": tuple(obj.location), "scale": tuple(obj.scale)}


def offset(obj, rot=(0, 0, 0), loc=(0, 0, 0), scale=None):
    """Rest transform plus an offset, as a key dict."""
    r = rest(obj)
    r["rot"] = tuple(a + b for a, b in zip(r["rot"], rot))
    r["loc"] = tuple(a + b for a, b in zip(r["loc"], loc))
    if scale is not None:
        r["scale"] = scale
    return r


# ----------------------------------------------------------------------------- bmesh kit (props / ruins)
# Everything below builds geometry directly in bmesh (no modifiers to apply), so chamfers, chips,
# cracks and weathering noise are baked into the exported mesh. Typical flow:
#     bm = sb.bm_box((1, 0.6, 2), slices=(4, 3, 8))
#     sb.bm_chip(bm, rng, 3, 0.12); sb.bm_crack(bm, rng); sb.bm_bevel(bm, 0.03)
#     sb.bm_noise(bm, 0.02, 2.0, seed=1)
#     sb.bm_obj("Block", parent, bm, material, loc=(0, 0, 1))
from mathutils import noise as _noise  # noqa: E402


def bm_box(size=(1, 1, 1), slices=(1, 1, 1), z0=False):
    """Box bmesh centred at the origin (or with its base at z=0 if `z0`), cut into a grid of
    `slices` segments per axis (needed so noise/cracks have vertices to move)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    for axis in range(3):
        n = max(1, int(slices[axis]))
        for i in range(1, n):
            co = [0.0, 0.0, 0.0]
            co[axis] = -size[axis] * 0.5 + size[axis] * i / n
            no = [0.0, 0.0, 0.0]
            no[axis] = 1.0
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                                   plane_co=co, plane_no=no)
    if z0:
        bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, size[2] * 0.5))
    return bm


def bm_auto_slices(size, step=0.25, lo=1, hi=12):
    """Slice counts so grid cells are roughly `step` meters."""
    return tuple(max(lo, min(hi, int(round(s / step)))) for s in size)


def bm_cut(bm, co, no, fill=True):
    """Cuts away everything on the +`no` side of the plane and caps the hole. Returns cap faces."""
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                           plane_co=co, plane_no=no, clear_outer=True)
    if not fill:
        return []
    edges = [e for e in bm.edges if e.is_boundary]
    if not edges:
        return []
    return bmesh.ops.holes_fill(bm, edges=edges, sides=0)["faces"]


def bm_bounds(bm):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for v in bm.verts:
        lo = Vector((min(lo.x, v.co.x), min(lo.y, v.co.y), min(lo.z, v.co.z)))
        hi = Vector((max(hi.x, v.co.x), max(hi.y, v.co.y), max(hi.z, v.co.z)))
    return lo, hi


def bm_chip(bm, rng, count=3, depth=0.1, skip_bottom=True, rough=0.0):
    """Knocks `count` chips off corners/edges of the mesh's bounding box (planar breaks).
    `rough` > 0 roughens the fresh break faces."""
    caps = []
    for _ in range(count):
        lo, hi = bm_bounds(bm)
        size = hi - lo
        sgn = [rng.choice((-1.0, 1.0)) for _ in range(3)]
        if skip_bottom:
            sgn[2] = 1.0 if rng.random() < 0.8 else rng.choice((-1.0, 1.0))
        c = Vector([(lo[k] if sgn[k] < 0 else hi[k]) for k in range(3)])
        n = Vector(sgn)
        if rng.random() < 0.5:  # edge chip instead of corner chip
            k = rng.randrange(3)
            n[k] = 0.0
            c[k] = lo[k] + size[k] * rng.uniform(0.2, 0.8)
        n += Vector((rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35)))
        if n.length < 0.1:
            continue
        n.normalize()
        d = depth * rng.uniform(0.6, 1.3)
        caps += bm_cut(bm, c - n * d, n)
    caps = [f for f in caps if f.is_valid]
    if rough > 0.0 and caps:
        bm_roughen(bm, caps, rng, rough)
    return caps


def bm_roughen(bm, faces, rng, amount=0.05, inset=0.3):
    """Turns flat (break) faces into a jagged fracture: inset + poke, jittered along the normal."""
    faces = [f for f in faces if f.is_valid and len(f.verts) >= 3]
    if not faces:
        return
    for f in faces:
        if not f.is_valid:
            continue
        nrm = f.normal.copy()
        rad = max((v.co - f.calc_center_median()).length for v in f.verts)
        res = bmesh.ops.inset_individual(bm, faces=[f], thickness=rad * inset, depth=0.0)
        inner = [g for g in res["faces"]]
        if f.is_valid:
            for v in f.verts:
                v.co += nrm * rng.uniform(-amount, amount)
            pk = bmesh.ops.poke(bm, faces=[f])
            for v in pk["verts"]:
                v.co += nrm * rng.uniform(-amount * 1.6, amount * 1.2)
        del inner


def bm_crack(bm, rng, count=1, depth=0.025, width=0.012, axis=None):
    """Thin V-groove cracks: three close parallel cuts, the middle one pushed into the surface."""
    for _ in range(count):
        lo, hi = bm_bounds(bm)
        c = lo + Vector([(hi[k] - lo[k]) * rng.uniform(0.25, 0.75) for k in range(3)])
        if axis is None:
            n = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        else:
            n = Vector(axis) + Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4)))
        if n.length < 0.1:
            continue
        n.normalize()
        for o in (-width, width):
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                                   plane_co=c + n * o, plane_no=n)
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                                     plane_co=c, plane_no=n)
        bm.normal_update()
        for v in [g for g in res["geom_cut"] if isinstance(g, bmesh.types.BMVert)]:
            v.co -= v.normal * depth * rng.uniform(0.6, 1.2)


def bm_bevel(bm, width=0.03, angle=30.0):
    """Chamfers edges sharper than `angle` degrees (1 segment)."""
    lim = math.radians(angle)
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim]
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=width, segments=1, affect="EDGES", clamp_overlap=True,
                        profile=0.5)


def bm_noise(bm, strength=0.02, scale=2.0, seed=0, verts=None, axis_scale=(1, 1, 1)):
    """Weathering: two-octave Perlin displacement along vertex normals."""
    bm.normal_update()
    off = Vector((seed * 13.71, seed * 7.31, seed * 3.17))
    moves = []
    for v in (verts if verts is not None else bm.verts):
        p = Vector((v.co.x * axis_scale[0], v.co.y * axis_scale[1], v.co.z * axis_scale[2])) * scale + off
        n = _noise.noise(p) + 0.45 * _noise.noise(p * 2.7 + Vector((5.1, 1.3, 2.9)))
        moves.append((v, v.normal * (n * strength)))
    for v, d in moves:
        v.co += d


def bm_dent(bm, center, radius, depth):
    """Pushes vertices near `center` inward along their normals (eye sockets, chisel marks)."""
    bm.normal_update()
    c = Vector(center)
    for v in bm.verts:
        d = (v.co - c).length
        if d < radius:
            v.co -= v.normal * depth * (1.0 - (d / radius) ** 2)


def bm_xform(bm, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    from mathutils import Matrix
    m = (Matrix.Translation(loc) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4()
         @ Matrix.Diagonal((*scale, 1.0)))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm


def bm_merge(dst, src):
    """Appends bmesh `src` into `dst` (src is freed)."""
    me = bpy.data.meshes.new("_tmp_merge")
    src.to_mesh(me)
    src.free()
    dst.from_mesh(me)
    bpy.data.meshes.remove(me)
    return dst


def bm_lathe(profile, segments=12, cap_bottom=True, cap_top=True, wobble=None):
    """Surface of revolution around Z. `profile` = [(radius, z), ...] bottom->top.
    Radius 0 makes a pole. `wobble(angle, t) -> radius multiplier` (folds, flutes, drips)."""
    bm = bmesh.new()
    rows = []
    n = len(profile)
    for i, (r, z) in enumerate(profile):
        if r <= 1e-6:
            rows.append([bm.verts.new((0, 0, z))])
            continue
        row = []
        for j in range(segments):
            a = 2 * math.pi * j / segments
            rr = r * (wobble(a, i / max(1, n - 1)) if wobble else 1.0)
            row.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z)))
        rows.append(row)
    for a, b in zip(rows[:-1], rows[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:
            for j in range(segments):
                bm.faces.new((a[0], b[j], b[(j + 1) % segments]))
        elif len(b) == 1:
            for j in range(segments):
                bm.faces.new((a[j], a[(j + 1) % segments], b[0]))
        else:
            for j in range(segments):
                bm.faces.new((a[j], a[(j + 1) % segments], b[(j + 1) % segments], b[j]))
    if cap_bottom and len(rows[0]) > 1:
        bm.faces.new(list(reversed(rows[0])))
    if cap_top and len(rows[-1]) > 1:
        bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def bm_column(radius=0.4, height=1.0, segments=16, rings=4, flutes=0, flute_depth=0.08, taper=0.0):
    """Column drum (base at z=0). `flutes` concave channels (use segments = 4 * flutes)."""
    def wob(a, t):
        if flutes <= 0:
            return 1.0
        return 1.0 - flute_depth * max(0.0, math.cos(flutes * a))
    prof = [(radius * (1.0 - taper * (i / rings)), height * i / rings) for i in range(rings + 1)]
    return bm_lathe(prof, segments, True, True, wob)


def bm_limb(points, radii, sides=7, samples=2, rng=None, gnarl=0.0, cap_end=True):
    """Organic tube along a Catmull-Rom spline (branches, roots, bones, arms).
    `samples` rings per input segment, `gnarl` = random radius jitter (0..0.4)."""
    P = [Vector(p) for p in points]
    R = list(radii)
    pts, rs = [], []
    for i in range(len(P) - 1):
        p0 = P[i - 1] if i > 0 else P[i] * 2 - P[i + 1]
        p1, p2 = P[i], P[i + 1]
        p3 = P[i + 2] if i + 2 < len(P) else P[i + 1] * 2 - P[i]
        for s in range(samples):
            t = s / samples
            t2, t3 = t * t, t * t * t
            pts.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
            rs.append(R[i] + (R[i + 1] - R[i]) * t)
    pts.append(P[-1])
    rs.append(R[-1])
    bm = bmesh.new()
    rows = []
    prev_n = None
    for i, p in enumerate(pts):
        tan = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)])
        if tan.length < 1e-6:
            tan = Vector((0, 0, 1))
        tan.normalize()
        if prev_n is None:
            ref = Vector((0, 0, 1)) if abs(tan.z) < 0.9 else Vector((1, 0, 0))
            nrm = tan.cross(ref).normalized()
        else:
            nrm = (prev_n - tan * prev_n.dot(tan)).normalized()
        prev_n = nrm
        bin_ = tan.cross(nrm)
        row = []
        for j in range(sides):
            a = 2 * math.pi * j / sides
            rr = rs[i] * (1.0 + (rng.uniform(-gnarl, gnarl) if (rng and gnarl > 0) else 0.0))
            row.append(bm.verts.new(p + (nrm * math.cos(a) + bin_ * math.sin(a)) * rr))
        rows.append(row)
    for a, b in zip(rows[:-1], rows[1:]):
        for j in range(sides):
            bm.faces.new((a[j], a[(j + 1) % sides], b[(j + 1) % sides], b[j]))
    bm.faces.new(list(reversed(rows[0])))
    if cap_end:
        bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def bm_rock(rng, size=(1, 1, 1), cuts=4, subdiv=1, noise=0.08, flat_bottom=True):
    """Angular broken stone: icosphere, scaled, with planar fracture cuts and noise."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=0.5)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    for _ in range(cuts):
        n = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.6, 1)))
        if n.length < 0.1:
            continue
        n.normalize()
        ext = abs(n.x) * size[0] * 0.5 + abs(n.y) * size[1] * 0.5 + abs(n.z) * size[2] * 0.5
        bm_cut(bm, n * ext * rng.uniform(0.45, 0.8), n)
    if flat_bottom:
        bm_cut(bm, (0, 0, -size[2] * 0.3), (0, 0, -1))
    bm_noise(bm, noise * min(size), 2.0 / max(min(size), 0.1), seed=rng.randrange(1000))
    lo, _hi = bm_bounds(bm)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, -lo.z))
    return bm


def bm_arc(bm, center, r_in, r_out, a0, a1):
    """Bends a unit-ish box (x in [-.5,.5] along the arc, z in [-.5,.5] radial, y = depth)
    into an arc segment in the XZ plane around `center` (angles in degrees, 0 = +X)."""
    c = Vector(center)
    for v in bm.verts:
        u = v.co.x + 0.5
        w = v.co.z + 0.5
        a = math.radians(a0 + (a1 - a0) * u)
        r = r_in + (r_out - r_in) * w
        v.co = Vector((c.x + math.cos(a) * r, v.co.y, c.z + math.sin(a) * r))
    return bm


def bm_obj(name, parent, bm, material=None, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1),
           sharp=35.0):
    """bmesh -> mesh object. Smooth shaded with edges sharper than `sharp` degrees split
    (so chamfers and breaks read crisp). sharp=None -> flat shading, 0 -> fully smooth."""
    bm.normal_update()
    for f in bm.faces:
        f.smooth = sharp is not None
    if sharp:
        lim = math.radians(sharp)
        for e in bm.edges:
            if len(e.link_faces) != 2 or e.calc_face_angle(0.0) > lim:
                e.smooth = False
    obj = _new_mesh_obj(name, bm)
    return _finish(obj, parent, material, loc, rot, scale, 0.0, 0, False, name)


def stone_block(name, parent, size, material, rng, loc=(0, 0, 0), rot=(0, 0, 0), chips=2,
                chip_depth=None, cracks=0, bevel=None, noise=None, step=0.22, z0=False, taper=None):
    """Weathered masonry block: grid-sliced box, chipped corners, cracks, chamfer, noise."""
    bm = bm_box(size, bm_auto_slices(size, step), z0=False)
    if taper is not None:
        for v in bm.verts:
            if v.co.z > 0:
                v.co.x *= taper[0]
                v.co.y *= taper[1]
    m = min(size)
    if chips:
        bm_chip(bm, rng, chips, chip_depth if chip_depth is not None else min(0.14, m * 0.3), rough=m * 0.04)
    if cracks:
        bm_crack(bm, rng, cracks, depth=m * 0.06)
    bm_bevel(bm, bevel if bevel is not None else min(0.04, m * 0.08))
    bm_noise(bm, noise if noise is not None else m * 0.035, 1.8, seed=rng.randrange(10000))
    if z0:
        bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, size[2] * 0.5))
    return bm_obj(name, parent, bm, material, loc, rot)


def variants(prefix, count, spacing=6.0):
    """`count` top-level variant roots named v0..vN (Godot picks one per instance; the root's
    own offset is ignored there - it only spreads them out for previews)."""
    return [empty(f"v{i}", None, loc=(i * spacing, 0, 0)) for i in range(count)]


def tri_report(label=""):
    """Prints triangle counts per top-level root (call at the end of build())."""
    totals = {}
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        r = o
        while r.parent is not None:
            r = r.parent
        dg = bpy.context.evaluated_depsgraph_get()
        me = o.evaluated_get(dg).to_mesh()
        t = sum(len(p.vertices) - 2 for p in me.polygons)
        o.evaluated_get(dg).to_mesh_clear()
        totals[r.name] = totals.get(r.name, 0) + t
    print(f"TRIS {label} " + " ".join(f"{k}={v}" for k, v in sorted(totals.items())))


# ----------------------------------------------------------------------------- export

def export(path):
    bpy.ops.object.select_all(action="SELECT")
    # The glTF exporter appends "/" to the output directory and then isdir()s it, which fails
    # for "\\?\" long-path-prefixed paths (build.py uses those). Export to a short temp path
    # and move the file into place instead.
    final = None
    if path.startswith("\\\\?\\"):
        import os
        import tempfile
        final = path
        path = os.path.join(tempfile.gettempdir(), "sb_export_%d.glb" % os.getpid())
    _export_gltf(path)
    if final is not None:
        import shutil
        shutil.move(path, final)


def _export_gltf(path):
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_frame_range=False,
        export_materials="EXPORT",
        export_extras=False,
        export_lights=False,
        export_cameras=False,
    )


# ----------------------------------------------------------------------------- extra helpers
# (added for weapons / menu set dressing; generic, usable by any model script)

def mesh_from(name, parent, verts, faces, material=None, loc=(0, 0, 0), rot=(0, 0, 0),
              smooth=False, bevel=0.0, subdiv=0):
    """Mesh from raw vertex / face index lists (parent space)."""
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in verts]
    for f in faces:
        try:
            bm.faces.new([vs[i] for i in f])
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = _new_mesh_obj(name, bm)
    return _finish(obj, parent, material, loc, rot, (1, 1, 1), bevel, subdiv, smooth, name)


def lathe(name, parent, profile, segments=24, material=None, loc=(0, 0, 0), rot=(0, 0, 0),
          scale=(1, 1, 1), smooth=True, jitter=0.0, seed=0, caps=True):
    """Surface of revolution around local Z. `profile` = [(radius, z), ...] bottom to top.
    A radius of 0 at either end closes it to a point. `jitter` roughens radii (weathered stone)."""
    import random
    rnd = random.Random(seed)
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r <= 1e-5:
            rings.append([bm.verts.new((0.0, 0.0, z))])
            continue
        ring = []
        for k in range(segments):
            a = 2.0 * math.pi * k / segments
            rr = r * (1.0 + rnd.uniform(-jitter, jitter))
            ring.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z)))
        rings.append(ring)
    for a, b in zip(rings[:-1], rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:
            for k in range(segments):
                bm.faces.new((a[0], b[k], b[(k + 1) % segments]))
        elif len(b) == 1:
            for k in range(segments):
                bm.faces.new((a[k], b[0], a[(k + 1) % segments]))
        else:
            for k in range(segments):
                bm.faces.new((a[k], a[(k + 1) % segments], b[(k + 1) % segments], b[k]))
    if caps and len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if caps and len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = _new_mesh_obj(name, bm)
    o = _finish(obj, parent, material, loc, rot, scale, 0.0, 0, smooth, name)
    if smooth and hasattr(o.data, "set_sharp_from_angle"):
        o.data.set_sharp_from_angle(angle=math.radians(40))
    return o


def extrude_outline(name, parent, outline, depth, material=None, loc=(0, 0, 0), rot=(0, 0, 0),
                    bevel=0.0, smooth=False):
    """Flat 2D outline [(x, y), ...] (counter-clockwise, in the XY plane) extruded along +Z by
    `depth`, centred on z=0. Good for blades, plates, tracery, rune stones."""
    n = len(outline)
    verts = [(x, y, -depth * 0.5) for x, y in outline] + [(x, y, depth * 0.5) for x, y in outline]
    faces = [list(reversed(range(n))), list(range(n, 2 * n))]
    for k in range(n):
        j = (k + 1) % n
        faces.append([k, j, n + j, n + k])
    return mesh_from(name, parent, verts, faces, material, loc, rot, smooth, bevel)


def descendants(root):
    out = []
    for o in root.children:
        out.append(o)
        out.extend(descendants(o))
    return out


def join_meshes(root, name="mesh"):
    """Applies modifiers and joins every mesh under `root` into ONE multi-material object
    (parented to root). Use for static props: one draw call per material in Godot."""
    objs = [o for o in descendants(root) if o.type == "MESH"]
    if not objs:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    j = bpy.context.active_object
    j.name = name
    j.data.name = name
    mw = j.matrix_world.copy()
    j.parent = root
    j.matrix_world = mw
    # drop now-empty helper empties under root (keep root itself)
    for o in descendants(root):
        if o.type == "EMPTY" and not o.children:
            bpy.data.objects.remove(o)
    return j


def tri_count(root=None):
    """Triangle count (modifiers applied) of all meshes, or those under `root`. Prints + returns."""
    dg = bpy.context.evaluated_depsgraph_get()
    objs = [o for o in (descendants(root) if root else bpy.context.scene.objects) if o.type == "MESH"]
    total = 0
    for o in objs:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        total += sum(len(p.vertices) - 2 for p in me.polygons)
        ev.to_mesh_clear()
    print(f"TRIS {root.name if root else 'scene'} = {total}")
    return total


def ptube(name, parent, points, radii, sides=5, material=None, smooth=True, caps=True):
    """Low-poly tube straight through `points` (no curve smoothing): sides * (n-1) quads.
    Cheap cracks, veins, chain bars, rods, tendrils."""
    pts = [Vector(p) for p in points]
    n = len(pts)
    bm = bmesh.new()
    rings = []
    prev_side = None
    for i, p in enumerate(pts):
        if i == 0:
            t = (pts[1] - pts[0]).normalized()
        elif i == n - 1:
            t = (pts[-1] - pts[-2]).normalized()
        else:
            t = ((pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()).normalized()
        ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        side = (t.cross(ref)).normalized() if prev_side is None else (prev_side - t * prev_side.dot(t)).normalized()
        prev_side = side
        up = t.cross(side).normalized()
        r = radii[i]
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ring.append(bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * r))
        rings.append(ring)
    for a, b in zip(rings[:-1], rings[1:]):
        for k in range(sides):
            bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
    if caps:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = _new_mesh_obj(name, bm)
    return _finish(obj, parent, material, (0, 0, 0), (0, 0, 0), (1, 1, 1), 0.0, 0, smooth, name)
