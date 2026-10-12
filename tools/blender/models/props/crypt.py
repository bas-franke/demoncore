"""Stone sarcophagi (3 variants): sealed, lid pushed aside, lid fallen and broken."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402

CATEGORY = "props"
W, L, H = 1.2, 2.15, 0.62


def chest(v, rng):
    S = K.M("Prop_Stone")
    sb.stone_block("plinth", v, (W + 0.4, L + 0.4, 0.22), S, rng, loc=(0, 0, 0.11), chips=3, step=0.35)
    sb.stone_block("body", v, (W, L, H), S, rng, loc=(0, 0, 0.22 + H * 0.5), chips=2, cracks=1, step=0.3)
    sb.stone_block("band_lo_ns", v, (W + 0.1, L + 0.1, 0.1), S, rng, loc=(0, 0, 0.27), chips=2, step=0.4)
    sb.stone_block("band_hi_ns", v, (W + 0.08, L + 0.08, 0.08), S, rng, loc=(0, 0, 0.22 + H - 0.06), chips=2,
                   step=0.4)
    for sx in (-1, 1):
        for sy in (-1, 1):
            sb.stone_block(f"pil{sx}{sy}_ns", v, (0.16, 0.16, H - 0.1), S, rng,
                           loc=(sx * (W * 0.5 - 0.02), sy * (L * 0.5 - 0.02), 0.22 + H * 0.5), chips=1, step=0.3)
    # carved side panels (shallow raised frames)
    for sx in (-1, 1):
        sb.stone_block(f"panel{sx}_ns", v, (0.04, L * 0.62, H * 0.5), S, rng, loc=(sx * (W * 0.5 + 0.01), 0, 0.22 + H * 0.5),
                       chips=0, step=0.4)
    return 0.22 + H


def lid(name, v, rng, loc, rot, cut=None):
    """Gabled lid with a raised cross."""
    import bmesh
    bm = sb.bm_box((W + 0.14, L + 0.14, 0.2), (4, 6, 2))
    for vv in bm.verts:
        if vv.co.z > 0:
            vv.co.z += 0.12 * (1.0 - abs(vv.co.x) / ((W + 0.14) * 0.5))
    if cut is not None:
        caps = sb.bm_cut(bm, cut[0], cut[1])
        sb.bm_roughen(bm, caps, rng, 0.04, 0.35)
    sb.bm_chip(bm, rng, 3, 0.12, rough=0.01)
    sb.bm_crack(bm, rng, 1, 0.012, 0.008)
    sb.bm_bevel(bm, 0.02)
    sb.bm_noise(bm, 0.01, 3.0, seed=rng.randrange(999))
    cr = sb.bm_box((0.1, 1.3, 0.06), (1, 4, 1))
    sb.bm_xform(cr, loc=(0, 0.1, 0.22))
    ar = sb.bm_box((0.6, 0.1, 0.06), (2, 1, 1))
    sb.bm_xform(ar, loc=(0, -0.25, 0.2))
    sb.bm_merge(bm, cr)
    sb.bm_merge(bm, ar)
    if cut is not None:
        sb.bm_cut(bm, cut[0], cut[1], fill=True)
    return sb.bm_obj(name, v, bm, K.M("Prop_Stone"), loc, rot)


def void(v):
    sb.box("void_ns", v, size=(W - 0.22, L - 0.22, 0.02), loc=(0, 0, 0.22 + H + 0.012), material=K.M("Prop_Void"),
           bevel=0.0)


def build():
    vs = sb.variants("cr", 3, 4.0)
    rng = K.rng_for(31)
    v = vs[0]
    top = chest(v, rng)
    lid("lid", v, rng, (0, 0, top + 0.1), (0, 0, 0))

    rng = K.rng_for(32)
    v = vs[1]
    top = chest(v, rng)
    void(v)
    lid("lid", v, rng, (0.45, -0.25, top + 0.1), (0, -6, 14))
    K.rubble(v, rng, (0.9, 0.8, 0), 0.5, 3, 0.08, 0.2)

    rng = K.rng_for(33)
    v = vs[2]
    top = chest(v, rng)
    void(v)
    lid("lidA", v, rng, (1.25, 0.35, 0.28), (4, -62, 8), cut=((0, 0.15, 0), (0.2, 1, 0)))
    lid("lidB", v, rng, (1.1, -0.7, 0.16), (-3, 12, -10), cut=((0, 0.15, 0), (-0.2, -1, 0)))
    K.skull("skull_ns", v, rng, (0.05, 0.4, top - 0.06), (10, 0, 140), 0.9)
    K.rubble(v, rng, (1.3, -0.2, 0), 0.8, 5, 0.06, 0.2)
    sb.tri_report("crypt")
    return vs[0]
