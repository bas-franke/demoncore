"""Single pillar candle (0.3 m tall, r 0.05) with drips and a flame; scaled per instance."""
import os
import sys
sys.path.insert(0, os.path.dirname(__file__))
import sb  # noqa: E402
import _kit as kit  # noqa: E402

CATEGORY = "menu"


def build():
    m = kit.mats()
    root = sb.root("Candle")
    kit.candle("c", root, m, h=0.3, r=0.05, seed=77)
    sb.lathe("puddle", root, [(0.0, 0.0), (0.09, 0.0), (0.07, 0.01), (0.0, 0.012)], segments=8, material=m["wax"],
             jitter=0.15, seed=1)
    sb.join_meshes(root, "candle")
    sb.tri_count(root)
    return root
