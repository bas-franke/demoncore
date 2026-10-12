"""Animation contact sheets: SEE the motion of a model script's animations without Godot.

  blender -b --factory-startup --python tools/blender/anim_preview.py -- enemies/seraph_sentinel walk
  blender -b --factory-startup --python tools/blender/anim_preview.py -- _anim_demo/_knight            (all anims)
  ... -- demons/vharok attack hit --frames 12 --cols 6 --view front --size 300 --trace hand_R,foot_L

Writes tools/blender/previews/<category>_<name>_<anim>_sheet.png : a grid of evenly spaced frames
(loops skip the duplicate last frame) rendered with a FIXED orthographic camera framed on the
whole motion, over a 0.5 m ground grid, each cell labelled with its frame number. Motion arcs
(world paths of the most-moving end joints, or --trace joints) are drawn as coloured lines in
every cell, with a dot showing where the joint is on that frame - check arcs, spacing (ease)
and holds at a glance.

Options:
  --frames N     cells per anim (default 8)          --cols C   grid columns (default 4)
  --size PX      cell size (default 320)              --view side|front|back|three|top|game
                 (default: side for walk/run/fly, three-quarter for the rest)
  --trace a,b    joint names to trace ('none' = off; default = auto, 4 most-moving end joints)
  --at 0,12,17   exact frames (overrides --frames)    --range A:B  only frames A..B of the clip
         --eevee    render with EEVEE (default Workbench)
"""
import importlib.util
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
import numpy as np  # noqa: E402
import sb  # noqa: E402
from mathutils import Vector  # noqa: E402

MODELS = os.path.join(HERE, "models")
OUT = os.path.join(HERE, "previews")
LOOPS = ("idle", "walk", "run", "fly", "hover", "loop")
TRACE_COLORS = [(1.0, 0.25, 0.2), (0.25, 0.75, 1.0), (1.0, 0.85, 0.2), (0.45, 1.0, 0.4), (1.0, 0.4, 1.0),
                (1.0, 0.6, 0.2)]


def parse(argv):
    o = {"frames": 8, "cols": 4, "size": 320, "view": None, "trace": "auto", "eevee": False, "range": None, "at": None}
    pos = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--eevee":
            o["eevee"] = True
        elif a.startswith("--"):
            o[a[2:]] = argv[i + 1]
            i += 1
        else:
            pos.append(a)
        i += 1
    for k in ("frames", "cols", "size"):
        o[k] = int(o[k])
    return pos, o


def all_tracks():
    names = []
    for ob in bpy.data.objects:
        if ob.animation_data:
            for t in ob.animation_data.nla_tracks:
                if t.name not in names:
                    names.append(t.name)
    return names


def solo(name):
    """Mute every NLA track except `name`; returns (start, end) frame range of that clip."""
    lo, hi = None, None
    for ob in bpy.data.objects:
        ad = ob.animation_data
        if ad is None:
            continue
        ad.action = None
        for t in ad.nla_tracks:
            t.mute = t.name != name
            t.is_solo = False
            if t.name == name:
                for s in t.strips:
                    lo = s.frame_start if lo is None else min(lo, s.frame_start)
                    hi = s.frame_end if hi is None else max(hi, s.frame_end)
    return (int(lo or 0), int(hi or 0))


def set_frame(f):
    bpy.context.scene.frame_set(int(f))
    bpy.context.view_layer.update()


def mesh_bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def flat_mat(name, color, emit=False):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1.0)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    if emit:
        b.inputs["Emission Color"].default_value = (*color, 1.0)
        b.inputs["Emission Strength"].default_value = 3.0
    return m


def sync_viewport_colors():
    """Workbench shows material.diffuse_color - copy each node base color (emissive -> its glow)."""
    for m in bpy.data.materials:
        if not m.use_nodes or m.node_tree is None:
            continue
        b = m.node_tree.nodes.get("Principled BSDF")
        if b is None:
            continue
        col = list(b.inputs["Base Color"].default_value)
        es = b.inputs["Emission Strength"].default_value
        if es > 0.5:
            col = list(b.inputs["Emission Color"].default_value)
        m.diffuse_color = (col[0], col[1], col[2], 1.0)


def path_curve(name, pts, color, radius):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 1
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for p, v in zip(sp.points, pts):
        p.co = (v.x, v.y, v.z, 1.0)
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    cu.materials.append(flat_mat("trace_" + name, color, emit=True))
    return ob


