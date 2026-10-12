"""Baked-texture demo: "Reliquary of the Oathbound" -- a knight's shrine showing every sbmat
material (obsidian with ember cracks, weathered marble, worn steel, gold filigree, aged ivory,
leather, linen, feathers). Underscore category = not built by `all`. Build explicitly:

   blender -b --factory-startup --python tools/blender/build.py -- _bake_demo/reliquary
   (SB_BAKE=0 in the environment builds the flat, untextured version for comparison)
"""
import math

import sb
import sbmat

CATEGORY = "_bake_demo"
BAKE = {"size": 1024, "samples": 24}


def _cloth(name, parent, w, h, folds, depth, material, loc, rot=(0, 0, 0)):
    """Hanging cloth: grid in XZ with vertical folds deepening towards the hem."""
    nx, nz = 20, 14
    verts, faces = [], []
    for j in range(nz + 1):
        t = j / nz
        for i in range(nx + 1):
            u = i / nx
            x = (u - 0.5) * w * (1.0 + 0.12 * (1 - t))
            y = depth * math.sin(u * math.pi * folds) * (0.3 + 0.7 * (1 - t)) + 0.01 * math.sin(u * 37 + t * 9)
            z = -t * h + 0.03 * math.sin(u * math.pi * 3) * (1 - t)
            verts.append((x, y, z))
    for j in range(nz):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
    o = sb.mesh_from(name, parent, verts, faces, material, loc=loc, rot=rot, smooth=True)
    s = o.modifiers.new("Solidify", "SOLIDIFY")
    s.thickness = 0.012
    return o


def build():
    obs = sbmat.obsidian_ember("Rel_ObsidianEmber")
    marble = sbmat.weathered_marble("Rel_WeatheredMarble")
    steel = sbmat.worn_steel("Rel_WornSteel", rust=0.25)
    gold = sbmat.gold_filigree("Rel_GoldFiligree")
    ivory = sbmat.aged_ivory("Rel_AgedIvory")
    leather = sbmat.leather("Rel_Leather")
    linen = sbmat.linen("Rel_Linen")
    feath = sbmat.feathers("Rel_Feathers")
    eye = sb.mat("Rel_EyeGlow", (0.3, 0.05, 0.02), 0.5, emission=(1.0, 0.35, 0.08), strength=5.0)

    root = sb.root("Reliquary")
    base = sb.empty("base", root)
    # obsidian plinth (stepped) with ember cracks
    sb.box("plinth_low", base, size=(1.5, 1.5, 0.22), loc=(0, 0, 0.11), material=obs, bevel=0.03)
    sb.box("plinth_high", base, size=(1.15, 1.15, 0.2), loc=(0, 0, 0.32), material=obs, bevel=0.025)
    # marble column with gold collar and leather straps
    sb.lathe("column", base, [(0.36, 0.42), (0.36, 0.5), (0.3, 0.56), (0.27, 0.62), (0.25, 1.25),
                                    (0.28, 1.3), (0.36, 1.38), (0.38, 1.46), (0.0, 1.46)],
                   segments=28, material=marble)
    sb.torus("collar", base, major=0.265, minor=0.035, loc=(0, 0, 1.2), material=gold, minor_segments=10)
    sb.torus("collar_low", base, major=0.29, minor=0.03, loc=(0, 0, 0.6), material=gold, minor_segments=10)
    for k, z in enumerate((0.78, 0.92)):
        sb.torus(f"strap{k}", base, major=0.262, minor=0.018, loc=(0, 0, z), rot=(4 - 8 * k, 0, 0),
                 material=leather, minor_segments=6)
    # gilded tray + ivory skull offering
    sb.box("tray", base, size=(0.7, 0.7, 0.05), loc=(0, 0, 1.485), material=gold, bevel=0.012)
    skull = sb.empty("skull", base, loc=(0.0, -0.14, 1.6))
    sb.sphere("cranium", skull, radius=0.13, scale=(0.9, 1.05, 0.95), material=ivory)
    sb.box("jaw", skull, size=(0.14, 0.1, 0.07), loc=(0, -0.07, -0.09), material=ivory, bevel=0.02)
    for s in (-1, 1):
        sb.sphere(f"socket{s}", skull, radius=0.03, loc=(0.045 * s, -0.11, -0.005), material=eye, segments=10, rings=6)
    # great helm on the tray, behind the skull
    helm = sb.empty("helm", base, loc=(0, 0.12, 1.51))
    sb.lathe("helm_shell", helm, [(0.0, 0.0), (0.17, 0.0), (0.18, 0.12), (0.175, 0.26), (0.15, 0.33),
                                  (0.08, 0.37), (0.0, 0.38)], segments=24, material=steel)
    sb.box("visor_bar", helm, size=(0.05, 0.05, 0.3), loc=(0, -0.17, 0.17), material=steel, bevel=0.01)
    sb.box("brow_band", helm, size=(0.36, 0.05, 0.035), loc=(0, -0.155, 0.24), material=gold, bevel=0.008)
    plume = sb.empty("plume", helm, loc=(0, 0.02, 0.36))
    for k in range(7):
        a = -45 + k * 15
        sb.blade(f"feather{k}", plume, length=0.42 - abs(k - 3) * 0.04, width=0.05, thickness=0.006,
                 rot=(-15 - abs(k - 3) * 4, a * 0.6, 0), curve=0.35, material=feath)
    # linen banner hanging off the front of the plinth
    _cloth("banner", base, 0.6, 0.46, 3.5, 0.03, linen, loc=(0, -0.6, 0.43))
    # worn sword leaning on the plinth
    sword = sb.empty("sword", base, loc=(0.55, -0.45, 0.42), rot=(-12, 18, 0))
    sb.blade("sword_blade", sword, length=0.95, width=0.045, thickness=0.009, loc=(0, 0, 0.0),
             rot=(180, 0, 0), material=steel)
    sb.box("guard", sword, size=(0.24, 0.04, 0.035), loc=(0, 0, 0.02), material=gold, bevel=0.01)
    sb.cylinder("grip", sword, r1=0.018, depth=0.2, loc=(0, 0, 0.035), material=leather, segments=10)
    sb.sphere("pommel", sword, radius=0.032, loc=(0, 0, 0.25), material=gold, segments=12, rings=8)

    sb.anim("idle", {
        plume: [(0, sb.rest(plume)), (30, sb.offset(plume, rot=(4, 3, 0))), (60, sb.rest(plume))],
        skull: [(0, sb.rest(skull)), (30, sb.offset(skull, rot=(0, 0, 6))), (60, sb.rest(skull))],
    }, frames=60)
    return root
