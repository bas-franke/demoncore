"""Full-height (10 m) clustered gothic pier holding up the chamber ceiling."""
import os
import sys
sys.path.insert(0, os.path.dirname(__file__))
import sb  # noqa: E402
import _kit as kit  # noqa: E402
import _pillar  # noqa: E402

CATEGORY = "menu"


def build():
    m = kit.mats()
    root = sb.root("PillarFull")
    _pillar.pier(root, m, 10.0, seed=1)
    sb.join_meshes(root, "pillar")
    sb.tri_count(root)
    return root
