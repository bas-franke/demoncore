class_name IchorDrop
extends Pickup
## Run currency pickup: a bead of golden angelic ichor. Spilled by slain angels through
## RunState.drop_currency(); flies to the demon once its PickupArea touches it, then calls
## RunState.add_currency(value). Pops out of the corpse in a short arc so piles spread out.

const GOLD_CORE := Color(1.0, 0.82, 0.38)
const GOLD_HALO := Color(1.0, 0.7, 0.25)
## Uncollected drops fade away after this many seconds (keeps the floor readable).
const LIFETIME := 60.0

static var _core_mat: StandardMaterial3D
static var _shell_mat: StandardMaterial3D

@export var value := 1

var _t := 0.0
var _age := 0.0
## Spawn hop: horizontal velocity + vertical arc.
var _hop := Vector3.ZERO
var _hop_y := 0.0
var _hop_vy := 0.0
var _model: Node3D
var _halo: MeshInstance3D


func _ready() -> void:
	homing_accel = 50.0
	homing_start_speed = -3.0
	_t = randf() * TAU
	var a := randf() * TAU
	_hop = Vector3(cos(a), 0.0, sin(a)) * randf_range(0.6, 1.8)
	_hop_vy = randf_range(3.0, 4.5)
	_build()


func _physics_process(delta: float) -> void:
	_t += delta
	_age += delta
	# Spawn arc (purely visual height on the model; the area itself slides along the ground).
	if _hop_vy != 0.0 or _hop_y > 0.0:
		_hop_vy -= 14.0 * delta
		_hop_y = maxf(_hop_y + _hop_vy * delta, 0.0)
		if _hop_y <= 0.0 and _hop_vy < 0.0:
			_hop_vy = 0.0
			_hop = Vector3.ZERO
		global_position += _hop * delta
	_animate()
	if _target == null:
		if _age > LIFETIME:
			queue_free()
		return
	_home(delta)


func _collect(player: Player) -> void:
	Sfx.play(&"coin", 0.08, -3.0)
	RunState.add_currency(value)
	DamageNumber.spawn(value, player.global_position + Vector3(0.0, 2.1, 0.0), GOLD_CORE, "+")


func _animate() -> void:
	if _model == null:
		return
	var fade := clampf((LIFETIME - _age) / 3.0, 0.0, 1.0)
	_model.position.y = 0.12 + _hop_y + sin(_t * 3.0) * 0.05
	_model.rotation.y = _t * (5.0 if _target else 1.2)
	var pulse := 1.0 + sin(_t * 5.0) * 0.12
	_model.scale = Vector3.ONE * maxf(fade, 0.01) * (1.0 + 0.15 * minf(float(value - 1), 4.0))
	if _halo:
		_halo.scale = Vector3.ONE * 0.55 * pulse


func _build() -> void:
	if _core_mat == null:
		_core_mat = Art.glow(GOLD_CORE, 2.6, false)
		_shell_mat = Art.glow(GOLD_HALO, 0.9, true)
	_model = Node3D.new()
	add_child(_model)
	# Teardrop: a squashed sphere with a cone tip pointing up.
	Art.part(_model, Art.sphere(), _core_mat, Vector3.ZERO, Vector3(0.2, 0.22, 0.2))
	Art.part(_model, Art.cone(0.5), _core_mat, Vector3(0.0, 0.16, 0.0), Vector3(0.16, 0.18, 0.16))
	_halo = Art.part(_model, Art.sphere(), _shell_mat, Vector3(0.0, 0.04, 0.0), Vector3.ONE * 0.55)
	Art.no_shadows(_model)
