"""Pipeline smoke test (underscore prefix = not built by `all`). Build explicitly:
   blender -b --factory-startup --python tools/blender/build.py -- enemies/_example_pillar
"""
import sb

CATEGORY = "enemies"


def build():
    stone = sb.mat("Stone", (0.45, 0.42, 0.38), roughness=0.9)
    gold = sb.mat("Gold", (0.83, 0.66, 0.3), roughness=0.35, metallic=1.0)
    glow = sb.mat("Halo", (1.0, 0.9, 0.6), roughness=0.4, emission=(1.0, 0.85, 0.5), strength=6.0)
    root = sb.root("ExamplePillar")
    body = sb.empty("body", root, loc=(0, 0, 0))
    sb.cylinder("shaft", body, r1=0.25, r2=0.2, depth=1.4, material=stone)
    head = sb.empty("head", body, loc=(0, 0, 1.4))
    sb.box("cap", head, size=(0.6, 0.6, 0.15), loc=(0, 0, 0.07), material=gold, bevel=0.03)
    halo = sb.empty("halo", head, loc=(0, 0, 0.5))
    sb.torus("halo_ring", halo, major=0.3, minor=0.03, rot=(90, 0, 0), material=glow)
    sb.anim("idle", {
        halo: [(0, sb.rest(halo)), (30, sb.offset(halo, rot=(0, 0, 180))), (60, sb.offset(halo, rot=(0, 0, 360)))],
        body: [(0, sb.rest(body)), (30, sb.offset(body, loc=(0, 0, 0.05))), (60, sb.rest(body))],
    })
    sb.anim("hit", {
        body: [(0, sb.rest(body)), (4, sb.offset(body, rot=(-15, 0, 0))), (12, sb.rest(body))],
    })
    return root
