"""Soul shard: a faceted crimson-violet crystal of condensed sin, with splinters drifting around it."""
import math
import random
import sb
import _ikit as k

ACCENT = (1.0, 0.16, 0.4)
VIEW = {"pitch": 8, "yaw": -15, "fill": 0.82}


def build():
    crystal = sb.mat("I_Shard", (0.28, 0.02, 0.1), roughness=0.15, metallic=0.3,
                     emission=(0.9, 0.08, 0.3), strength=0.15)
    core = k.glow("I_ShardCore", (1.0, 0.3, 0.5), 2.2)
    root = sb.root("Shard")
    rnd = random.Random(40)

    body = sb.lathe("shard", root, [(0.0, -1.0), (0.32, -0.45), (0.36, 0.25), (0.22, 0.75), (0.0, 1.2)], 5, crystal,
                    rot=(0, 10, 0), smooth=False)
    del body
    sb.lathe("core", root, [(0.0, -0.55), (0.12, -0.2), (0.12, 0.3), (0.0, 0.65)], 5, core, rot=(0, 10, 0),
             smooth=False)
    for i in range(6):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.55, 0.85)
        sz = rnd.uniform(0.07, 0.16)
        sb.lathe(f"splinter{i}", root, [(0.0, -sz), (sz * 0.35, 0.0), (0.0, sz * 1.4)], 4, crystal,
                 loc=(math.cos(a) * r, math.sin(a) * r * 0.5, rnd.uniform(-0.8, 0.8)),
                 rot=(rnd.uniform(-40, 40), rnd.uniform(-40, 40), rnd.uniform(0, 90)), smooth=False)
    return root
