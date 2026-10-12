extends Weapon
## Hurls spinning scythes in the facing direction. They slow, turn and fly back to the demon,
## cutting every enemy once on the way out and once more on the way back.

const ScytheProjectile := preload("res://scenes/weapons/reapers_scythe/scythe_projectile.gd")

## How far a scythe flies before turning around.
@export var base_range := 6.0
@export var throw_speed := 12.0
@export var knockback := 5.0
## Radians between scythes when throwing several at once.
@export var spread := 0.5

var amount := 1
var damage_mult := 1.0
var range_mult := 1.0
var size_mult := 1.0
var speed_mult := 1.0


func _on_level_changed() -> void:
	amount = 1 + int(level >= 2) + int(level >= 5)
	damage_mult = 1.0 + 0.3 * int(level >= 3) + 0.4 * int(level >= 6)
	range_mult = 1.25 if level >= 4 else 1.0
	size_mult = 1.3 if level >= 4 else 1.0
	speed_mult = 1.25 if level >= 7 else 1.0
	cooldown_mult = 0.75 if level >= 7 else 1.0


func attack() -> bool:
	var dir := player.facing
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var n := amount + player.bonus_projectiles
	var origin := player.global_position + Vector3(0.0, ScytheProjectile.HEIGHT, 0.0)
	for i in n:
		var off := (float(i) - float(n - 1) * 0.5) * spread
		var p := ScytheProjectile.new()
		p.player = player
		p.direction = dir.rotated(Vector3.UP, off)
		p.speed = throw_speed * speed_mult * player.projectile_speed
		p.max_distance = base_range * range_mult * lerpf(1.0, get_area(), 0.5)
		p.size = size_mult * get_area()
		p.damage = get_damage() * damage_mult
		p.knockback = knockback
		p.source = self
		Game.spawn(p, origin + p.direction * 0.4)
	Sfx.play(&"scythe")
	return true
