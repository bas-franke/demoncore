"""Ravager's Cleave: a ghostly executioner's greatsword that sweeps the cleave arc.
Points along -Y (Godot -Z). Hilt at the origin end, tip at y = -1.0 (scaled to reach in code).
Rendered half-spectral in Godot: the 'Spectral' materials become additive glow."""
import math
import sb

CATEGORY = "weapons"


def build():
    steel = sb.mat("Cleave_SteelBlade", (0.12, 0.1, 0.1), roughness=0.3, metallic=0.9)
    edge = sb.mat("Cleave_EdgeGlow", (1.0, 0.45, 0.15), roughness=0.3, emission=(1.0, 0.36, 0.08), strength=5.0)
    rune = sb.mat("Cleave_RuneGlow", (1.0, 0.6, 0.3), roughness=0.3, emission=(1.0, 0.55, 0.2), strength=7.0)
    iron = sb.mat("Cleave_Iron", (0.16, 0.14, 0.13), roughness=0.4, metallic=0.85)
    leather = sb.mat("Cleave_LeatherGrip", (0.14, 0.08, 0.06), roughness=0.85)
    root = sb.root("RavagerSword")

    # Broad blade, flat in XY (it sweeps flat), with a diamond cross-section and a clipped,
    # slightly hooked tip. Edge faces glow.
    y0, y1 = -0.2, -1.0
    n = 10
    verts, faces, mats = [], [], []
    rows = []
    for i in range(n + 1):
        u = i / n
        y = y0 + (y1 - y0) * u
        w = 0.085 * (1.0 - 0.25 * u) * (1.0 if u < 0.82 else max(0.05, 1.0 - (u - 0.82) / 0.18 * 0.95))
        h = 0.022 * (1.0 - 0.6 * u)
        ew = 0.016
        sec = [(-w, 0), (-w + ew, h * 0.5), (0, h), (w - ew, h * 0.5), (w, 0), (w - ew, -h * 0.5), (0, -h), (-w + ew, -h * 0.5)]
        rows.append(len(verts))
        for x, z in sec:
            verts.append((x, y, z))
    for a, b in zip(rows[:-1], rows[1:]):
        for k in range(8):
            j = (k + 1) % 8
            faces.append([a + k, a + j, b + j, b + k])
            mats.append(1 if k in (0, 3, 4, 7) else 0)
    faces.append([rows[0] + k for k in range(8)][::-1])
    mats.append(0)
    tip = len(verts)
    verts.append((0.01, y1 - 0.06, 0))
    for k in range(8):
        faces.append([rows[-1] + k, rows[-1] + (k + 1) % 8, tip])
        mats.append(1)
    o = sb.mesh_from("blade", root, verts, faces, steel)
    o.data.materials.append(edge)
    for p, m in zip(o.data.polygons, mats):
        p.material_index = m
    # Fuller runes: glowing sigils down the centre on both faces.
    for k in range(5):
        y = -0.3 - k * 0.11
        for zs in (1, -1):
            sb.box(f"rune{k}{zs}", root, size=(0.03 if k % 2 else 0.018, 0.05, 0.006),
                   loc=(0, y, zs * 0.02 * (1.0 - 0.6 * (y0 - y) / (y0 - y1)) * 0.9), rot=(0, 0, 45 if k % 2 else 0),
                   material=rune, bevel=0)
    # Crossguard: down-swept iron quillons with skull-boss.
    sb.ptube("guard", root, [(-0.2, -0.13, 0), (-0.13, -0.18, 0), (0, -0.2, 0), (0.13, -0.18, 0), (0.2, -0.13, 0)],
             [0.012, 0.024, 0.03, 0.024, 0.012], sides=6, material=iron)
    sb.sphere("boss", root, radius=0.045, loc=(0, -0.2, 0), scale=(1, 0.8, 0.8), material=iron, segments=8, rings=6)
    # Grip and pommel.
    sb.lathe("grip", root, [(0.0, 0.0), (0.024, 0.005), (0.028, 0.05), (0.024, 0.1), (0.028, 0.15), (0.022, 0.19),
                            (0.0, 0.195)], segments=7, material=leather, rot=(90, 0, 0), loc=(0, 0.0, 0))
    sb.sphere("pommel", root, radius=0.04, loc=(0, 0.03, 0), material=iron, segments=8, rings=6)
    sb.cylinder("pommel_spike", root, r1=0.02, r2=0.0, depth=0.06, loc=(0, 0.06, 0), rot=(-90, 0, 0),
                material=iron, segments=5, bevel=0)
    sb.join_meshes(root, "ravager_sword")
    sb.tri_count(root)
    return root
