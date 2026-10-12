"""Shared pieces for the select-screen ritual chamber props (not built itself: underscore).
Model scripts do:  sys.path.insert(0, os.path.dirname(__file__)); import _kit as kit"""
import math
import random
import sb


def mats():
    return {
        "stone": sb.mat("Chamber_Stone", (0.3, 0.285, 0.27), roughness=0.9),
        "stone_dark": sb.mat("Chamber_StoneDark", (0.17, 0.16, 0.155), roughness=0.92),
        "marble": sb.mat("Chamber_Marble", (0.42, 0.4, 0.38), roughness=0.55),
        "obsidian": sb.mat("Chamber_Obsidian", (0.05, 0.045, 0.05), roughness=0.35),
        "bone": sb.mat("Chamber_SkullBone", (0.62, 0.56, 0.46), roughness=0.65),
        "void": sb.mat("Chamber_Void", (0.015, 0.01, 0.01), roughness=1.0),
        "iron": sb.mat("Chamber_Iron", (0.13, 0.12, 0.115), roughness=0.5, metallic=0.85),
        "bronze": sb.mat("Chamber_Bronze", (0.32, 0.22, 0.12), roughness=0.45, metallic=0.85),
        "wax": sb.mat("Chamber_CandleWax", (0.72, 0.66, 0.54), roughness=0.55),
        "cloth": sb.mat("Chamber_ClothBanner", (0.28, 0.03, 0.035), roughness=0.95),
        "flame": sb.mat("Chamber_FlameGlow", (1.0, 0.7, 0.35), roughness=0.5, emission=(1.0, 0.62, 0.28), strength=9.0),
        "coal": sb.mat("Chamber_CoalGlow", (0.25, 0.06, 0.02), roughness=0.8, emission=(1.0, 0.3, 0.06), strength=4.0),
        "rune": sb.mat("Chamber_RuneGlow", (0.8, 0.25, 0.08), roughness=0.5, emission=(1.0, 0.32, 0.08), strength=2.5),
    }


def skull(name, parent, m, loc=(0, 0, 0), rot=(0, 0, 0), s=1.0):
    """A human skull ~0.2 m long (s=1), resting on its jaw, facing -Y."""
    g = sb.empty(name, parent, loc=loc, rot=rot)
    g.scale = (s, s, s)
    sb.sphere("cran", g, radius=0.09, loc=(0, 0.02, 0.11), scale=(0.85, 1.05, 0.92), material=m["bone"], segments=12, rings=8)
    sb.box("face", g, size=(0.11, 0.06, 0.07), loc=(0, -0.055, 0.075), material=m["bone"], bevel=0.015, taper=(1.1, 0.9))
    for x in (-1, 1):
        sb.sphere(f"eye{x}", g, radius=0.022, loc=(0.03 * x, -0.085, 0.09), scale=(1, 0.6, 0.9), material=m["void"],
                  segments=8, rings=5)
        sb.box(f"cheek{x}", g, size=(0.03, 0.05, 0.03), loc=(0.05 * x, -0.05, 0.06), material=m["bone"], bevel=0.008)
    sb.cylinder("nose", g, r1=0.012, r2=0.0, depth=0.025, loc=(0, -0.088, 0.045), material=m["void"], segments=3, bevel=0)
    sb.box("jaw", g, size=(0.08, 0.06, 0.03), loc=(0, -0.05, 0.02), material=m["bone"], bevel=0.01, taper=(1.15, 1.0))
    sb.box("teeth", g, size=(0.06, 0.012, 0.02), loc=(0, -0.08, 0.04), material=m["bone"], bevel=0.004)
    return g


