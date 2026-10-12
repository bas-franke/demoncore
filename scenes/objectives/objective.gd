class_name Objective
extends Node3D
## Base class for one in-map objective (a shrine to desecrate, a saint to hunt, ...). The
## ObjectiveDirector creates it from a JSON definition (data/objectives/objectives.json), places it
## in the world and grants its rewards when it completes.
##
## Life cycle: DORMANT (placed, beacon lit, waiting for the demon) -> ACTIVE (the player engaged it)
## -> COMPLETED or FAILED. A DORMANT objective that is ignored for `dormant_life` seconds fades
## away (EXPIRED) so the map keeps refreshing. Subclasses override:
##   _build()          build the visuals (called once from _ready)
##   _tick(delta)      per-frame logic in any state but the final ones
##   _on_activated()   the demon engaged it
##   _on_finished(ok)  completed (ok) / failed / expired (cleanup, final FX)
## and call activate(), complete() or fail(). They report progress (0..1) and a short status
## line ("3 / 4 souls", "0:24") for the tracker through `progress` and `status_text`.

signal state_changed(objective: Objective)

enum State { DORMANT, ACTIVE, COMPLETED, FAILED, EXPIRED }

## Seconds the beacon takes to fade after the objective ends, before the node frees itself.
const LINGER := 3.0
## Height of the beacon light column.
const BEACON_HEIGHT := 22.0

## The JSON definition (id, type, title, description, glyph, color, params, rewards, ...).
var def: Dictionary = {}
var id: StringName = &""
var title := "Objective"
var description := ""
var glyph := "◆"
var color := Color("ffd77a")
var state := State.DORMANT
## 0..1, shown by the tracker.
var progress := 0.0
## Short detail line for the tracker ("2 / 4", "0:31", "Hold the circle").
var status_text := ""
## Seconds before an untouched DORMANT objective expires (< 0 = never).
var dormant_life := -1.0
## Seconds since this objective was placed / activated.
var age := 0.0
var active_time := 0.0

var _beacon: MeshInstance3D
var _beacon_mat: StandardMaterial3D
var _beacon_light: OmniLight3D
var _linger_t := 0.0
var _minimap_node: Node3D


## Call before adding to the tree.
func setup(definition: Dictionary) -> void:
	def = definition
	id = StringName(str(def.get("id", "objective")))
	title = str(def.get("title", title))
	description = str(def.get("description", ""))
	glyph = str(def.get("glyph", glyph))
	color = Color(str(def.get("color", color.to_html(false))))


func _ready() -> void:
	add_to_group(&"objectives")
	_minimap_follow(self)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_beacon = ObjectiveFX.beacon(self, color, BEACON_HEIGHT)
	_beacon_mat = _beacon.material_override as StandardMaterial3D
	_beacon_light = Art.light(self, color, 1.2, 6.0, Vector3(0.0, 1.2, 0.0))
	if bool(def.get("event", false)):
		# Run events happen around the demon: no beacon, no fixed minimap pin.
		_beacon.visible = false
		_beacon_light.visible = false
		remove_from_group(&"minimap_marker")
	_build()


func _process(delta: float) -> void:
	age += delta
	if is_finished():
		_linger_t += delta
		var k := clampf(1.0 - _linger_t / LINGER, 0.0, 1.0)
		_set_beacon(k * 0.6)
		_tick_finished(delta)
		if _linger_t >= LINGER:
			queue_free()
		return
	if state == State.ACTIVE:
		active_time += delta
	elif dormant_life > 0.0 and age >= dormant_life:
		_finish(State.EXPIRED)
		return
	# The beacon breathes while dormant and dims once engaged (the zone itself takes over).
	var pulse := 0.75 + 0.25 * sin(age * 2.2)
	_set_beacon(pulse if state == State.DORMANT else 0.35)
	_tick(delta)


# ---------------------------------------------------------------- public

func is_finished() -> bool:
	return state == State.COMPLETED or state == State.FAILED or state == State.EXPIRED


func is_active() -> bool:
	return state == State.ACTIVE


## Where markers point (moving objectives such as the saint override this).
func marker_position() -> Vector3:
	return global_position


