class_name Dissolve
extends RefCounted
## Burn-into-light dissolve for models using the flashable lit shader (res://shaders/lit.gdshader:
## `dissolve` / `dissolve_color` instance uniforms in lit_common.gdshaderinc). Noise eats the
## surface away behind a glowing edge of `color`. Meshes with other materials (unshaded glows,
## halos, StandardMaterial3D) fade out through GeometryInstance3D.transparency instead.
##
##   Dissolve.play(corpse, 0.9, Art.HOLY, true)   # burn away over 0.9 s, then free `corpse`
##   Dissolve.set_amount(model, 0.0)               # restore instantly
##
## Per-instance, so it never touches shared (cached) materials. Use it on short-lived copies or
## on models that are about to be freed.

static var _support := {}


## Tweens the dissolve 0 -> 1 on every GeometryInstance3D under `root` over `duration` seconds.
## `free_when_done` queue_frees `root` at the end. Returns the tween (bound to `root`).
static func play(root: Node3D, duration: float = 0.8, color: Color = Art.HOLY,
		free_when_done: bool = false) -> Tween:
	if root == null or not root.is_inside_tree():
		return null
	var lit: Array[GeometryInstance3D] = []
	var other: Array[GeometryInstance3D] = []
	_collect(root, lit, other)
	for g in lit:
		g.set_instance_shader_parameter(&"dissolve_color", color)
	var tw := root.create_tween()
	tw.tween_method(func(v: float) -> void: _apply(v, lit, other), 0.0, 1.0, maxf(duration, 0.01)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if free_when_done:
		tw.tween_callback(root.queue_free)
	return tw


## Sets the dissolve amount (0 = solid, 1 = gone) on everything under `root` immediately.
static func set_amount(root: Node, amount: float, color: Color = Art.HOLY) -> void:
	var lit: Array[GeometryInstance3D] = []
	var other: Array[GeometryInstance3D] = []
	_collect(root, lit, other)
	for g in lit:
		g.set_instance_shader_parameter(&"dissolve_color", color)
	_apply(amount, lit, other)


## True if `g` renders with a material that has the dissolve instance uniform.
static func supports(g: GeometryInstance3D) -> bool:
	if _is_lit(g.material_override):
		return true
	var mi := g as MeshInstance3D
	if mi and mi.mesh:
		for i in mi.mesh.get_surface_count():
			if _is_lit(mi.get_surface_override_material(i)) or _is_lit(mi.mesh.surface_get_material(i)):
				return true
	return false


static func _apply(v: float, lit: Array[GeometryInstance3D], other: Array[GeometryInstance3D]) -> void:
	for g in lit:
		if is_instance_valid(g):
			g.set_instance_shader_parameter(&"dissolve", v)
	# Glows vanish a little ahead of the body so nothing floats once the surface has burned away.
	var t := clampf(v * 1.5, 0.0, 1.0)
	for g in other:
		if is_instance_valid(g):
			g.transparency = t


static func _collect(n: Node, lit: Array[GeometryInstance3D], other: Array[GeometryInstance3D]) -> void:
	if n is GeometryInstance3D and not n is GPUParticles3D and not n is CPUParticles3D:
		var g := n as GeometryInstance3D
		if supports(g):
			lit.append(g)
		else:
			other.append(g)
	for c in n.get_children():
		_collect(c, lit, other)


static func _is_lit(m: Material) -> bool:
	var sm := m as ShaderMaterial
	if sm == null or sm.shader == null:
		return false
	var s := sm.shader
	if s == Art.LIT:
		return true
	var key := s.get_instance_id()
	if not _support.has(key):
		var code := s.code
		_support[key] = code.contains("instance uniform float dissolve") or (code.contains("FLASHABLE") and code.contains("lit_common"))
	return _support[key]
