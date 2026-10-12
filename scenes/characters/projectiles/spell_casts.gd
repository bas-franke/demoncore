class_name SpellCast
extends Node3D
## "Projectile" scenes that are really spells (characters-new, round 4): Enemy._fire() spawns them at
## the muzzle with `velocity` and `damage` set, like any projectile; on _ready they cast one of the
## shared, telegraphed boss hazards and free themselves. `kind` (set in the .tscn) picks the spell:
##   bell     a ring of sound expands from the caster (BellRing)        - Bell-Ringer Monk
##   beam     a mirror-beam lane from the caster toward the demon       - Sun-Priest
##   strike   lightning called down on the demon's position (pillar)    - Lightning-Rod Acolyte
## `tint` colours the hazard (HolyFX.hazard_tint scope).

@export_enum("bell", "beam", "strike") var kind := "bell"
@export var tint := Color(1.0, 0.85, 0.5)
@export var reach := 12.0

var velocity := Vector3.ZERO
var damage := 10.0


func _ready() -> void:
	_cast.call_deferred()


func _cast() -> void:
	if not is_inside_tree():
		return
	var at := Vector3(global_position.x, 0.0, global_position.z)
	var dir := Vector3(velocity.x, 0.0, velocity.z)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	HolyFX.hazard_tint = tint
	match kind:
		"bell":
			BellRing.cast(at, reach, 5.5, 0.8, damage, 0.15)
			Sfx.play_at(&"bell_ring", at, 0.08, -4.0)  # cold hand-bell toll (sfx)
		"beam":
			InquisitorLane.cast(at + dir * 0.6, dir, reach, 0.9, 0.7, damage)
			Sfx.play_at(&"mirror_beam", at, 0.06, -4.0)
		"strike":
			var p := Game.player
			var target := at + dir * 6.0
			if p:
				target = Vector3(p.global_position.x, 0.0, p.global_position.z)
			JudgementPillar.cast(target, 1.3, 0.9, damage)
	HolyFX.hazard_tint = Art.HOLY
	queue_free()