## A `params` entry from the definition, with a default.
func param(key: String, default: Variant) -> Variant:
	var p: Dictionary = def.get("params", {})
	return p.get(key, default)


## Seconds left before a dormant objective expires (-1 = no limit / not dormant).
func time_to_expire() -> float:
	if state != State.DORMANT or dormant_life <= 0.0:
		return -1.0
	return maxf(dormant_life - age, 0.0)


func activate() -> void:
	if state != State.DORMANT:
		return
	state = State.ACTIVE
	active_time = 0.0
	_on_activated()
	_spawn_variant_guardian()
	state_changed.emit(self)


func complete() -> void:
	_finish(State.COMPLETED)


func fail() -> void:
	_finish(State.FAILED)


## Lets an untouched objective fade away (the director calls it when the demon left it far behind).
func expire() -> void:
	if state == State.DORMANT:
		_finish(State.EXPIRED)


# ---------------------------------------------------------------- overridables

func _build() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


## Runs while the beacon fades out after the end (e.g. a burning shrine).
func _tick_finished(_delta: float) -> void:
	pass


func _on_activated() -> void:
	pass


func _on_finished(_completed: bool) -> void:
	pass


# ---------------------------------------------------------------- helpers

func _finish(final_state: State) -> void:
	if is_finished():
		return
	state = final_state
	if final_state == State.COMPLETED:
		progress = 1.0
	_linger_t = 0.0
	if is_instance_valid(_minimap_node):
		_minimap_node.remove_from_group(&"minimap_marker")
	_on_finished(final_state == State.COMPLETED)
	state_changed.emit(self)


func _set_beacon(k: float) -> void:
	if _beacon_mat:
		_beacon_mat.albedo_color = HolyFX.scaled(color, 0.9 * k)
	if _beacon_light:
		_beacon_light.light_energy = 1.4 * k


## Variants with "guardian": <enemy id> send a crowned elite (x`guardian_hp` HP) when engaged.
func _spawn_variant_guardian() -> void:
	var v: Dictionary = def.get("variant", {})
	var gid := str(v.get("guardian", ""))
	if gid == "":
		return
	var e := _spawn_enemy(gid, ObjectiveFX.ring_point(global_position, 4.0), float(v.get("guardian_hp", 5.0)))
	if e:
		e.add_to_group(&"champions")
		var crown := Art.pivot(e, Vector3(0.0, e.data.size * 1.55 + e.data.hover, 0.0))
		HolyFX.glow_part(crown, Art.torus(0.82, 1.0), Art.GOLD, 2.4, Vector3.ZERO, Vector3.ONE * 0.4 * e.data.size)
		_toast("A guardian answers", Color("f2c66b"))


## Shows this objective on the HUD minimap (ui/components/minimap.gd) at `node`'s position:
## the objective itself, or the moving target it spawned (a champion, a saint).
func _minimap_follow(node: Node3D) -> void:
	if is_instance_valid(_minimap_node):
		_minimap_node.remove_from_group(&"minimap_marker")
	_minimap_node = node
	node.set_meta(&"minimap_color", color)
	node.set_meta(&"minimap_size", 6.0)
	node.set_meta(&"minimap_pin", true)
	node.set_meta(&"minimap_label", glyph)
	node.add_to_group(&"minimap_marker")


## Horizontal distance to the demon (INF without one).
func _player_distance(from: Vector3 = Vector3.INF) -> float:
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.is_dead:
		return INF
	var o := global_position if from == Vector3.INF else from
	var d := p.global_position - o
	d.y = 0.0
	return d.length()


func _toast(text: String, tint: Color = Color.TRANSPARENT) -> void:
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"toast"):
		hud.call(&"toast", text, color if tint == Color.TRANSPARENT else tint)


## Spawns an angel by enemy id (data/enemies/<id>.tres) at `at`, scaled like the regular waves.
## Returns null if the id is unknown.
func _spawn_enemy(enemy_id: String, at: Vector3, hp_scale_mult: float = 1.0) -> Enemy:
	return ObjectiveFX.spawn_enemy(enemy_id, at, hp_scale_mult)


static func fmt_time(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	@warning_ignore("integer_division")  # whole minutes
	return "%d:%02d" % [s / 60, s % 60]
