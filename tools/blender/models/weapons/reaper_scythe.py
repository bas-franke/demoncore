"""Reaper's Scythe projectile: laid FLAT (Blender XY = Godot XZ), spin centre at the origin.
Bone haft along X through the centre; a black crescent blade sweeps from the haft head (R, 0)
around the centre, its inner cutting edge burning crimson. Spun in code (scythe_projectile.gd)."""
import math
import sb

CATEGORY = "weapons"
R = 0.56          # cutting-edge radius (matches the old code-built blade)
SPAN = 1.8        # radians of blade arc
N = 18            # samples along the blade


def _blade(parent, steel, edge):
    verts, faces, mats = [], [], []
    rows = []
    for i in range(N + 1):
        u = i / N
        t = u * SPAN
        # width swells just past the heel, then tapers to a hooked needle point
        w = 0.26 * (1.0 - u ** 1.35) * (0.82 + 0.35 * math.sin(min(u * 3.2, math.pi * 0.5))) + 0.004
        h = 0.03 * (1.0 - 0.7 * u) + 0.004
        r_edge = R - 0.035 * u * u          # the point curls inward a little
        c, s = math.cos(t), math.sin(t)
        sec = [(r_edge, 0.0), (r_edge + 0.45 * w, h), (r_edge + w, 0.62 * h),
               (r_edge + w + 0.006, 0.0), (r_edge + w, -0.62 * h), (r_edge + 0.45 * w, -h)]
        base = len(verts)
        for rr, z in sec:
            verts.append((c * rr, s * rr, z))
        rows.append(base)
    for a, b in zip(rows[:-1], rows[1:]):
        for k in range(6):
            j = (k + 1) % 6
            faces.append([a + k, a + j, b + j, b + k])
            mats.append(1 if k in (0, 5) else 0)  # faces touching the edge vertex burn
    faces.append([rows[0] + k for k in range(6)])
    mats.append(0)
    tip = len(verts)
    tt = SPAN + 0.12
    verts.append((math.cos(tt) * (R - 0.02), math.sin(tt) * (R - 0.02), 0.0))
    for k in range(6):
        faces.append([rows[-1] + k, rows[-1] + (k + 1) % 6, tip])
        mats.append(1 if k in (0, 5) else 0)
    o = sb.mesh_from("blade", parent, verts, faces, steel)
    o.data.materials.append(edge)
    for p, m in zip(o.data.polygons, mats):
        p.material_index = m
    return o


def _spine_teeth(parent, steel):
    # three back-swept barbs on the spine near the heel
    for k, u in enumerate((0.12, 0.24, 0.36)):
        t = u * SPAN
        w = 0.26 * (1.0 - u ** 1.35) * (0.82 + 0.35 * math.sin(min(u * 3.2, math.pi * 0.5)))
        rr = R + w
        ln = 0.09 - k * 0.018
        base = [(rr - 0.01, -0.035), (rr - 0.01, 0.035)]
        pts = []
        for (r0, dt) in base:
            pts.append((math.cos(t + dt / rr) * r0, math.sin(t + dt / rr) * r0))
        tipr = rr + ln
        tip = (math.cos(t - 0.07) * tipr, math.sin(t - 0.07) * tipr)
        outline = [pts[0], tip, pts[1]]
        sb.extrude_outline(f"barb{k}", parent, outline, 0.018, steel)


def build():
    bone = sb.mat("Scythe_Bone", (0.66, 0.6, 0.5), roughness=0.6)
    leather = sb.mat("Scythe_LeatherStrap", (0.16, 0.1, 0.07), roughness=0.85)
    steel = sb.mat("Scythe_SteelBlade", (0.42, 0.4, 0.4), roughness=0.3, metallic=0.55)
    iron = sb.mat("Scythe_Iron", (0.18, 0.16, 0.15), roughness=0.45, metallic=0.85)
    edge = sb.mat("Scythe_EdgeGlow", (0.45, 0.04, 0.04), roughness=0.3, emission=(1.0, 0.14, 0.08), strength=6.0)

    root = sb.root("ReaperScythe")
    _blade(root, steel, edge)
    _spine_teeth(root, steel)

    # Bone haft along X: knuckled like a spine, from the pommel (-0.64) to the head (R).
    prof = [(0.0, -0.66), (0.05, -0.64)]
    z = -0.6
    while z < R - 0.05:
        prof += [(0.034, z), (0.046, z + 0.035), (0.034, z + 0.07)]
        z += 0.09
    prof += [(0.036, R + 0.02), (0.0, R + 0.03)]
    sb.lathe("haft", root, prof, segments=8, material=bone, rot=(0, 90, 0))
    # Leather grip wraps.
    for x in (-0.36, -0.1):
        sb.lathe(f"wrap{x}", root, [(0.0, x - 0.065), (0.052, x - 0.06), (0.056, x), (0.052, x + 0.06), (0.0, x + 0.065)],
                 segments=8, material=leather, rot=(0, 90, 0))
    # Pommel: a little horned skull-knob of bone with an iron spike.
    sb.sphere("pommel", root, radius=0.07, loc=(-0.68, 0, 0), scale=(1.1, 0.9, 0.8), material=bone, segments=10, rings=6)
    sb.cylinder("spike", root, r1=0.03, r2=0.0, depth=0.12, loc=(-0.73, 0, 0), rot=(0, -90, 0), material=iron,
                segments=6, bevel=0)
    # Iron socket clamping blade to haft, with a rivet collar.
    sb.box("socket", root, size=(0.14, 0.1, 0.09), loc=(R + 0.02, 0.02, 0), material=iron, bevel=0.012)
    sb.cylinder("collar", root, r1=0.06, r2=0.055, depth=0.04, loc=(R - 0.1, 0, 0), rot=(0, 90, 0), material=iron,
                segments=8, bevel=0.005)
    sb.join_meshes(root, "reaper_scythe")
    sb.tri_count(root)
    return root
