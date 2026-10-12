"""SINBOUND texture baker: procedural Blender materials -> real textures embedded in the GLB.

HOW A MODEL SCRIPT OPTS IN
--------------------------
1. Use procedural materials from sbmat.py (or any Principled BSDF whose inputs are driven by
   node graphs -- Bevel / AO / noise / bump nodes are fine, they are evaluated by Cycles):

       import sb, sbmat
       CATEGORY = "bosses"
       BAKE = {"size": 1024}          # <- the opt-in. Optional keys below.

       def build():
           steel = sbmat.worn_steel("Knight_WornSteel")
           ...

2. Build as usual:  blender -b --factory-startup --python tools/blender/build.py -- bosses/knight
   build.py sees BAKE and, before exporting, calls bake.bake_scene():
     * applies modifiers + triangulates every mesh that uses a baked material (same geometry the
       exporter would write, so the tangent-space normal map matches exactly),
     * Smart-UV-projects ONLY the faces of baked materials into ONE shared atlas per model
       (texel density equalised across objects incl. object scale), UV map "BakeUV" = TEXCOORD_0,
     * bakes with Cycles (GPU if available) into 4 images per model:
         <model>_albedo   sRGB   base color (edge wear / grime / veins baked in)
         <model>_orm      linear R = ambient occlusion, G = roughness, B = metallic (glTF layout)
         <model>_normal   linear tangent-space normal (bump nodes + Bevel-node rounded edges)
         <model>_emission sRGB   only if a baked material glows (emission color; strength kept)
     * rewires each baked material to Image Texture nodes (glTF-exportable) and packs the
       images, so they are embedded in the .glb. Godot extracts them next to the .glb on import
       and GlbModel builds Art.textured_mat() materials from them (albedo/normal/ORM/emission).
   Plain sb.mat() materials (unlinked Principled inputs) are NOT baked and keep the usual
   Art.mat / Art.emissive path. They MAY share a mesh with baked materials (e.g. a glowing seam
   joined into a plate by merge_by_joint): their faces are hidden from the UV packer and parked
   at UV (0, 0), so they cost no atlas space.
   Each baked mesh object's own rotation/scale (kits' joins inherit the active part's transform)
   is folded into its vertices first, so object-space patterns / Bevel radii are in true meters.

BAKE options (all optional):
   size        512 | 1024 | 2048   atlas resolution                      (default 1024)
   samples     Cycles samples per pass (AO/Bevel noise)                  (default 24)
   margin      bake bleed in px                                          (default 8)
   island_margin  UV pack gap (fraction of atlas, exact)                (default 0.002)
   angle       smart-project angle limit, degrees                       (default 80)
   relax       re-flatten smart-project islands conformally (True) -> fewer, larger islands
   ao_distance AO ray length for the ORM red channel, meters            (default 0.35)
   skip        list of material names never baked (stay flat)
   only        list of material names to bake (default: every procedural material)
   device      "GPU" | "CPU"                                             (default GPU if found)
   debug_dir   folder for PNG copies of the maps (default tools/blender/previews/bake/)
   jpeg        JPEG quality for the embedded albedo/emission maps, 0 = PNG  (default 90)

Quick iteration without baking:  set SB_BAKE=0 in the environment; sbmat materials are then
flattened to their stored flat colors (bake.flatten_scene) and the model exports untextured.

Bake time: a ~20-object hero model at 1024 px bakes in roughly 10-30 s on the GPU (4 passes).
"""
import math
import os
import shutil
import tempfile
import time

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULTS = {
    "size": 1024, "samples": 24, "margin": 8, "island_margin": 0.002, "angle": 80.0,
    "ao_distance": 0.35, "skip": (), "only": None, "device": "GPU", "debug_dir": None, "relax": True,
    "jpeg": 90,
}
UV_NAME = "BakeUV"


# ----------------------------------------------------------------------------- material analysis

def _bsdf(mat):
    if mat is None or not mat.use_nodes or mat.node_tree is None:
        return None
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    return None


def _output(mat):
    outs = [n for n in mat.node_tree.nodes if n.type == "OUTPUT_MATERIAL"]
    for n in outs:
        if n.is_active_output:
            return n
    return outs[0] if outs else None


def is_procedural(mat):
    """True when the material's Principled BSDF is driven by node links (needs baking)."""
    b = _bsdf(mat)
    if b is None:
        return False
    if mat.get("sb_bake"):
        return True
    return any(i.is_linked for i in b.inputs)


