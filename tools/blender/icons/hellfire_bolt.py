"""Hellfire Bolt: a charred skull wreathed in fire, eyes blazing."""
import random
import sb
import _ikit as k

ACCENT = (1.0, 0.4, 0.08)
VIEW = {"pitch": 10, "yaw": -18, "fill": 0.88}


def build():
    bone = sb.mat("I_Bone", (0.36, 0.27, 0.19), roughness=0.7)
    char = sb.mat("I_Char", (0.07, 0.045, 0.035), roughness=0.85)
    void = sb.mat("I_Void", (0.0, 0.0, 0.0), roughness=1.0)
    hot = k.glow("I_Hot", (1.0, 0.55, 0.18), 1.5)
    fire = k.glow("I_Fire", (1.0, 0.3, 0.04), 1.3)
    ember = k.glow("I_Ember", (0.85, 0.1, 0.02), 1.1)
    root = sb.root("Skull")

    rnd = random.Random(3)
    # Cranium: big rounded vault, slightly elongated back.
    cran = sb.sphere("cran", root, 0.5, loc=(0, 0.08, 0.14), scale=(0.86, 1.08, 0.9), material=bone)
    sb.displace(cran, 0.025, 0.35)
    sb.sphere("temple", root, 0.42, loc=(0, -0.12, 0.02), scale=(0.95, 0.9, 0.85), material=bone)
    sb.sphere("face", root, 0.5, loc=(0, -0.24, -0.08), scale=(0.78, 0.55, 0.72), material=bone)
    for s_ in (-1, 1):
        sb.sphere(f"sock{s_}", root, 0.13, loc=(0.16 * s_, -0.5, -0.04), rot=(0, 18 * s_, 0),
                  scale=(1.15, 0.55, 0.85), material=void)
        sb.sphere(f"eye{s_}", root, 0.04, loc=(0.16 * s_, -0.52, -0.06), material=hot)
        sb.sphere(f"cheek{s_}", root, 0.11, loc=(0.25 * s_, -0.42, -0.24), scale=(0.9, 0.8, 0.6), material=bone)
    nose = sb.cylinder("nose", root, r1=0.06, r2=0.0, depth=0.12, loc=(0, -0.55, -0.27), material=void,
                       segments=3, bevel=0)
    nose.rotation_euler = (0, 0, 3.14159 / 2)
    sb.box("maxilla", root, (0.3, 0.2, 0.1), loc=(0, -0.42, -0.4), material=bone, bevel=0.035, subdiv=2)
    sb.box("jaw", root, (0.32, 0.26, 0.09), loc=(0, -0.36, -0.62), rot=(-10, 0, 0), material=bone, bevel=0.03,
           subdiv=2)
    sb.box("mouth", root, (0.24, 0.12, 0.13), loc=(0, -0.42, -0.52), material=fire)
    for i in range(6):
        x = -0.11 + i * 0.044
        sb.box(f"tu{i}", root, (0.034, 0.04, 0.065), loc=(x, -0.51, -0.47), material=bone, bevel=0.01)
        sb.box(f"tl{i}", root, (0.034, 0.04, 0.055), loc=(x * 0.9, -0.47, -0.575), material=bone, bevel=0.01)
    # Molten cracks over the vault.
    for c in range(6):
        x0 = rnd.uniform(-0.3, 0.3)
        pts = [(x0, -0.25 + rnd.uniform(-0.05, 0.1), 0.58)]
        for j in range(3):
            px, py, pz = pts[-1]
            pts.append((px + rnd.uniform(-0.1, 0.1), py - 0.06, pz - 0.13))
        sb.ptube(f"crack{c}", root, pts, [0.01, 0.018, 0.014, 0.005], sides=4, material=hot)
    sb.sphere("charcap", root, 0.44, loc=(0, 0.25, 0.32), scale=(0.88, 0.9, 0.7), material=char)

    # Fire: three layers of fat tongues swept up and back (dark red outside, white-hot core).
    for layer, (mat, rad, hmul, n, yb) in enumerate(((ember, 0.2, 1.15, 7, 0.38),
                                                     (fire, 0.17, 1.0, 8, 0.22),
                                                     (hot, 0.09, 0.6, 6, 0.1))):
        for f in range(n):
            x = -0.4 + 0.8 * f / (n - 1) + rnd.uniform(-0.04, 0.04)
            h = (0.6 + 0.75 * (1.0 - abs(x) / 0.45) + rnd.uniform(-0.12, 0.18)) * hmul
            k.flame(f"fl{layer}_{f}", root, (x, yb + rnd.uniform(-0.08, 0.08), 0.3), h, rad, mat,
                    seed=f * 3 + layer, lean=(x * 0.5, 0.45), sides=8)
    return root
