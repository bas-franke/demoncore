"""Demon plinth for the select screen: an octagonal gothic pedestal (top at z = 0.5) with a carved
rim, blind-arch panels on every face, a step down toward the summoning circle (front = -Y),
two candles at its foot, and a separate inlaid rune ring mesh named "rune" that demon_select.gd
lights up (material override) for the chosen demon."""
import math
import os
import random
import sys
sys.path.insert(0, os.path.dirname(__file__))
import sb  # noqa: E402
import _kit as kit  # noqa: E402

CATEGORY = "menu"
TOP = 0.5


def build():
    m = kit.mats()
    root = sb.root("Plinth")
    body = sb.empty("body", root)
    # Octagonal body: chamfered base slab, torus moulding, drum, cornice. Vertices at k*45 deg
    # rotated by 22.5 so a flat face looks straight down -Y (the front).
    prof = [(0.0, 0.0), (1.02, 0.0), (1.02, 0.11), (0.96, 0.16), (0.86, 0.16), (0.9, 0.19), (0.86, 0.23),
            (0.8, 0.24), (0.8, 0.4), (0.84, 0.41), (0.88, 0.445), (0.86, 0.47), (0.84, TOP), (0.0, TOP)]
    sb.lathe("octagon", body, prof, segments=8, material=m["stone"], rot=(0, 0, 22.5), jitter=0.006, seed=3)
    # Raised carved lip around the top, notched.
    sb.lathe("lip", body, [(0.7, TOP - 0.01), (0.8, TOP - 0.01), (0.8, TOP + 0.04), (0.74, TOP + 0.05), (0.7, TOP + 0.04),
                           (0.7, TOP - 0.01)], segments=24, material=m["marble"], smooth=False, caps=False)
    for k in range(16):
        a = 2 * math.pi * k / 16
        sb.box(f"notch{k}", body, size=(0.05, 0.12, 0.03), loc=(math.cos(a) * 0.75, math.sin(a) * 0.75, TOP + 0.045),
               rot=(0, 0, math.degrees(a)), material=m["stone_dark"], bevel=0)
    # Blind trefoil arch on each of the 8 drum faces.
    apo = 0.8 * math.cos(math.radians(22.5))
    for k in range(8):
        ang = k * 45.0
        e = sb.empty(f"face{k}", body, rot=(0, 0, ang))
        outer, inner = kit.pointed_arch(0.16, 0.27, 0.385, 0.035, steps=4)
        kit.band(outer, inner, 0.03, f"arch{k}", e, m["marble"], loc=(0, -apo - 0.005, 0))
        sb.box(f"recess{k}", e, size=(0.25, 0.01, 0.13), loc=(0, -apo + 0.001, 0.31), material=m["stone_dark"], bevel=0)
    # Step down toward the circle.
    sb.box("step", body, size=(0.95, 0.5, 0.24), loc=(0, -1.05, 0.12), material=m["stone"], bevel=0.03)
    sb.box("step_cap", body, size=(1.0, 0.54, 0.04), loc=(0, -1.05, 0.25), material=m["marble"], bevel=0.015)
    # Candles at the foot, either side of the step.
    for k, (sgn, h) in enumerate(((1, 0.2), (-1, 0.32))):
        a = 1.2 * sgn
        kit.candle(f"candle{k}", body, m, loc=(math.sin(a) * 1.15, -math.cos(a) * 1.15, 0), h=h, r=0.05, seed=40 + k)
    # Weathering chips / a fallen chunk at the back.
    rnd = random.Random(8)
    for k in range(3):
        a = rnd.uniform(0.4, 2.7)
        sb.box(f"chip{k}", body, size=(0.12, 0.09, 0.07), loc=(math.cos(a) * 1.1, math.sin(a) * 1.1, 0.035),
               rot=(rnd.uniform(-20, 20), 0, rnd.uniform(0, 90)), material=m["stone"], bevel=0.015)
    sb.join_meshes(body, "plinth")
    # Separate rune ring (material swapped in Godot): inlaid circle with 8 glyph strokes.
    rune = sb.empty("rune_root", root)
    sb.lathe("rune_ring", rune, [(0.56, TOP + 0.004), (0.62, TOP + 0.004), (0.62, TOP + 0.01), (0.56, TOP + 0.01),
                                 (0.56, TOP + 0.004)], segments=32, material=m["rune"], smooth=False, caps=False)
    for k in range(8):
        a = 2 * math.pi * (k + 0.5) / 8
        r0, r1 = 0.3, 0.5
        pts = [(math.cos(a) * r0, math.sin(a) * r0, TOP + 0.008), (math.cos(a + 0.12) * 0.4, math.sin(a + 0.12) * 0.4, TOP + 0.008),
               (math.cos(a) * r1, math.sin(a) * r1, TOP + 0.008)]
        sb.ptube(f"glyph{k}", rune, pts, [0.012, 0.012, 0.012], sides=4, material=m["rune"], smooth=False)
    j = sb.join_meshes(rune, "rune")
    sb.tri_count(root)
    return root