def setup_world(eevee):
    sc = bpy.context.scene
    if eevee:
        sc.render.engine = "BLENDER_EEVEE"
        world = bpy.data.worlds.new("W")
        world.use_nodes = True
        bg = world.node_tree.nodes.get("Background")
        bg.inputs["Color"].default_value = (0.05, 0.05, 0.06, 1)
        bg.inputs["Strength"].default_value = 0.8
        sc.world = world
        for nm, en, col, rot in (("Key", 3.0, (1.0, 0.88, 0.7), (50, 0, -35)),
                                 ("Fill", 1.0, (0.6, 0.7, 1.0), (60, 0, 150))):
            li = bpy.data.objects.new(nm, bpy.data.lights.new(nm, "SUN"))
            li.data.energy = en
            li.data.color = col
            li.rotation_euler = [math.radians(a) for a in rot]
            sc.collection.objects.link(li)
    else:
        sc.render.engine = "BLENDER_WORKBENCH"
        sh = sc.display.shading
        sh.light = "STUDIO"
        sh.color_type = "MATERIAL"
        sh.show_shadows = True
        sh.shadow_intensity = 0.55
        sh.show_cavity = True
        sh.cavity_type = "WORLD"
        sh.show_object_outline = True
        sh.object_outline_color = (0.0, 0.0, 0.0)
        sh.background_type = "VIEWPORT"
        sh.background_color = (0.07, 0.07, 0.08)
        sc.display.light_direction = (0.4, -0.5, 0.75)
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"


def ground(center, extent):
    """Dark ground with a 0.5 m grid (reference for sliding / travel)."""
    gm = flat_mat("pv_ground", (0.16, 0.16, 0.15))
    lm = flat_mat("pv_grid", (0.3, 0.3, 0.28))
    half = max(2.0, extent)
    g = sb.box("pv_ground", None, size=(half * 4, half * 4, 0.02), loc=(center.x, center.y, -0.011), material=gm,
               bevel=0.0)
    n = int(half * 4 / 0.5)
    x0 = round(center.x * 2) / 2 - n * 0.25
    y0 = round(center.y * 2) / 2 - n * 0.25
    lines = []
    for k in range(n + 1):
        lines.append(sb.box(f"pv_gx{k}", None, size=(0.02, half * 4, 0.006), loc=(x0 + k * 0.5, center.y, 0.0),
                            material=lm, bevel=0.0))
        lines.append(sb.box(f"pv_gy{k}", None, size=(half * 4, 0.02, 0.006), loc=(center.x, y0 + k * 0.5, 0.0),
                            material=lm, bevel=0.0))
    return [g] + lines


VIEWS = {"side": (8, 90), "front": (10, 0), "back": (10, 180), "three": (18, 40), "top": (89, 0),
         "game": (55, 0)}


