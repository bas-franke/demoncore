class_name StatusHost
extends Node
## Status effects on one Enemy (burn, plague, bleed, curse, chill, root, shock, doom, soul_mark).
## Added on demand as a child named "StatusHost" by StatusHost.ensure(enemy); freed with it.
## Definitions (duration, max stacks, dps, amp, ...) come from "statuses" in
## data/abilities/abilities.json via Abilities.statuses.
##
## - DoTs (burn / plague / bleed) are batched into one hit every TICK seconds, so damage numbers
##   stay readable and the tick goes through AbilityCombat.hit (curses and synergies apply).
## - Chill and root set Enemy.set_move_factor(&"abilities", f): it multiplies all self-propelled
##   movement (charges and leaps too) and composes with other speed changes.
## - On death (Enemy.die -> queue_free) the host reports its statuses to Abilities, which runs
##   death effects (plague spread, Explosive Miasma, soul marks, ...). Kills from any source count.

const NODE_NAME := &"StatusHost"
const TICK := 0.5
const DOT_IDS: Array[StringName] = [&"burn", &"plague", &"bleed"]
## Bound bosses are only slowed by this much instead of held fast.
const BOSS_ROOT_SLOW := 0.35

var enemy: Enemy

var _stacks := {}  # StringName -> int
var _time := {}  # StringName -> float (seconds left)
var _tick_t := TICK
var _move := 1.0  # last factor pushed to Enemy.set_move_factor
var _doom_hp := 0.0  # enemy hp when the doom mark landed
var _fx: CPUParticles3D
var _fx_status: StringName


static func of(e: Enemy) -> StatusHost:
	if e == null or not is_instance_valid(e):
		return null
	return e.get_node_or_null(NodePath(String(NODE_NAME))) as StatusHost


static func ensure(e: Enemy) -> StatusHost:
	var h := of(e)
	if h:
		return h
	h = StatusHost.new()
	h.name = NODE_NAME
	h.enemy = e
	e.add_child(h)
	return h


func _ready() -> void:
	enemy.tree_exiting.connect(_on_enemy_tree_exiting)


func _physics_process(delta: float) -> void:
	if enemy == null or enemy.is_dying:
		return
	var expired: Array[StringName] = []
	for id: StringName in _time:
		_time[id] = float(_time[id]) - delta
		if float(_time[id]) <= 0.0:
			expired.append(id)
	for id in expired:
		_remove(id)

	_tick_t -= delta * (1.0 + Abilities.mod("dot_rate"))
	if _tick_t <= 0.0:
		_tick_t += TICK
		_dot_tick()
	_update_speed()


# ---------------------------------------------------------------- api

## Adds `n` stacks of `id` (clamped to its max) and refreshes its duration.
func add(id: StringName, n: int) -> void:
	var def: Dictionary = Abilities.statuses.get(id, {})
	if def.is_empty():
		return
	if id == &"root" and enemy.is_in_group(&"boss"):
		# Bosses can't be held; chains only drag at them.
		id = &"chill"
		n = 2
		def = Abilities.statuses[id]
	var cap := int(def.get("max", 1)) + int(Abilities.mod("max:" + String(id)))
	var before: int = _stacks.get(id, 0)
	_stacks[id] = clampi(before + n, 0, maxi(cap, 1))
	var dur := float(def.get("duration", 3.0)) * Abilities.duration_mult() * (1.0 + Abilities.mod("dur:" + String(id)))
	if id == &"doom" and before > 0:
		return  # a doom mark is not refreshed: it always erupts on schedule
	_time[id] = maxf(float(_time.get(id, 0.0)), dur)
	if id == &"doom":
		_doom_hp = enemy.hp
	_refresh_fx()


func has(id: StringName) -> bool:
	return int(_stacks.get(id, 0)) > 0


func count(id: StringName) -> int:
	return int(_stacks.get(id, 0))


## Copy of the current stacks (StringName -> int), e.g. to judge a killing blow.
func snapshot() -> Dictionary:
	return _stacks.duplicate()


## Extra damage taken from Curse stacks (and Shackled Damnation while Bound).
func curse_amp() -> float:
	var stacks := count(&"curse")
	if has(&"root") and Abilities.has_synergy(&"shackled_damnation"):
		stacks += int(Abilities.syn_param(&"shackled_damnation", "curse_stacks", 3))
	if stacks == 0:
		return 0.0
	var def: Dictionary = Abilities.statuses[&"curse"]
	return stacks * float(def.get("amp", 0.08)) * (1.0 + Abilities.mod("power:curse"))


