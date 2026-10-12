class_name InquisitorModel
extends EnemyModel
## "The Grand Inquisitor": a tall, hovering judge of Heaven in crimson robes under an ivory mozzetta,
## a towering gilded mitre, a hood of shadow with two burning eyes, a crown of iron thorns ringed
## with light behind its head, a great iron censer swinging from its right hand on a chain and a
## sealed book of sentences in its left. Built from the Art kit (code only), ~1.75 units tall;
## the boss scales it by EnemyData.size.
##
## InquisitorBoss drives the pose through the public fields (targets, eased here):
##   raise   censer lifted overhead (Censure, Bell)     book    book thrown open (Chains)
##   wide    arms flung wide (Pyre, phase changes)       kneel   death: sinks to its knees
##   burn    phase 2+: the robe's hem smoulders with holy fire; 3 = the whole figure blazes
##   dissolve  death: the figure burns away to light (one-way)

## Censer lifted, 0..1.
var raise := 0.0
## Book open (left arm forward), 0..1.
var book := 0.0
## Arms wide, 0..1.
var wide := 0.0
## Death kneel, 0..1.
var kneel := 0.0
## 0 = calm, 1 = hem burning (phase II), 2 = blazing (phase III).
var burn := 0.0
## Death: 0..1, burns away from the hem up.
var dissolve := 0.0

var _raise := 0.0
var _book := 0.0
var _wide := 0.0
var _kneel := 0.0
var _burn := 0.0
var _swing := 0.0

var _float: Node3D
var _body: Node3D
var _head: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _censer: Node3D
var _censer_glow: StandardMaterial3D
var _book_root: Node3D
var _cover_l: Node3D
var _cover_r: Node3D
var _pages_glow: StandardMaterial3D
var _thorns: Node3D
var _hem_glow: StandardMaterial3D
var _eye_glow: StandardMaterial3D
var _light: OmniLight3D
var _censer_light: OmniLight3D
var _parts: Array[Node3D] = []