def camera(lo, hi, view):
    pitch, yaw = VIEWS[view]
    center = (lo + hi) * 0.5
    p, y = math.radians(pitch), math.radians(yaw)
    d = Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))
    cam_data = bpy.data.cameras.new("pv_cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("pv_cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    dist = (hi - lo).length * 2 + 5
    cam.location = center + d * dist
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()
    # fit: project bound corners onto camera right/up axes
    inv = cam.matrix_world.inverted()
    xs, ys = [], []
    for cx in (lo.x, hi.x):
        for cy in (lo.y, hi.y):
            for cz in (lo.z, hi.z):
                q = inv @ Vector((cx, cy, cz))
                xs.append(q.x)
                ys.append(q.y)
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    cam_data.ortho_scale = max(w, h) * 1.12 + 0.1
    cam_data.shift_x = ((max(xs) + min(xs)) * 0.5) / cam_data.ortho_scale
    cam_data.shift_y = ((max(ys) + min(ys)) * 0.5) / cam_data.ortho_scale
    cam_data.clip_end = dist * 3
    bpy.context.scene.camera = cam
    return cam


def label(cam, text_):
    cu = bpy.data.curves.new("pv_label", "FONT")
    cu.body = text_
    ob = bpy.data.objects.new("pv_label", cu)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = cam
    s = cam.data.ortho_scale
    cu.size = s * 0.065
    ob.location = (-s * 0.47 + cam.data.shift_x * s, s * 0.47 - cu.size + cam.data.shift_y * s, -1.0)
    cu.materials.append(flat_mat("pv_label_m", (0.95, 0.9, 0.75), emit=True))
    return ob


def end_joints(root_objs):
    """Empties whose subtree has no further empties (hands, feet, tips, heads...)."""
    out = []
    for o in bpy.data.objects:
        if o.type == "EMPTY" and o.animation_data is not None:
            if not any(c.type == "EMPTY" for c in o.children):
                out.append(o)
    return out


def render_anim(rel, anim, o):
    sc = bpy.context.scene
    f0, f1 = solo(anim)
    if o["range"]:
        a, b = o["range"].split(":")
        f0, f1 = int(a), int(b)
    loop = anim in LOOPS or anim.startswith(LOOPS)
    n = o["frames"]
    if loop:
        frames = [f0 + (f1 - f0) * k / n for k in range(n)]
    else:
        frames = [f0 + (f1 - f0) * k / (n - 1) for k in range(n)]
    frames = [int(round(f)) for f in frames]
    if o["at"]:
        frames = [f0 + int(x) for x in o["at"].split(",")]
    meshes = [m for m in bpy.data.objects if m.type == "MESH" and not m.name.startswith("pv_")]
    # bounds over the full motion + dense joint paths
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    cands = end_joints(None)
    paths = {j.name: [] for j in cands}
    for f in range(f0, f1 + 1):
        set_frame(f)
        if f in frames or f == f0 or f == f1 or f % 4 == 0:
            l2, h2 = mesh_bounds([m for m in meshes if max(m.dimensions) < 50])
            lo = Vector((min(lo.x, l2.x), min(lo.y, l2.y), min(lo.z, l2.z)))
            hi = Vector((max(hi.x, h2.x), max(hi.y, h2.y), max(hi.z, h2.z)))
        for j in cands:
            paths[j.name].append(j.matrix_world.translation.copy())
    lo.z = min(lo.z, 0.0)
    trace = []
    if o["trace"] == "auto":
        def travel(pts):
            return sum((pts[i + 1] - pts[i]).length for i in range(len(pts) - 1))
        ranked = sorted(cands, key=lambda j: -travel(paths[j.name]))
        def near(a, b):  # same limb branch: share parent or grandparent
            ua = [a.parent, a.parent.parent if a.parent else None]
            ub = [b.parent, b.parent.parent if b.parent else None]
            return any(x is not None and x in ub for x in ua)
        picked = []
        for j in ranked:  # one joint per limb branch, skip near-identical paths
            if travel(paths[j.name]) < 0.05:
                break
            if all(not near(j, p) and (paths[j.name][0] - paths[p.name][0]).length > 0.12 for p in picked):
                picked.append(j)
            if len(picked) == 4:
                break
        trace = picked
    elif o["trace"] != "none":
        trace = [bpy.data.objects[t] for t in o["trace"].split(",") if t in bpy.data.objects]
    view = o["view"] or ("side" if anim.startswith(("walk", "run")) else
                         "front" if anim.startswith(("fly", "hover")) else "three")
    cam = camera(lo, hi, view)
    extra = ground((lo + hi) * 0.5, max(hi.x - lo.x, hi.y - lo.y))
    ortho = cam.data.ortho_scale
    for i, j in enumerate(trace):
        col = TRACE_COLORS[i % len(TRACE_COLORS)]
        extra.append(path_curve(f"pv_trace{i}", paths[j.name], col, ortho * 0.0025))
    dots = []
    for i, j in enumerate(trace):
        d = sb.sphere(f"pv_dot{i}", None, ortho * 0.009, material=flat_mat(f"trace_dot{i}",
                      TRACE_COLORS[i % len(TRACE_COLORS)], emit=True), segments=10, rings=6)
        dots.append((d, j))
    lab = label(cam, "")
    extra += [lab] + [d for d, _ in dots]
    size = o["size"]
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.resolution_percentage = 100
    cols = min(o["cols"], len(frames))
    rows = (len(frames) + cols - 1) // cols
    sheet = np.zeros((rows * size, cols * size, 4), dtype=np.float32)
    # Per-process temp file: several agents render contact sheets in parallel.
    tmp = os.path.join(OUT, "_pv_tmp_%d.png" % os.getpid())
    for k, f in enumerate(frames):
        set_frame(f)
        for d, j in dots:
            d.location = j.matrix_world.translation
        lab.data.body = f"{anim}  f{f - f0}" if k == 0 else f"f{f - f0}"
        bpy.context.view_layer.update()
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp, check_existing=False)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)
        bpy.data.images.remove(img)
        r, c = k // cols, k % cols
        y0 = (rows - 1 - r) * size  # image rows are bottom-up
        sheet[y0:y0 + size, c * size:(c + 1) * size] = px
        # thin separators
        sheet[y0:y0 + size, c * size:c * size + 1] = (0.35, 0.35, 0.35, 1)
        sheet[y0 + size - 1:y0 + size, c * size:(c + 1) * size] = (0.35, 0.35, 0.35, 1)
    os.remove(tmp)
    out_img = bpy.data.images.new("sheet", cols * size, rows * size, alpha=False)
    out_img.pixels[:] = sheet.ravel()
    path = os.path.join(OUT, f"{rel.replace('/', '_')}_{anim}_sheet.png")
    out_img.filepath_raw = path
    out_img.file_format = "PNG"
    out_img.save()
    bpy.data.images.remove(out_img)
    for ob in extra + [cam]:
        bpy.data.objects.remove(ob, do_unlink=True)
    print(f"SHEET {rel} {anim} frames={frames} view={view} trace={[j.name for j in trace]} -> "
          f"{os.path.relpath(path, os.path.join(HERE, '..', '..'))}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    pos, o = parse(argv)
    if not pos:
        print(__doc__)
        return
    rel = pos[0].replace("\\", "/").removesuffix(".py")
    anims = pos[1:]
    os.makedirs(OUT, exist_ok=True)
    spec = importlib.util.spec_from_file_location("m", os.path.join(MODELS, rel + ".py"))
    mod = importlib.util.module_from_spec(spec)
    sb.reset()
    spec.loader.exec_module(mod)
    mod.build()
    setup_world(o["eevee"])
    sync_viewport_colors()
    names = all_tracks()
    for a in anims or names:
        if a not in names:
            print(f"SHEET_MISSING {rel} has no animation '{a}' (has {names})")
            continue
        render_anim(rel, a, o)


main()
