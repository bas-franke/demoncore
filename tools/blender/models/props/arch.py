"""Gothic pointed arches and ruined wall sections (3 variants), centred on x=0, wall plane y=0."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402

CATEGORY = "props"


def pier(v, rng, x, h, tag, th=0.65, depth=0.8):
    sb.stone_block(tag + "foot", v, (th + 0.35, depth + 0.3, 0.3), K.M("Prop_Stone"), rng, loc=(x, 0, 0.15),
                   chips=2, step=0.4)
    K.wall(v, rng, x - th * 0.5, x + th * 0.5, lambda _x: h, depth, 0.5, 0.0, tag=tag, step=0.5)


def build():
    vs = sb.variants("ar", 3, 8.0)
    # v0: whole arch
    rng = K.rng_for(7)
    v = vs[0]
    span, spring = 2.8, 2.5
    for sx in (-1, 1):
        pier(v, rng, sx * (span * 0.5 + 0.33), spring, f"p{sx}")
        sb.stone_block(f"imp{sx}", v, (0.9, 0.95, 0.2), K.M("Prop_Stone"), rng,
                       loc=(sx * (span * 0.5 + 0.33), 0, spring + 0.1), chips=1, step=0.4)
    K.pointed_arch(v, rng, span + 0.0, spring + 0.2, 0.5, 0.75, 5)
    K.rubble(v, rng, (1.2, 0.8, 0), 1.4, 4)

    # v1: collapsed right side, voussoirs fallen in the grass
    rng = K.rng_for(8)
    v = vs[1]
    pier(v, rng, -(span * 0.5 + 0.33), spring, "pl")
    sb.stone_block("imp", v, (0.9, 0.95, 0.2), K.M("Prop_Stone"), rng, loc=(-(span * 0.5 + 0.33), 0, spring + 0.1),
                   chips=1, step=0.4)
    pier(v, rng, span * 0.5 + 0.33, 1.2, "pr")
    K.pointed_arch(v, rng, span, spring + 0.2, 0.5, 0.75, 5, keep_left=lambda i: i < 4,
                   keep_right=lambda i: False, key=False)
    for i in range(3):
        sb.stone_block(f"fall{i}", v, (0.6, 0.75, 0.5), K.M("Prop_Stone"), rng,
                       loc=(1.6 + rng.uniform(-0.4, 1.0), rng.uniform(-1.3, 1.3), 0.25),
                       rot=(rng.uniform(-15, 15), rng.uniform(-15, 15), rng.uniform(0, 360)), chips=2, step=0.3)
    K.rubble(v, rng, (1.9, 0.0, 0), 1.6, 7)

    # v2: ruined wall section with a pointed window
    rng = K.rng_for(9)
    v = vs[2]
    win_span, win_spring, win_base = 1.0, 2.0, 0.9

    def top(x):
        return max(0.5, 3.5 - 0.55 * max(0.0, x - 0.2) ** 1.4 + 0.25 * math.sin(x * 3.1))

    def opening(z):
        return K.pointed_hole(z, win_span + 0.4, win_spring, win_base)

    K.wall(v, rng, -2.2, 2.2, top, 0.6, 0.45, 0.0, tag="w", opening=opening, step=0.5)
    K.pointed_arch(v, rng, win_span, win_spring, 0.22, 0.66, 3, key=True)
    sb.stone_block("sill", v, (1.3, 0.75, 0.14), K.M("Prop_Stone"), rng, loc=(0, 0.0, win_base + 0.02), chips=1,
                   step=0.4)

    K.rubble(v, rng, (1.6, 0.9, 0), 1.5, 8)
    sb.tri_report("arch")
    return vs[0]
