"""Reliquary of Sin: a horned black-iron coffer bound in tarnished gilt, crimson sigils burning on
its panels (~1.15 m tall). Boss reward (scenes/bosses/reliquary.gd).

Godot finds the `lid` joint (thrown open) and swaps materials Reliquary_SeamGlow / _SigilGlow /
_HeartCrystal for pulsing additive ones.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _kit as kit  # noqa: E402

CATEGORY = "bosses"
W, D = 0.98, 0.7      # casket width (x) / depth (y)
Z0, Z1 = 0.2, 0.82    # casket bottom / top


def sigil(name, parent, loc, rot, size, glow, gold):
    """A crimson sigil: ring, inverted triangle and a piercing vertical stroke, in a gilt frame."""
    e = sb.empty(name, parent, loc=loc, rot=rot)
    sb.torus(name + "_ring", e, major=size, minor=size * 0.06, rot=(90, 0, 0), material=glow,
             major_segments=24, minor_segments=4)
    for k in range(3):
        a = math.radians(90 + k * 120)
        b = math.radians(90 + (k + 1) * 120)
        p0 = (math.cos(a) * size * -0.85, 0, math.sin(a) * size * -0.85)
        p1 = (math.cos(b) * size * -0.85, 0, math.sin(b) * size * -0.85)
        mid = ((p0[0] + p1[0]) / 2, 0, (p0[2] + p1[2]) / 2)
        ln = math.dist(p0, p1)
        ang = math.degrees(math.atan2(p1[2] - p0[2], p1[0] - p0[0]))
        sb.box(f"{name}_tri{k}", e, size=(ln, size * 0.08, size * 0.07), loc=mid, rot=(0, -ang, 0), material=glow,
               bevel=0.0)
    sb.box(name + "_stroke", e, size=(size * 0.07, size * 0.08, size * 2.5), material=glow, bevel=0.0)
    sb.box(name + "_frame", e, size=(size * 2.5, size * 0.05, size * 2.9), loc=(0, size * 0.06, 0), material=gold,
           bevel=size * 0.05)


def build():
    iron = sb.mat("Reliquary_IronMetal", (0.075, 0.068, 0.072), 0.5, 0.75)
    iron2 = sb.mat("Reliquary_DarkIronPlate", (0.13, 0.11, 0.11), 0.6, 0.6)
    gold = sb.mat("Reliquary_GiltTrim", (0.55, 0.41, 0.18), 0.35, 0.95)
    bone = sb.mat("Reliquary_HornBone", (0.6, 0.55, 0.45), 0.6)
    seam = sb.mat("Reliquary_SeamGlow", (0.85, 0.12, 0.18), 0.4, emission=(0.85, 0.12, 0.18), strength=4.0)
    sig = sb.mat("Reliquary_SigilGlow", (0.85, 0.12, 0.18), 0.4, emission=(0.85, 0.12, 0.18), strength=4.0)
    heart = sb.mat("Reliquary_HeartCrystal", (0.5, 0.03, 0.06), 0.1, emission=(0.95, 0.15, 0.2), strength=5.0)

    root = sb.root("Reliquary")
    body = sb.empty("casket", root)
    # stepped plinth with clawed feet.
    sb.box("plinth0", body, size=(1.2, 0.92, 0.1), loc=(0, 0, 0.05), material=iron, bevel=0.02)
    sb.box("plinth1", body, size=(1.1, 0.82, 0.08), loc=(0, 0, 0.14), material=iron2, bevel=0.015)
    sb.box("plinth_trim", body, size=(1.12, 0.84, 0.02), loc=(0, 0, 0.18), material=gold, bevel=0.0)
    for sx in (1, -1):
        for sy in (1, -1):
            f = sb.empty(f"foot{sx}{sy}", body, loc=(sx * 0.56, sy * 0.42, 0.0))
            for k in range(3):
                a = math.radians(45 * sx * sy + (k - 1) * 30 + (0 if sy < 0 else 180))
                kit.filigree(f"claw{sx}{sy}{k}", f, [(0, 0, 0.12), (math.sin(a) * 0.06 * sx, -math.cos(a) * 0.06 * sy, 0.05),
                                                    (math.sin(a) * 0.1 * sx, -math.cos(a) * 0.1 * sy, 0.0)], 1.0,
                             bone, radii=[0.03, 0.022, 0.006])
    # casket and panels.
    h = Z1 - Z0
    sb.box("casket_box", body, size=(W, D, h), loc=(0, 0, Z0 + h / 2), material=iron, bevel=0.015)
    for y in (Z0 + 0.03, Z1 - 0.03):
        sb.box(f"band{y:.2f}", body, size=(W + 0.03, D + 0.03, 0.05), loc=(0, 0, y), material=gold, bevel=0.008)
    for y in (Z0 + 0.075, Z1 - 0.075):
        sb.box(f"seam{y:.2f}", body, size=(W + 0.012, D + 0.012, 0.016), loc=(0, 0, y), material=seam, bevel=0.0)
    for sx in (1, -1):
        for sy in (1, -1):
            kit.lathe(f"pillar{sx}{sy}", body, [(0.05, Z0), (0.045, Z0 + 0.06), (0.035, Z0 + 0.1), (0.04, Z1 - 0.1),
                                                (0.05, Z1 - 0.05), (0.045, Z1)], 10,
                      loc=(sx * W / 2, sy * D / 2, 0), material=gold)
            kit.crystal(f"finial{sx}{sy}", body, height=0.14, radius=0.035, sides=4, top=0.8,
                        loc=(sx * W / 2, sy * D / 2, Z1 + 0.05), material=gold, jitter=0.0, seed=2)
    zc = (Z0 + Z1) / 2
    # side + back panels with sigils.
    for name, loc, rot, sz in (("back", (0, D / 2 + 0.005, zc), (0, 0, 180), 0.12),
                               ("sideL", (W / 2 + 0.005, 0, zc), (0, 0, 90), 0.1),
                               ("sideR", (-W / 2 - 0.005, 0, zc), (0, 0, -90), 0.1)):
        pw = 0.7 if name == "back" else 0.5
        sb.box(f"panel_{name}", body, size=(pw, 0.012, h - 0.2), loc=loc, rot=rot, material=iron2, bevel=0.004)
        e = sb.empty(f"sig_{name}", body, loc=loc, rot=rot)
        sigil(f"sigil_{name}", e, (0, -0.012, 0), (0, 0, 0), sz, sig, gold)
    # front: crimson heart-stone in a gilt sunburst, flanked by two smaller sigils.
    fr = sb.empty("front", body, loc=(0, -D / 2 - 0.005, zc + 0.02))
    sb.box("panel_front", fr, size=(0.78, 0.012, h - 0.18), loc=(0, 0.004, -0.02), material=iron2, bevel=0.004)
    sb.torus("sun_ring", fr, major=0.13, minor=0.02, rot=(90, 0, 0), loc=(0, -0.02, 0), material=gold,
             major_segments=24, minor_segments=5)
    kit.crystal("heart", fr, height=0.2, radius=0.075, sides=6, top=0.55, loc=(0, -0.04, -0.01), rot=(90, 0, 0),
                material=heart, jitter=0.08, seed=5, scale=(1, 1, 1))
    for i in range(16):
        a = math.tau * i / 16
        ln = 0.13 if i % 2 == 0 else 0.07
        sb.blade(f"sunray{i}", fr, length=ln, width=0.018, thickness=0.006,
                 loc=(math.sin(a) * 0.15, -0.02, math.cos(a) * 0.15), rot=(0, math.degrees(a), 0), material=gold)
    for s in (1, -1):
        sigil(f"sigil_f{s}", fr, (s * 0.3, -0.01, 0), (0, 0, 0), 0.06, sig, gold)
    # lid: peaked roof, gilt ridge with a crimson crack, bone horns curling out of the gable.
    lid = sb.empty("lid", root, loc=(0, 0, Z1 + 0.01))
    sb.box("lid_base", lid, size=(W + 0.08, D + 0.08, 0.07), loc=(0, 0, 0.035), material=iron, bevel=0.012)
    sb.box("lid_trim", lid, size=(W + 0.1, D + 0.1, 0.018), loc=(0, 0, 0.01), material=gold, bevel=0.0)
    sb.box("lid_roof", lid, size=(W + 0.02, D + 0.02, 0.26), loc=(0, 0, 0.2), material=iron, bevel=0.01,
           taper=(1.0, 0.04))
    sb.box("lid_ridge", lid, size=(W + 0.06, 0.04, 0.035), loc=(0, 0, 0.33), material=gold, bevel=0.008)
    sb.box("lid_crack", lid, size=(W - 0.05, 0.05, 0.012), loc=(0, 0, 0.345), material=seam, bevel=0.0)
    for sy in (1, -1):
        for k in range(5):
            x = (k - 2) * 0.2
            sb.box(f"rib{sy}{k}", lid, size=(0.025, 0.4, 0.02), loc=(x, sy * 0.2, 0.2), rot=(-sy * 50, 0, 0),
                   material=gold, bevel=0.0)
    for sx in (1, -1):
        kit.filigree(f"horn{sx}", lid, [(sx * 0.42, 0, 0.25), (sx * 0.58, -0.04, 0.4), (sx * 0.62, -0.12, 0.6),
                                        (sx * 0.52, -0.2, 0.72), (sx * 0.44, -0.16, 0.66)], 1.0, bone, res=5,
                     radii=[0.07, 0.055, 0.04, 0.022, 0.006])
        for k in range(3):
            sb.cylinder(f"spike{sx}{k}", lid, r1=0.02, r2=0.0, depth=0.12 - k * 0.025,
                        loc=(sx * (0.15 + k * 0.12), 0, 0.33), rot=(0, sx * 15, 0), material=gold, segments=6,
                        bevel=0.0)
    kit.merge_joint_meshes(root)
    print("RELIQUARY TRIS", kit.tri_count())
    return root
