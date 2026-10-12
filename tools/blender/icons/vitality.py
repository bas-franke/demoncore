"""Unholy Vigor: a dark beating heart bound in a crown of thorns, veins aglow."""
import math
import random
import sb
import _ikit as k

ACCENT = (0.85, 0.1, 0.16)
VIEW = {"pitch": 6, "yaw": -12, "fill": 0.86}


def build():
    flesh = sb.mat("I_Heart", (0.32, 0.03, 0.05), roughness=0.3)
    deep = sb.mat("I_HeartDeep", (0.16, 0.015, 0.03), roughness=0.4)
    vein = k.glow("I_Vein", (1.0, 0.12, 0.12), 1.3)
    thorn = sb.mat("I_Thorn", (0.06, 0.045, 0.035), roughness=0.7)
    root = sb.root("Heart")
    rnd = random.Random(2)

    # Heart body: two lobes and a tapering apex, tilted like the real organ.
    body = sb.root("body")
    body.parent = root
    body.rotation_euler = (0, math.radians(-14), 0)
    sb.sphere("lobeL", body, 0.42, loc=(-0.2, 0, 0.12), scale=(1.0, 0.85, 1.0), material=flesh)
    sb.sphere("lobeR", body, 0.36, loc=(0.24, 0.02, 0.18), scale=(1.0, 0.85, 1.0), material=flesh)
    apex = sb.lathe("apex", body, [(0.0, -0.78), (0.18, -0.55), (0.36, -0.25), (0.46, 0.05), (0.0, 0.1)], 20, flesh,
                    loc=(-0.02, 0, 0.02), scale=(1.0, 0.85, 1.0))
    sb.displace(apex, 0.01, 0.3)
    # Great vessels rising from the top.
    sb.ptube("aorta", body, [(-0.05, 0.05, 0.4), (-0.02, 0.05, 0.68), (0.18, 0.05, 0.82), (0.36, 0.08, 0.7)],
             [0.13, 0.12, 0.1, 0.09], sides=10, material=deep)
    sb.ptube("vena", body, [(-0.35, 0.1, 0.4), (-0.4, 0.1, 0.7), (-0.48, 0.12, 0.84)], [0.08, 0.075, 0.07],
             sides=8, material=deep)
    sb.ptube("pulm", body, [(0.18, -0.05, 0.42), (0.22, -0.1, 0.6), (0.12, -0.12, 0.74)], [0.07, 0.065, 0.06],
             sides=8, material=deep)
    # Glowing veins crawling over the front.
    for i in range(6):
        x = rnd.uniform(-0.35, 0.3)
        z = rnd.uniform(0.0, 0.35)
        pts = [(x, -0.4, z)]
        for j in range(4):
            px, py, pz = pts[-1]
            pts.append((px + rnd.uniform(-0.08, 0.1), -0.34 + 0.05 * j - 0.02, pz - 0.14))
        sb.ptube(f"vein{i}", body, pts, [0.02, 0.016, 0.012, 0.008, 0.004], sides=5, material=vein)
    # Crown of thorns: a twisted vine coiling around it, studded with spikes.
    for v in range(2):
        pts = []
        n = 40
        for i in range(n + 1):
            t = i / n
            a = t * 2 * math.pi * 1.6 + v * 1.4
            pts.append((math.cos(a) * 0.62, math.sin(a) * 0.5, 0.45 - t * 1.0 + 0.06 * math.sin(a * 3 + v)))
        sb.ptube(f"vine{v}", root, pts, [0.03] * (n + 1), sides=6, material=thorn)
        for i in range(0, n, 3):
            p = pts[i]
            d = (p[0] * 1.0 + rnd.uniform(-0.3, 0.3), p[1] * 1.0 + rnd.uniform(-0.3, 0.3), rnd.uniform(-0.5, 0.5))
            k.spike(f"th{v}_{i}", root, p, d, rnd.uniform(0.12, 0.2), 0.025, thorn, segments=4)
    return root