def _bake_set(cfg):
    out = set()
    for m in bpy.data.materials:
        if m.name in cfg["skip"] or m.users == 0:
            continue
        if cfg["only"] is not None and m.name not in cfg["only"]:
            continue
        if is_procedural(m):
            out.add(m)
    return out


# ----------------------------------------------------------------------------- flat fallback

def flatten_material(mat):
    """Replace a procedural sbmat graph with its stored flat Principled values."""
    flat = mat.get("sb_flat")
    b = _bsdf(mat)
    if flat is None or b is None:
        return
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n != b and n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    b.inputs["Base Color"].default_value = (flat[0], flat[1], flat[2], 1.0)
    b.inputs["Roughness"].default_value = flat[3]
    b.inputs["Metallic"].default_value = flat[4]
    fe = mat.get("sb_flat_emit")
    if fe:
        b.inputs["Emission Color"].default_value = (fe[0], fe[1], fe[2], 1.0)
        b.inputs["Emission Strength"].default_value = fe[3]
    else:
        b.inputs["Emission Strength"].default_value = 0.0


def flatten_scene():
    """Flatten every sbmat material (used when a model is built without baking)."""
    for m in bpy.data.materials:
        if m.get("sb_flat") is not None and not m.get("sb_baked"):
            flatten_material(m)


# ----------------------------------------------------------------------------- scene prep

def _mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def _uses(obj, mats):
    return any(s.material in mats for s in obj.material_slots)


def _realize(objs):
    """Apply modifiers + triangulate (so bake geometry == exported geometry)."""
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        ev = o.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
        old = o.data
        me.name = old.name
        o.modifiers.clear()
        o.data = me
        if old.users == 0:
            bpy.data.meshes.remove(old)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
        bm.to_mesh(me)
        bm.free()
        me.update()


def _fold_transforms(objs):
    """Fold each mesh object's own rotation/scale (incl. its parent-inverse matrix) into the
    vertices, leaving only a translation. Joined meshes (sb kits' merge_by_joint / finalize) take
    the active part's transform, often a scaled one; baking (object-space patterns, Bevel radius,
    texel density) must see true meters. World-space result is unchanged. Animated mesh objects
    are left alone (their keys are relative to the current basis)."""
    from mathutils import Matrix
    ident = Matrix.Identity(3)
    for o in objs:
        ad = o.animation_data
        if ad and (ad.action or any(t.strips for t in ad.nla_tracks)):
            continue
        local = o.matrix_parent_inverse @ o.matrix_basis
        m3 = local.to_3x3()
        if all(abs(m3[r][c] - ident[r][c]) < 1e-6 for r in range(3) for c in range(3)):
            continue
        t = local.to_translation()
        o.data.transform(m3.to_4x4())
        if m3.determinant() < 0.0:
            o.data.flip_normals()
        o.matrix_parent_inverse = Matrix.Identity(4)
        o.matrix_basis = Matrix.Translation(t)
        o.data.update()


def _select_only(objs, active=None):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or (objs[0] if objs else None)


def _set_face_selection(objs, mats):
    for o in objs:
        me = o.data
        bm = bmesh.from_edit_mesh(me)
        for f in bm.faces:
            slot = o.material_slots[f.material_index] if f.material_index < len(o.material_slots) else None
            f.select_set(bool(slot and slot.material in mats))
        bm.select_flush_mode()
        bmesh.update_edit_mesh(me)


