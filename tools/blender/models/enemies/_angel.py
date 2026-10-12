"""Shared helpers for the angel enemies (not built itself: underscore prefix).

Import from a model script with:
    import importlib.util, os
    _spec = importlib.util.spec_from_file_location("_angel", os.path.join(os.path.dirname(__file__), "_angel.py"))
    A = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(A)

Material names carry the keywords GlbModel uses to pick surface detail textures
(ivory/bone -> bone, gold -> gold, steel/armor -> metal, feather -> feather, cloth/robe -> cloth,
stone/marble -> stone, leather -> leather, wood/haft -> wood). Emissive ones get none.
"""
import math
import bpy
import bmesh
from mathutils import Vector, Matrix
import sb


# ----------------------------------------------------------------------------- materials

def mats():
    m = {}
    m["ivory"] = sb.mat("Angel_IvoryArmor", (0.86, 0.82, 0.72), roughness=0.38, metallic=0.1)
    m["ivory_dark"] = sb.mat("Angel_IvoryBone", (0.6, 0.56, 0.48), roughness=0.55)
    m["gold"] = sb.mat("Angel_Gold", (0.85, 0.63, 0.27), roughness=0.28, metallic=1.0)
    m["gold_dark"] = sb.mat("Angel_GoldAged", (0.5, 0.36, 0.15), roughness=0.45, metallic=1.0)
    m["steel"] = sb.mat("Angel_SteelBlade", (0.62, 0.64, 0.68), roughness=0.22, metallic=1.0)
    m["mail"] = sb.mat("Angel_SteelMailArmor", (0.3, 0.3, 0.32), roughness=0.5, metallic=0.9)
    m["feather"] = sb.mat("Angel_WingFeather", (0.93, 0.91, 0.85), roughness=0.75)
    m["feather_tip"] = sb.mat("Angel_WingFeatherTip", (0.74, 0.68, 0.56), roughness=0.8)
    m["leather"] = sb.mat("Angel_LeatherStrap", (0.25, 0.16, 0.1), roughness=0.75)
    m["haft"] = sb.mat("Angel_WoodHaft", (0.36, 0.26, 0.17), roughness=0.7)
    m["cloth"] = sb.mat("Angel_ClothRobe", (0.8, 0.77, 0.69), roughness=0.92)
    m["cloth_dark"] = sb.mat("Angel_ClothRobeShade", (0.46, 0.43, 0.38), roughness=0.95)
    m["void"] = sb.mat("Angel_Void", (0.015, 0.012, 0.012), roughness=1.0)
    m["halo"] = sb.mat("Angel_HaloLight", (1.0, 0.9, 0.62), roughness=0.4,
                       emission=(1.0, 0.84, 0.48), strength=4.5)
    m["light"] = sb.mat("Angel_HolyLight", (1.0, 0.97, 0.88), roughness=0.4,
                        emission=(1.0, 0.95, 0.82), strength=5.0)
    m["eye"] = sb.mat("Angel_EyeLight", (1.0, 0.96, 0.85), roughness=0.3,
                      emission=(1.0, 0.92, 0.72), strength=3.5)
    m["pupil"] = sb.mat("Angel_EyePupil", (0.02, 0.018, 0.015), roughness=0.2)
    m["ember"] = sb.mat("Angel_EmberLight", (1.0, 0.5, 0.15), roughness=0.5,
                        emission=(1.0, 0.38, 0.08), strength=5.0)
    return m


