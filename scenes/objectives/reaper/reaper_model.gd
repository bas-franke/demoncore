class_name ReaperModel
extends EnemyModel
## "The Pale Reaper": Heaven's angel of death. A gaunt, hovering figure in a long ash-white shroud,
## hood empty but for two cold stars, four tattered grey wings, and a great scythe whose blade
## burns with pale light. ~2 units tall at size 1. Code-built (Art kit).
## The Reaper drives `swing` (0 = blade back, 1 = swung through) and `raise` (scythe lifted).

var swing := 0.0
var raise := 0.0

var _swing := 0.0
var _raise := 0.0
var _body: Node3D
var _arm: Node3D
var _blade_mat: StandardMaterial3D


func build() -> void:
	light_color = Color(0.85, 0.9, 1.0)
	feather_color = Color(0.7, 0.7, 0.72)
	feather_count = 10
	mote_count = 14
	var shroud := Art.mat(Color(0.78, 0.77, 0.74), 0.95, 0.0, 0.45, true, 0.3, &"cloth")
	var shadow := Art.mat(Color(0.015, 0.015, 0.02), 1.0, 0.0, 0.0)
	var iron := Art.mat(Art.OBSIDIAN.lightened(0.15), 0.5, 0.7, 0.4, true, 0.0, &"metal")
	var wood := Art.mat(Art.LEATHER.darkened(0.4), 0.9, 0.0, 0.4, true, 0.0, &"wood")
	_body = Art.pivot(self, Vector3(0.0, 0.25, 0.0))
	Art.part(_body, Art.cone(0.5), shroud, Vector3(0.0, 0.75, 0.0), Vector3(0.95, 1.6, 0.85))
	Art.part(_body, Art.sphere(), shroud, Vector3(0.0, 1.55, 0.02), Vector3(0.36, 0.42, 0.38))
	Art.part(_body, Art.sphere(), shadow, Vector3(0.0, 1.52, -0.1), Vector3(0.24, 0.3, 0.2))
	for sx: float in [-0.06, 0.06]:
		HolyFX.glow_part(_body, Art.sphere(), Color(0.75, 0.85, 1.0), 3.0, Vector3(sx, 1.55, -0.2), Vector3.ONE * 0.04)
	wing_pair(_body, Vector3(0.0, 1.35, 0.18), 1.1, 5, Art.mat(Color(0.55, 0.55, 0.57), 0.9, 0.0, 0.5, true, 0.2, &"feather"))
	wing_pair(_body, Vector3(0.0, 1.05, 0.2), 0.8, 4, Art.mat(Color(0.45, 0.45, 0.47), 0.9, 0.0, 0.5, true, 0.2, &"feather"))
	wing_speed = 2.0
	wing_amp = 0.2
	# Scythe in the right hand.
	_arm = Art.pivot(_body, Vector3(0.3, 1.3, 0.0))
	Art.part(_arm, Art.capsule(0.06, 0.5), shroud, Vector3(0.0, -0.22, 0.0))
	var haft := Art.pivot(_arm, Vector3(0.0, -0.45, -0.1))
	Art.part(haft, Art.cylinder(), wood, Vector3(0.0, 0.3, 0.0), Vector3(0.05, 2.0, 0.05))
	Art.part(haft, Art.box(), iron, Vector3(-0.35, 1.25, 0.0), Vector3(0.75, 0.08, 0.03), Vector3(0.0, 0.0, -0.25))
	var edge := HolyFX.glow_part(haft, Art.box(), Color(0.8, 0.9, 1.0), 1.6, Vector3(-0.38, 1.2, 0.0), Vector3(0.72, 0.02, 0.035))
	edge.rotation.z = -0.25
	_blade_mat = edge.material_override as StandardMaterial3D
	Art.light(_body, Color(0.75, 0.85, 1.0), 1.0, 5.0, Vector3(0.0, 1.6, -0.3))


func animate(delta: float, move_ratio: float, state: int) -> void:
	super.animate(delta, move_ratio, state)
	_swing = damp(_swing, swing, 10.0, delta)
	_raise = damp(_raise, raise, 6.0, delta)
	_body.position.y = 0.25 + sin(t * 1.3) * 0.08
	_body.rotation.x = move_ratio * 0.1
	# Raised: scythe hauled back over the shoulder; swing: carried across the body.
	_arm.rotation = Vector3(-_raise * 1.6 + _swing * 1.2, 0.0, 0.3 + _raise * 0.4 - _swing * 1.4)
	_blade_mat.albedo_color = HolyFX.scaled(Color(0.8, 0.9, 1.0), 1.6 + _raise * 2.0 + eye_flare)
