"""Pointed gothic window frame set into the chamber's back wall. Fits the wall opening built in
demon_select.gd: x in [-1.5, 1.5], z in [2.6, 8.8], wall 0.8 thick centred on y = 0, room side
= -Y (Godot +Z, toward the camera). Spandrels fill the opening's top corners around a pointed
arch springing at z = 6.5; two mullions split it into three lancets, an oculus with cusps in
the head, a hood moulding with label stops, and a deep sill."""
import math
import os
import sys
sys.path.insert(0, os.path.dirname(__file__))
import sb  # noqa: E402
import _kit as kit  # noqa: E402

CATEGORY = "menu"
HW, Y0, SPRING, APEX, TOP = 1.5, 2.6, 6.5, 8.8, 8.8
DEPTH = 0.84


def build():
    m = kit.mats()
    root = sb.root("Window")
    stone, trim = m["stone_dark"], m["stone"]
    # Spandrels (fill between the arch and the rectangular opening's top corners).
    curve = kit.arch_curve(HW, SPRING, APEX, steps=10)
    left = [(-HW, SPRING)] + curve[1:] + [(-HW, TOP)]
    kit.slab_xz("spandrel_l", root, left, DEPTH, stone)
    kit.slab_xz("spandrel_r", root, [(-x, z) for x, z in reversed(left)], DEPTH, stone)
    # Arch moulding ring + jamb shafts.
    outer, inner = kit.pointed_arch(HW, SPRING, APEX, 0.2, steps=10)
    kit.band(outer, inner, DEPTH + 0.06, "arch", root, trim)
    outer2, inner2 = kit.pointed_arch(HW - 0.2, SPRING, APEX - 0.26, 0.08, steps=10)
    kit.band(outer2, inner2, 0.3, "arch_inner", root, trim, loc=(0, -0.1, 0))
    for sx in (-1, 1):
        sb.box(f"jamb{sx}", root, size=(0.2, DEPTH + 0.06, SPRING - Y0), loc=(sx * (HW - 0.1), 0, (Y0 + SPRING) * 0.5),
               material=trim, bevel=0.02)
        sb.cylinder(f"shaft{sx}", root, r1=0.08, depth=SPRING - Y0 - 0.2, loc=(sx * (HW - 0.24), -0.1, Y0 + 0.1),
                    material=trim, segments=8, bevel=0)
        sb.box(f"jcap{sx}", root, size=(0.42, 0.42, 0.12), loc=(sx * (HW - 0.18), -0.1, SPRING - 0.06), material=trim,
               bevel=0.02, taper=(1.15, 1.15))
    # Mullions and three lancet heads.
    for sx in (-1, 1):
        sb.box(f"mullion{sx}", root, size=(0.13, 0.26, 6.35 - Y0), loc=(sx * 0.43, -0.05, (Y0 + 6.35) * 0.5),
               material=trim, bevel=0.015)
    for k, cx in enumerate((-0.86, 0.0, 0.86)):
        hw = 0.43 if k == 1 else 0.36
        o, i = kit.pointed_arch(hw, 6.3, 7.05, 0.07, steps=5)
        kit.band(o, i, 0.24, f"lancet{k}", root, trim, loc=(cx, -0.05, 0))
    # Oculus with four cusps.
    sb.torus("oculus", root, major=0.36, minor=0.06, loc=(0, -0.05, 7.8), rot=(90, 0, 0), material=trim,
             major_segments=20, minor_segments=6)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        sb.sphere(f"cusp{k}", root, radius=0.07, loc=(math.cos(a) * 0.29, -0.05, 7.8 + math.sin(a) * 0.29),
                  material=trim, segments=6, rings=4)
    # Tracery bars tying the oculus to the lancet heads.
    for sx in (-1, 1):
        sb.ptube(f"tie{sx}", root, [(sx * 0.43, -0.05, 6.95), (sx * 0.24, -0.05, 7.5)], [0.04, 0.04], sides=5,
                 material=trim)
    # Hood moulding following the arch on the room side, with carved label stops.
    hood = kit.arch_curve(HW + 0.18, SPRING, APEX + 0.25, steps=10)
    pts = [(x, -DEPTH * 0.5 - 0.06, z) for x, z in hood] + [(-x, -DEPTH * 0.5 - 0.06, z) for x, z in reversed(hood[:-1])]
    sb.ptube("hood", root, pts, [0.07] * len(pts), sides=6, material=trim)
    for sx in (-1, 1):
        sb.box(f"stop{sx}", root, size=(0.22, 0.2, 0.28), loc=(sx * (HW + 0.18), -DEPTH * 0.5 - 0.06, SPRING - 0.1),
               material=trim, bevel=0.03, taper=(0.7, 0.7))
    # Sill.
    sb.box("sill", root, size=(HW * 2 + 0.6, DEPTH + 0.4, 0.2), loc=(0, -0.2, Y0), material=trim, bevel=0.03)
    sb.box("sill_under", root, size=(HW * 2 + 0.3, 0.3, 0.2), loc=(0, -DEPTH * 0.5 - 0.15, Y0 - 0.2), material=stone,
           bevel=0.02, taper=(1.0, 1.0))
    sb.join_meshes(root, "window")
    sb.tri_count(root)
    return root
