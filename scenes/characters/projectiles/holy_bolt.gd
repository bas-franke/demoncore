class_name HolyBolt
extends Area3D
## Enemy projectile: a fast, straight blessed crossbow bolt / arrow with a gold head and a
## streak of light. Used by the Inquisitor (and any EnemyData whose `projectile` is
## res://scenes/characters/projectiles/holy_bolt.tscn). Configure `velocity` and `damage` before
## Game.spawn(bolt, pos); it flies level at CRUISE_HEIGHT and points along its velocity.
## `tint` recolours the light (set before adding to the tree).

const CRUISE_HEIGHT := 0.7
const TRAIL_EVERY := 0.05

var velocity := Vector3.ZERO
var damage := 6.0
var lifetime := 2.5
var tint := Art.HOLY

var _done := false
var _visual: Node3D


func _ready() -> void:
	_visual = Art.pivot(self)
	var wood := Art.mat(Color(0.5, 0.4, 0.3), 0.8)
	# Shaft along -Z (forward), head in front, fletching behind.
	EnemyModel.limb(_visual, Vector3(0.0, 0.0, 0.28), Vector3(0.0, 0.0, -0.22), 0.018, wood)
	Art.part(_visual, Art.cone(0.5), Art.mat(Art.GOLD, 0.3, 1.0), Vector3(0.0, 0.0, -0.28),
			Vector3(0.06, 0.14, 0.06), Vector3(-PI * 0.5, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		Art.part(_visual, Art.box(), Art.mat(Art.HOLY_WHITE, 0.8), Vector3(s * 0.025, 0.0, 0.24), Vector3(0.04, 0.005, 0.1))
	Art.part(_visual, Art.sphere(), Art.glow(tint, 1.2), Vector3(0.0, 0.0, 0.05), Vector3(0.09, 0.09, 0.7))
	# Perf: one particle trail instead of a MeshInstance3D + tween per mote (see MoteTrail).
	MoteTrail.attach(self, Art.glow(tint, 2.0), 0.06, 0.25, TRAIL_EVERY, 0.0, 0.0)
	body_entered.connect(_on_body_entered)
	_face()


func _face() -> void:
	if velocity.length_squared() > 0.0001:
		var d := Vector3(velocity.x, 0.0, velocity.z).normalized()
		_visual.basis = Basis.looking_at(d, Vector3.UP)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	global_position.y = EnemyModel.damp(global_position.y, CRUISE_HEIGHT, 6.0, delta)
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _done:
		return
	var player := body as Player
	if player == null:
		return
	_done = true
	player.take_damage(damage, global_position)
	Sfx.play(&"holy_hit", 0.1, -6.0)
	EnemyModel.light_flash(global_position, 0.4, tint, false)
	queue_free()


## A single fading mote (kept for callers; the trail uses MoteTrail).
func _mote() -> void:
	if Game.world == null:
		return
	var m := Art.part(Game.world, Art.sphere(), Art.glow(tint, 2.0), global_position, Vector3.ONE * 0.06)
	m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE * 0.005, 0.25)
	tw.tween_callback(m.queue_free)
