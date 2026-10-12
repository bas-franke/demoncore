class_name HolySmoke
extends Area3D
## Enemy projectile (Censer Cleric): a short-range gust of burning incense that billows, slows
## and thins away. Small damage, and it shoves the player back for a moment.
## Configure velocity/damage before spawning with Game.spawn(smoke, pos).

const SMOKE_A := Color(0.86, 0.82, 0.7)
const SMOKE_B := Color(0.6, 0.56, 0.5)
const CRUISE_HEIGHT := 0.7
const DRAG := 2.2
const PUSH_SPEED := 9.0
const PUSH_TIME := 0.25
const PUFFS := 6
const EMBERS := 4

var velocity := Vector3.ZERO
var damage := 4.0
var lifetime := 0.8

var _age := 0.0
var _hit := false
var _target: Player
var _push_dir := Vector3.ZERO
var _push_t := 0.0
var _visual: Node3D
var _puffs: Array[Node3D] = []
var _puff_dir: Array[Vector3] = []
var _embers: Array[Node3D] = []


func _ready() -> void:
	_visual = Art.pivot(self)
	if velocity.length_squared() > 0.0001:
		_visual.basis = Basis.looking_at(velocity.normalized(), Vector3.UP)
	var mat_a := Art.glow(SMOKE_A, 0.6, false, 0.35)
	var mat_b := Art.glow(SMOKE_B, 0.6, false, 0.3)
	for i in PUFFS:
		var a := TAU * float(i) / float(PUFFS) + randf_range(-0.3, 0.3)
		var d := Vector3(cos(a) * 0.6, sin(a) * 0.45, randf_range(-0.3, 0.3))
		var p := Art.part(_visual, Art.sphere(), mat_a if i % 2 == 0 else mat_b, d * 0.2,
				Vector3.ONE * randf_range(0.3, 0.45))
		_puffs.append(p)
		_puff_dir.append(d)
	# Burning grains of incense carried in the gust.
	for i in EMBERS:
		var e := Art.part(_visual, Art.sphere(), Art.glow(Art.EMBER if i % 2 == 0 else Art.HOLY, 3.0),
				Vector3(randf_range(-0.25, 0.25), randf_range(-0.2, 0.2), randf_range(-0.3, 0.1)), Vector3.ONE * 0.06)
		_embers.append(e)
	_visual.scale = Vector3.ONE * 0.6
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_age += delta
	global_position += velocity * delta
	global_position.y = EnemyModel.damp(global_position.y, CRUISE_HEIGHT, 6.0, delta)
	velocity *= exp(-DRAG * delta)
	var k := clampf(_age / lifetime, 0.0, 1.0)
	var fade := 1.0 if k < 0.7 else (1.0 - k) / 0.3
	_visual.scale = Vector3.ONE * (0.6 + 1.1 * k) * maxf(fade, 0.01)
	for i in _puffs.size():
		_puffs[i].position = _puff_dir[i] * (0.2 + 0.35 * k) + Vector3(0.0, 0.15 * k, 0.0)
	for e in _embers:
		e.position.y += delta * 0.4

	if _push_t > 0.0:
		_push_t -= delta
		if is_instance_valid(_target) and not _target.is_dead:
			var strength := clampf(_push_t / PUSH_TIME, 0.0, 1.0)
			_target.move_and_collide(_push_dir * PUSH_SPEED * strength * delta)
	if _age >= lifetime and _push_t <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _hit or _age >= lifetime:
		return
	var player := body as Player
	if player == null:
		return
	_hit = true
	_target = player
	player.take_damage(damage, player.global_position)  # no extra knock: the smoke pushes itself
	Sfx.play(&"holy_hit", 0.1, -6.0)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() < 0.0001:
		flat = player.global_position - global_position
		flat.y = 0.0
	_push_dir = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	_push_t = PUSH_TIME
	EnemyModel.poof(player.global_position + Vector3(0.0, 0.6, 0.0), SMOKE_A, SMOKE_B, 4, 0.25, 0.5)
