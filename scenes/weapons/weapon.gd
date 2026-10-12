class_name Weapon
extends Node3D
## Base class for all weapons. Weapons live under Player/Weapons, so they move with the player.
##
## To make a new weapon: extend this, override attack() (called every cooldown) and/or
## _on_level_changed() (recompute per-level stats), save it as a scene, and add the
## scene to Player.weapon_pool.

@export var display_name := "Weapon"
@export_multiline var description := ""
@export var color := Color.WHITE
## Emoji or short text shown on level-up cards and the HUD weapon row.
@export var icon := "?"
@export var base_damage := 10.0
## Seconds between attack() calls, before the player's cooldown multiplier.
@export var base_cooldown := 1.0
## Upgrade text for level 2, 3, ... The max level is this size + 1.
@export var level_descriptions: PackedStringArray = []

var level := 1
var player: Player
## Per-level cooldown multiplier. Subclasses set it in _on_level_changed() (e.g. 0.75 at level 7);
## get_cooldown() applies it on top of base_cooldown and the player's cooldown stat.
var cooldown_mult := 1.0

var _cooldown_left := 0.0


func _ready() -> void:
	_on_level_changed()


func _physics_process(delta: float) -> void:
	if player == null or player.is_dead:
		return
	_cooldown_left -= delta
	if _cooldown_left <= 0.0:
		# attack() returns false when it had nothing to do (e.g. no target); retry next frame.
		if attack():
			_cooldown_left = get_cooldown()


## Override. Return true if the attack happened (starts the cooldown).
func attack() -> bool:
	return true


## Override to recompute stats from `level`.
func _on_level_changed() -> void:
	pass


## Raises the level by one (no-op at max) and recomputes stats via _on_level_changed().
func level_up() -> void:
	if is_max_level():
		return
	level += 1
	_on_level_changed()


## One level per entry in level_descriptions, plus the starting level.
func get_max_level() -> int:
	return level_descriptions.size() + 1


func is_max_level() -> bool:
	return level >= get_max_level()


## Upgrade text for the next level (shown on level-up cards), or "" at max level.
func get_next_level_description() -> String:
	return "" if is_max_level() else level_descriptions[level - 1]


## Damage per hit before per-weapon multipliers: base_damage scaled by the player's might.
func get_damage() -> float:
	return base_damage * player.might


## Seconds between attack() calls: base_cooldown * player cooldown stat * cooldown_mult.
func get_cooldown() -> float:
	return base_cooldown * player.cooldown * cooldown_mult


## Area multiplier from the player (scale radii / lengths by it).
func get_area() -> float:
	return player.area