## Extra storm damage taken from Shock stacks.
func shock_amp() -> float:
	var stacks := count(&"shock")
	if stacks == 0:
		return 0.0
	var def: Dictionary = Abilities.statuses[&"shock"]
	return stacks * float(def.get("amp", 0.1)) * (1.0 + Abilities.mod("power:shock"))


# ---------------------------------------------------------------- internals

func _dot_tick() -> void:
	var dps := 0.0
	var tags := PackedStringArray()
	for id in DOT_IDS:
		var n := count(id)
		if n == 0:
			continue
		var def: Dictionary = Abilities.statuses[id]
		var power := 1.0 + Abilities.mod("power:" + String(id))
		if id == &"bleed" and Abilities.has_synergy(&"crimson_pact"):
			power += float(Abilities.syn_param(&"crimson_pact", "bleed_amp", 0.4))
		dps += n * float(def.get("dps", 2.0)) * power
		for t: Variant in def.get("tags", []):
			tags.append(str(t))
	if dps <= 0.0:
		return
	tags.append("dot")
	if has(&"plague") and Abilities.has_synergy(&"contagion") and count(&"curse") < 3:
		add(&"curse", 1)
	var amount := dps * TICK * Abilities.player_might() * (1.0 + Abilities.mod("damage"))
	AbilityCombat.hit(enemy, amount, {"tags": tags, "dot": true})


func _remove(id: StringName) -> void:
	_stacks.erase(id)
	_time.erase(id)
	if id == &"doom" and is_instance_valid(enemy) and not enemy.is_dying:
		_erupt_doom()
	_refresh_fx()


func _erupt_doom() -> void:
	var def: Dictionary = Abilities.statuses[&"doom"]
	var fury := maxf(_doom_hp - enemy.hp, 0.0)
	var dmg := fury + 10.0 * float(def.get("burst", 4.0)) * Abilities.player_might()
	var pos := enemy.global_position
	AbilityFx.pillar(pos, 0.9, Abilities.status_color(&"doom"), 0.45)
	AbilityFx.ring(pos, 1.6, Abilities.status_color(&"doom"), 0.3)
	Sfx.play(&"smite", 0.1, -4.0)
	AbilityCombat.hit(enemy, dmg, {"tags": PackedStringArray(["shadow", "curse"]), "origin": pos})


func _update_speed() -> void:
	var slow := 0.0
	if has(&"chill"):
		slow += count(&"chill") * float((Abilities.statuses[&"chill"] as Dictionary).get("slow", 0.12))
	var rooted := has(&"root")
	if rooted:
		slow = 1.0
	slow = clampf(slow, 0.0, 1.0 if rooted else 0.75)
	# A named factor on the enemy composes with anything else that changes its speed, and also
	# scales charges and leaps, so a Bound charger can't dash out of its chains.
	var f := 1.0 - slow
	if not is_equal_approx(f, _move):
		_move = f
		enemy.set_move_factor(&"abilities", f)


## One small ember emitter tinted by the most important active status.
func _refresh_fx() -> void:
	var top: StringName = &""
	for id: StringName in [&"doom", &"root", &"plague", &"burn", &"curse", &"bleed", &"shock", &"chill", &"soul_mark"]:
		if has(id):
			top = id
			break
	if top == _fx_status:
		return
	_fx_status = top
	if top == &"":
		if _fx:
			_fx.emitting = false
		return
	if _fx == null:
		var s := enemy.data.size if enemy.data else 1.0
		_fx = InfernalFx.embers(enemy, Art.EMBER, 6, 0.7, 0.35 * s, Vector3(0.0, 0.7 * s, 0.0), 2.5)
	_fx.color_ramp = InfernalFx.ramp(Abilities.status_color(top))
	_fx.emitting = true


func _on_enemy_tree_exiting() -> void:
	if is_instance_valid(enemy) and enemy.is_dying and not _stacks.is_empty():
		# Deferred: the world is busy removing children right now, so nothing can be spawned.
		Abilities.on_status_enemy_died.call_deferred(enemy.global_position, snapshot())
