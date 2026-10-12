"""Tufts of dry grass blades (3 variants)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb  # noqa: E402
import _props_kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

CATEGORY = "props"
import bmesh  # noqa: E402


def build():
    vs = sb.variants("gr", 3, 1.5)
    for i, v in enumerate(vs):
        rng = K.rng_for(1400 + i)
        for mat in ("Prop_GrassDry", "Prop_GrassDark"):
            bm = bmesh.new()
            for k in range(6 + i * 2):
                a = rng.uniform(0, math.tau)
                d = rng.uniform(0, 0.2)
                h = rng.uniform(0.25, 0.6)
                lean = rng.uniform(0.15, 0.55)
                base = Vector((math.cos(a) * d, math.sin(a) * d, 0))
                tip = base + Vector((math.cos(a) * lean * h, math.sin(a) * lean * h, h))
                mid = base.lerp(tip, 0.5) + Vector((0, 0, h * 0.08))
                w = 0.03
                side = Vector((-math.sin(a), math.cos(a), 0)) * w
                v0, v1, v2, v3 = (bm.verts.new(base - side), bm.verts.new(base + side), bm.verts.new(mid + side * 0.6),
                                  bm.verts.new(mid - side * 0.6))
                vt = bm.verts.new(tip)
                back = bm.verts.new(base + Vector((math.cos(a), math.sin(a), 0)) * -0.02)
                for f in ((v0, v1, v2, v3), (v3, v2, vt), (v1, back, v2), (back, v0, v3), (v2, back, vt), (back, v3, vt)):
                    try:
                        bm.faces.new(f)
                    except ValueError:
                        pass
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            sb.bm_obj(mat + "_ns", v, bm, K.M(mat), sharp=None)
    sb.tri_report("grass_tuft")
    return vs[0]
