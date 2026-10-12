"""Infernal Chain: heavy forged links, the lowest ones still glowing from the hellforge."""
import math
import sb
import _ikit as k

ACCENT = (1.0, 0.45, 0.14)
VIEW = {"pitch": 10, "yaw": -10, "fill": 0.9}


def build():
    iron = k.metal("I_Iron", (0.16, 0.14, 0.13), 0.5)
    heat = [
        sb.mat("I_Heat0", (0.2, 0.08, 0.05), roughness=0.5, metallic=0.6, emission=(0.6, 0.08, 0.02), strength=0.5),
        sb.mat("I_Heat1", (0.5, 0.15, 0.04), roughness=0.4, emission=(1.0, 0.25, 0.04), strength=1.1),
        sb.mat("I_Heat2", (0.9, 0.45, 0.1), roughness=0.3, emission=(1.0, 0.55, 0.15), strength=1.6),
    ]
    root = sb.root("Chain")
    root.rotation_euler = (0, math.radians(-38), 0)
    n = 6
    pitch = 0.44
    for i in range(n):
        z = 1.1 - i * pitch
        sag = math.sin(i / (n - 1) * math.pi) * 0.12
        if i % 2 == 0:
            rot = (90, 0, 0)       # ring in the XZ plane, facing the camera
        else:
            rot = (90, 0, 90)      # ring edge-on
        mat = iron if i < 3 else heat[i - 3]
        t = sb.torus(f"link{i}", root, 0.2, 0.065, loc=(sag, 0, z), rot=rot, material=mat,
                     major_segments=28, minor_segments=10)
        t.scale = (1.0, 1.45, 1.0)
    # A broken, hooked end link at the top.
    sb.ptube("hook", root, [(0.0, 0, 1.38), (0.0, 0, 1.6), (0.12, 0, 1.75), (0.26, 0, 1.68), (0.27, 0, 1.55)],
             [0.07, 0.07, 0.065, 0.06, 0.03], sides=8, material=iron)
    # Sparks shed from the hot end.
    spark = k.glow("I_Spark", (1.0, 0.65, 0.25), 2.0)
    import random
    rnd = random.Random(4)
    for i in range(10):
        sb.sphere(f"spark{i}", root, rnd.uniform(0.012, 0.028),
                  loc=(rnd.uniform(-0.35, 0.45), rnd.uniform(-0.3, 0.1), rnd.uniform(-1.4, -0.7)), material=spark)
    return root
