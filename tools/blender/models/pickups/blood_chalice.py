"""Blood chalice: an ornate dark-gold chalice brimming with glowing blood (~0.6 m tall).

Godot (scenes/pickups/blood_chalice.gd) finds `blood_glow` (the glowing surface; pulsed) and
swaps the material named Chalice_BloodGlow for an additive one.
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bosses"))
import sb  # noqa: E402
import _kit as kit  # noqa: E402

CATEGORY = "pickups"


def build():
    dark = sb.mat("Chalice_DarkGold", (0.42, 0.3, 0.13), 0.38, 0.95)
    gold = sb.mat("Chalice_GoldTrim", (0.72, 0.54, 0.24), 0.3, 1.0)
    blood = sb.mat("Chalice_BloodSurface", (0.42, 0.04, 0.05), 0.12, emission=(0.85, 0.12, 0.18), strength=1.4)
    glow = sb.mat("Chalice_BloodGlow", (0.85, 0.12, 0.18), 0.4, emission=(0.85, 0.12, 0.18), strength=3.0)
    gem = sb.mat("Chalice_GarnetCrystal", (0.3, 0.02, 0.04), 0.1, emission=(0.9, 0.1, 0.12), strength=1.2)
    drip = sb.mat("Chalice_DripBlood", (0.5, 0.05, 0.05), 0.15, emission=(0.6, 0.08, 0.07), strength=1.5)

    root = sb.root("BloodChalice")
    cup = sb.empty("cup", root)
    # foot: stepped, lobed base.
    kit.lathe("foot", cup, [(0.2, 0.0), (0.205, 0.02), (0.18, 0.045), (0.12, 0.07), (0.07, 0.1), (0.045, 0.13)], 32,
              material=dark, folds=6, fold_amp=0.08)
    kit.lathe("foot_rim", cup, [(0.207, 0.004), (0.21, 0.016), (0.2, 0.024)], 32, material=gold, folds=6,
              fold_amp=0.08, cap_bottom=False, cap_top=False)
    # stem with two knots; the upper knot is set with garnets.
    kit.lathe("stem", cup, [(0.045, 0.12), (0.035, 0.16), (0.06, 0.2), (0.07, 0.24), (0.06, 0.28), (0.03, 0.31),
                            (0.03, 0.34), (0.05, 0.36), (0.035, 0.38), (0.04, 0.4)], 20, material=gold)
    for i in range(6):
        a = math.tau * i / 6
        kit.crystal(f"garnet{i}", cup, height=0.035, radius=0.016, sides=4, top=0.5,
                    loc=(math.cos(a) * 0.068, math.sin(a) * 0.068, 0.24), rot=(0, 90, math.degrees(a)),
                    material=gem, jitter=0.0, seed=i)
    # bowl: deep, flared, with a heavy rim.
    bowl = [(0.04, 0.4), (0.09, 0.42), (0.14, 0.46), (0.175, 0.51), (0.19, 0.56), (0.195, 0.6)]
    kit.lathe("bowl", cup, bowl, 36, material=dark, cap_top=False)
    kit.lathe("bowl_in", cup, [(0.18, 0.598), (0.17, 0.53), (0.12, 0.47), (0.0, 0.45)], 36, material=dark,
              cap_top=False)
    kit.lathe("rim", cup, [(0.18, 0.598), (0.2, 0.592), (0.21, 0.605), (0.2, 0.618), (0.18, 0.61)], 36,
              material=gold, cap_top=False, cap_bottom=False)
    kit.lathe("bowl_band", cup, [(0.145, 0.462), (0.155, 0.47), (0.162, 0.485), (0.152, 0.492)], 36, material=gold,
              cap_top=False, cap_bottom=False)
    # thorned band and filigree arches around the bowl.
    for i in range(12):
        a = math.tau * i / 12
        sb.cylinder(f"thorn{i}", cup, r1=0.012, r2=0.0, depth=0.05, loc=(math.cos(a) * 0.162, math.sin(a) * 0.162, 0.478),
                    rot=(0, 90, math.degrees(a)), material=gold, segments=5, bevel=0.0)
        if i % 2 == 0:
            pts = []
            for k in range(5):
                u = k / 4
                aa = a + (u - 0.5) * 0.5
                z = 0.5 + 0.06 * math.sin(math.pi * u)
                r = 0.18 + 0.012 * math.sin(math.pi * u)
                pts.append((math.cos(aa) * r, math.sin(aa) * r, z))
            kit.filigree(f"arch{i}", cup, pts, 0.005, gold)
    # handles: two curled scrolls.
    for s in (1, -1):
        kit.filigree(f"handle{s}", cup, [(s * 0.19, 0, 0.57), (s * 0.27, 0, 0.56), (s * 0.29, 0, 0.47),
                                         (s * 0.22, 0, 0.42), (s * 0.19, 0, 0.46), (s * 0.23, 0, 0.49)], 0.012, gold,
                     res=4, radii=[1.0, 1.0, 0.9, 0.8, 0.6, 0.5])
    # blood: glossy brimming surface + glowing core (separate node for the pulse) + drips.
    kit.lathe("blood_surf", cup, [(0.0, 0.595), (0.1, 0.598), (0.183, 0.6)], 32, material=blood,
              cap_bottom=False, cap_top=False)
    g = sb.empty("blood_glow", cup, loc=(0, 0, 0.603))
    sb.cylinder("blood_glow_disc", g, r1=0.12, depth=0.004, material=glow, segments=24, bevel=0.0)
    for i in range(3):
        a = math.tau * i / 3 + 0.7
        ln = 0.06 + 0.03 * i
        sb.tube(f"drip{i}", cup, [(math.cos(a) * 0.203, math.sin(a) * 0.203, 0.612),
                                  (math.cos(a) * 0.197, math.sin(a) * 0.197, 0.585),
                                  (math.cos(a) * 0.19, math.sin(a) * 0.19, 0.565 - ln)], [0.009, 0.006, 0.01], drip,
                segments=6)
    kit.merge_joint_meshes(root)
    print("CHALICE TRIS", kit.tri_count())
    return root
