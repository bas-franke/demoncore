"""Shared helpers for the icon models (tools/blender/icons/*.py). Builds on tools/blender/sb.py."""
import math
import random

import bmesh
import bpy
import sb
from mathutils import Vector


def glow(name, color, strength=6.0, base=None):
    return sb.mat(name, base or color, roughness=0.4, emission=color, strength=strength)


def metal(name, color, roughness=0.35):
    return sb.mat(name, color, roughness=roughness, metallic=1.0)


def glass(name, color, alpha=0.25):
    m = sb.mat(name, color, roughness=0.05)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Alpha"].default_value = alpha
    if hasattr(m, "surface_render_method"):
        m.surface_render_method = "BLENDED"
    elif hasattr(m, "blend_method"):
        m.blend_method = "BLEND"
    return m


def flame(name, parent, base, height, radius, mat, seed=0, lean=(0.0, 0.0), sides=6):
    """A licking tongue of fire: tapered wavy tube rising from `base`."""
    rnd = random.Random(seed)
    b = Vector(base)
    pts, radii = [], []
    n = 6
    for i in range(n + 1):
        t = i / n
        wob = math.sin(t * 5.0 + seed) * radius * 0.6 * t
        p = b + Vector((lean[0] * t * t * height + wob, lean[1] * t * t * height, t * height))
        pts.append(tuple(p))
        radii.append(radius * (1.0 - t) ** 0.8 * (1.0 + 0.25 * math.sin(t * 9 + rnd.random() * 6)) + 0.002)
    return sb.ptube(name, parent, pts, radii, sides=sides, material=mat)


def point_at(obj, direction):
    obj.rotation_euler = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized()).to_euler()
    return obj


def spike(name, parent, base, direction, length, radius, mat, segments=5):
    o = sb.cylinder(name, parent, r1=radius, r2=0.0, depth=length, loc=base, material=mat,
                    segments=segments, bevel=0.0, smooth=False)
    return point_at(o, direction)


def rng(seed):
    return random.Random(seed)


def shell(name, parent, radius, scale, cut_y, thickness, mat, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Front half of an ellipsoid (everything with y > cut_y removed), solidified: masks, plates."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=20, radius=radius)
    for v in bm.verts:
        v.co.x *= scale[0]
        v.co.y *= scale[1]
        v.co.z *= scale[2]
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                           plane_co=(0, cut_y, 0), plane_no=(0, 1, 0), clear_outer=True)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    sol = ob.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = thickness
    sol.offset = 1.0
    return sb._finish(ob, parent, mat, loc, rot, (1, 1, 1), 0.0, 0, True, name)


def teardrop(name, parent, radius, height, mat, loc=(0, 0, 0), rot=(0, 0, 0), segments=24):
    import math as _m
    prof = []
    n = 14
    for i in range(n + 1):
        t = i / n  # 0 bottom .. 1 tip
        if t < 0.5:
            a = _m.pi * (1 - t / 0.5) / 2
            r = radius * _m.cos(a) if t > 0 else 0.0
            z = radius - radius * _m.sin(a)
        else:
            u = (t - 0.5) / 0.5
            r = radius * (1 - u) ** 1.5
            z = radius + (height - radius) * u
        prof.append((max(r, 0.0), z))
    prof[0] = (0.0, 0.0)
    prof[-1] = (0.0, height)
    return sb.lathe(name, parent, prof, segments, mat, loc, rot)


def ghost(name, color, strength=1.0, alpha=0.5):
    """Translucent emissive (souls, wisps)."""
    m = glow(name, color, strength)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Alpha"].default_value = alpha
    if hasattr(m, "surface_render_method"):
        m.surface_render_method = "BLENDED"
    return m
