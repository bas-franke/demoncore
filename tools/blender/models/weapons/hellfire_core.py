"""Hellfire Bolt core: a charred, cracked skull with molten fire welling through the cracks,
blazing eye sockets, and a crown of jagged meteor-rock shards swept back behind it.
Faces -Y (Godot -Z = flight direction). ~0.4 m across; the fire halo / tail stay in code."""
import math
import os
import random
import sb

CATEGORY = "weapons"


def build():
    char = sb.mat("Core_CharredBone", (0.09, 0.06, 0.05), roughness=0.85)
    rock = sb.mat("Core_ObsidianRock", (0.05, 0.04, 0.04), roughness=0.55)
    magma = sb.mat("Core_Magma", (1.0, 0.5, 0.15), roughness=0.4, emission=(1.0, 0.42, 0.1), strength=6.0)
    hot = sb.mat("Core_WhiteHot", (1.0, 0.85, 0.6), roughness=0.4, emission=(1.0, 0.8, 0.5), strength=10.0)

    root = sb.root("HellfireCore")
    if os.environ.get("SB_LIFT"):
        root.location = (0, 0, 0.3)
    # Molten heart: slightly smaller than the skull; shows through where the skull is cracked.
    sb.sphere("heart", root, radius=0.135, loc=(0, 0.01, 0.01), scale=(1.0, 1.15, 0.95), material=magma,
              segments=10, rings=6)
    # Cranium: a lumpy, cracked dome (displaced so the heart burns through in places).
    cran = sb.sphere("cranium", root, radius=0.15, loc=(0, 0.02, 0.03), scale=(0.92, 1.12, 0.95), material=char,
                     segments=12, rings=8)
    sb.displace(cran, strength=0.012, scale=0.05)
    # Molten cracks crawling over the cranium.
    from mathutils import Vector
    rc = random.Random(11)
    ctr = Vector((0, 0.02, 0.03))
    radii = Vector((0.15 * 0.92, 0.15 * 1.12, 0.15 * 0.95))
    for k in range(6):
        d = Vector((rc.uniform(-1, 1), rc.uniform(-0.3, 1), rc.uniform(0.1, 1))).normalized()
        pts = []
        for j in range(5):
            p = ctr + Vector((d.x * radii.x, d.y * radii.y, d.z * radii.z)) * 1.02
            pts.append(tuple(p))
            d = (d + Vector((rc.uniform(-0.45, 0.45), rc.uniform(-0.45, 0.45), rc.uniform(-0.45, 0.45)))).normalized()
        sb.ptube(f"crack{k}", root, pts, [0.004, 0.009, 0.01, 0.007, 0.003], sides=4, material=hot)
    # Brow ridge + cheekbones + upper jaw (the face, toward -Y).
    sb.box("brow", root, size=(0.24, 0.07, 0.05), loc=(0, -0.12, 0.04), material=char, bevel=0.024, taper=(0.85, 0.7))
    for s in (-1, 1):
        sb.box(f"cheek{s}", root, size=(0.06, 0.08, 0.06), loc=(0.085 * s, -0.11, -0.04), rot=(0, 0, -20 * s),
               material=char, bevel=0.012)
        # Blazing eye sockets.
        sb.sphere(f"eye{s}", root, radius=0.042, loc=(0.054 * s, -0.14, 0.0), scale=(1.0, 0.6, 0.85), material=hot,
                  segments=8, rings=5)
    sb.box("maxilla", root, size=(0.13, 0.08, 0.06), loc=(0, -0.12, -0.075), material=char, bevel=0.015, taper=(0.8, 0.8))
    sb.cylinder("nose", root, r1=0.02, r2=0.0, depth=0.045, loc=(0, -0.158, -0.055), rot=(0, 0, 0), material=magma,
                segments=3, bevel=0)
    # Jaw hangs open in a scream: mouth glows.
    sb.box("jaw", root, size=(0.14, 0.1, 0.035), loc=(0, -0.09, -0.15), rot=(-18, 0, 0), material=char, bevel=0.012,
           taper=(0.75, 0.9))
    sb.box("mouth", root, size=(0.1, 0.03, 0.04), loc=(0, -0.13, -0.115), material=hot, bevel=0)
    for k in range(5):
        x = -0.04 + k * 0.02
        sb.cylinder(f"tooth{k}", root, r1=0.008, r2=0.0, depth=0.025, loc=(x, -0.152, -0.1), rot=(180, 0, 0),
                    material=char, segments=4, bevel=0)

    # Crown of jagged meteor shards swept back (+Y) and out, glowing at their roots.
    rnd = random.Random(7)
    for k in range(7):
        a = k / 7 * 2 * math.pi + 0.3
        tilt_out = 50 + rnd.uniform(-10, 15)
        ln = rnd.uniform(0.13, 0.22)
        x, z = math.cos(a) * 0.11, math.sin(a) * 0.11
        o = sb.cylinder(f"shard{k}", root, r1=rnd.uniform(0.035, 0.05), r2=0.0, depth=ln, loc=(x, 0.06, z),
                        rot=(0, 0, 0), material=rock, segments=4, bevel=0, smooth=False)
        # point it back (+Y) and outward
        d = (math.cos(a) * math.sin(math.radians(tilt_out)), math.cos(math.radians(tilt_out)),
             math.sin(a) * math.sin(math.radians(tilt_out)))
        from mathutils import Vector
        o.rotation_euler = Vector((0, 0, 1)).rotation_difference(Vector(d)).to_euler()
        sb.sphere(f"shardglow{k}", root, radius=0.028, loc=(x, 0.06, z), material=magma, segments=6, rings=4)
    sb.join_meshes(root, "hellfire_core")
    sb.tri_count(root)
    return root
