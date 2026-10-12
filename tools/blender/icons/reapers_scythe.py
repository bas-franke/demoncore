"""Reaper's Scythe: a bone-white, crescent-bladed war scythe on a gnarled black haft."""
import math
import sb
import _ikit as k

ACCENT = (0.78, 0.82, 0.92)
VIEW = {"pitch": 6, "yaw": 0, "fill": 0.9, "backglow": 0.6}


def build():
    blade = sb.mat("I_PaleSteel", (0.42, 0.41, 0.4), roughness=0.38, metallic=0.55)
    edge = sb.mat("I_Edge", (0.85, 0.85, 0.9), roughness=0.15, metallic=1.0,
                  emission=(0.75, 0.85, 1.0), strength=1.4)
    wood = sb.mat("I_BlackWood", (0.06, 0.045, 0.04), roughness=0.75)
    bone = sb.mat("I_Bone", (0.55, 0.5, 0.42), roughness=0.6)
    iron = k.metal("I_Iron", (0.12, 0.11, 0.1), 0.45)
    root = sb.root("Scythe")

    # Haft: long, slightly bowed, running bottom-right to top-left.
    haft = [(0.75, 0, -1.25), (0.45, 0, -0.45), (0.15, 0, 0.35), (-0.12, 0, 1.12)]
    sb.ptube("haft", root, haft, [0.05, 0.055, 0.05, 0.06], sides=10, material=wood)
    for i, t in enumerate((0.25, 0.55)):
        p = (0.75 + (-0.87) * t, 0.0, -1.25 + 2.37 * t)
        sb.torus(f"band{i}", root, 0.065, 0.018, loc=p, rot=(0, -20, 0), material=iron)
    sb.ptube("grip", root, [(0.48, 0, -0.5), (0.65, -0.05, -0.38), (0.72, -0.05, -0.3)], [0.03, 0.035, 0.04],
             sides=6, material=bone)
    sb.sphere("pommel", root, 0.08, loc=(0.77, 0, -1.3), material=bone)
    # Socket at the head.
    sb.box("socket", root, (0.17, 0.13, 0.22), loc=(-0.12, 0, 1.1), rot=(0, 20, 0), material=iron, bevel=0.03)
    sb.sphere("skull", root, 0.09, loc=(-0.14, -0.08, 1.12), scale=(0.9, 0.8, 1.0), material=bone)

    # Crescent blade: an outer spine curve from the socket out to the right and down to a point;
    # the cutting edge is offset inward along the curve normal, widest near the socket.
    n = 20
    spine = []
    for i in range(n + 1):
        t = i / n
        a = math.radians(170 - 150 * t)
        spine.append((-0.12 + 1.2 + math.cos(a) * 1.2, 1.15 + math.sin(a) * 0.62 - math.sin(math.radians(170)) * 0.62
                      - 0.25 * t ** 2))
    inner = []
    for i in range(n + 1):
        t = i / n
        p0 = spine[max(i - 1, 0)]
        p1 = spine[min(i + 1, n)]
        tx, ty = p1[0] - p0[0], p1[1] - p0[1]
        ln = math.hypot(tx, ty) or 1.0
        nx, ny = ty / ln, -tx / ln  # right-hand normal = toward the inside of the arc
        w = 0.36 * (1 - t) ** 0.75 + 0.004
        inner.append((spine[i][0] + nx * w, spine[i][1] + ny * w))
    pts = spine + list(reversed(inner))
    sb.extrude_outline("blade", root, pts, 0.035, blade, rot=(90, 0, 0), bevel=0.012)
    edge_pts = [(x, -0.012, y) for x, y in inner]
    sb.ptube("edge", root, edge_pts, [0.014 * (1 - i / (n + 2)) + 0.004 for i in range(n + 1)], sides=5,
             material=edge)
    sb.ptube("spine", root, [(x, 0.0, y + 0.0) for x, y in spine], [0.03 * (1 - i / (n + 2)) + 0.006 for i in range(n + 1)],
             sides=6, material=iron)
    return root
