class_name AbilityKind
extends RefCounted
## Base for one ability behaviour archetype ("kind"). An AbilityCaster owns exactly one kind
## instance (created by AbilityKinds.create from AbilityDef.kind) and forwards to it:
##   cast()      when the cooldown is up; return true if it fired (starts the cooldown)
##   tick(delta) every physics frame (persistent kinds: orbits, turrets, charge-ups)
##   rebuild()   after the stats changed (rank-up, area / count boons)
##   cleanup()   when the caster leaves the tree (undo buffs, free persistent nodes)
## Helpers below forward to the caster so kind code stays short.

var caster: AbilityCaster


func cast() -> bool:
	return false


func tick(_delta: float) -> void:
	pass


func rebuild() -> void:
	pass


func cleanup() -> void:
	pass


## False for persistent kinds that have nothing to "fire early" (see AbilityCaster.unleash).
func can_unleash() -> bool:
	return true


# ---------------------------------------------------------------- helpers

var player: Player:
	get:
		return caster.player

var def: AbilityDef:
	get:
		return caster.def


func p(key: String, default: float = 0.0) -> float:
	return caster.p(key, default)


func style(default: String) -> String:
	return str(caster.stats.get("style", default))


func damage() -> float:
	return caster.get_damage()


func count() -> int:
	return caster.get_count()


func source() -> Dictionary:
	return caster.source()


func area() -> float:
	return Abilities.area_mult()


func tree() -> SceneTree:
	return caster.get_tree()


func origin() -> Vector3:
	return player.global_position + Vector3(0.0, 0.8, 0.0)


func sfx(sound: StringName, db: float = -6.0) -> void:
	Sfx.play(sound, 0.12, db)


## Runs the ability's "after" effects (lingering craters, Magma Forge) at `at`.
func after(at: Vector3) -> void:
	caster.run_after(at)


## Hits every enemy in `foes` with the ability's damage and source (origin = `from`).
func hit_all(foes: Array[Enemy], from: Vector3, dmg: float = -1.0) -> void:
	var src := source()
	src["origin"] = from
	var d := damage() if dmg < 0.0 else dmg
	for e in foes:
		AbilityCombat.hit(e, d, src)