def baked_mats():
    """mats() with every non-glowing surface swapped for a procedural sbmat equivalent of the SAME
    name (for models that set BAKE = {...}): filigreed ivory, engraved gold, worn steel / mail,
    pale feather barbs, leather grain, wood-like haft, linen weave. Albedos sit a bit below the flat
    versions (bright 0.85+ whites clip to glare under the golden light + bloom)."""
    import sbmat
    m = {}  # sbmat first: mats() then returns these (sb.mat reuses an existing name)
    m["ivory"] = sbmat.filigree_ivory("Angel_IvoryArmor", tint=(0.66, 0.62, 0.52), inlay=(0.8, 0.58, 0.24),
                                      yellow=(0.55, 0.46, 0.31), grime=(0.15, 0.1, 0.05), line_k=0.6)
    m["ivory_dark"] = sbmat.aged_ivory("Angel_IvoryBone", tint=(0.5, 0.46, 0.38))
    m["gold"] = sbmat.gold_filigree("Angel_Gold", tint=(0.88, 0.64, 0.27), scale=2.0)
    m["gold_dark"] = sbmat.gold_filigree("Angel_GoldAged", tint=(0.55, 0.39, 0.16), scale=2.0)
    m["steel"] = sbmat.worn_steel("Angel_SteelBlade", (0.62, 0.64, 0.68), roughness=0.22, grime=0.5)
    m["mail"] = sbmat.worn_steel("Angel_SteelMailArmor", (0.3, 0.3, 0.32), roughness=0.48, scale=3.0, edge_k=2.0)
    pale = dict(barbs=55.0, vary=(0.86, 1.12), shade=0.6)
    m["feather"] = sbmat.feathers("Angel_WingFeather", (0.68, 0.66, 0.6), sheen=(0.74, 0.7, 0.6),
                                  edge_col=(0.52, 0.49, 0.42), shade_col=(0.3, 0.26, 0.2), **pale)
    m["feather_tip"] = sbmat.feathers("Angel_WingFeatherTip", (0.56, 0.5, 0.39), sheen=(0.62, 0.55, 0.42),
                                      edge_col=(0.44, 0.38, 0.29), shade_col=(0.22, 0.17, 0.11), **pale)
    m["leather"] = sbmat.leather("Angel_LeatherStrap", (0.25, 0.16, 0.1), scale=0.6)
    m["haft"] = sbmat.horn("Angel_WoodHaft", (0.36, 0.26, 0.17), rough=0.7, rings=10.0)
    m["cloth"] = sbmat.linen("Angel_ClothRobe", (0.62, 0.59, 0.52), weave=100.0, rough=0.9, stain=0.4,
                             stain_col=(0.42, 0.36, 0.27), grime_col=(0.12, 0.1, 0.08))
    m["cloth_dark"] = sbmat.linen("Angel_ClothRobeShade", (0.4, 0.37, 0.32), weave=100.0, rough=0.93,
                                  stain_col=(0.28, 0.24, 0.18), grime_col=(0.08, 0.07, 0.05))
    out = mats()
    out.update(m)
    return out


# ----------------------------------------------------------------------------- geometry

def seg(name, parent, a, b, r1, r2=None, material=None, segments=10, bevel=0.0):
    """Cylinder/cone from point a to b (parent space)."""
    a = Vector(a)
    b = Vector(b)
    d = b - a
    e = d.normalized().to_track_quat("Z", "Y").to_euler()
    return sb.cylinder(name, parent, r1=r1, r2=r2, depth=d.length, loc=tuple(a),
                       rot=tuple(math.degrees(x) for x in e), material=material,
                       segments=segments, bevel=bevel)


