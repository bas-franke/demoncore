class_name Toon
## LEGACY primitive-model toolkit (pre-SINBOUND). New code should use Art (res://scripts/art.gd).
## The API is kept so older models keep working during the transition, but the look is no longer
## cel-shaded: Toon.material() now returns an Art.mat() (lit pipeline, muted colors)
## and no ink outlines are attached (the `outline` arguments are accepted and ignored).
##
##   var head := Toon.part(root, Toon.sphere(), Color.ORANGE, Vector3(0, 1, 0), Vector3(0.8, 0.7, 0.7))
##   Toon.flash(model_root, 1.0)   # white hit-flash on every mesh under model_root
##   Toon.make_static(prop_root)   # decor: swap to the no-flash variant (saves instance uniforms)

const TOON_SHADER := preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")
## Decor variants: no `flash` instance uniform, dithered see-through when in front of the player.
const TOON_STATIC_SHADER := preload("res://shaders/toon_static.gdshader")
const OUTLINE_STATIC_SHADER := preload("res://shaders/outline_static.gdshader")

## Ink color used for outlines, pupils, whiskers and other line-work.
const INK := Color(0.17, 0.11, 0.2)
## Default outline thickness in world units (before any parent scaling).
const OUTLINE := 0.045

# Friendly pastel palette shared by models, props and UI.
const CREAM := Color(1.0, 0.96, 0.88)
const PINK := Color(1.0, 0.62, 0.72)
const BLUSH := Color(1.0, 0.55, 0.62)
const MINT := Color(0.6, 0.92, 0.75)
const SKY := Color(0.62, 0.82, 1.0)
const LEMON := Color(1.0, 0.9, 0.45)
const LAVENDER := Color(0.78, 0.68, 1.0)
const PEACH := Color(1.0, 0.75, 0.55)

static var _outlines := {}
static var _meshes := {}
static var _statics := {}  # flashable ShaderMaterial -> static variant
static var _static_outlines := {}
## Every static-variant material (toon + outline), for set_fade_focus().
static var _fade_materials: Array[ShaderMaterial] = []


## Cached toon material. `outline_width` is object-space (0 = no outline).
## `flashable = false` returns the static decor variant (no `flash` instance uniform).
static func material(color: Color, _outline_width: float = OUTLINE, gloss: float = 0.0,
		flashable: bool = true) -> ShaderMaterial:
	# Art-style round 2: legacy Toon content renders with the Art lit pipeline (Art.mat), so it
	# gets hit flash, dissolve, faction rim, outlines and (static variant) the corruption blight.
	# The pastel input colors are muted the way toon_common.gdshaderinc used to (desaturate 0.45,
	# darken 0.3). outline_width is accepted and ignored.
	var l := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	var muted := Color(lerpf(color.r, l, 0.45), lerpf(color.g, l, 0.45), lerpf(color.b, l, 0.45)) * 0.7
	muted.a = 1.0
	return Art.mat(muted, lerpf(0.8, 0.35, clampf(gloss, 0.0, 1.0)), 0.0, 0.35, flashable)


static func _outline(width: float) -> ShaderMaterial:
	if not _outlines.has(width):
		var o := ShaderMaterial.new()
		o.shader = OUTLINE_SHADER
		o.set_shader_parameter(&"width", width)
		_outlines[width] = o
	return _outlines[width]


