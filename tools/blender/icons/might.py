"""Wrath: a clenched, spiked iron gauntlet, knuckles toward the viewer."""
import sb
import _ikit as k

ACCENT = (0.85, 0.18, 0.1)
VIEW = {"pitch": 12, "yaw": -24, "fill": 0.84}


def build():
    iron = k.metal("I_Iron", (0.17, 0.15, 0.14), 0.38)
    dark = k.metal("I_DarkIron", (0.07, 0.06, 0.06), 0.5)
    gold = k.metal("I_Gold", (0.5, 0.33, 0.13), 0.35)
    cloth = sb.mat("I_RedCloth", (0.22, 0.03, 0.03), roughness=0.9)
    ember = k.glow("I_Ember", (1.0, 0.22, 0.05), 1.3)
    root = sb.root("Gauntlet")

    # Back of the hand and palm block.
    sb.box("palm", root, (0.84, 0.62, 0.66), loc=(0, 0.08, 0.02), material=dark, bevel=0.1, subdiv=1)
    sb.box("backplate", root, (0.82, 0.5, 0.12), loc=(0, 0.04, 0.4), rot=(-14, 0, 0), material=iron, bevel=0.04,
           taper=(0.9, 0.9))
    sb.box("backtrim", root, (0.84, 0.06, 0.06), loc=(0, -0.22, 0.42), rot=(-14, 0, 0), material=gold, bevel=0.02)
    # Four curled fingers: knuckle plate (top front), middle phalanx (front), tip tucked under.
    for i in range(4):
        x = -0.3 + i * 0.2
        drop = 0.03 * abs(i - 1.5)
        sb.box(f"kn{i}", root, (0.18, 0.22, 0.2), loc=(x, -0.26, 0.24 - drop), rot=(-20, 0, 0), material=iron,
               bevel=0.04, subdiv=1)
        sb.box(f"mid{i}", root, (0.17, 0.18, 0.2), loc=(x, -0.35, 0.03 - drop), rot=(-5, 0, 0), material=iron,
               bevel=0.035, subdiv=1)
        sb.box(f"tip{i}", root, (0.16, 0.18, 0.12), loc=(x, -0.25, -0.15 - drop), rot=(30, 0, 0), material=dark,
               bevel=0.03, subdiv=1)
        k.spike(f"spk{i}", root, (x, -0.33, 0.27 - drop), (0, -1, 0.35), 0.18, 0.05, gold, segments=4)
    # Thumb wrapped across the front of the fingers.
    sb.ptube("thumb", root, [(0.46, -0.05, -0.12), (0.38, -0.3, -0.13), (0.15, -0.45, -0.1), (-0.02, -0.45, -0.08)],
             [0.09, 0.085, 0.075, 0.06], sides=8, material=iron)
    sb.sphere("thumbtip", root, 0.065, loc=(-0.03, -0.45, -0.08), material=iron)
    # Flared cuff with gold rim, trailing a torn red cloth.
    sb.lathe("cuff", root, [(0.3, -0.78), (0.36, -0.74), (0.3, -0.6), (0.3, -0.32), (0.0, -0.32)], 24, iron,
             loc=(0, 0.14, 0.0))
    sb.torus("cuffrim", root, 0.35, 0.03, loc=(0, 0.14, -0.75), material=gold)
    sb.torus("cuffrim2", root, 0.31, 0.025, loc=(0, 0.14, -0.4), material=gold)
    # Red-hot seams between the plates.
    for i in range(3):
        x = -0.2 + i * 0.2
        sb.sphere(f"seam{i}", root, 0.03, loc=(x, -0.36, 0.14), material=ember)
    return root
