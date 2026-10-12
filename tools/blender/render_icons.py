"""Renders the painted-look UI icons (Elden-Ring-style item icons) for SINBOUND.

  blender -b --factory-startup --python tools/blender/render_icons.py -- all
  blender -b --factory-startup --python tools/blender/render_icons.py -- hellfire_bolt might

Each tools/blender/icons/<id>.py defines:

    ACCENT = (r, g, b)      # rim / back-glow colour (0..1)
    VIEW = {"pitch": 8, "yaw": 0, "fill": 0.84}   # optional camera tweaks
    def build(): ...        # model the object (any size; it is normalised + auto-framed)

and is written to res://assets/icons/<id>.png (256 px, transparent): EEVEE render at 2x with a warm
key, a strong accent-coloured rim, then a numpy post pass: Kuwahara "brush" filter (painted look),
bloom on the emissive parts, a dark contact halo and a dark radial vignette backdrop.
Re-import in Godot afterwards (the editor or `--headless --import`).
"""
import importlib.util
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.normpath(os.path.join(HERE, "..", ".."))
ICONS = os.path.join(HERE, "icons")
OUT = os.path.join(PROJECT, "assets", "icons")
sys.path.insert(0, HERE)
sys.path.insert(0, ICONS)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
import sb  # noqa: E402
from mathutils import Vector, Matrix, Euler  # noqa: E402

SIZE = 256
SS = 2  # supersampling factor for the render (post filters run at this size)


# ----------------------------------------------------------------------------- scene

def _normalise():
    """Parents every top-level object under one empty, centres the model and scales it to ~2 m."""
    bpy.context.view_layer.update()
    tops = [o for o in bpy.context.scene.objects if o.parent is None]
    holder = bpy.data.objects.new("IconHolder", None)
    bpy.context.scene.collection.objects.link(holder)
    for o in tops:
        mw = o.matrix_world.copy()
        o.parent = holder
        o.matrix_world = mw
    lo, hi = _bounds()
    size = max((hi - lo).length, 1e-3)
    s = 2.4 / size
    holder.scale = (s, s, s)
    holder.location = -(lo + hi) * 0.5 * s
    bpy.context.view_layer.update()


def _mesh_points():
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in bpy.context.scene.objects:
        if o.type not in {"MESH", "CURVE"} or o.hide_render:
            continue
        ev = o.evaluated_get(dg)
        try:
            me = ev.to_mesh()
        except RuntimeError:
            continue
        mw = ev.matrix_world
        pts.extend(mw @ v.co for v in me.vertices)
        ev.to_mesh_clear()
    return pts


def _bounds():
    pts = _mesh_points()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def _light(name, kind, energy, color, loc, size=1.0, target=(0, 0, 0)):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = color
    if kind == "AREA":
        ld.size = size
    elif kind in {"POINT", "SPOT"}:
        ld.shadow_soft_size = size
    ob = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    d = Vector(target) - Vector(loc)
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return ob


