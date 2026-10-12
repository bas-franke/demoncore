class_name HolyOrb
extends Area3D
## Enemy projectile (Ophanim): a slow sphere of radiant light ringed by a spinning band, leaving
## a trail of fading motes. Configure velocity/damage before spawning with Game.spawn(orb, pos);
## it eases down from the muzzle to CRUISE_HEIGHT.

const CRUISE_HEIGHT := 0.8
const TRAIL_EVERY := 0.06
const RADIUS := 0.22

var velocity := Vector3.ZERO
var damage := 8.0
var lifetime := 5.0

var _done := false
var _t := 0.0
var _visual: Node3D
var _band: Node3D
var _bloom: MeshInstance3D


func _ready() -> void:
	_visual = Art.pivot(self)
	Art.part(_visual, Art.sphere(), Art.glow(Art.HOLY_WHITE, 3.0), Vector3.ZERO, Vector3.ONE * RADIUS * 1.2)
	_bloom = Art.part(_visual, Art.sphere(), Art.glow(Art.HOLY, 0.45), Vector3.ZERO, Vector3.ONE * RADIUS * 3.0)
	_band = Art.pivot(_visual, Vector3.ZERO, Vector3(randf_range(0.4, 1.2), 0.0, randf_range(-0.6, 0.6)))
	Art.part(_band, Art.torus(0.86, 1.0), Art.glow(Art.HOLY, 2.2), Vector3.ZERO, Vector3.ONE * RADIUS * 1.9)
	_t = randf() * TAU
	_make_trail()
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	global_position.y = EnemyModel.damp(global_position.y, CRUISE_HEIGHT, 4.0, delta)
	_t += delta
	_band.rotate_object_local(Vector3.UP, delta * 7.0)
	_bloom.scale = Vector3.ONE * RADIUS * (3.0 + 0.4 * sin(_t * 9.0))
	lifetime -= delta
	if lifetime <= 0.0:
		_burst()
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _done:
		return
	var player := body as Player
	if player == null:
		return
	_done = true
	player.take_damage(damage, global_position - velocity)
	Sfx.play(&"holy_hit", 0.1, -4.0)
	_burst()
	queue_free()


## Trail of motes left behind in the air (hang, sink a little, wink out). One particle system
## per orb (perf: this used to spawn a MeshInstance3D + tween every 0.06 s per orb).
func _make_trail() -> void:
	MoteTrail.attach(self, Art.glow(Art.HOLY, 2.5), 0.1, 0.4, TRAIL_EVERY, 1.6)


## A single mote left behind in the air (kept for callers; the trail uses _make_trail()).
func _mote() -> void:
	if Game.world == null:
		return
	var off := Vector3(randf_range(-0.08, 0.08), randf_range(-0.08, 0.08), randf_range(-0.08, 0.08))
	var m := Art.part(Game.world, Art.sphere(), Art.glow(Art.HOLY, 2.5), global_position + off, Vector3.ONE * 0.1)
	m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var tw := m.create_tween()
	tw.tween_property(m, "position:y", m.position.y - 0.15, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "scale", Vector3.ONE * 0.005, 0.4)
	tw.tween_callback(m.queue_free)


func _burst() -> void:
	EnemyModel.light_flash(global_position, 0.6, Art.HOLY, false)
	EnemyModel.spawn_motes(global_position, 5, 0.6, Art.HOLY)
