"""Landmark: corner of a ruined gothic chapel - two broken coursed walls with pointed windows,
buttresses, cracked floor, altar. Sockets: candles x2 on the altar, brazier."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import bmesh  # noqa: E402
import _props_kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"

def build():
    v = sb.variants("cp", 1)[0]
    rng = K.rng_for(2000)
    S = "Prop_Stone"
    win = [(-1.6, 1.2), (1.4, 1.2)]

    def top_long(x):
        return max(0.6, 6.4 * (1.0 - (x + 4.5) / 13.0) + 0.5 * math.sin(x * 1.7) - 1.2 * max(0.0, x - 2.4))

    def open_long(z):
        return [K.pointed_hole(z, sp + 0.56, 2.6, 1.0, cx) for cx, sp in win]

    K.wall(v, rng, -4.2, 4.6, top_long, 0.7, 0.62, 0.0, tag="wl", opening=open_long, step=1.0, blen=(0.95, 1.6))
    for cx, sp in win:
        if top_long(cx) > 3.7:
            K.voussoir_arc(v, rng, (cx + sp * 0.5, 0, 2.6), sp, sp + 0.28, 180, 120, 3, 0.75, 0.0, S, f"wa{cx}L")
            K.voussoir_arc(v, rng, (cx - sp * 0.5, 0, 2.6), sp, sp + 0.28, 0, 60, 3, 0.75, 0.0, S, f"wa{cx}R")
        sb.stone_block(f"sill{cx}", v, (sp + 0.5, 0.85, 0.14), K.M(S), rng, loc=(cx, 0, 1.0), chips=2, step=0.5)

    def top_short(y):
        return max(0.5, 5.2 * (1.0 - y / 7.0) + 0.5 * math.sin(y * 2.3))

    K.wall(v, rng, 0.35, 6.2, top_short, 0.7, 0.62, -4.5, tag="ws", axis="y", step=1.0, blen=(0.95, 1.6))
    # buttresses on the outside
    for i, x in enumerate((-3.0, 0.0)):
        h = min(top_long(x) * 0.8, 3.6)
        sb.stone_block(f"bt{i}", v, (0.6, 0.9, h), K.M(S), rng, loc=(x, -0.75, h * 0.5), chips=2, step=0.7)
        sb.stone_block(f"bt{i}c", v, (0.6, 0.7, 0.6), K.M(S), rng, loc=(x, -0.6, h + 0.12), rot=(-35, 0, 0), chips=2,
                       step=0.6)
    sb.stone_block("btc", v, (0.9, 0.9, 4.2), K.M(S), rng, loc=(-4.75, -0.25, 2.1), chips=2, step=0.7)
    # cracked floor
    for gx in range(6):
        for gy in range(5):
            if rng.random() < 0.5:
                continue
            sb.stone_block(f"fl{gx}{gy}_ns", v, (1.2, 1.2, 0.12), K.M("Prop_StoneDark"), rng,
                           loc=(-3.5 + gx * 1.28, 0.95 + gy * 1.28, 0.03),
                           rot=(rng.uniform(-1.5, 1.5), rng.uniform(-1.5, 1.5), rng.uniform(-3, 3)), chips=1, step=0.6,
                           chip_depth=0.2)
    # altar
    sb.stone_block("altar_step", v, (2.6, 1.5, 0.22), K.M(S), rng, loc=(-2.4, 1.6, 0.11), chips=2, step=0.6)
    sb.stone_block("altar", v, (1.8, 0.85, 0.82), K.M(S), rng, loc=(-2.4, 1.6, 0.63), chips=2, cracks=1, step=0.45)
    sb.stone_block("altar_top", v, (2.0, 1.0, 0.12), K.M("Prop_Marble"), rng, loc=(-2.4, 1.6, 1.1), chips=2, step=0.5)
    K.socket(v, "candles", (-2.85, 1.6, 1.16))
    K.socket(v, "candles2", (-1.95, 1.55, 1.16))
    K.socket(v, "brazier", (-0.5, 2.6, 0.08))
    # a broken column and fallen tracery
    K.plinth("colp", v, rng, 1.1, 0.25, (1.6, 3.6, 0.05))
    K.drum("col0", v, rng, 0.34, 1.1, (1.6, 3.6, 0.3), (0, 0, 0), broken_top=0.5)
    K.drum("col1", v, rng, 0.34, 0.9, (2.6, 2.9, 0.34), (90, 0, 70), broken_top=0.3)
    for i in range(2):
        sb.stone_block(f"fall{i}", v, (0.6, 0.7, 0.5), K.M(S), rng,
                       loc=(rng.uniform(0.5, 3.5), rng.uniform(-1.8, -1.0), 0.22),
                       rot=(rng.uniform(-12, 12), rng.uniform(-12, 12), rng.uniform(0, 360)), chips=2, step=0.5)
    K.rubble(v, rng, (3.2, 0.9, 0), 1.4, 5, 0.15, 0.55, blocks=0.2)
    K.rubble(v, rng, (-3.8, 5.6, 0), 1.2, 4, 0.15, 0.45, blocks=0.3)
    sb.tri_report("chapel_ruin")
    return v