def _unwrap(objs, mats, cfg):
    for o in objs:
        me = o.data
        while me.uv_layers:
            me.uv_layers.remove(me.uv_layers[0])
        uv = me.uv_layers.new(name=UV_NAME)
        uv.active = True
        uv.active_render = True
    _select_only(objs)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    _set_face_selection(objs, mats)
    bpy.ops.uv.smart_project(angle_limit=math.radians(cfg["angle"]), island_margin=0.0,
                             area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    if cfg["relax"]:
        # Keep smart-project's islands (as seams) but re-flatten each one conformally: a high
        # angle limit then gives few, large islands without the projection squash at their rims.
        bpy.ops.mesh.hide(unselected=True)
        bpy.ops.uv.select_all(action="SELECT")
        bpy.ops.uv.seams_from_islands(mark_seams=True, mark_sharp=False)
        bpy.ops.uv.unwrap(method="CONFORMAL", margin=0.0, correct_aspect=True)
        bpy.ops.uv.average_islands_scale()
        bpy.ops.mesh.reveal(select=False)
        _set_face_selection(objs, mats)
    bpy.ops.object.mode_set(mode="OBJECT")
    # Equalise texel density between objects: smart_project works in local space.
    for o in objs if not cfg["relax"] else ():
        s = o.matrix_world.to_scale()
        k = (abs(s.x) + abs(s.y) + abs(s.z)) / 3.0
        if abs(k - 1.0) < 1e-4:
            continue
        uv = o.data.uv_layers[UV_NAME].data
        for p in o.data.polygons:
            if p.select:
                for li in p.loop_indices:
                    uv[li].uv = uv[li].uv * k
    # Faces of flat (non-baked) materials sharing these meshes keep the default full-square UVs
    # of a new layer: collapse them to a point and HIDE them so pack_islands ignores them
    # (otherwise every such face is packed as a full-size island and the real islands shrink
    # to specks). Their UVs are never sampled (flat materials have no textures).
    for o in objs:
        uv = o.data.uv_layers[UV_NAME].data
        for p in o.data.polygons:
            if not p.select:
                for li in p.loop_indices:
                    uv[li].uv = (0.0, 0.0)
    bpy.ops.object.mode_set(mode="EDIT")
    _set_face_selection(objs, mats)
    bpy.ops.mesh.hide(unselected=True)
    bpy.ops.mesh.select_all(action="SELECT")
    try:
        bpy.ops.uv.select_all(action="SELECT")
    except RuntimeError:
        pass
    try:  # FRACTION = an exact gap in atlas units (default SCALED inflates it on many small islands)
        bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=cfg["island_margin"],
                                shape_method="CONCAVE")
    except TypeError:
        bpy.ops.uv.pack_islands(rotate=True, margin=cfg["island_margin"])
    bpy.ops.mesh.reveal(select=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    # Safety: if pack touched them anyway, park the flat faces' UVs in a corner again.
    for o in objs:
        uv = o.data.uv_layers[UV_NAME].data
        for p in o.data.polygons:
            slot = o.material_slots[p.material_index] if p.material_index < len(o.material_slots) else None
            if not (slot and slot.material in mats):
                for li in p.loop_indices:
                    uv[li].uv = (0.0, 0.0)


# ----------------------------------------------------------------------------- cycles setup

def _setup_cycles(cfg):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = cfg["samples"]
    sc.cycles.use_denoising = False
    sc.cycles.device = "CPU"
    used = "CPU"
    if cfg["device"] == "GPU":
        try:
            prefs = bpy.context.preferences.addons["cycles"].preferences
            for kind in ("OPTIX", "CUDA", "HIP", "ONEAPI", "METAL"):
                try:
                    prefs.compute_device_type = kind
                except TypeError:
                    continue
                prefs.get_devices()
                gpus = [d for d in prefs.devices if d.type == kind]
                if gpus:
                    for d in prefs.devices:
                        d.use = d.type == kind
                    sc.cycles.device = "GPU"
                    used = kind
                    break
        except Exception as e:  # noqa: BLE001
            print("BAKE: GPU setup failed, using CPU:", e)
    bk = sc.render.bake
    bk.margin = cfg["margin"]
    try:
        bk.margin_type = "EXTEND"
    except (AttributeError, TypeError):
        pass
    bk.use_selected_to_active = False
    try:
        bk.target = "IMAGE_TEXTURES"
    except (AttributeError, TypeError):
        pass
    return used


def _save_takes_quality():
    try:
        return "quality" in {p.identifier for p in bpy.types.Image.bl_rna.functions["save"].parameters}
    except (KeyError, AttributeError):
        return False


def _image(name, size, data, color=(0, 0, 0, 1)):
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False, is_data=data)
    img.colorspace_settings.name = "Non-Color" if data else "sRGB"
    img.generated_color = color
    return img


# ----------------------------------------------------------------------------- passes

