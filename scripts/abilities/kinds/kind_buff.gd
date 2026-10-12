extends AbilityKind
## "buff": while an enemy is within 10 m, raises player stats for params.duration seconds.
## Params: might, cooldown_stat (added to Player.cooldown), move_speed, armor, and
## might_per_wrath (extra might per Wrath stack when cast).

var _applied := {}  # player stat -> amount currently added
var _left := 0.0


func cast() -> bool:
	if Targeting.nearest_enemy(tree(), player.global_position, 10.0) == null:
		return false
	cleanup()
	_applied = {
		&"might": p("might") + p("might_per_wrath") * Abilities.wrath,
		&"cooldown": p("cooldown_stat"), &"move_speed": p("move_speed"), &"armor": p("armor"),
	}
	for stat: StringName in _applied:
		player.set(stat, float(player.get(stat)) + float(_applied[stat]))
	_left = p("duration", 5.0) * Abilities.duration_mult()
	InfernalFx.flash_sphere(origin(), def.color, 1.4, 0.3)
	AbilityFx.ring(player.global_position, 2.5, def.color, 0.4)
	var fx := InfernalFx.embers(player, def.color, 20, 0.6, 0.5, Vector3(0.0, 1.0, 0.0))
	tree().create_timer(_left, false).timeout.connect(fx.queue_free)
	sfx(&"chalice", -3.0)
	return true


func tick(delta: float) -> void:
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			cleanup()


func cleanup() -> void:
	if not _applied.is_empty() and is_instance_valid(player):
		for stat: StringName in _applied:
			player.set(stat, float(player.get(stat)) - float(_applied[stat]))
	_applied.clear()
	_left = 0.0
