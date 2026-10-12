class_name ExorcismBolt
extends Area3D
## Enemy projectile (Exorcist): a spinning violet sigil of binding. Light damage, but the rite
## tears at what the demon has gathered: on hit it drains `drain_ichor` Ichor (RunState run
## currency) and `drain_souls` reaped souls (Abilities), and flings the stolen sparks back toward
## where it came from. Configure `velocity` and `damage` before Game.spawn(bolt, pos).
## Autoloads are looked up by name, so it degrades gracefully if one is missing.

const CRUISE_HEIGHT := 0.75
const COLOR := Color(0.75, 0.6, 1.0)

var velocity := Vector3.ZERO
var damage := 4.0
var lifetime := 3.0
## Ichor removed per hit.
var drain_ichor := 3
## Abilities "souls reaped" removed per hit.
var drain_souls := 6

var _done := false
var _spin: Node3D
var _from := Vector3.ZERO


func _ready() -> void:
	_from = global_position
	_spin = Art.pivot(self)
	Art.part(_spin, Art.torus(0.75, 1.0), Art.glow(COLOR, 2.4), Vector3.ZERO, Vector3.ONE * 0.24, Vector3(PI * 0.5, 0.0, 0.0))
	Art.part(_spin, Art.box(), Art.glow(COLOR, 2.0), Vector3.ZERO, Vector3(0.03, 0.36, 0.03))
	Art.part(_spin, Art.box(), Art.glow(COLOR, 2.0), Vector3(0.0, 0.05, 0.0), Vector3(0.22, 0.03, 0.03))
	Art.part(_spin, Art.sphere(), Art.glow(COLOR, 0.4), Vector3.ZERO, Vector3.ONE * 0.5)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	global_position.y = EnemyModel.damp(global_position.y, CRUISE_HEIGHT, 5.0, delta)
	if velocity.length_squared() > 0.0001:
		_spin.basis = Basis.looking_at(Vector3(velocity.x, 0.0, velocity.z).normalized(), Vector3.UP) \
				* Basis(Vector3.FORWARD, lifetime * 9.0)
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
	var drained := _drain()
	Sfx.play(&"holy_hit", 0.1, -4.0)
	EnemyModel.light_flash(global_position, 0.6, COLOR, false)
	if drained:
		# The stolen sparks stream back toward the exorcist's side.
		EnemyModel.spawn_motes(global_position, 8, 0.8, COLOR)
	queue_free()


## Takes Ichor and reaped souls. Returns true if anything was taken.
func _drain() -> bool:
	var took := false
	var rs := get_node_or_null(^"/root/RunState")
	if rs and drain_ichor > 0 and int(rs.get(&"currency")) > 0:
		rs.call(&"add_currency", -drain_ichor)
		took = true
	var ab := get_node_or_null(^"/root/Abilities")
	if ab and drain_souls > 0:
		var s := int(ab.get(&"souls"))
		if s > 0:
			ab.set(&"souls", maxi(s - drain_souls, 0))
			if ab.has_signal(&"souls_changed"):
				ab.emit_signal(&"souls_changed", int(ab.get(&"souls")))
			took = true
	return took