class _MatState:
    """Per-material bake plumbing: target image nodes + an Emission node we can rewire."""

    def __init__(self, mat, baked, cfg):
        self.mat = mat
        self.baked = baked
        nt = mat.node_tree
        self.nt = nt
        self.bsdf = _bsdf(mat)
        self.out = _output(mat)
        if self.out is None:
            self.out = nt.nodes.new("ShaderNodeOutputMaterial")
        surf = self.out.inputs["Surface"]
        self.orig_surface = surf.links[0].from_socket if surf.is_linked else None
        self.emit = nt.nodes.new("ShaderNodeEmission")
        self.emit.inputs["Strength"].default_value = 1.0
        self.targets = {}
        if baked:
            ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
            ao.samples = 16
            ao.only_local = False
            ao.inputs["Distance"].default_value = cfg["ao_distance"]
            if self.bsdf.inputs["Normal"].is_linked:
                nt.links.new(self.bsdf.inputs["Normal"].links[0].from_socket, ao.inputs["Normal"])
            self.comb = nt.nodes.new("ShaderNodeCombineColor")
            nt.links.new(ao.outputs["AO"], self.comb.inputs[0])
            self._feed(self.comb.inputs[1], "Roughness")
            self._feed(self.comb.inputs[2], "Metallic")

    def _feed(self, dst, name):
        src = self.bsdf.inputs[name]
        if src.is_linked:
            self.nt.links.new(src.links[0].from_socket, dst)
        else:
            v = src.default_value
            scalar = isinstance(v, (float, int))
            if dst.type == "RGBA":
                dst.default_value = (v, v, v, 1.0) if scalar else tuple(v)
            else:
                dst.default_value = v if scalar else v[0]

    def target(self, key, img):
        n = self.nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        self.targets[key] = n

    def activate(self, key):
        n = self.targets[key]
        for m in self.nt.nodes:
            m.select = False
        n.select = True
        self.nt.nodes.active = n

    def surface(self, sock):
        self.nt.links.new(sock, self.out.inputs["Surface"])

    def emit_from(self, what):
        e = self.emit.inputs["Color"]
        for l in list(e.links):
            self.nt.links.remove(l)
        if not self.baked:
            pass  # bakes into the dummy image; content irrelevant
        elif what == "albedo":
            self._feed(e, "Base Color")
        elif what == "orm":
            self.nt.links.new(self.comb.outputs[0], e)
        elif what == "emission":
            self._feed(e, "Emission Color")
        self.surface(self.emit.outputs[0])

    def restore_surface(self):
        if self.orig_surface is not None:
            self.surface(self.orig_surface)


def _bake(kind, states, key, objs, **kw):
    for st in states:
        st.activate(key if st.baked else "dummy")
    _select_only(objs)
    t = time.time()
    bpy.ops.object.bake(type=kind, use_clear=True, margin=bpy.context.scene.render.bake.margin, **kw)
    return time.time() - t


def _emission_strength(mat):
    b = _bsdf(mat)
    s = b.inputs["Emission Strength"]
    c = b.inputs["Emission Color"]
    if s.is_linked:
        return 1.0
    if not c.is_linked and (max(c.default_value[:3]) <= 0.0):
        return 0.0
    return s.default_value


# ----------------------------------------------------------------------------- final materials

def _gltf_output_group():
    name = "glTF Material Output"
    if name in bpy.data.node_groups:
        return bpy.data.node_groups[name]
    g = bpy.data.node_groups.new(name, "ShaderNodeTree")
    g.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    g.interface.new_socket("Thickness", in_out="INPUT", socket_type="NodeSocketFloat")
    return g


