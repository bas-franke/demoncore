"""Wings of Ash: a pair of burnt, grey-feathered wings, their primaries still smouldering."""
import math
import random
import sb
import _ikit as k

ACCENT = (1.0, 0.5, 0.2)
VIEW = {"pitch": 6, "yaw": 0, "fill": 0.9, "key": 1.3}


def build():
    ash = sb.mat("I_Ash", (0.3, 0.29, 0.28), roughness=0.9)
    ash_d = sb.mat("I_AshDark", (0.12, 0.115, 0.11), roughness=0.9)
    char = sb.mat("I_Charcoal", (0.04, 0.035, 0.03), roughness=0.95)
    ember = k.glow("I_Ember", (1.0, 0.35, 0.06), 1.4)
    root = sb.root("Wings")
    rnd = random.Random(8)

    for s in (-1, 1):
        wing = sb.empty(f"wing{s}", root, loc=(0.08 * s, 0, 0))
        # Arm bone of the wing.
        sb.ptube(f"arm{s}", wing, [(0, 0, 0), (0.35 * s, 0, 0.55), (0.75 * s, 0, 0.95), (1.1 * s, 0, 1.05)],
                 [0.05, 0.045, 0.035, 0.02], sides=6, material=char)
        # Three tiers of feathers fanning down and out (primaries longest, outermost).
        tiers = ((14, 1.35, 0.13, ash_d, 0.0), (11, 0.85, 0.12, ash, 0.04), (8, 0.45, 0.11, ash, 0.08))
        for ti, (n, ln, wd, mat, dy) in enumerate(tiers):
            for i in range(n):
                t = i / (n - 1)
                # Anchor along the arm.
                ax = (0.08 + 1.0 * t) * s
                az = 0.1 + 0.95 * math.sin(t * math.pi * 0.5)
                ang = (182 - 62 * t) * s  # point down, swinging outward toward the tip
                L = ln * (0.75 + 0.5 * t) * rnd.uniform(0.92, 1.08)
                f = sb.blade(f"f{s}_{ti}_{i}", wing, L, wd * (0.8 + 0.4 * t), 0.012, loc=(ax, -dy - 0.01 * i, az),
                             rot=(0, ang, 0), material=mat, curve=0.0)
                if ti == 0 and t > 0.45:
                    # Burning tip.
                    tip_a = math.radians(ang)
                    tip = (ax + math.sin(tip_a) * L * 0.95, -dy - 0.01 * i - 0.02, az + math.cos(tip_a) * L * 0.95)
                    sb.sphere(f"tip{s}_{i}", wing, 0.035, loc=tip, material=ember)
        wing.rotation_euler = (0, math.radians(-12 * s), 0)
    # Drifting embers and ash.
    for i in range(14):
        sb.sphere(f"e{i}", root, rnd.uniform(0.012, 0.03),
                  loc=(rnd.uniform(-1.4, 1.4), rnd.uniform(-0.4, 0.2), rnd.uniform(-1.0, 0.9)),
                  material=ember if i % 3 else ash)
    # Small horned spine knot where the wings meet.
    sb.sphere("knot", root, 0.12, loc=(0, 0, 0.05), scale=(0.9, 0.8, 1.2), material=char)
    return root
