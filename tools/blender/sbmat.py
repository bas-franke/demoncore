"""SINBOUND procedural material library (Blender 5.x, Cycles) -- made to be BAKED by bake.py.

Every function returns a named Principled-BSDF material whose inputs are driven by procedural node
graphs in OBJECT space (meters), so the same material looks consistent across parts:

    import sbmat
    steel = sbmat.worn_steel("Knight_WornSteel")
    gold  = sbmat.gold_filigree("Knight_GoldFiligree")
    sb.box("pauldron", parent, size=(...), material=steel, bevel=0.02)

Library:  worn_steel  gold_filigree  weathered_marble  aged_ivory  leather  linen  feathers
          obsidian_ember (glowing ember cracks; strength=0 -> dark charred cracks)  bone
          skin (pores, wrinkles, veins)  horn (growth rings, fibres)  silk  hair
Shared tricks:
  * edge wear  = Bevel-node normal vs. true normal (works on low-poly hard edges, per pixel),
                 restricted to convex edges with an AO term, broken up by noise.
  * cavities   = Ambient Occlusion node -> grime / tarnish / dirt.
  * normals    = Bump nodes fed by the Bevel normal, so the baked normal map also rounds hard edges.
These nodes are Cycles-only and are meant to be baked (the model script sets BAKE = {...}, see
bake.py). Each material also stores a flat fallback (custom props "sb_flat" / "sb_flat_emit");
when a model is built WITHOUT baking, bake.flatten_scene() swaps the graph for that flat color so
the GLB still exports sensibly. Keep the material name keywords (steel, gold, marble, ivory,
leather, linen, feather, obsidian, bone) -- the Godot side picks surface presets from them.
"""
import bpy

# ----------------------------------------------------------------------------- graph helper


def _rgba(c):
    return (c[0], c[1], c[2], 1.0) if len(c) == 3 else tuple(c)


