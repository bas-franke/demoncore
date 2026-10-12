extends Weapon
## Hurls bolts of hellfire at the nearest enemies.

@export var projectile_scene: PackedScene
@export var projectile_speed := 14.0
@export var target_range := 18.0

var amount := 1
var pierce := 0
var damage_mult := 1.0


func _on_level_changed() -> void:
	amount = 1 + int(level >= 2) + int(level >= 5)
	damage_mult = 1.0 + 0.3 * int(level >= 3) + 0.4 * int(level >= 6)
	pierce = int(level >= 4)
	cooldown_mult = 0.75 if level >= 7 else 1.0


func attack() -> bool:
	var count := amount + player.bonus_projectiles
	var origin := global_position + Vector3(0, 0.8, 0)
	var targets := Targeting.nearest_enemies(get_tree(), origin, count, target_range)
	if targets.is_empty():
		return false
	for i in count:
		var target := targets[i % targets.size()]
		var dir := Targeting.flat_dir(origin, target.global_position)
		if i >= targets.size():
			dir = dir.rotated(Vector3.UP, randf_range(-0.25, 0.25))
		var p: Projectile = projectile_scene.instantiate()
		p.damage = get_damage() * damage_mult
		p.pierce = pierce
		p.velocity = dir * projectile_speed * player.projectile_speed
		p.spin_speed = randf_range(9.0, 14.0)
		p.source = self
		Game.spawn(p, origin)
	Sfx.play(&"fire_bolt", 0.12)
	return true
