class_name BloodChalice
extends Pickup
## Healing pickup: a dark gold chalice brimming with glowing blood. Heals HEAL HP. Sits still
## until the player's PickupArea touches it, then flies to the player.
## Use BloodChalice.try_drop(world_position, chance).

const HEAL := 25.0
const SCENE_PATH := "res://scenes/pickups/blood_chalice.tscn"
const MODEL := "res://assets/models/pickups/blood_chalice.glb"

static var _blood_mat: StandardMaterial3D

var _t := 0.0
var _pop := 0.0
var _model: Node3D
var _surface: Node3D
var _motes: Array[Node3D] = []
var _light: OmniLight3D


## Spawns a chalice at ground level below `at` with probability `chance` (0..1).
## Safe to call from physics callbacks (spawn is deferred).
static func try_drop(at: Vector3, chance: float) -> void:
	if randf() >= chance:
		return
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		return
	var cup := scene.instantiate() as Node3D
	if cup == null:
		return
	Game.spawn.call_deferred(cup, Vector3(at.x, 0.0, at.z))


func _ready() -> void:
	homing_accel = 40.0
	_t = randf() * TAU
	_build()
	_animate(0.0)


func _physics_process(delta: float) -> void:
	_t += delta
	_animate(delta)
	_home(delta)


func _collect(player: Player) -> void:
	Sfx.play(&"chalice", 0.04)
	player.heal(HEAL)
	HolyFX.motes(player.global_position + Vector3(0.0, 0.7, 0.0), 10, Art.SOUL, 0.6, 1.2, 0.8, 0.05)


func _animate(delta: float) -> void:
	if _pop < 1.0:
		_pop = minf(_pop + delta * 3.0, 1.0)
	var p := maxf(_ease_out_back(_pop), 0.01)
	_model.scale = Vector3.ONE * p
	_model.position.y = 0.04 + sin(_t * 1.8) * 0.03
	_model.rotation.y = _t * 0.4
	# The blood's surface breathes and the light pulses like a slow heartbeat.
	var beat := pow(maxf(sin(_t * 3.2), 0.0), 6.0)
	_surface.scale = Vector3(1.0, 1.0, 1.0) * (1.0 + 0.08 * beat)
	_light.light_energy = 0.7 + 0.6 * beat
	for i in _motes.size():
		var k := fmod(_t * 0.45 + float(i) / float(_motes.size()), 1.0)
		var a := float(i) * 2.4 + _t * 0.6
		var m := _motes[i]
		m.position = Vector3(cos(a) * 0.08, 0.62 + k * 0.6, sin(a) * 0.08)
		m.scale = Vector3.ONE * maxf(0.045 * sin(k * PI), 0.002)


func _build() -> void:
	if _blood_mat == null:
		_blood_mat = HolyFX.additive(Art.SOUL, 2.4)
	_model = Art.pivot(self)
	# Blender-made chalice (tools/blender/models/pickups/blood_chalice.py).
	var glb := GlbModel.create(MODEL, false)
	_model.add_child(glb)
	if glb.scene_root:
		_surface = glb.scene_root.find_child("blood_glow", true, false) as Node3D
		_swap_glow(glb.scene_root)
	if _surface == null:
		_surface = Art.pivot(_model)
	# Crimson motes rising from the brim.
	for i in 4:
		var m := Art.part(self, Art.sphere(), _blood_mat, Vector3.ZERO, Vector3.ONE * 0.04)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_motes.append(m)
	_light = Art.light(self, Art.SOUL, 0.8, 2.6, Vector3(0.0, 0.8, 0.0))
	Art.no_shadows(_surface)


## The glowing core of the blood becomes an additive light-like surface.
func _swap_glow(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi and mi.mesh:
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src and src.resource_name == "Chalice_BloodGlow":
				mi.set_surface_override_material(i, _blood_mat)
	for c in n.get_children():
		_swap_glow(c)