func build() -> void:
	wrap_pose_pivot = true  # characters-polish: hit flinch + squash on EnemyModel.pose_pivot
	light_color = Art.HOLY
	feather_count = 0
	mote_count = 10
	var crimson := Art.mat(Art.CRIMSON.darkened(0.35), 0.85, 0.0, 0.3, true, 0.25, &"cloth")
	var ivory := Art.mat(Art.IVORY, 0.7, 0.0, 0.2, true, 0.3, &"cloth")
	var gold := Art.mat(Art.GOLD, 0.3, 1.0, 0.2, true, 0.0, &"gold")
	var iron := Art.mat(Art.OBSIDIAN.lightened(0.08), 0.5, 0.8, 0.4, true, 0.0, &"metal")
	var shadow := Art.mat(Color(0.02, 0.015, 0.015), 1.0, 0.0, 0.0)
	var leather := Art.mat(Art.LEATHER, 0.8, 0.0, 0.3, true, 0.0, &"leather")

	_float = Art.pivot(self)
	_body = Art.pivot(_float)
	# Robe: a long flared skirt, a narrower torso, an ivory scapular down the front.
	Art.part(_body, Art.cylinder(0.2, 0.56), crimson, Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.0, 0.85))
	Art.part(_body, Art.cylinder(0.2, 0.25), crimson, Vector3(0.0, 1.12, 0.0), Vector3(1.0, 0.3, 0.85))
	Art.part(_body, Art.box(), ivory, Vector3(0.0, 0.62, -0.33), Vector3(0.18, 1.0, 0.03), Vector3(-0.19, 0.0, 0.0))
	Art.part(_body, Art.box(), gold, Vector3(0.0, 0.62, -0.345), Vector3(0.05, 0.9, 0.02), Vector3(-0.19, 0.0, 0.0))
	Art.part(_body, Art.box(), gold, Vector3(0.0, 0.85, -0.3), Vector3(0.16, 0.04, 0.02), Vector3(-0.19, 0.0, 0.0))
	# Hem fire band (dark until phase II).
	var hem := HolyFX.glow_part(_body, Art.torus(0.86, 1.0), Art.HOLY, 0.0, Vector3(0.0, 0.03, 0.0), Vector3(0.57, 0.6, 0.49))
	_hem_glow = hem.material_override as StandardMaterial3D
	# A long cape behind, gilded pauldrons.
	Art.part(_body, Art.box(), crimson, Vector3(0.0, 0.66, 0.24), Vector3(0.64, 1.2, 0.04), Vector3(0.14, 0.0, 0.0))
	for sx: float in [-1.0, 1.0]:
		Art.part(_body, Art.sphere(), gold, Vector3(sx * 0.29, 1.2, 0.0), Vector3(0.17, 0.12, 0.17))
	# Mozzetta (short shoulder cape) with a gold trim.
	Art.part(_body, Art.cylinder(0.14, 0.34), ivory, Vector3(0.0, 1.22, 0.0), Vector3(1.0, 0.24, 0.9))
	Art.part(_body, Art.torus(0.9, 1.0), gold, Vector3(0.0, 1.1, 0.0), Vector3(0.34, 0.5, 0.31))
	# Head: hood of shadow, burning eyes, the mitre.
	_head = Art.pivot(_body, Vector3(0.0, 1.38, 0.0))
	Art.part(_head, Art.sphere(), crimson, Vector3(0.0, 0.0, 0.02), Vector3(0.26, 0.3, 0.27))
	Art.part(_head, Art.sphere(), shadow, Vector3(0.0, -0.02, -0.08), Vector3(0.17, 0.2, 0.14))
	var eyes := HolyFX.glow_part(_head, Art.box(), Art.HOLY_WHITE, 3.0, Vector3(0.0, 0.0, -0.15), Vector3(0.11, 0.018, 0.01))
	_eye_glow = eyes.material_override as StandardMaterial3D
	Art.part(_head, Art.box(), ivory, Vector3(0.0, 0.17, 0.0), Vector3(0.2, 0.1, 0.18))
	Art.part(_head, Art.prism(), ivory, Vector3(0.0, 0.44, 0.0), Vector3(0.25, 0.46, 0.18))
	Art.part(_head, Art.box(), gold, Vector3(0.0, 0.17, 0.0), Vector3(0.21, 0.025, 0.19))
	var gilt := Art.emissive(Art.GOLD, Art.HOLY, 1.2, 0.3)
	Art.part(_head, Art.box(), gilt, Vector3(0.0, 0.38, -0.092), Vector3(0.03, 0.26, 0.01))
	Art.part(_head, Art.box(), gilt, Vector3(0.0, 0.43, -0.092), Vector3(0.12, 0.03, 0.01))
	# Crown of thorns behind the head, ringed with light.
	_thorns = Art.pivot(_head, Vector3(0.0, 0.12, 0.2), Vector3(PI * 0.5, 0.0, 0.0))
	Art.part(_thorns, Art.torus(0.85, 1.0), iron, Vector3.ZERO, Vector3.ONE * 0.36)
	for i in 12:
		var a := TAU * float(i) / 12.0
		var out := Vector3(cos(a), 0.0, sin(a))
		var thorn := Art.part(_thorns, Art.cone(0.5), iron, out * 0.38)
		# Cones point +Y: tip the thorn 90 degrees so it points radially outward.
		thorn.basis = Basis(Vector3.UP.cross(out).normalized(), PI * 0.5) * Basis.from_scale(Vector3(0.035, 0.16, 0.035))
	halo(_head, Vector3(0.0, 0.1, 0.22), 0.33, 1.7, true, false, Art.HOLY)
	# Right arm: the censer on its chain.
	_arm_r = Art.pivot(_body, Vector3(0.3, 1.2, 0.0))
	Art.part(_arm_r, Art.capsule(0.07, 0.55), crimson, Vector3(0.0, -0.24, 0.0))
	Art.part(_arm_r, Art.sphere(), ivory, Vector3(0.0, -0.52, 0.0), Vector3(0.11, 0.08, 0.11))
	var chain := Art.pivot(_arm_r, Vector3(0.0, -0.55, 0.0))
	Art.part(chain, Art.box(), gold, Vector3(0.0, -0.22, 0.0), Vector3(0.015, 0.44, 0.015))
	_censer = Art.pivot(chain, Vector3(0.0, -0.46, 0.0))
	Art.part(_censer, Art.sphere(), iron, Vector3(0.0, -0.08, 0.0), Vector3(0.2, 0.17, 0.2))
	Art.part(_censer, Art.cone(0.5), gold, Vector3(0.0, 0.04, 0.0), Vector3(0.2, 0.14, 0.2))
	var ember := HolyFX.glow_part(_censer, Art.sphere(), Art.HOLY, 2.0, Vector3(0.0, -0.06, 0.0), Vector3.ONE * 0.13)
	_censer_glow = ember.material_override as StandardMaterial3D
	_censer_light = Art.light(_censer, Art.HOLY, 1.0, 3.5)
	_censer.set_meta(&"chain", chain)
	# Left arm: the book of sentences.
	_arm_l = Art.pivot(_body, Vector3(-0.3, 1.2, 0.0))
	Art.part(_arm_l, Art.capsule(0.07, 0.55), crimson, Vector3(0.0, -0.24, 0.0))
	_book_root = Art.pivot(_arm_l, Vector3(0.0, -0.5, -0.1))
	_cover_l = Art.pivot(_book_root, Vector3(0.0, 0.0, 0.0))
	_cover_r = Art.pivot(_book_root, Vector3(0.0, 0.0, 0.0))
	Art.part(_cover_l, Art.box(), leather, Vector3(-0.08, 0.0, 0.0), Vector3(0.16, 0.22, 0.03))
	Art.part(_cover_r, Art.box(), leather, Vector3(0.08, 0.0, 0.0), Vector3(0.16, 0.22, 0.03))
	Art.part(_cover_r, Art.box(), gold, Vector3(0.08, 0.0, -0.017), Vector3(0.04, 0.12, 0.01))
	var pages := HolyFX.glow_part(_book_root, Art.box(), Art.HOLY_WHITE, 0.0, Vector3(0.0, 0.0, -0.01), Vector3(0.3, 0.2, 0.01))
	_pages_glow = pages.material_override as StandardMaterial3D
	_light = Art.light(_body, Art.HOLY, 1.2, 6.0, Vector3(0.0, 1.5, 0.0))
	_parts = [_body]


