class_name CelestialWhale
extends Node3D
## "The Celestial Leviathan" (map event, characters-new): a whale of light the size of a chapel
## drifts slowly across the sky over the demon, singing. It cannot be fought. As it passes it
## sheds falling stars - telegraphed Judgement Pillars along its path, biased toward the demon -
## and its shadow of light sweeps the ground. Spawned by RosterDirector on open-sky maps, or by
## anyone: CelestialWhale.spawn_pass(); signal `passed` when it leaves.

signal passed

## High enough to read as "overhead" from the run camera without filling the screen.
const HEIGHT := 4.5
const LENGTH := 13.0
const SPEED := 1.6
## Distance from the demon at which the pass starts and ends.
const REACH := 26.0
const DROP_EVERY := 1.1
const DROP_DAMAGE := 16.0
const LIGHT := Color(0.75, 0.88, 1.0)

var _dir := Vector3.RIGHT
var _travelled := 0.0
var _total := REACH * 2.0
var _drop_t := 2.0
var _body: Node3D
var _tail: Node3D
var _fins: Array[Node3D] = []
var _t := 0.0


## Starts a pass across the demon at a random heading. Returns the whale (null without a run).
static func spawn_pass() -> CelestialWhale:
	if Game.world == null or Game.player == null:
		return null
	var w := CelestialWhale.new()
	var a := randf() * TAU
	w._dir = Vector3(cos(a), 0.0, sin(a))
	var p := Game.player.global_position
	# Offset sideways a little so it doesn't pass exactly overhead every time.
	var side := Vector3(-w._dir.z, 0.0, w._dir.x) * randf_range(-5.0, 5.0)
	Game.spawn(w, p - w._dir * REACH + side + Vector3(0.0, HEIGHT, 0.0))
	return w


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	basis = Basis.looking_at(_dir, Vector3.UP)
	_build()
	Sfx.play(&"choir", 0.0, -3.0)
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"toast"):
		hud.call(&"toast", "The Celestial Leviathan passes overhead", Color("cfe3ff"))


func _build() -> void:
	# Faint, translucent light: overlapping additive parts add up quickly.
	var skin := Art.glow(LIGHT, 0.3, true, 0.55)
	var core := Art.glow(Art.HOLY_WHITE, 0.3, true, 0.5)
	var gold := Art.glow(Art.GOLD, 1.6)
	_body = Art.pivot(self)
	# Long tapering body (forward = -Z), pale belly grooves of gold, a ring of eyes along the flank.
	Art.part(_body, Art.sphere(), skin, Vector3(0.0, 0.0, -1.0), Vector3(3.6, 3.0, LENGTH * 0.62))
	Art.part(_body, Art.sphere(), core, Vector3(0.0, -0.3, -1.0), Vector3(2.4, 1.8, LENGTH * 0.5))
	for k in 6:
		Art.part(_body, Art.box(), gold, Vector3(-0.9 + k * 0.36, -1.35, -1.5), Vector3(0.06, 0.04, LENGTH * 0.35))
	for s: float in [-1.0, 1.0]:
		for k in 5:
			Art.part(_body, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.4), Vector3(s * 1.7, 0.3, -4.0 + k * 1.3), Vector3(0.28, 0.2, 0.2))
		# Pectoral fins (flap slowly).
		var f := Art.pivot(_body, Vector3(s * 1.5, -0.6, -2.5))
		Art.part(f, Art.sphere(), skin, Vector3(s * 1.6, 0.0, 0.6), Vector3(3.4, 0.2, 1.6), Vector3(0.0, s * 0.4, 0.0))
		_fins.append(f)
	_tail = Art.pivot(_body, Vector3(0.0, 0.0, LENGTH * 0.3))
	Art.part(_tail, Art.sphere(), skin, Vector3(0.0, 0.0, 1.6), Vector3(1.4, 1.2, 3.6))
	Art.part(_tail, Art.sphere(), skin, Vector3(0.0, 0.0, 3.6), Vector3(5.0, 0.25, 1.4))
	# A halo ring above the head.
	Art.part(_body, Art.torus(0.9, 1.0), gold, Vector3(0.0, 2.2, -4.5), Vector3.ONE * 1.3)
	Art.light(_body, LIGHT, 2.0, 18.0, Vector3(0.0, -2.0, -1.0))
	Art.no_shadows(self)


func _physics_process(delta: float) -> void:
	_t += delta
	var step := SPEED * delta
	global_position += _dir * step
	_travelled += step
	# Drift sideways toward the demon so the pass stays over the fight (it keeps its heading).
	var p := Game.player
	if p:
		var side := Vector3(-_dir.z, 0.0, _dir.x)
		var off := (p.global_position - global_position).dot(side)
		global_position += side * clampf(off * 0.6, -4.0, 4.0) * delta
		# Keep the pass centred on the demon along the heading too (it can run away).
		var ahead := (p.global_position - global_position).dot(_dir)
		_travelled = REACH - ahead
	_body.position.y = sin(_t * 0.5) * 0.4
	_body.rotation.z = sin(_t * 0.3) * 0.05
	_tail.rotation.x = sin(_t * 0.8) * 0.25
	for i in _fins.size():
		_fins[i].rotation.z = (1.0 if i == 0 else -1.0) * sin(_t * 0.9) * 0.25
	_drop_t -= delta
	if _drop_t <= 0.0 and _travelled > 6.0 and _travelled < _total - 6.0:
		_drop_t = DROP_EVERY
		_drop_star()
	if _travelled >= _total:
		passed.emit()
		queue_free()


## A falling star: a pillar under the whale, pulled toward the demon when it is near the path.
func _drop_star() -> void:
	var below := Vector3(global_position.x, 0.0, global_position.z)
	var at := below + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
	var p := Game.player
	if p and not p.is_dead:
		var pp := Vector3(p.global_position.x, 0.0, p.global_position.z)
		if pp.distance_to(below) < 12.0:
			at = at.lerp(pp, 0.6)
	HolyFX.hazard_tint = LIGHT
	JudgementPillar.cast(at, 1.6, 1.3, DROP_DAMAGE)
	HolyFX.hazard_tint = Art.HOLY
