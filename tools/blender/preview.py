"""Renders preview PNGs of model scripts (so you can look at them without Godot).

  blender -b --factory-startup --python tools/blender/preview.py -- enemies/choir_wisp [more...]

Writes tools/blender/previews/<category>_<name>.png: left = game-camera view (high angle, ~55 deg),
right = close 3/4 hero view. Uses EEVEE with a dusk key light.
"""
import importlib.util
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
import sb  # noqa: E402
from mathutils import Vector  # noqa: E402

MODELS = os.path.join(HERE, "models")
OUT = os.path.join(HERE, "previews")


def bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    bpy.context.view_layer.update()
    for o in bpy.context.scene.objects:
        if o.type != "MESH" or o.name == "ground":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def setup_scene():
    sc = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    sc.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else engines[0]
    sc.render.resolution_x = 640
    sc.render.resolution_y = 640
    sc.render.film_transparent = False
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.06, 0.06, 0.07, 1)
    bg.inputs["Strength"].default_value = 0.6
    sc.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.0
    sun.data.color = (1.0, 0.85, 0.65)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    sc.collection.objects.link(sun)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
    fill.data.energy = 0.8
    fill.data.color = (0.6, 0.7, 1.0)
    fill.rotation_euler = (math.radians(60), 0, math.radians(150))
    sc.collection.objects.link(fill)
    plane = sb.box("ground", None, size=(30, 30, 0.02), loc=(0, 0, -0.01), material=sb.mat("PrevGround", (0.12, 0.12, 0.11), 1.0))
    return plane


def shoot(path, cam_dir_deg_pitch, yaw_deg, dist_scale):
    lo, hi = bounds()
    center = (lo + hi) * 0.5
    size = max((hi - lo).length, 0.5)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    pitch = math.radians(cam_dir_deg_pitch)
    yaw = math.radians(yaw_deg)
    d = size * dist_scale
    # Character faces -Y; camera in front (-Y side) looking at it.
    off = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch))) * d
    cam.location = center + off
    direction = center - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(OUT, exist_ok=True)
    for rel in args:
        rel = rel.replace("\\", "/").removesuffix(".py")
        spec = importlib.util.spec_from_file_location("m", os.path.join(MODELS, rel + ".py"))
        mod = importlib.util.module_from_spec(spec)
        sb.reset()
        spec.loader.exec_module(mod)
        mod.build()
        setup_scene()
        base = os.path.join(OUT, rel.replace("/", "_"))
        shoot(base + "_game.png", 55, 0, 2.2)
        shoot(base + "_hero.png", 15, 35, 1.6)
        print(f"PREVIEW {rel} -> {base}_game.png / _hero.png")


main()