class G:
    """Tiny node-graph builder. Every helper returns an output SOCKET; inputs accept a socket or
    a constant (float / rgb tuple)."""

    def __init__(self, mat):
        self.m = mat
        self.nt = mat.node_tree
        self.nodes = self.nt.nodes
        self.links = self.nt.links
        self.bsdf = self.nodes.get("Principled BSDF")
        self._co = None
        self._x = 0

    def node(self, kind, **props):
        n = self.nodes.new(kind)
        self._x -= 40
        n.location = (self._x - 300, len(self.nodes) * -30)
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def set(self, inp, v):
        if isinstance(v, bpy.types.NodeSocket):
            self.links.new(v, inp)
        elif isinstance(v, (tuple, list)):
            if inp.type == "RGBA":
                inp.default_value = _rgba(v)
            else:
                inp.default_value = tuple(v)[:len(inp.default_value)]
        else:
            inp.default_value = v
        return inp

    @staticmethod
    def _sock(sockets, name, kind=None):
        for s in sockets:
            if s.name == name and (kind is None or s.type == kind) and s.enabled:
                return s
        for s in sockets:
            if s.name == name and (kind is None or s.type == kind):
                return s
        raise KeyError(name)

    # -- coordinates
    def co(self, scale=1.0, offset=(0.0, 0.0, 0.0)):
        if self._co is None:
            self._co = self.node("ShaderNodeTexCoord").outputs["Object"]
        if scale == 1.0 and offset == (0.0, 0.0, 0.0):
            return self._co
        m = self.node("ShaderNodeMapping")
        self.set(m.inputs["Vector"], self._co)
        m.inputs["Location"].default_value = offset
        m.inputs["Scale"].default_value = scale if isinstance(scale, (tuple, list)) else (scale,) * 3
        return m.outputs["Vector"]

    # -- math
    def math(self, op, a, b=None, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        self.set(n.inputs[0], a)
        if b is not None:
            self.set(n.inputs[1], b)
        return n.outputs[0]

    def mul(self, a, b, clamp=False):
        return self.math("MULTIPLY", a, b, clamp)

    def add(self, a, b, clamp=False):
        return self.math("ADD", a, b, clamp)

    def sub(self, a, b, clamp=False):
        return self.math("SUBTRACT", a, b, clamp)

    def inv(self, a):
        return self.math("SUBTRACT", 1.0, a, True)

    def maxf(self, a, b):
        return self.math("MAXIMUM", a, b)

    def remap(self, v, lo, hi, out_lo=0.0, out_hi=1.0, smooth=True):
        n = self.node("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP" if smooth else "LINEAR",
                      clamp=True)
        self.set(n.inputs["Value"], v)
        n.inputs["From Min"].default_value = lo
        n.inputs["From Max"].default_value = hi
        n.inputs["To Min"].default_value = out_lo
        n.inputs["To Max"].default_value = out_hi
        return n.outputs["Result"]

    def vadd(self, a, b):
        n = self.node("ShaderNodeVectorMath", operation="ADD")
        self.set(n.inputs[0], a)
        self.set(n.inputs[1], b)
        return n.outputs["Vector"]

    def vscale(self, a, s):
        n = self.node("ShaderNodeVectorMath", operation="SCALE")
        self.set(n.inputs[0], a)
        self.set(self._sock(n.inputs, "Scale"), s)
        return n.outputs["Vector"]

    # -- color
    def mix(self, fac, a, b, blend="MIX"):
        n = self.node("ShaderNodeMix", data_type="RGBA", blend_type=blend, clamp_result=True)
        self.set(self._sock(n.inputs, "Factor", "VALUE"), fac)
        self.set(self._sock(n.inputs, "A", "RGBA"), a)
        self.set(self._sock(n.inputs, "B", "RGBA"), b)
        return self._sock(n.outputs, "Result", "RGBA")

    def lerp(self, fac, a, b):
        """Float lerp (a, b floats or sockets)."""
        n = self.node("ShaderNodeMix", data_type="FLOAT", clamp_factor=True)
        self.set(self._sock(n.inputs, "Factor", "VALUE"), fac)
        self.set(self._sock(n.inputs, "A", "VALUE"), a)
        self.set(self._sock(n.inputs, "B", "VALUE"), b)
        return self._sock(n.outputs, "Result", "VALUE")

    def ramp(self, fac, stops, interp="LINEAR"):
        n = self.node("ShaderNodeValToRGB")
        cr = n.color_ramp
        cr.interpolation = interp
        while len(cr.elements) < len(stops):
            cr.elements.new(0.5)
        for el, (pos, col) in zip(cr.elements, stops):
            el.position = pos
            el.color = _rgba(col)
        self.set(n.inputs["Fac"], fac)
        return n.outputs["Color"]

    def gray(self, c):
        n = self.node("ShaderNodeRGBToBW")
        self.set(n.inputs[0], c)
        return n.outputs[0]

    # -- textures
    def noise(self, vec, scale, detail=4.0, rough=0.55, distortion=0.0, color=False):
        n = self.node("ShaderNodeTexNoise")
        self.set(n.inputs["Vector"], vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        n.inputs["Distortion"].default_value = distortion
        return n.outputs["Color" if color else "Fac"]

    def voronoi(self, vec, scale, feature="F1", out="Distance", randomness=1.0):
        n = self.node("ShaderNodeTexVoronoi", feature=feature)
        self.set(n.inputs["Vector"], vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Randomness"].default_value = randomness
        return n.outputs[out]

    def wave(self, vec, scale, kind="BANDS", direction="X", profile="SIN", distortion=0.0, detail=2.0):
        n = self.node("ShaderNodeTexWave", wave_type=kind, wave_profile=profile)
        if kind == "BANDS":
            n.bands_direction = direction
        else:
            n.rings_direction = direction if direction in ("X", "Y", "Z", "SPHERICAL") else "SPHERICAL"
        self.set(n.inputs["Vector"], vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Distortion"].default_value = distortion
        n.inputs["Detail"].default_value = detail
        return n.outputs["Fac"]

    # -- surface analysis (Cycles)
    def bevel_normal(self, radius=0.012, samples=8):
        if not hasattr(self, "_bev"):
            self._bev = {}
        key = round(radius, 5)
        if key not in self._bev:
            b = self.node("ShaderNodeBevel", samples=samples)
            b.inputs["Radius"].default_value = radius
            self._bev[key] = b.outputs["Normal"]
        return self._bev[key]

    def edges(self, radius=0.012, sharp=0.06, breakup=None, convex_only=True):
        """0..1 mask on (convex) edges within `radius`, optionally broken up by a 0..1 socket."""
        geo = self.node("ShaderNodeNewGeometry")
        d = self.node("ShaderNodeVectorMath", operation="DOT_PRODUCT")
        self.set(d.inputs[0], self.bevel_normal(radius))
        self.set(d.inputs[1], geo.outputs["Normal"])
        e = self.remap(self.inv(d.outputs["Value"]), 0.0, sharp)
        if convex_only:
            e = self.mul(e, self.remap(self.ao(radius * 6.0), 0.55, 0.9))
        if breakup is not None:
            e = self.remap(self.sub(e, breakup), 0.0, 0.35)
        return e

    def ao(self, distance=0.1, samples=16, inside=False):
        n = self.node("ShaderNodeAmbientOcclusion", samples=samples, inside=inside, only_local=False)
        n.inputs["Distance"].default_value = distance
        return n.outputs["AO"]

    def cavity(self, distance=0.12, lo=0.35, hi=0.95):
        """0 open surface .. 1 deep crevice."""
        return self.inv(self.remap(self.ao(distance), lo, hi))

    def bump(self, height, strength=0.3, distance=0.004, normal=None, invert=False):
        n = self.node("ShaderNodeBump", invert=invert)
        self.set(n.inputs["Height"], height)
        n.inputs["Strength"].default_value = strength
        n.inputs["Distance"].default_value = distance
        if normal is not None:
            self.set(n.inputs["Normal"], normal)
        return n.outputs["Normal"]

    # -- outputs
    def out(self, base=None, rough=None, metal=None, normal=None, emit=None, emit_strength=None):
        b = self.bsdf
        if base is not None:
            self.set(b.inputs["Base Color"], base)
        if rough is not None:
            self.set(b.inputs["Roughness"], rough)
        if metal is not None:
            self.set(b.inputs["Metallic"], metal)
        if normal is not None:
            self.set(b.inputs["Normal"], normal)
        if emit is not None:
            self.set(b.inputs["Emission Color"], emit)
            b.inputs["Emission Strength"].default_value = emit_strength or 1.0


def _new(name, flat, flat_rough, flat_metal, flat_emit=None):
    """Returns (material, G) or (existing material, None) when already created."""
    if name in bpy.data.materials:
        return bpy.data.materials[name], None
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m["sb_bake"] = 1
    m["sb_flat"] = [float(flat[0]), float(flat[1]), float(flat[2]), float(flat_rough), float(flat_metal)]
    if flat_emit:
        m["sb_flat_emit"] = [float(x) for x in flat_emit]
    m.diffuse_color = _rgba(flat)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = _rgba(flat)
    bsdf.inputs["Roughness"].default_value = flat_rough
    bsdf.inputs["Metallic"].default_value = flat_metal
    return m, G(m)


def _lin(c, k):
    return tuple(min(1.0, x * k) for x in c)


# ----------------------------------------------------------------------------- metals


def worn_steel(name="WornSteel", tint=(0.42, 0.43, 0.46), roughness=0.36, wear=1.0, grime=1.0,
               rust=0.0, scale=1.0, bevel=0.012, edge_k=1.7, scratch_k=1.45):
    """Battle-worn plate: brushed scratches, polished bright convex edges, dark oily grime in
    crevices, optional rust blooms (rust 0..1). `scale` multiplies all pattern frequencies."""
    m, g = _new(name, tint, roughness + 0.1, 1.0)
    if g is None:
        return m
    co = g.co(scale)
    smudge = g.noise(co, 3.0, 6.0, 0.6)
    breakup = g.noise(co, 14.0, 4.0, 0.6)
    # scratches: thin cell edges of two stretched voronoi layers
    s1 = g.voronoi(g.co((scale * 2.0, scale * 2.0, scale * 9.0)), 9.0, "DISTANCE_TO_EDGE")
    s2 = g.voronoi(g.co((scale * 7.0, scale * 2.5, scale * 2.0), (3.1, 1.7, 0.4)), 7.0, "DISTANCE_TO_EDGE")
    scratch = g.maxf(g.remap(s1, 0.018, 0.0), g.mul(g.remap(s2, 0.012, 0.0), 0.7))
    scratch = g.mul(scratch, g.remap(g.noise(co, 2.5, 2.0), 0.4, 0.65))
    pits = g.remap(g.noise(co, 70.0, 2.0), 0.62, 0.75)
    edge = g.mul(g.edges(bevel, 0.06, breakup), wear)
    cav = g.mul(g.cavity(0.15), grime)
    dirt = g.mul(g.remap(smudge, 0.45, 0.75), 0.35 * grime)
    col = g.mix(g.remap(smudge, 0.3, 0.7), _lin(tint, 0.82), tint)
    col = g.mix(scratch, col, _lin(tint, scratch_k))
    col = g.mix(edge, col, _lin(tint, edge_k))
    grime_col = (0.045, 0.04, 0.035)
    col = g.mix(g.maxf(cav, dirt), col, grime_col)
    rough = g.add(roughness, g.mul(g.sub(smudge, 0.5), 0.35))
    rough = g.lerp(scratch, rough, roughness * 0.6)
    rough = g.lerp(edge, rough, 0.18)
    rough = g.lerp(g.maxf(cav, dirt), rough, 0.85)
    metal = g.inv(g.mul(g.maxf(cav, dirt), 0.75))
    if rust > 0.0:
        rmask = g.mul(g.remap(g.noise(co, 4.0, 8.0, 0.65), 0.55, 0.7), rust)
        rmask = g.maxf(rmask, g.mul(cav, rust))
        rcol = g.mix(g.noise(co, 40.0, 3.0), (0.16, 0.05, 0.02), (0.32, 0.12, 0.04))
        col = g.mix(rmask, col, rcol)
        rough = g.lerp(rmask, rough, 0.92)
        metal = g.lerp(rmask, metal, 0.05)
    height = g.sub(g.mul(pits, -0.4), g.mul(scratch, 0.6))
    nrm = g.bump(height, 0.25, 0.002, g.bevel_normal(bevel))
    g.out(col, rough, metal, nrm)
    return m


def gold_filigree(name="GoldFiligree", tint=(1.0, 0.72, 0.3), scale=1.0, bevel=0.01):
    """Engraved gold: raised polished scrollwork over a recessed tarnished ground, dark patina in
    cavities, bright worn edges."""
    m, g = _new(name, _lin(tint, 0.85), 0.35, 1.0)
    if g is None:
        return m
    co = g.co(scale)
    warp = g.vadd(co, g.vscale(g.noise(co, 3.0, 3.0, 0.5, color=True), 0.12))
    w1 = g.wave(warp, 9.0, "RINGS", "SPHERICAL", "SIN", 6.0, 3.0)
    w2 = g.wave(warp, 14.0, "BANDS", "DIAGONAL", "SIN", 9.0, 2.0)
    line1 = g.remap(w1, 0.12, 0.0)
    line2 = g.remap(w2, 0.1, 0.0)
    # scroll lines + small punched dots between them
    dots = g.remap(g.voronoi(co, 70.0, "F1"), 0.2, 0.1)
    raised = g.maxf(g.maxf(line1, line2), g.mul(dots, 0.6))
    cav = g.cavity(0.1)
    edge = g.edges(bevel, 0.05, g.noise(co, 18.0, 3.0))
    ground = g.mix(g.noise(co, 30.0, 4.0), _lin(tint, 0.55), _lin(tint, 0.7))
    col = g.mix(raised, ground, tint)
    col = g.mix(edge, col, _lin(tint, 1.25))
    patina = (0.12, 0.07, 0.025)
    col = g.mix(g.maxf(g.mul(cav, 0.9), g.mul(g.inv(raised), 0.25)), col, patina)
    rough = g.lerp(raised, 0.48, 0.2)
    rough = g.lerp(edge, rough, 0.14)
    rough = g.lerp(cav, rough, 0.7)
    metal = g.inv(g.mul(cav, 0.6))
    nrm = g.bump(raised, 0.45, 0.003, g.bevel_normal(bevel))
    g.out(col, rough, metal, nrm)
    return m


# ----------------------------------------------------------------------------- stone / glass


def weathered_marble(name="WeatheredMarble", tint=(0.74, 0.72, 0.68), vein=(0.22, 0.22, 0.24),
                     scale=1.0, bevel=0.02):
    """Pale veined marble, rain-dulled with dirt in crevices, lighter chipped edges, pitting."""
    m, g = _new(name, tint, 0.65, 0.0)
    if g is None:
        return m
    co = g.co(scale)
    vn = g.noise(co, 1.3, 8.0, 0.62, 2.5)
    vein1 = g.remap(g.math("ABSOLUTE", g.sub(vn, 0.5)), 0.03, 0.0)
    vn2 = g.noise(g.co(scale, (5.0, 2.0, 1.0)), 3.2, 6.0, 0.6, 1.5)
    vein2 = g.mul(g.remap(g.math("ABSOLUTE", g.sub(vn2, 0.5)), 0.015, 0.0), 0.6)
    veins = g.maxf(vein1, vein2)
    cloud = g.noise(co, 2.0, 5.0)
    weather = g.remap(g.noise(co, 1.6, 6.0, 0.6), 0.48, 0.72)
    cav = g.cavity(0.25)
    edge = g.edges(bevel, 0.06, g.noise(co, 9.0, 4.0))
    pits = g.remap(g.noise(co, 45.0, 2.0), 0.6, 0.72)
    base = g.mix(cloud, _lin(tint, 0.93), _lin(tint, 1.05))
    col = g.mix(veins, base, vein)
    col = g.mix(g.mul(weather, 0.55), col, (0.4, 0.37, 0.31))
    col = g.mix(edge, col, _lin(tint, 1.15))
    col = g.mix(g.maxf(cav, g.mul(pits, 0.5)), col, (0.12, 0.11, 0.08))
    rough = g.lerp(weather, 0.42, 0.82)
    rough = g.lerp(cav, rough, 0.95)
    height = g.sub(g.mul(pits, -0.5), g.mul(weather, 0.15))
    nrm = g.bump(height, 0.3, 0.003, g.bevel_normal(bevel))
    g.out(col, rough, 0.0, nrm)
    return m


def obsidian_ember(name="ObsidianEmber", tint=(0.018, 0.016, 0.02), ember=(1.0, 0.3, 0.05),
                   strength=6.0, crack_scale=3.5, crack_width=0.03, scale=1.0, bevel=0.01):
    """Glassy black volcanic glass split by glowing ember cracks (emission is baked to a texture;
    `strength` stays the emission multiplier)."""
    m, g = _new(name, tint, 0.2, 0.0)
    if g is None:
        return m
    co = g.co(scale)
    warp = g.vadd(co, g.vscale(g.noise(co, 2.0, 4.0, 0.6, color=True), 0.18))
    d = g.voronoi(warp, crack_scale, "DISTANCE_TO_EDGE")
    d2 = g.voronoi(g.vadd(warp, (7.0, 3.0, 1.0)), crack_scale * 2.7, "DISTANCE_TO_EDGE")
    crack = g.maxf(g.remap(d, crack_width, 0.0), g.mul(g.remap(d2, crack_width * 0.5, 0.0), 0.65))
    char = g.maxf(g.remap(d, crack_width * 1.8, crack_width * 0.4), g.mul(g.remap(d2, crack_width * 1.0, 0.0), 0.5))
    heat = g.remap(g.noise(co, 2.5, 3.0), 0.3, 0.7, 0.35, 1.0)
    ripple = g.wave(warp, 6.0, "RINGS", "SPHERICAL", "SIN", 4.0, 2.0)
    edge = g.edges(bevel, 0.05, g.noise(co, 20.0, 3.0))
    col = g.mix(g.noise(co, 8.0, 3.0), tint, _lin(tint, 1.8))
    col = g.mix(edge, col, (0.07, 0.065, 0.075))
    col = g.mix(char, col, (0.09, 0.03, 0.012))
    rough = g.lerp(g.remap(ripple, 0.2, 0.8), 0.08, 0.22)
    rough = g.lerp(char, rough, 0.85)
    emit = g.mix(g.mul(crack, heat), (0.0, 0.0, 0.0), ember)
    height = g.add(g.mul(ripple, 0.08), g.mul(char, -0.6))
    nrm = g.bump(height, 0.4, 0.004, g.bevel_normal(bevel))
    if strength > 0.0:
        g.out(col, rough, 0.0, nrm, emit, strength)
    else:  # dark carved obsidian, no glow (strength 0): charred cracks only
        g.out(col, rough, 0.0, nrm)
    return m


# ----------------------------------------------------------------------------- organics


def aged_ivory(name="AgedIvory", tint=(0.78, 0.7, 0.53), scale=1.0, bevel=0.01):
    """Old ivory / polished bone: growth banding, fine dark crackle, yellow-brown in crevices,
    worn glossy highs."""
    m, g = _new(name, tint, 0.45, 0.0)
    if g is None:
        return m
    co = g.co(scale)
    bands = g.wave(g.vadd(co, g.vscale(g.noise(co, 2.0, 2.0, color=True), 0.05)), 18.0, "BANDS", "Z", "SIN", 2.0, 1.0)
    crack = g.remap(g.voronoi(g.vadd(co, g.vscale(g.noise(co, 6.0, 2.0, color=True), 0.02)), 22.0,
                              "DISTANCE_TO_EDGE"), 0.025, 0.0)
    crack = g.mul(crack, g.remap(g.noise(co, 4.0, 3.0), 0.4, 0.6))
    cav = g.cavity(0.1)
    edge = g.edges(bevel, 0.05, g.noise(co, 15.0, 3.0))
    yellow = g.remap(g.noise(co, 2.2, 5.0), 0.4, 0.75)
    col = g.mix(g.mul(bands, 0.5), tint, _lin(tint, 0.9))
    col = g.mix(g.mul(yellow, 0.6), col, (0.62, 0.48, 0.26))
    col = g.mix(edge, col, _lin(tint, 1.18))
    col = g.mix(g.maxf(g.mul(cav, 0.85), g.mul(crack, 0.8)), col, (0.22, 0.14, 0.06))
    rough = g.lerp(edge, g.lerp(yellow, 0.38, 0.55), 0.25)
    rough = g.lerp(cav, rough, 0.75)
    nrm = g.bump(g.sub(g.mul(bands, 0.1), crack), 0.25, 0.002, g.bevel_normal(bevel))
    g.out(col, rough, 0.0, nrm)
    return m


def filigree_ivory(name="FiligreeIvory", tint=(0.84, 0.8, 0.7), inlay=(0.95, 0.7, 0.3), scale=1.0, bevel=0.01,
                   yellow=(0.7, 0.6, 0.42), grime=(0.2, 0.14, 0.07), line_k=1.0):
    """Ivory plate engraved with scrolling gold-inlaid filigree (warped ring + band scrollwork),
    polished worn edges, warm grime in the crevices (the Archon's plate, shared)."""
    m, g = _new(name, tint, 0.36, 0.1)
    if g is None:
        return m
    co = g.co(scale)
    warp = g.vadd(co, g.vscale(g.noise(co, 2.2, 3.0, 0.5, color=True), 0.16))
    w1 = g.wave(warp, 4.5, "RINGS", "SPHERICAL", "SIN", 6.0, 2.0)
    w2 = g.wave(warp, 7.0, "BANDS", "Z", "SIN", 4.0, 2.0)
    line = g.maxf(g.remap(w1, 0.11, 0.03), g.mul(g.remap(w2, 0.09, 0.02), g.remap(g.noise(co, 3.0, 2.0), 0.45, 0.6)))
    if line_k != 1.0:
        line = g.mul(line, line_k)
    cav = g.cavity(0.1)
    edge = g.edges(bevel, 0.05, g.noise(co, 15.0, 3.0))
    yel = g.remap(g.noise(co, 2.2, 5.0), 0.4, 0.75)
    col = g.mix(g.mul(yel, 0.22), tint, yellow)
    col = g.mix(edge, col, _lin(tint, 1.15))
    col = g.mix(line, col, inlay)
    col = g.mix(g.mul(cav, 0.85), col, grime)
    rough = g.lerp(line, g.lerp(edge, 0.4, 0.24), 0.22)
    rough = g.lerp(cav, rough, 0.75)
    metal = g.mul(line, 0.95)
    nrm = g.bump(g.mul(line, -1.0), 0.35, 0.002, g.bevel_normal(bevel))
    g.out(col, rough, metal, nrm)
    return m


def bone(name="Bone", tint=(0.66, 0.6, 0.48), scale=1.0):
    """Dry, porous bone (rougher, dirtier variant of aged ivory)."""
    m, g = _new(name, tint, 0.7, 0.0)
    if g is None:
        return m
    co = g.co(scale)
    pores = g.remap(g.voronoi(co, 90.0, "F1"), 0.12, 0.03)
    streak = g.noise(g.co((scale * 1.0, scale * 1.0, scale * 6.0)), 6.0, 4.0)
    cav = g.cavity(0.12)
    edge = g.edges(0.012, 0.05, g.noise(co, 12.0, 3.0))
    col = g.mix(streak, _lin(tint, 0.85), tint)
    col = g.mix(edge, col, _lin(tint, 1.15))
    col = g.mix(g.maxf(cav, g.mul(pores, 0.5)), col, (0.2, 0.15, 0.09))
    rough = g.lerp(cav, g.lerp(edge, 0.72, 0.5), 0.9)
    nrm = g.bump(g.sub(g.mul(streak, 0.2), pores), 0.25, 0.002, g.bevel_normal(0.012))
    g.out(col, rough, 0.0, nrm)
    return m


def leather(name="Leather", tint=(0.16, 0.085, 0.045), scale=1.0, bevel=0.008):
    """Oiled, pebble-grained leather; burnished lighter edges, creases, dark cavities."""
    m, g = _new(name, tint, 0.65, 0.0)
    if g is None:
        return m
    co = g.co(scale)
    grain = g.voronoi(co, 140.0, "F1")
    pebble = g.remap(grain, 0.0, 0.45)
    crease = g.remap(g.noise(g.co((scale * 1.0, scale * 4.0, scale * 1.0)), 9.0, 5.0, 0.65), 0.5, 0.58)
    crease = g.math("ABSOLUTE", g.sub(crease, 0.5))
    crease = g.remap(crease, 0.08, 0.0)
    blot = g.noise(co, 4.0, 5.0)
    cav = g.cavity(0.08)
    edge = g.edges(bevel, 0.07, g.noise(co, 10.0, 3.0))
    col = g.mix(blot, _lin(tint, 0.75), _lin(tint, 1.2))
    col = g.mix(g.mul(pebble, 0.3), col, _lin(tint, 0.6))
    col = g.mix(edge, col, (0.34, 0.2, 0.11))
    col = g.mix(g.maxf(cav, g.mul(crease, 0.5)), col, (0.03, 0.017, 0.01))
    rough = g.lerp(pebble, 0.55, 0.78)
    rough = g.lerp(edge, rough, 0.38)
    height = g.sub(g.mul(pebble, 0.35), crease)
    nrm = g.bump(height, 0.35, 0.002, g.bevel_normal(bevel))
    g.out(col, rough, 0.0, nrm)
    return m


def linen(name="Linen", tint=(0.5, 0.45, 0.37), weave=180.0, scale=1.0, rough=0.86, stain=0.6,
          stain_col=(0.24, 0.18, 0.12), grime_col=(0.06, 0.05, 0.04)):
    """Coarse woven linen / burial cloth: visible over-under weave, stains, grime in folds."""
    m, g = _new(name, tint, min(1.0, rough + 0.04), 0.0)
    if g is None:
        return m
    co = g.co(scale)
    jitter = g.vadd(co, g.vscale(g.noise(co, 30.0, 2.0, color=True), 0.004))
    wx = g.wave(jitter, weave, "BANDS", "X", "SIN", 0.5, 1.0)
    wz = g.wave(jitter, weave, "BANDS", "Z", "SIN", 0.5, 1.0)
    wy = g.wave(jitter, weave, "BANDS", "Y", "SIN", 0.5, 1.0)
    threads = g.maxf(g.maxf(wx, wz), g.mul(wy, 0.7))
    slub = g.noise(g.co((scale * 2.0, scale * 30.0, scale * 2.0)), 6.0, 2.0)
    stain_m = g.remap(g.noise(co, 2.5, 6.0, 0.6), 0.5, 0.72)
    cav = g.cavity(0.2, 0.45, 0.98)
    col = g.mix(g.mul(threads, 0.6), _lin(tint, 0.78), tint)
    col = g.mix(g.mul(slub, 0.3), col, _lin(tint, 1.15))
    col = g.mix(g.mul(stain_m, stain), col, stain_col)
    col = g.mix(cav, col, grime_col)
    r = g.lerp(stain_m, rough, min(1.0, rough + 0.09))
    nrm = g.bump(threads, 0.35, 0.0015)
    g.out(col, r, 0.0, nrm)
    return m


def feathers(name="Feathers", tint=(0.05, 0.045, 0.05), sheen=(0.05, 0.07, 0.09), barbs=90.0, scale=1.0,
             edge_col=(0.16, 0.15, 0.15), shade_col=(0.01, 0.01, 0.012), vary=(0.6, 1.6), shade=1.0):
    """Dark corvid feathers: fine barb striations, per-feather value shifts, oil-slick blue-green
    sheen, pale frayed tips on edges. For PALE feathers pass a warm mid-tone `shade_col`, a soft
    `edge_col`, a narrower `vary` and `shade` < 1 so barbs/rachis read as form, not as dirt."""
    m, g = _new(name, tint, 0.6, 0.0)
    if g is None:
        return m
    co = g.co(scale)
    cell = g.voronoi(g.co((scale * 1.0, scale * 1.0, scale * 0.35)), 5.0, "F1", "Color")
    v = g.gray(cell)
    barb = g.wave(g.vadd(co, g.vscale(g.noise(co, 8.0, 2.0, color=True), 0.01)), barbs, "BANDS",
                  "DIAGONAL", "SAW", 1.5, 1.0)
    split = g.remap(g.noise(g.co((scale * 1.0, scale * 1.0, scale * 12.0)), 20.0, 2.0), 0.62, 0.7)
    edge = g.edges(0.01, 0.05, g.noise(co, 25.0, 2.0), convex_only=False)
    cav = g.cavity(0.08)
    col = g.mix(v, _lin(tint, vary[0]), _lin(tint, vary[1]))
    col = g.mix(g.mul(g.remap(g.noise(co, 3.0, 3.0), 0.5, 0.75), 0.8), col, sheen)
    col = g.mix(g.mul(barb, 0.35), col, _lin(tint, 1.7))
    col = g.mix(g.mul(edge, 0.6), col, edge_col)
    col = g.mix(g.mul(g.maxf(cav, split), shade), col, shade_col)
    rough = g.lerp(barb, 0.5, 0.7)
    nrm = g.bump(g.sub(barb, g.mul(split, 1.5)), 0.3, 0.0015)
    g.out(col, rough, 0.0, nrm)
    return m


def skin(name="Skin", tint=(0.3, 0.08, 0.06), scale=1.0, pores=110.0, crease=(0.05, 0.012, 0.01),
         high=None, veins=0.0, vein_col=(0.08, 0.01, 0.015), rough=0.55, scars=0.0):
    """Living (or undead) hide: blotchy mottling, fine pores, wrinkle creases darkening into the
    cavities, slightly lighter / glossier stretched highs on convex forms; optional dark veins
    (voronoi cell walls) for wing membranes / sickly flesh and pale scar streaks."""
    m, g = _new(name, tint, rough, 0.0)
    if g is None:
        return m
    co = g.co(scale)
    high = high or _lin(tint, 1.35)
    mottle = g.noise(co, 5.0, 5.0, 0.6)
    blot = g.remap(g.noise(co, 1.8, 4.0), 0.35, 0.7)
    pore = g.remap(g.voronoi(co, pores, "F1"), 0.18, 0.04)
    wr = g.noise(g.co((scale * 1.0, scale * 1.0, scale * 3.5)), 14.0, 4.0, 0.6)
    wrinkle = g.remap(g.math("ABSOLUTE", g.sub(wr, 0.5)), 0.05, 0.0)
    cav = g.cavity(0.1)
    hi = g.edges(0.03, 0.1, None, convex_only=True)
    col = g.mix(mottle, _lin(tint, 0.8), _lin(tint, 1.12))
    col = g.mix(g.mul(blot, 0.35), col, _lin(tint, 0.65))
    col = g.mix(g.mul(hi, 0.55), col, high)
    if veins > 0.0:
        vw = g.voronoi(g.vadd(co, g.vscale(g.noise(co, 4.0, 3.0, color=True), 0.05)), 6.0, "DISTANCE_TO_EDGE")
        vmask = g.mul(g.remap(vw, 0.02, 0.0), veins)
        col = g.mix(vmask, col, vein_col)
    else:
        vmask = None
    if scars > 0.0:
        sc = g.remap(g.math("ABSOLUTE", g.sub(g.noise(g.co((scale * 1.0, scale * 6.0, scale * 1.0)), 3.0, 3.0), 0.5)),
                     0.025, 0.0)
        sc = g.mul(sc, g.mul(g.remap(g.noise(co, 2.0, 2.0), 0.5, 0.65), scars))
        col = g.mix(sc, col, _lin(tint, 1.6))
    col = g.mix(g.maxf(g.mul(cav, 0.85), g.mul(g.maxf(wrinkle, pore), 0.45)), col, crease)
    r = g.add(rough, g.mul(g.sub(mottle, 0.5), 0.2))
    r = g.lerp(g.mul(hi, 0.6), r, rough * 0.7)
    r = g.lerp(cav, r, min(1.0, rough + 0.25))
    height = g.add(g.mul(pore, -0.5), g.mul(wrinkle, -0.7))
    if vmask is not None:
        height = g.add(height, g.mul(vmask, 0.6))
    nrm = g.bump(height, 0.3, 0.0015)
    g.out(col, r, 0.0, nrm)
    return m


def horn(name="Horn", tint=(0.3, 0.25, 0.2), scale=1.0, rings=22.0, tip=None, rough=0.5):
    """Keratin horn / claw: growth rings, long fibrous striations, darker cavities, polished worn
    highs. `tip` = optional colour blended in by object-space height noise (dark horn tips)."""
    m, g = _new(name, tint, rough, 0.0)
    if g is None:
        return m
    co = g.co(scale)
    warp = g.vadd(co, g.vscale(g.noise(co, 3.0, 2.0, color=True), 0.04))
    ring = g.wave(warp, rings, "RINGS", "SPHERICAL", "SIN", 2.0, 2.0)
    fib = g.noise(g.co((scale * 14.0, scale * 14.0, scale * 1.0)), 6.0, 4.0, 0.6)
    fib2 = g.noise(g.co((scale * 1.0, scale * 14.0, scale * 14.0)), 6.0, 4.0, 0.6)
    fibre = g.lerp(0.5, fib, fib2)
    cav = g.cavity(0.08)
    edge = g.edges(0.012, 0.06, g.noise(co, 14.0, 3.0))
    col = g.mix(fibre, _lin(tint, 0.7), _lin(tint, 1.25))
    col = g.mix(g.mul(g.remap(ring, 0.15, 0.0), 0.6), col, _lin(tint, 0.45))
    if tip is not None:
        col = g.mix(g.remap(g.noise(co, 1.5, 2.0), 0.4, 0.65), col, tip)
    col = g.mix(edge, col, _lin(tint, 1.5))
    col = g.mix(g.mul(cav, 0.85), col, _lin(tint, 0.18))
    r = g.lerp(edge, g.add(rough, g.mul(g.sub(fibre, 0.5), 0.25)), rough * 0.55)
    r = g.lerp(cav, r, 0.85)
    nrm = g.bump(g.add(g.mul(g.remap(ring, 0.15, 0.0), -0.6), g.mul(fibre, 0.25)), 0.35, 0.002,
                 g.bevel_normal(0.012))
    g.out(col, r, 0.0, nrm)
    return m


def silk(name="Silk", tint=(0.3, 0.03, 0.05), rough=0.45, scale=1.0, weave=260.0):
    """Fine silk / velvet: very fine weave, broad sheen bands along the folds, dust in cavities."""
    m, g = _new(name, tint, rough, 0.0)
    if g is None:
        return m
    co = g.co(scale)
    wx = g.wave(co, weave, "BANDS", "X", "SIN", 0.3, 0.0)
    wz = g.wave(co, weave, "BANDS", "Z", "SIN", 0.3, 0.0)
    threads = g.maxf(wx, wz)
    sheen = g.noise(g.co((scale * 1.0, scale * 1.0, scale * 0.3)), 3.0, 3.0, 0.5)
    cav = g.cavity(0.15, 0.4, 0.97)
    col = g.mix(sheen, _lin(tint, 0.75), _lin(tint, 1.3))
    col = g.mix(g.mul(threads, 0.2), col, _lin(tint, 0.85))
    col = g.mix(cav, col, _lin(tint, 0.25))
    r = g.lerp(sheen, rough + 0.12, rough - 0.1)
    r = g.lerp(cav, r, 0.9)
    nrm = g.bump(threads, 0.15, 0.001)
    g.out(col, r, 0.0, nrm)
    return m


def hair(name="Hair", tint=(0.4, 0.38, 0.4), scale=1.0, rough=0.45):
    """Long strands: fine anisotropic streaks along object Z, darker roots in cavities."""
    m, g = _new(name, tint, rough, 0.0)
    if g is None:
        return m
    co = g.co(scale)
    s1 = g.noise(g.co((scale * 60.0, scale * 60.0, scale * 1.2)), 4.0, 3.0, 0.6)
    s2 = g.noise(g.co((scale * 25.0, scale * 25.0, scale * 0.6)), 3.0, 2.0, 0.5)
    cav = g.cavity(0.1)
    col = g.mix(s1, _lin(tint, 0.6), _lin(tint, 1.3))
    col = g.mix(g.mul(s2, 0.5), col, _lin(tint, 0.8))
    col = g.mix(g.mul(cav, 0.9), col, _lin(tint, 0.2))
    r = g.lerp(s1, rough + 0.12, rough - 0.12)
    nrm = g.bump(s1, 0.25, 0.001)
    g.out(col, r, 0.0, nrm)
    return m


ALL = {
    "worn_steel": worn_steel, "gold_filigree": gold_filigree, "weathered_marble": weathered_marble,
    "obsidian_ember": obsidian_ember, "aged_ivory": aged_ivory, "bone": bone, "leather": leather,
    "linen": linen, "feathers": feathers, "skin": skin, "horn": horn, "silk": silk, "hair": hair,
}