def lathe(name, parent, profile, segments=16, material=None, loc=(0, 0, 0), rot=(0, 0, 0),
          scale=(1, 1, 1), smooth=True):
    """Surface of revolution around local Z. profile = [(radius, z), ...] bottom->top.
    radius 0 at either end closes the surface with a pole."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-5:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(2 * math.pi * k / segments),
                                        r * math.sin(2 * math.pi * k / segments), z))
                          for k in range(segments)])
    for lo, hi in zip(rings[:-1], rings[1:]):
        for k in range(segments):
            k1 = (k + 1) % segments
            if len(lo) == 1 and len(hi) == 1:
                continue
            if len(lo) == 1:
                bm.faces.new((lo[0], hi[k1], hi[k]))
            elif len(hi) == 1:
                bm.faces.new((lo[k], lo[k1], hi[0]))
            else:
                bm.faces.new((lo[k], lo[k1], hi[k1], hi[k]))
    # close open ends with a cap
    if len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    obj = sb._new_mesh_obj(name, bm)
    return sb._finish(obj, parent, material, loc, rot, scale, 0.0, 0, smooth, name)


def ellipsoid(name, parent, size, loc=(0, 0, 0), rot=(0, 0, 0), material=None, seg=12, rings=8):
    """Sphere scaled to full extents `size` (x, y, z)."""
    return sb.sphere(name, parent, radius=0.5, loc=loc, rot=rot, scale=size, material=material,
                     segments=seg, rings=rings)


def ring(name, parent, radius, minor, loc=(0, 0, 0), rot=(0, 0, 0), material=None, seg=32, mseg=6):
    return sb.torus(name, parent, major=radius, minor=minor, loc=loc, rot=rot, material=material,
                    major_segments=seg, minor_segments=mseg)


def feather(name, parent, length=1.0, width=0.12, thickness=0.02, loc=(0, 0, 0), rot=(0, 0, 0),
            material=None, curve=0.0, steps=4):
    """Like sb.blade but with a configurable step count (cheaper). Tip at +Z, curls to +Y."""
    bm = bmesh.new()
    rows = []
    for i in range(steps + 1):
        t = i / steps
        w = width * (0.6 + 0.4 * math.sin(math.pi * min(t * 1.5, 1.0))) * (1.0 - t ** 2.5) + 0.002
        z = t * length
        y = curve * t * t * length
        rows.append([bm.verts.new((-w, y - thickness, z)), bm.verts.new((w, y - thickness, z)),
                     bm.verts.new((w, y + thickness * 0.4, z)), bm.verts.new((-w, y + thickness * 0.4, z))])
    for a, b in zip(rows[:-1], rows[1:]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = sb._new_mesh_obj(name, bm)
    return sb._finish(obj, parent, material, loc, rot, (1, 1, 1), 0.0, 0, False, name)


def spike(name, parent, base, direction, length, width, thick=None, material=None, up=(0, 0, 1)):
    """Tapered 4-sided spike (12 tris) from `base` along `direction`. Flat side faces `up`."""
    d = Vector(direction).normalized()
    u = Vector(up)
    x = u.cross(d)
    if x.length < 1e-4:
        x = Vector((1, 0, 0)).cross(d)
    x.normalize()
    y = d.cross(x)
    mtx = Matrix(((x[0], y[0], d[0]), (x[1], y[1], d[1]), (x[2], y[2], d[2])))
    c = Vector(base) + d * length * 0.5
    return sb.box(name, parent, size=(width, thick if thick else width * 0.4, length), loc=tuple(c),
                  rot=tuple(math.degrees(a) for a in mtx.to_euler()), material=material, bevel=0.0,
                  taper=(0.04, 0.04))


# ----------------------------------------------------------------------------- angel parts

def halo(name, parent, loc, radius, m, rays=0, ray_len=0.3, upright=False, minor=None, seg=32,
         studs=0, band=True, alt=True):
    """Glowing ring. Returns the SPIN joint (rotate it about its local Z). Horizontal unless
    `upright` (then it stands behind the head facing forward). Rays / gold studs make the
    rotation readable."""
    mount = sb.empty(name + "_mount", parent, loc=loc, rot=(90, 0, 0) if upright else (0, 0, 0))
    spin = sb.empty(name, mount)
    minor = minor if minor is not None else radius * 0.07
    ring(name + "_ring", spin, radius, minor, material=m["halo"], seg=seg, mseg=5)
    if band:
        ring(name + "_band", spin, radius * 0.86, minor * 0.45, material=m["gold"], seg=seg, mseg=4)
    for i in range(rays):
        a = 360.0 * i / rays
        long = (i % 2 == 0) or not alt
        ln = radius * ray_len * (1.0 if long else 0.55)
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        r0 = radius + minor * 1.2
        spike(f"{name}_ray{i}", spin, (ca * r0, sa * r0, 0), (ca, sa, 0), ln, minor * 1.8, minor * 0.6,
              material=m["halo"])
    for i in range(studs):
        a = 2 * math.pi * (i + 0.5) / studs
        sb.sphere(f"{name}_stud{i}", spin, radius=minor * 1.5,
                  loc=(math.cos(a) * radius, math.sin(a) * radius, 0), material=m["gold"],
                  segments=6, rings=4)
    return spin


def eye(name, parent, loc, size, facing=(0, -1, 0), m=None, rim=True, seg=10):
    """A glowing eye looking along `facing` (parent space): almond glow, dark slit, gold rim.
    Returns its joint (scale Z to blink / widen)."""
    f = Vector(facing).normalized()
    q = f.to_track_quat("-Y", "Z")
    j = sb.empty(name, parent, loc=loc, rot=tuple(math.degrees(x) for x in q.to_euler()))
    ellipsoid(name + "_ball", j, (size, size * 0.55, size * 0.62), material=m["eye"], seg=seg, rings=6)
    sb.box(name + "_pupil", j, size=(size * 0.12, size * 0.1, size * 0.5), loc=(0, -size * 0.25, 0),
           material=m["pupil"], bevel=0.0)
    if rim:
        sb.torus(name + "_lid", j, major=size * 0.52, minor=size * 0.09, loc=(0, -size * 0.04, 0),
                 rot=(90, 0, 0), material=m["gold"], major_segments=10, minor_segments=3)
    return j


def wing_pose(s, up=0.0, sweep=0.0, pitch=0.0):
    """Rotation (deg) for a wing root on side s (+1 = +X): up = raise, sweep = fold back,
    pitch = tilt feathers backwards."""
    return (pitch, -s * up, s * sweep)


def wing(name, parent, s, loc, span, m, n_prim=6, n_sec=4, up=15.0, sweep=20.0, pitch=0.0,
         chord=1.0, bone=True, coverts=True, fmat=None, tipmat=None, cmat=None, width=1.0, steps=4):
    """Feathered wing on side s (+1 = +X, -1 = -X), spanning ~`span` outward from `loc`.
    Two joints: root (shoulder) and hand (outer half, primaries). Returns (root, hand)."""
    fmat = fmat or m["feather"]
    tipmat = tipmat or m["feather_tip"]
    cmat = cmat or m["ivory"]
    root = sb.empty(name, parent, loc=loc, rot=wing_pose(s, up, sweep, pitch))
    elbow = Vector((s * span * 0.45, 0.0, span * 0.14))
    hand = sb.empty(name + "_hand", root, loc=tuple(elbow))
    tip = Vector((s * span * 0.58, 0.0, -span * 0.02))
    if bone:
        seg(name + "_arm", root, (0, 0, 0), elbow, span * 0.045, span * 0.03, material=cmat, segments=8)
        seg(name + "_fore", hand, (0, 0, 0), tip * 0.85, span * 0.03, span * 0.012, material=m["gold"],
            segments=6)
        sb.sphere(name + "_knuckle", hand, radius=span * 0.04, material=m["gold"], segments=8, rings=5)
    fw = span * 0.07 * width
    for i in range(n_sec):
        t = (i + 0.5) / n_sec
        p = elbow * (0.15 + 0.85 * t)
        ln = span * chord * (0.5 + 0.08 * t)
        ang = -4 + 12 * t
        feather(f"{name}_sec{i}", root, steps=steps, length=ln, width=fw, thickness=0.004 * span,
                 loc=(p.x, 0.012 * span * (n_sec - i) / n_sec, p.z - 0.02 * span),
                 rot=(0, 180 - s * ang, 0), material=fmat if i % 3 else tipmat, curve=0.12)
    for i in range(n_prim):
        t = (i + 0.5) / n_prim
        p = tip * t
        ln = span * chord * (0.6 + 0.22 * t)
        ang = 12 + 50 * t ** 1.1
        feather(f"{name}_pri{i}", hand, steps=steps, length=ln, width=fw * (1.0 - 0.15 * t), thickness=0.004 * span,
                 loc=(p.x, 0.01 * span * (1 - t), p.z - 0.01 * span),
                 rot=(0, 180 - s * ang, 0), material=fmat if i % 2 == 0 else tipmat, curve=0.18)
    if coverts:
        nc = max(2, (n_sec + n_prim) // 3)
        for i in range(nc):
            t = (i + 0.5) / nc
            if t < 0.55:
                par, p = root, elbow * (t / 0.55)
            else:
                par, p = hand, tip * ((t - 0.55) / 0.45)
            feather(f"{name}_cov{i}", par, steps=max(2, steps - 1), length=span * 0.22, width=fw * 1.25, thickness=0.006 * span,
                     loc=(p.x, -0.012 * span, p.z + 0.01 * span), rot=(0, 180 - s * (10 + 40 * t), 0),
                     material=cmat, curve=0.1)
    return root, hand


# ----------------------------------------------------------------------------- animation

class Rig:
    """Collects joints so every animation keys every joint (Godot keeps un-keyed tracks at
    their last value when switching clips, so loops must reset everything)."""

    def __init__(self):
        self.joints = []

    def add(self, *objs):
        for o in objs:
            if o not in self.joints:
                self.joints.append(o)
        return objs[0] if len(objs) == 1 else objs

    def anim(self, name, keys, end):
        full = dict(keys)
        for j in self.joints:
            if j not in full:
                full[j] = [(0, sb.rest(j)), (end, sb.rest(j))]
        sb.anim(name, full)


def R(obj, rot=None, loc=None, scale=None):
    """Absolute-rotation key dict built from the rest pose: rot replaces rotation (deg),
    loc is an OFFSET from rest location, scale replaces scale."""
    k = sb.rest(obj)
    if rot is not None:
        k["rot"] = tuple(rot)
    if loc is not None:
        k["loc"] = tuple(a + b for a, b in zip(k["loc"], loc))
    if scale is not None:
        k["scale"] = tuple(scale) if hasattr(scale, "__len__") else (scale, scale, scale)
    return k


def O(obj, rot=(0, 0, 0), loc=(0, 0, 0), scale=None):
    """Offset key from rest (rot added in degrees, loc added, scale multiplied)."""
    k = sb.offset(obj, rot=rot, loc=loc)
    if scale is not None:
        sc = scale if hasattr(scale, "__len__") else (scale, scale, scale)
        k["scale"] = tuple(a * b for a, b in zip(sb.rest(obj)["scale"], sc))
    return k


def wing_keys(root, hand, s, frames, up0, up1, sweep, pitch=0.0, hand_lag=18.0, beats=1):
    """Flap keys for one wing: `beats` full beats over `frames` frames between up0 (down) and
    up1 (up) elevation. Hand trails the root. Returns {root: keys, hand: keys}."""
    rk, hk = [], []
    rest_hand = sb.rest(hand)["rot"]
    steps = beats * 4
    for i in range(steps + 1):
        f = round(frames * i / steps)
        ph = (i % 4)
        # 0 = top, 1 = mid-down, 2 = bottom, 3 = mid-up
        up = {0: up1, 1: (up0 + up1) * 0.5, 2: up0, 3: (up0 + up1) * 0.5}[ph]
        lag = {0: -hand_lag * 0.3, 1: hand_lag, 2: hand_lag * 0.3, 3: -hand_lag}[ph]
        rk.append((f, {"rot": wing_pose(s, up, sweep, pitch)}))
        hk.append((f, {"rot": (rest_hand[0], rest_hand[1] - s * lag, rest_hand[2])}))
    return {root: rk, hand: hk}


def merge_by_joint(root):
    """Joins the meshes under each joint into one multi-material mesh (modifiers applied), so a
    model costs one mesh instance per animated joint instead of one per part."""
    groups = {}
    stack = [root]
    while stack:
        o = stack.pop()
        for c in o.children:
            stack.append(c)
            if c.type == "MESH":
                groups.setdefault(c.parent, []).append(c)
    for parent, objs in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.convert(target="MESH")
        if len(objs) > 1:
            bpy.ops.object.join()
        j = bpy.context.active_object
        j.name = parent.name + "_mesh"
        j.data.name = j.name


def finish(root, label):
    merge_by_joint(root)
    return report(label)


def report(label):
    dg = bpy.context.evaluated_depsgraph_get()
    tris = 0
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        tris += len(me.loop_triangles)
        o.evaluated_get(dg).to_mesh_clear()
    print(f"TRIS {label} = {tris}")
    return tris


# ----------------------------------------------------------------------------- shapes

def plate(name, parent, outline, thickness, material=None, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0,
          bulge=0.0):
    """Flat plate from a 2D outline [(x, z), ...] in the XZ plane, extruded along Y by
    `thickness` (centered). `bulge` raises the center of the front (-Y) face into a low cone."""
    bm = bmesh.new()
    n = len(outline)
    cx = sum(p[0] for p in outline) / n
    cz = sum(p[1] for p in outline) / n
    front = [bm.verts.new((x, -thickness * 0.5, z)) for x, z in outline]
    back = [bm.verts.new((x, thickness * 0.5, z)) for x, z in outline]
    if bulge > 0.0:
        c = bm.verts.new((cx, -thickness * 0.5 - bulge, cz))
        for k in range(n):
            bm.faces.new((front[k], front[(k + 1) % n], c))
    else:
        bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for k in range(n):
        k1 = (k + 1) % n
        bm.faces.new((front[k1], front[k], back[k], back[k1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = sb._new_mesh_obj(name, bm)
    return sb._finish(obj, parent, material, loc, rot, (1, 1, 1), bevel, 0, False, name)


def attach(name, parent, world_loc, world_rot=(0, 0, 0)):
    """Joint parented to `parent` but placed at a WORLD location / rotation (deg)."""
    from mathutils import Euler
    e = sb.empty(name, parent)
    bpy.context.view_layer.update()
    mw = Euler([math.radians(a) for a in world_rot]).to_matrix().to_4x4()
    mw.translation = Vector(world_loc)
    e.matrix_world = mw
    bpy.context.view_layer.update()
    return e


# ----------------------------------------------------------------------------- knight body

def knight(rig, root, m, h=1.0, bulk=1.0, tabard=True, skirt=1.0, armor=None, trim=None, arms=True):
    """Armored humanoid body (forward -Y). Joints: hips, thigh_L/R, shin_L/R, chest, arm_L/R,
    fore_L/R, hand_L/R, head (empty: the model adds its helm). All registered in `rig`.
    Feet on z=0 at rest. Returns a dict of joints."""
    armor = armor or m["ivory"]
    trim = trim or m["gold"]
    J = {}
    hips = rig.add(sb.empty("hips", root, loc=(0, 0, 0.85 * h)))
    J["hips"] = hips
    for s, sd in ((-1, "L"), (1, "R")):
        th = rig.add(sb.empty(f"thigh_{sd}", hips, loc=(s * 0.1 * h * bulk, 0, -0.03 * h)))
        seg(f"thighmail_{sd}", th, (0, 0, 0), (0, 0, -0.38 * h), 0.068 * h * bulk, 0.058 * h * bulk,
            material=m["mail"], segments=8)
        lathe(f"cuisse_{sd}", th, [(0.0, -0.36 * h), (0.06 * h, -0.34 * h), (0.078 * h, -0.2 * h),
                                    (0.072 * h, -0.04 * h), (0.0, 0.0)], segments=10, material=armor,
              loc=(0, -0.012 * h, 0), scale=(bulk, 0.85, 1))
        sh = rig.add(sb.empty(f"shin_{sd}", th, loc=(0, 0, -0.38 * h)))
        ellipsoid(f"knee_{sd}", sh, (0.1 * h * bulk, 0.08 * h, 0.1 * h), loc=(0, -0.045 * h, 0),
                  material=trim, seg=8, rings=6)
        spike(f"kneespike_{sd}", sh, (0, -0.07 * h, 0.0), (0, -0.4, 1), 0.08 * h, 0.06 * h, 0.02 * h,
              material=armor)
        lathe(f"greave_{sd}", sh, [(0.0, -0.4 * h), (0.05 * h, -0.39 * h), (0.068 * h, -0.24 * h),
                                    (0.072 * h, -0.12 * h), (0.058 * h, -0.02 * h), (0.0, 0.0)],
              segments=10, material=armor, scale=(bulk, 1, 1))
        ellipsoid(f"sabaton_{sd}", sh, (0.1 * h * bulk, 0.27 * h, 0.085 * h), loc=(0, -0.07 * h, -0.405 * h),
                  material=armor, seg=10, rings=6)
        ellipsoid(f"toecap_{sd}", sh, (0.07 * h, 0.1 * h, 0.05 * h), loc=(0, -0.17 * h, -0.4 * h),
                  material=trim, seg=8, rings=5)
        J[f"thigh_{sd}"] = th
        J[f"shin_{sd}"] = sh
    # skirt: mail, faulds, belt, tassets, tabard
    lathe("mailskirt", hips, [(0.215 * h * bulk, -0.3 * h * skirt), (0.17 * h * bulk, 0.05 * h)],
          segments=14, material=m["mail"])
    lathe("faulds", hips, [(0.215 * h * bulk, -0.1 * h), (0.2 * h * bulk, 0.0), (0.17 * h * bulk, 0.1 * h)],
          segments=14, material=armor)
    ring("belt", hips, 0.178 * h * bulk, 0.018 * h, loc=(0, 0, 0.09 * h), material=trim, seg=16, mseg=4)
    for i, a in enumerate((-50, 50, -110, 110)):
        ca, sa = math.sin(math.radians(a)), -math.cos(math.radians(a))
        plate(f"tasset{i}", hips, [(-0.07 * h, 0.0), (0.07 * h, 0.0), (0.06 * h, -0.22 * h * skirt),
                                    (0.0, -0.25 * h * skirt), (-0.06 * h, -0.22 * h * skirt)], 0.012 * h,
              material=armor, loc=(ca * 0.2 * h * bulk, sa * 0.2 * h * bulk, -0.02 * h), rot=(-12, 0, a))
    if tabard:
        for nm, y, ry in (("front", -1, 0), ("back", 1, 180)):
            plate(f"tabard_{nm}", hips, [(-0.085 * h, 0.08 * h), (0.085 * h, 0.08 * h), (0.075 * h, -0.5 * h * skirt),
                                         (0.0, -0.56 * h * skirt), (-0.075 * h, -0.5 * h * skirt)], 0.01 * h,
                  material=m["cloth"], loc=(0, y * 0.2 * h * bulk * 0.78, 0), rot=(y * -6, 0, ry))
    chest = rig.add(sb.empty("chest", hips, loc=(0, 0, 0.1 * h)))
    J["chest"] = chest
    lathe("cuirass", chest, [(0.0, -0.02 * h), (0.155 * h, -0.02 * h), (0.19 * h, 0.1 * h), (0.215 * h, 0.22 * h),
                             (0.2 * h, 0.31 * h), (0.14 * h, 0.37 * h), (0.07 * h, 0.39 * h), (0.0, 0.39 * h)],
          segments=16, material=armor, scale=(bulk, 0.72, 1))
    sb.box("ridge", chest, size=(0.016 * h, 0.03 * h, 0.3 * h), loc=(0, -0.145 * h, 0.2 * h),
           rot=(6, 0, 0), material=trim, bevel=0.0)
    for k in range(2):
        ring(f"lame{k}", chest, 0.16 * h * bulk + k * 0.012 * h, 0.008 * h, loc=(0, 0, 0.02 * h + k * 0.04 * h),
             material=trim if k == 0 else armor, seg=16, mseg=3).scale = (1, 0.78, 1)
    lathe("gorget", chest, [(0.13 * h, 0.33 * h), (0.11 * h, 0.4 * h), (0.07 * h, 0.45 * h), (0.0, 0.45 * h)],
          segments=12, material=trim, scale=(bulk, 0.85, 1))
    for s, sd in ((-1, "L"), (1, "R")):
        arm = rig.add(sb.empty(f"arm_{sd}", chest, loc=(s * 0.25 * h * bulk, 0, 0.32 * h)))
        for k, (mat_, sc) in enumerate(((armor, 1.0), (trim, 0.9), (armor, 0.8))):
            lathe(f"pauldron{k}_{sd}", arm, [(0.0, -0.035 * h), (0.1 * h, -0.03 * h), (0.095 * h, 0.0),
                                              (0.07 * h, 0.03 * h), (0.0, 0.04 * h)], segments=10,
                  material=mat_, loc=(s * (0.015 + 0.012 * k) * h, 0, 0.035 * h - k * 0.05 * h),
                  rot=(0, s * (22 + 12 * k), 0), scale=(sc * bulk, sc * 1.05, 1.0))
        seg(f"rerebrace_{sd}", arm, (0, 0, -0.02 * h), (0, 0, -0.26 * h), 0.052 * h * bulk, 0.045 * h * bulk,
            material=armor, segments=8)
        fore = rig.add(sb.empty(f"fore_{sd}", arm, loc=(0, 0, -0.28 * h)))
        ellipsoid(f"couter_{sd}", fore, (0.085 * h, 0.09 * h, 0.08 * h), material=trim, seg=8, rings=6)
        lathe(f"vambrace_{sd}", fore, [(0.0, -0.25 * h), (0.045 * h, -0.24 * h), (0.058 * h, -0.08 * h),
                                        (0.048 * h, 0.0), (0.0, 0.01 * h)], segments=10, material=armor,
              scale=(bulk, 1, 1))
        hand = rig.add(sb.empty(f"hand_{sd}", fore, loc=(0, 0, -0.27 * h)))
        ellipsoid(f"gauntlet_{sd}", hand, (0.07 * h, 0.085 * h, 0.1 * h), loc=(0, 0, -0.02 * h), material=armor,
                  seg=8, rings=6)
        ring(f"cuff_{sd}", hand, 0.05 * h, 0.012 * h, loc=(0, 0, 0.03 * h), material=trim, seg=10, mseg=3)
        J[f"arm_{sd}"] = arm
        J[f"fore_{sd}"] = fore
        J[f"hand_{sd}"] = hand
        if not arms:
            # two-handed rigs build their own arms; keep only the pauldron
            for o in list(arm.children_recursive):
                if o.name.startswith(("rerebrace", "couter", "vambrace", "gauntlet", "cuff")):
                    bpy.data.objects.remove(o)
            rig.joints.remove(fore)
            rig.joints.remove(hand)
            bpy.data.objects.remove(hand)
            bpy.data.objects.remove(fore)
            del J[f"fore_{sd}"], J[f"hand_{sd}"]
    head = rig.add(sb.empty("head", chest, loc=(0, 0, 0.47 * h)))
    seg("neck", chest, (0, 0, 0.36 * h), (0, 0, 0.5 * h), 0.06 * h, 0.055 * h, material=m["mail"], segments=8)
    J["head"] = head
    return J


def walk_keys(J, F, stride=24.0, knee=40.0, bob=0.025, arm=14.0, lean=4.0, arms=("L", "R"), twist=5.0):
    """Walk cycle over F frames (loop). Keys for hips / thighs / shins / chest (+ listed arms).
    Rotations are offsets from each joint's rest pose."""
    keys = {}
    q = [0, F // 4, F // 2, 3 * F // 4, F]
    hips, chest = J["hips"], J["chest"]
    keys[hips] = [(q[0], O(hips)), (q[1], O(hips, loc=(0, 0, bob))), (q[2], O(hips)),
                  (q[3], O(hips, loc=(0, 0, bob))), (q[4], O(hips))]
    keys[chest] = [(q[0], O(chest, rot=(lean, 0, twist))), (q[2], O(chest, rot=(lean, 0, -twist))),
                   (q[4], O(chest, rot=(lean, 0, twist)))]
    for sd, ph in (("L", 0), ("R", 1)):
        th, sh = J[f"thigh_{sd}"], J[f"shin_{sd}"]
        a, b = (-stride, stride) if ph == 0 else (stride, -stride)
        # negative X = leg forward
        keys[th] = [(q[0], O(th, rot=(a, 0, 0))), (q[1], O(th)), (q[2], O(th, rot=(b, 0, 0))), (q[3], O(th)),
                    (q[4], O(th, rot=(a, 0, 0)))]
        # knee bends (positive X) while the leg passes forward
        bend = [(q[0], 5), (q[1], knee if ph == 1 else 8), (q[2], 5), (q[3], knee if ph == 0 else 8), (q[4], 5)]
        keys[sh] = [(f, O(sh, rot=(v, 0, 0))) for f, v in bend]
        if sd in arms:
            ar = J[f"arm_{sd}"]
            c, d = (arm, -arm) if ph == 0 else (-arm, arm)
            keys[ar] = [(q[0], O(ar, rot=(c, 0, 0))), (q[2], O(ar, rot=(d, 0, 0))), (q[4], O(ar, rot=(c, 0, 0)))]
    return keys