def _setup(accent, view):
    sc = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    sc.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else engines[0]
    sc.render.resolution_x = SIZE * SS
    sc.render.resolution_y = SIZE * SS
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    try:
        sc.view_settings.view_transform = "Standard"
        sc.view_settings.look = "Medium High Contrast"
    except TypeError:
        try:
            sc.view_settings.view_transform = "Filmic"
        except TypeError:
            pass
    sc.view_settings.exposure = view.get("exposure", 0.3)
    ee = sc.eevee
    for attr, val in (("taa_render_samples", 64), ("use_raytracing", True), ("use_shadows", True),
                      ("use_gtao", True)):
        if hasattr(ee, attr):
            try:
                setattr(ee, attr, val)
            except (TypeError, AttributeError):
                pass

    world = bpy.data.worlds.new("IconWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.045, 0.036, 0.03, 1)
    bg.inputs["Strength"].default_value = 0.5
    sc.world = world

    a = tuple(accent)
    warm = (1.0, 0.8, 0.58)
    # Key: warm, high and to the left, slightly in front.
    _light("Key", "AREA", 340.0 * view.get("key", 1.0), warm, (-2.6, -3.0, 3.0), size=1.6)
    # Rims: strong accent-coloured lights from behind, both sides, for the dramatic outline.
    rim = view.get("rim", 1.0)
    _light("RimR", "AREA", 900.0 * rim, a, (2.6, 2.8, 1.6), size=1.0)
    _light("RimL", "AREA", 520.0 * rim, a, (-2.8, 2.6, -0.6), size=1.0)
    _light("RimTop", "AREA", 300.0 * rim, tuple(0.5 + 0.5 * c for c in a), (0.3, 1.8, 3.4), size=1.2)
    # Low cold fill from below/front so the shadows are not pure black.
    _light("Fill", "AREA", 60.0 * view.get("fill_light", 1.0), (0.55, 0.6, 0.75), (1.5, -3.2, -1.6), size=3.0)


def _camera(view):
    sc = bpy.context.scene
    cd = bpy.data.cameras.new("IconCam")
    cd.type = "ORTHO"
    cam = bpy.data.objects.new("IconCam", cd)
    sc.collection.objects.link(cam)
    pitch = math.radians(view.get("pitch", 8.0))
    yaw = math.radians(view.get("yaw", 0.0))
    d = 10.0
    off = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch))) * d
    cam.location = off
    cam.rotation_euler = (-off).to_track_quat("-Z", "Y").to_euler()
    roll = view.get("roll", 0.0)
    if roll:
        cam.rotation_euler.rotate(Euler((0, 0, 0)))
        cam.matrix_world = cam.matrix_world @ Matrix.Rotation(math.radians(roll), 4, "Z")
    bpy.context.view_layer.update()
    # Fit the projected silhouette.
    inv = cam.matrix_world.inverted()
    pts = [inv @ p for p in _mesh_points()]
    xs = [p.x for p in pts]
    ys = [p.y for p in pts]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    cx, cy = (max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5
    cd.ortho_scale = max(w, h) / view.get("fill", 0.82)
    cd.clip_start = 0.1
    cd.clip_end = 40.0
    cam.matrix_world = cam.matrix_world @ Matrix.Translation((cx, cy, 0.0))
    sc.camera = cam
    return cam


# ----------------------------------------------------------------------------- post (numpy)

def _load_rgba(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return a  # bottom-up rows, straight alpha, display (sRGB) values


def _box(a, r, axis):
    if r <= 0:
        return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return (hi - lo) / (2 * r + 1)


def _blur(a, r, passes=3):
    for _ in range(passes):
        a = _box(_box(a, r, 0), r, 1)
    return a


def _kuwahara(rgb, r):
    """Classic Kuwahara: each pixel takes the mean of whichever of its 4 overlapping (r+1)^2
    quadrants is flattest -> flat painted strokes with crisp edges."""
    k = r + 1
    lum = rgb @ np.array([0.3, 0.59, 0.11], dtype=np.float32)

    def mean_k(x):  # mean over window [y, y+k) x [x, x+k), edge padded
        pad = [(0, k)] * 2 + [(0, 0)] * (x.ndim - 2)
        c = np.pad(x, pad, mode="edge").cumsum(0).cumsum(1)
        c = np.pad(c, [(1, 0), (1, 0)] + [(0, 0)] * (x.ndim - 2))
        H, W = x.shape[:2]
        return (c[k:k + H, k:k + W] - c[0:H, k:k + W] - c[k:k + H, 0:W] + c[0:H, 0:W]) / (k * k)

    m = mean_k(rgb)
    ml = mean_k(lum)
    v = mean_k(lum * lum) - ml * ml
    H, W = lum.shape

    def shift(x, dy, dx):  # value of x at (y+dy, x+dx), edge clamped
        ys = np.clip(np.arange(H) + dy, 0, H - 1)
        xs = np.clip(np.arange(W) + dx, 0, W - 1)
        return x[ys][:, xs]

    quads = [(-r, -r), (-r, 0), (0, -r), (0, 0)]
    vs = np.stack([shift(v, dy, dx) for dy, dx in quads])
    ms = np.stack([shift(m, dy, dx) for dy, dx in quads])
    idx = np.argmin(vs, axis=0)
    return np.take_along_axis(ms, idx[None, :, :, None], axis=0)[0]


def _smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _post(src, accent, view):
    a = _load_rgba(src)
    H, W = a.shape[:2]
    rgb, al = a[..., :3], a[..., 3:4]
    acc = np.array(accent, dtype=np.float32)

    # Painted look: Kuwahara on premultiplied colour, then un-premultiply.
    pm = rgb * al
    pm = _kuwahara(pm, view.get("brush", 3))
    al_k = _kuwahara(np.repeat(al, 3, axis=2), view.get("brush", 3))[..., :1]
    al = np.maximum(al_k, al * 0.0)
    rgb = np.where(al > 1e-4, pm / np.maximum(al, 1e-4), 0.0)
    rgb = np.clip(rgb, 0.0, 1.0)

    # Grade: crush the darks a touch, warm the mids, keep highlights.
    lum = (rgb @ np.array([0.3, 0.59, 0.11], dtype=np.float32))[..., None]
    rgb = np.clip(lum + (rgb - lum) * view.get("sat", 0.95), 0, 1)
    rgb = rgb * np.array([1.03, 1.0, 0.95], dtype=np.float32)
    rgb = np.clip((rgb - 0.015) / 0.985, 0, 1) ** 1.05

    # Bloom from the bright parts.
    lum = (rgb @ np.array([0.3, 0.59, 0.11], dtype=np.float32))[..., None]
    bright = np.clip(lum - 0.62, 0, 1) / 0.38 * al
    glow_src = rgb * bright
    g1 = _blur(glow_src, max(2, W // 96))
    g2 = _blur(glow_src, max(4, W // 32))
    glow = g1 * 0.9 + g2 * 1.3 * view.get("bloom", 1.0)
    glow_a = np.clip(glow.max(axis=2, keepdims=True) * 1.3, 0, 1)

    # Contact halo: a soft dark rim around the object so it separates from the back-glow.
    halo = np.clip(_blur(al, max(2, W // 80)) * 1.6, 0, 1) * 0.75

    # Backdrop: dark radial vignette disc + faint accent back-glow, transparent at the corners.
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    cx, cy = (W - 1) * 0.5, (H - 1) * 0.5
    d = np.sqrt(((xx - cx) / (W * 0.5)) ** 2 + ((yy - cy) / (H * 0.5)) ** 2)[..., None]
    bg_a = (1.0 - _smoothstep(0.42, 1.02, d)) * 0.94
    base = np.array([0.03, 0.024, 0.021], dtype=np.float32)
    back = np.clip(1.0 - d / 0.75, 0, 1) ** 1.8 * 0.32 * view.get("backglow", 1.0)
    bg_rgb = base + acc * back
    # Subtle mottled "canvas" in the backdrop.
    rng = np.random.default_rng(7)
    n = _blur(rng.random((H, W, 1), dtype=np.float32), max(2, W // 64), 2)
    n = (n - n.mean()) / (n.std() + 1e-6)
    bg_rgb = np.clip(bg_rgb * (1.0 + 0.1 * n), 0, 1)

    # Composite (premultiplied): bg <- halo <- glow (additive) <- object.
    out_pm = bg_rgb * bg_a
    out_a = bg_a
    out_pm = out_pm * (1 - halo)
    out_a = halo + out_a * (1 - halo)
    out_pm = out_pm + glow * 0.9
    out_a = np.clip(out_a + glow_a * (1 - out_a) * 0.8, 0, 1)
    out_pm = rgb * al + out_pm * (1 - al)
    out_a = al + out_a * (1 - al)

    # Downsample (box) to the final size.
    f = SS
    out_pm = out_pm.reshape(H // f, f, W // f, f, 3).mean(axis=(1, 3))
    out_a = out_a.reshape(H // f, f, W // f, f, 1).mean(axis=(1, 3))
    out_rgb = np.where(out_a > 1e-4, out_pm / np.maximum(out_a, 1e-4), 0)
    return np.clip(np.concatenate([out_rgb, out_a], axis=2), 0, 1)


def _save(rgba, path):
    h, w = rgba.shape[:2]
    img = bpy.data.images.new("icon_out", w, h, alpha=True)
    img.pixels[:] = rgba.astype(np.float32).ravel()
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=true
process/premult_alpha=false
detect_3d/compress_to=0
"""


def _write_import(png):
    """First render only: a .import asking Godot for mipmaps (icons are drawn at 30-110 px)."""
    imp = png + ".import"
    if not os.path.exists(imp):
        with open(imp, "w", encoding="utf-8") as f:
            f.write(IMPORT_TEMPLATE)


# ----------------------------------------------------------------------------- main

def render(icon_id):
    spec = importlib.util.spec_from_file_location("icon_" + icon_id, os.path.join(ICONS, icon_id + ".py"))
    mod = importlib.util.module_from_spec(spec)
    sb.reset()
    spec.loader.exec_module(mod)
    mod.build()
    accent = getattr(mod, "ACCENT", (1.0, 0.45, 0.15))
    view = dict(getattr(mod, "VIEW", {}))
    _normalise()
    _setup(accent, view)
    _camera(view)
    import tempfile
    raw = os.path.join(tempfile.gettempdir(), "sinbound_icon_raw_" + icon_id + ".png")
    bpy.context.scene.render.filepath = raw
    bpy.ops.render.render(write_still=True)
    out = os.path.join(OUT, icon_id + ".png")
    _save(_post(raw, accent, view), out)
    _write_import(out)
    if os.environ.get("ICON_KEEP_RAW") is None:
        os.remove(raw)
    print(f"ICON {icon_id} -> {out}")


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(OUT, exist_ok=True)
    if not args or args == ["all"]:
        args = sorted(f[:-3] for f in os.listdir(ICONS) if f.endswith(".py") and not f.startswith("_"))
    failed = []
    for icon_id in args:
        try:
            render(icon_id.removesuffix(".py"))
        except Exception:  # noqa: BLE001
            import traceback
            traceback.print_exc()
            failed.append(icon_id)
    if failed:
        print("ICON FAILED: " + " ".join(failed))


main()