## Static (non-flashing) twin of a Toon material, cached. Non-toon materials pass through.
static func static_variant(m: Material) -> Material:
	if m is ShaderMaterial and (m as ShaderMaterial).shader == Art.LIT:
		# Art lit -> its lit_static twin (no instance uniforms, occluder fade, blight).
		if not _statics.has(m):
			var d := (m as ShaderMaterial).duplicate() as ShaderMaterial
			d.shader = Art.LIT_STATIC
			_statics[m] = d
			_fade_materials.append(d)  # set_fade_focus() drives its occluder fade
		return _statics[m]
	if not m is ShaderMaterial or (m as ShaderMaterial).shader != TOON_SHADER:
		return m
	if _statics.has(m):
		return _statics[m]
	var src := m as ShaderMaterial
	var s := ShaderMaterial.new()
	s.shader = TOON_STATIC_SHADER
	s.set_shader_parameter(&"albedo", src.get_shader_parameter(&"albedo"))
	s.set_shader_parameter(&"gloss", src.get_shader_parameter(&"gloss"))
	if src.next_pass is ShaderMaterial:
		var width: float = (src.next_pass as ShaderMaterial).get_shader_parameter(&"width")
		if not _static_outlines.has(width):
			var o := ShaderMaterial.new()
			o.shader = OUTLINE_STATIC_SHADER
			o.set_shader_parameter(&"width", width)
			_static_outlines[width] = o
			_fade_materials.append(o)
		s.next_pass = _static_outlines[width]
	_statics[m] = s
	_fade_materials.append(s)
	return s


## Swaps every Toon material under `root` to its static variant (use for decor that never
## hit-flashes, so it doesn't use instance-uniform slots). Returns the number of meshes.
static func make_static(root: Node) -> int:
	var n := 0
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.material_override:
			mi.material_override = static_variant(mi.material_override)
		n += 1
	for c in root.get_children():
		n += make_static(c)
	return n


## World position the static decor turns see-through around (when between it and the camera).
static func set_fade_focus(world_pos: Vector3) -> void:
	for m in _fade_materials:
		m.set_shader_parameter(&"fade_focus", world_pos)


## Adds a toon-shaded MeshInstance3D to `parent`. `outline` is the world-space outline width
## (relative to `parent`); it is divided by the part's average scale so outlines stay even.
static func part(parent: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO, scl := Vector3.ONE,
		outline: float = OUTLINE, gloss: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var avg := maxf((absf(scl.x) + absf(scl.y) + absf(scl.z)) / 3.0, 0.001)
	mi.material_override = material(color, outline / avg if outline > 0.0 else 0.0, gloss)
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


## Empty pivot node, handy for animated joints (legs, tails, heads).
static func pivot(parent: Node3D, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## Sets the white hit-flash (0..1) on every GeometryInstance3D under `root`.
static func flash(root: Node, amount: float) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).set_instance_shader_parameter(&"flash", amount)
	for c in root.get_children():
		flash(c, amount)


## Turns shadow casting off for every mesh under `root` (cheap decor, tiny parts).
static func no_shadows(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in root.get_children():
		no_shadows(c)


# ---------------------------------------------------------------- shared unit meshes
# All meshes are ~1 unit in size; shape them with the part's scale.

## Diameter-1 sphere.
static func sphere() -> SphereMesh:
	return _cached(&"sphere", func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = 24
		m.rings = 12
		return m)


## Capsule of radius `r` and total height `h` (cached per size; avoid non-uniform scaling).
static func capsule(r: float = 0.25, h: float = 1.0) -> CapsuleMesh:
	return _cached(StringName("capsule_%.3f_%.3f" % [r, h]), func() -> Mesh:
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 20
		m.rings = 6
		return m)


## 1x1x1 box.
static func box() -> BoxMesh:
	return _cached(&"box", func() -> Mesh: return BoxMesh.new())


## Height-1 cylinder; radii are top/bottom (0.5 = unit diameter).
static func cylinder(top: float = 0.5, bottom: float = 0.5) -> CylinderMesh:
	return _cached(StringName("cyl_%.3f_%.3f" % [top, bottom]), func() -> Mesh:
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = 1.0
		m.radial_segments = 20
		m.rings = 1
		return m)


## 1x1x1 triangular prism (point up, triangle in the XY plane).
static func prism() -> PrismMesh:
	return _cached(&"prism", func() -> Mesh: return PrismMesh.new())


## Torus lying in the XZ plane.
static func torus(inner: float = 0.35, outer: float = 0.5) -> TorusMesh:
	return _cached(StringName("torus_%.3f_%.3f" % [inner, outer]), func() -> Mesh:
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 24
		m.ring_segments = 10
		return m)


static func _cached(key: StringName, make: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = make.call()
	return _meshes[key]