def candle(name, parent, m, loc=(0, 0, 0), h=0.3, r=0.045, seed=0, lit=True):
    """Pillar candle with a melted, uneven top, wax drips, wick and a flame."""
    rnd = random.Random(seed)
    g = sb.empty(name, parent, loc=loc)
    prof = [(0.0, 0.0), (r * 1.15, 0.0), (r * 1.08, 0.012), (r, 0.03), (r * rnd.uniform(0.97, 1.03), h * 0.6),
            (r * 1.02, h - 0.015), (r * 0.8, h), (r * 0.25, h - 0.012), (0.0, h - 0.01)]
    sb.lathe("body", g, prof, segments=8, material=m["wax"], jitter=0.04, seed=seed)
    for k in range(rnd.randint(1, 2)):
        a = rnd.uniform(0, 2 * math.pi)
        x, y = math.cos(a) * r * 0.98, math.sin(a) * r * 0.98
        dl = rnd.uniform(0.3, 0.7) * h
        sb.ptube(f"drip{k}", g, [(x, y, h - 0.01), (x * 1.04, y * 1.04, h - dl * 0.5), (x, y, h - dl)],
                 [r * 0.22, r * 0.18, r * 0.12], sides=4, material=m["wax"])
    if lit:
        sb.cylinder("wick", g, r1=0.003, depth=0.02, loc=(0, 0, h - 0.012), material=m["void"], segments=3, bevel=0)
        fh = 0.05 + r * 0.6
        sb.lathe("flame", g, [(0.0, 0.0), (r * 0.32, fh * 0.25), (r * 0.25, fh * 0.6), (0.0, fh)], segments=6,
                 material=m["flame"], loc=(0, 0, h + 0.004))
    return g


def arch_curve(hw, spring, apex, steps=6):
    """Left half of a pointed arch (x from -hw to 0), circle centred on the spring line."""
    rho = (hw * hw + (apex - spring) ** 2) / (2 * hw)
    cx = -hw + rho
    a0 = math.pi
    a1 = math.atan2(apex - spring, 0 - cx)
    return [(cx + math.cos(a0 + (a1 - a0) * i / steps) * rho, spring + math.sin(a0 + (a1 - a0) * i / steps) * rho)
            for i in range(steps + 1)]


def pointed_arch(hw, spring, apex, band_w, steps=6):
    """(outer, inner) polylines (x, height) of a full pointed arch band, left foot to right foot."""
    ol = arch_curve(hw, spring, apex, steps)
    il = arch_curve(hw - band_w, spring, apex - band_w * 1.3, steps)
    outer = ol + [(-x, y) for x, y in reversed(ol[:-1])]
    inner = il + [(-x, y) for x, y in reversed(il[:-1])]
    return outer, inner


def band(outer, inner, depth, name, parent, mat, loc=(0, 0, 0)):
    """Solid band between two (x, height) polylines of equal length, standing in the XZ plane,
    `depth` thick along Y."""
    n = len(outer)
    verts = []
    for y in (-depth * 0.5, depth * 0.5):
        verts += [(x, y, z) for x, z in outer] + [(x, y, z) for x, z in inner]
    o0, i0, o1, i1 = 0, n, 2 * n, 3 * n
    faces = []
    for k in range(n - 1):
        faces.append([o0 + k, o0 + k + 1, i0 + k + 1, i0 + k])
        faces.append([o1 + k, i1 + k, i1 + k + 1, o1 + k + 1])
        faces.append([o0 + k, o1 + k, o1 + k + 1, o0 + k + 1])
        faces.append([i0 + k, i0 + k + 1, i1 + k + 1, i1 + k])
    faces.append([o0, i0, i1, o1])
    faces.append([o0 + n - 1, o1 + n - 1, i1 + n - 1, i0 + n - 1])
    return sb.mesh_from(name, parent, verts, faces, mat, loc=loc)


def slab_xz(name, parent, outline, depth, mat, loc=(0, 0, 0)):
    """Flat polygon (x, height) standing in the XZ plane, extruded `depth` along Y."""
    n = len(outline)
    verts = [(x, -depth * 0.5, z) for x, z in outline] + [(x, depth * 0.5, z) for x, z in outline]
    faces = [list(range(n)), list(reversed(range(n, 2 * n)))]
    for k in range(n):
        j = (k + 1) % n
        faces.append([k, n + k, n + j, j])
    return sb.mesh_from(name, parent, verts, faces, mat, loc=loc)
