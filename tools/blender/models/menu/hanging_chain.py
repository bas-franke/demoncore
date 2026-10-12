"""Heavy iron chain hanging from the ceiling (top link at z=0, 5.6 m long, hanging toward -Z)
ending in a meat hook with a skull hung from it. Placed with its top hidden in the ceiling."""
import math
import os
import random
import sys
sys.path.insert(0, os.path.dirname(__file__))
import sb  # noqa: E402
import _kit as kit  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

CATEGORY = "menu"
PITCH = 0.165
LINKS = 34


def link_mesh(name, parent, m, z, turn, seed):
    rnd = random.Random(seed)
    L, W, R = 0.24, 0.13, 0.02
    hl, hw = L * 0.5 - R, W * 0.5 - R
    path = []
    seg = 4
    for side, cz in ((1, hl - hw), (-1, -(hl - hw))):
        for k in range(seg + 1):
            a = (k / seg) * math.pi if side == 1 else math.pi + (k / seg) * math.pi
            path.append(Vector((math.cos(a) * hw, 0.0, cz + math.sin(a) * hw)))
    rotm = Matrix.Rotation(turn, 3, "Z")
    n, sides = len(path), 5
    verts, faces = [], []
    for i, p in enumerate(path):
        t = (path[(i + 1) % n] - path[i - 1]).normalized()
        out = Vector((0, 1, 0)).cross(t).normalized()
        up = Vector((0, 1, 0))
        r = R * (1.0 + rnd.uniform(-0.1, 0.1))
        for k in range(sides):
            a = 2 * math.pi * k / sides
            v = p + (out * math.cos(a) + up * math.sin(a)) * r
            verts.append(tuple(rotm @ v + Vector((0, 0, z))))
    for i in range(n):
        j = (i + 1) % n
        for k in range(sides):
            kk = (k + 1) % sides
            faces.append([i * sides + k, i * sides + kk, j * sides + kk, j * sides + k])
    return sb.mesh_from(name, parent, verts, faces, m["iron"], smooth=True)


def build():
    m = kit.mats()
    root = sb.root("HangingChain")
    for i in range(LINKS):
        link_mesh(f"l{i}", root, m, -i * PITCH, (math.pi / 2) * (i % 2) + 0.1 * math.sin(i), i)
    bottom = -(LINKS - 1) * PITCH - 0.12
    # Meat hook.
    pts = [(0, 0, bottom), (0, 0, bottom - 0.25), (0.02, 0, bottom - 0.45), (0.1, 0, bottom - 0.55), (0.18, 0, bottom - 0.5),
           (0.2, 0, bottom - 0.38)]
    sb.ptube("hook", root, pts, [0.03, 0.03, 0.028, 0.025, 0.02, 0.006], sides=6, material=m["iron"])
    kit.skull("skull", root, m, loc=(0.1, 0, bottom - 0.75), rot=(-15, 0, 20), s=1.5)
    sb.join_meshes(root, "chain")
    sb.tri_count(root)
    return root