def _rebuild(mat, imgs, strength, emission_color_fallback):
    """Replace the material with a glTF-exportable textured Principled BSDF."""
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (400, 0)
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    b.location = (100, 0)
    nt.links.new(b.outputs[0], out.inputs["Surface"])
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = UV_NAME
    uv.location = (-900, 0)

    def tex(img, y):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        n.location = (-600, y)
        nt.links.new(uv.outputs["UV"], n.inputs["Vector"])
        return n

    alb = tex(imgs["albedo"], 300)
    nt.links.new(alb.outputs["Color"], b.inputs["Base Color"])
    orm = tex(imgs["orm"], 0)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-300, 0)
    nt.links.new(orm.outputs["Color"], sep.inputs[0])
    nt.links.new(sep.outputs[1], b.inputs["Roughness"])
    nt.links.new(sep.outputs[2], b.inputs["Metallic"])
    occ = nt.nodes.new("ShaderNodeGroup")
    occ.node_tree = _gltf_output_group()
    occ.location = (100, -500)
    nt.links.new(sep.outputs[0], occ.inputs["Occlusion"])
    nrm = tex(imgs["normal"], -300)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.uv_map = UV_NAME
    nm.location = (-300, -300)
    nt.links.new(nrm.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    if strength > 0.0:
        if "emission" in imgs:
            em = tex(imgs["emission"], -600)
            nt.links.new(em.outputs["Color"], b.inputs["Emission Color"])
        else:
            b.inputs["Emission Color"].default_value = emission_color_fallback
        b.inputs["Emission Strength"].default_value = strength
    mat["sb_baked"] = 1


# ----------------------------------------------------------------------------- entry point

def bake_scene(cfg=None, name="model"):
    """Bake every procedural material in the current scene into one texture atlas set.
    `name` prefixes the image names (e.g. "bosses/knight" -> "knight_albedo")."""
    cfg = {**DEFAULTS, **(cfg or {})}
    t0 = time.time()
    short = name.replace("\\", "/").split("/")[-1]
    sc = bpy.context.scene
    sc.frame_set(sc.frame_start)
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    mats = _bake_set(cfg)
    objs = [o for o in _mesh_objects() if _uses(o, mats)]
    if not mats or not objs:
        print(f"BAKE {short}: nothing procedural to bake")
        flatten_scene()
        return
    device = _setup_cycles(cfg)
    _realize(objs)
    _fold_transforms(objs)
    _unwrap(objs, mats, cfg)
    t_uv = time.time() - t0

    size = cfg["size"]
    glow = {m: _emission_strength(m) for m in mats}
    any_glow = any(_bsdf(m).inputs["Emission Color"].is_linked and s > 0 for m, s in glow.items())
    imgs = {
        "albedo": _image(f"{short}_albedo", size, False),
        "orm": _image(f"{short}_orm", size, True, (1, 1, 0, 1)),
        "normal": _image(f"{short}_normal", size, True, (0.5, 0.5, 1, 1)),
    }
    if any_glow:
        imgs["emission"] = _image(f"{short}_emission", size, False)
    dummy = _image("sb_bake_dummy", 8, True)

    all_mats = {s.material for o in objs for s in o.material_slots if s.material}
    states = []
    for m in all_mats:
        st = _MatState(m, m in mats, cfg)
        if m in mats:
            for k, img in imgs.items():
                st.target(k, img)
        st.target("dummy", dummy)
        states.append(st)

    times = {}
    for key in ("albedo", "orm") + (("emission",) if any_glow else ()):
        for st in states:
            st.emit_from(key)
        times[key] = _bake("EMIT", states, key, objs)
    for st in states:
        st.restore_surface()
    times["normal"] = _bake("NORMAL", states, "normal", objs, normal_space="TANGENT")

    # debug copies + pack into the .blend so the glTF exporter embeds them
    dbg = cfg["debug_dir"] or os.path.join(HERE, "previews", "bake")
    if os.name == "nt" and len(dbg) > 120 and not dbg.startswith(r"\\?" + "\\"):
        dbg = r"\\?" + "\\" + os.path.normpath(dbg)  # blender.exe is not long-path aware
    tmp = os.path.join(tempfile.gettempdir(), "sb_bake")
    for k, img in imgs.items():
        try:  # debug copy (written to a short temp path first: OIIO can't do >260-char paths)
            os.makedirs(tmp, exist_ok=True)
            os.makedirs(dbg, exist_ok=True)
            img.filepath_raw = os.path.join(tmp, f"{img.name}.png")
            img.file_format = "PNG"
            img.save()
            shutil.copyfile(img.filepath_raw, os.path.join(dbg, f"{img.name}.png"))
            if cfg["jpeg"] and k in ("albedo", "emission"):
                # colour maps embed as JPEG (~4x smaller); ORM / normal stay lossless PNG (chroma
                # subsampling would bleed the packed channels / bend normals).
                img.filepath_raw = os.path.join(tmp, f"{img.name}.jpg")
                img.file_format = "JPEG"
                bpy.context.scene.render.image_settings.quality = cfg["jpeg"]
                img.save(quality=cfg["jpeg"]) if _save_takes_quality() else img.save()
        except (RuntimeError, OSError) as e:
            print(f"BAKE: could not write debug copy of {img.name}: {e}")
        img.pack()

    for m in mats:
        b = _bsdf(m)
        fallback = tuple(b.inputs["Emission Color"].default_value)
        _rebuild(m, imgs if (glow[m] > 0 and b.inputs["Emission Color"].is_linked) else
                 {k: v for k, v in imgs.items() if k != "emission"}, glow[m], fallback)
    for st in states:
        if not st.baked:
            for n in list(st.targets.values()) + [st.emit]:
                st.nt.nodes.remove(n)
            st.restore_surface()
    bpy.data.images.remove(dummy)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    total = time.time() - t0
    print(f"BAKE {short}: {len(mats)} materials on {len(objs)} meshes, {size}px, {device}, "
          f"uv {t_uv:.1f}s, " + ", ".join(f"{k} {v:.1f}s" for k, v in times.items())
          + f", total {total:.1f}s")
