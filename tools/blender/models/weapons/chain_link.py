"""Infernal Chain link: one hand-forged, slightly irregular oval link, heated from within
(inner faces glow). Lies in the XY plane, long along Y (Godot: XZ plane, long along Z).
Outer length 0.3 m. infernal_chain.gd strings these between targets, alternating 90 deg."""
import math
import os
import random
import sb
from mathutils import Vector

CATEGORY = "weapons"


def build():
    iron = sb.mat("Chain_Iron", (0.11, 0.09, 0.08), roughness=0.5, metallic=0.85)
    hot = sb.mat("Chain_HeatGlow", (0.8, 0.2, 0.05), roughness=0.4, emission=(1.0, 0.22, 0.04), strength=3.0)
    root = sb.root("ChainLink")
    if os.environ.get("SB_LIFT"):
        root.location = (0, 0, 0.1)
    rnd = random.Random(5)
    L, W, R = 0.3, 0.18, 0.022      # outer length, outer width, bar radius
    hl, hw = L * 0.5 - R, W * 0.5 - R
    # Stadium centre-line.
    path = []
    seg = 5
    for side, cy in ((1, hl - hw), (-1, -(hl - hw))):
        for k in range(seg + 1):
            a = (k / seg) * math.pi if side == 1 else math.pi + (k / seg) * math.pi
            path.append(Vector((math.cos(a) * hw, cy + math.sin(a) * hw, 0)))
    n = len(path)
    sides = 6
    verts, faces, mats = [], [], []
    for i, p in enumerate(path):
        t = (path[(i + 1) % n] - path[i - 1]).normalized()
        outward = Vector((0, 0, 1)).cross(t).normalized() * -1  # points away from link centre
        up = Vector((0, 0, 1))
        r = R * (1.0 + rnd.uniform(-0.12, 0.12))   # hammered
        for k in range(sides):
            a = 2 * math.pi * k / sides
            verts.append(tuple(p + (outward * math.cos(a) + up * math.sin(a)) * r))
    for i in range(n):
        j = (i + 1) % n
        for k in range(sides):
            kk = (k + 1) % sides
            faces.append([i * sides + k, i * sides + kk, j * sides + kk, j * sides + k])
            # k ~ sides/2 faces the inside of the link
            a = 2 * math.pi * (k + 0.5) / sides
            mats.append(1 if math.cos(a) < -0.45 else 0)
    o = sb.mesh_from("link", root, verts, faces, iron, smooth=True)
    o.data.materials.append(hot)
    for p, m in zip(o.data.polygons, mats):
        p.material_index = m
    # The forge weld: a small lump on one long side.
    sb.sphere("weld", root, radius=R * 1.25, loc=(hw, 0, 0), scale=(1, 1.6, 1), material=iron, segments=6, rings=4)
    sb.join_meshes(root, "chain_link")
    sb.tri_count(root)
    return root