func animate(delta: float, move_ratio: float, state: int) -> void:
	super.animate(delta, move_ratio, state)
	_raise = damp(_raise, raise, 6.0, delta)
	_book = damp(_book, book, 7.0, delta)
	_wide = damp(_wide, wide, 5.0, delta)
	_kneel = damp(_kneel, kneel, 3.0, delta)
	_burn = damp(_burn, burn, 2.0, delta)
	# Hovers, bobbing; sinks to the ground as it kneels.
	_float.position.y = (0.14 + sin(t * 1.4) * 0.04) * (1.0 - _kneel)
	_body.rotation.x = move_ratio * 0.12 - _kneel * 0.25
	_body.position.y = -_kneel * 0.35
	_head.rotation.x = -_raise * 0.25 + _kneel * 0.4
	# Censer swings like a pendulum (faster when angry), and is hauled overhead for Censure.
	_swing += delta * (2.2 + _burn * 1.2)
	var arm_down := sin(_swing) * 0.5 * (1.0 - _raise)
	_arm_r.rotation = Vector3(arm_down - _raise * 2.6, 0.0, 0.25 + _wide * 1.1 + _raise * 0.2)
	var chain := _censer.get_meta(&"chain") as Node3D
	chain.rotation.x = sin(_swing - 0.6) * 0.6 * (1.0 - _raise) + _raise * 2.8
	# Book arm comes forward as the book opens.
	_arm_l.rotation = Vector3(-_book * 1.25, 0.0, -0.25 - _wide * 1.1)
	_cover_l.rotation.y = -_book * 1.3
	_cover_r.rotation.y = _book * 1.3
	_pages_glow.albedo_color = HolyFX.scaled(Art.HOLY_WHITE, 2.8 * _book)
	# Light and fire.
	var flare := 1.0 + eye_flare
	_eye_glow.albedo_color = HolyFX.scaled(Art.HOLY_WHITE.lerp(Art.HOLY, minf(_burn, 1.0) * 0.5), 3.0 * flare * (1.0 - dissolve))
	var flick := 0.8 + 0.2 * sin(t * 13.0) * sin(t * 7.1)
	_hem_glow.albedo_color = HolyFX.scaled(Art.HOLY, clampf(_burn, 0.0, 1.0) * 2.2 * flick + dissolve * 3.0)
	_censer_glow.albedo_color = HolyFX.scaled(Art.HOLY, (1.6 + _burn) * flick)
	_censer_light.light_energy = (0.8 + _burn * 0.8) * flick
	_light.light_energy = (1.0 + _burn * 0.9 + _raise * 0.8) * (1.0 - dissolve)
	_thorns.rotation.z += delta * (0.3 + _burn * 0.6)
	set_halo_scale(0, 1.0 + _burn * 0.25 + _raise * 0.2)
	if dissolve > 0.0:
		_body.scale = Vector3.ONE * maxf(1.0 - dissolve * 0.9, 0.05)


## World position of the censer (attack origin).
func censer_global() -> Vector3:
	return _censer.global_position


## World position of the open book.
func book_global() -> Vector3:
	return _book_root.global_position
