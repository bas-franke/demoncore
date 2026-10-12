class_name AbilityResources
extends RefCounted
## Run resources the abilities scale with (owned by the Abilities autoload as `Abilities.res`;
## the autoload forwards `souls`, `wrath`, `girth`, `damage_taken` and the methods below):
##   Souls (Soul Harvest)  +1 per kill (Soul Glutton / Soul Cage add more), cap 200 + boons.
##   Wrath (Wrath)         +1 per WRATH_PER_HP damage taken and per swarming angel; drains when
##                         left alone.
##   Greed (Greed)         Ichor carried (RunState.currency); Soul Market adds half the Souls.
##   Girth (Gluttony)      +1 per angel devoured: max HP and a slightly bigger body (ScaleStack).
## Also: temporary might ("empower"), stat passives that follow a resource, recent corpses.

const BASE_SOUL_CAP := 200
const CORPSE_LIFE := 4.0
const MAX_CORPSES := 40
## Wrath: one stack per WRATH_PER_HP damage taken, up to WRATH_CAP; after WRATH_HOLD s without
## being hurt it drains at WRATH_DECAY stacks per second.
const WRATH_PER_HP := 4.0
const WRATH_CAP := 40.0
const WRATH_HOLD := 3.0
const WRATH_DECAY := 4.0
## Being swarmed also stokes Wrath (contact damage is small and often dodged): each check, every
## angel within WRATH_SWARM_RANGE adds WRATH_PER_SWARMER stacks (at most 3 count).
const WRATH_SWARM_RANGE := 2.5
const WRATH_PER_SWARMER := 0.4
const GREED_CAP := 250.0
## Girth: max HP per stack, body scale per stack, stack cap.
const GIRTH_HP := 2.0
const GIRTH_SCALE := 0.008
const GIRTH_CAP := 40

var ab: Node  # the Abilities autoload
var souls := 0
var wrath := 0.0
## Total damage the demon has taken this run.
var damage_taken := 0.0
var girth := 0

var _wrath_idle := 0.0
var _applied := {}  # player stat -> amount currently added by passives
var _empowers: Array = []  # Array of [might added, expiry msec]
var _corpses: Array = []  # Array of [Vector3, float expiry]


func _init(p_ab: Node) -> void:
	ab = p_ab


## Undoes every stat this object added to `player` and clears the run's resources.
func reset(player: Player) -> void:
	if is_instance_valid(player):
		for stat: StringName in _applied:
			player.set(stat, float(player.get(stat)) - float(_applied[stat]))
		for e: Array in _empowers:
			player.might -= float(e[0])
		ScaleStack.set_factor(player.get_node_or_null(^"Body") as Node3D, &"girth", 1.0)
	_applied.clear()
	_empowers.clear()
	_corpses.clear()
	souls = 0
	wrath = 0.0
	damage_taken = 0.0
	girth = 0


## Every frame while a run is active.
func tick(delta: float) -> void:
	_wrath_idle += delta
	if _wrath_idle > WRATH_HOLD and wrath > 0.0:
		wrath = maxf(wrath - WRATH_DECAY * delta, 0.0)
	if not _empowers.is_empty():
		var now := Time.get_ticks_msec()
		for i in range(_empowers.size() - 1, -1, -1):
			if int(_empowers[i][1]) <= now:
				ab.player.might -= float(_empowers[i][0])
				_empowers.remove_at(i)


## Twice a second: passives that follow a resource, and swarm Wrath.
func slow_tick() -> void:
	_update_passives()
	if ab.owned_tags().has("wrath"):
		var n := mini(AbilityCombat.enemies_in_radius(ab.player.global_position, WRATH_SWARM_RANGE).size(), 3)
		if n > 0:
			add_wrath(n * WRATH_PER_SWARMER)


func on_enemy_died(pos: Vector3) -> void:
	_corpses.append([pos, Time.get_ticks_msec() / 1000.0 + CORPSE_LIFE * (1.0 + ab.mod("corpse_life"))])
	if _corpses.size() > MAX_CORPSES:
		_corpses.pop_front()
	var gain := 1
	if randf() < ab.mod("soul_bonus"):
		gain += 1
	if ab.has_synergy(&"soul_cage"):
		gain += int(ab.syn_param(&"soul_cage", "souls", 1))
	add_souls(gain)


func on_player_hit(amount: float) -> void:
	damage_taken += amount
	add_wrath(amount / WRATH_PER_HP)


func soul_cap() -> int:
	return BASE_SOUL_CAP + int(ab.mod("soul_cap"))


func add_souls(n: int) -> void:
	if n <= 0 or not is_instance_valid(ab.player):
		return
	var before := souls
	souls = mini(souls + n, soul_cap())
	if souls != before:
		ab.souls_changed.emit(souls)
		if ab.has_synergy(&"soul_transfusion"):
			ab.heal_player((souls - before) * float(ab.syn_param(&"soul_transfusion", "heal", 0.5)))


func add_wrath(stacks: float) -> void:
	wrath = minf(wrath + stacks * (1.0 + ab.mod("wrath_gain")), WRATH_CAP + ab.mod("wrath_cap"))
	_wrath_idle = 0.0


func add_girth(n: int) -> void:
	girth = mini(girth + n, GIRTH_CAP)


## Ichor held this run (RunState currency), 0 without RunState.
func ichor() -> int:
	var rs: Node = ab.get_node_or_null(^"/root/RunState")
	return int(rs.get(&"currency")) if rs else 0


func spend_ichor(n: int) -> bool:
	var rs: Node = ab.get_node_or_null(^"/root/RunState")
	return rs != null and bool(rs.call(&"spend_currency", n))


func drop_ichor(at: Vector3, n: int) -> void:
	var rs: Node = ab.get_node_or_null(^"/root/RunState")
	if rs and n > 0:
		rs.call(&"drop_currency", at, n, 1)


## Greed units: Ichor held (Soul Market also counts half your Souls), capped at GREED_CAP.
func greed() -> float:
	var g := float(ichor())
	if ab.has_synergy(&"soul_market"):
		g += souls * float(ab.syn_param(&"soul_market", "per_soul", 0.5))
	return minf(g, GREED_CAP)


## Temporary might: +`amount` for `seconds` (the "empower" effect).
func empower(amount: float, seconds: float) -> void:
	if not is_instance_valid(ab.player):
		return
	ab.player.might += amount
	_empowers.append([amount, Time.get_ticks_msec() + int(seconds * 1000.0)])


## Removes and returns up to `n` fresh corpse positions within `rng` of `center`, nearest first.
func take_corpses(center: Vector3, rng: float, n: int) -> Array[Vector3]:
	var now := Time.get_ticks_msec() / 1000.0
	var near: Array = []
	var live: Array = []
	for c: Array in _corpses:
		if float(c[1]) <= now:
			continue
		live.append(c)
		var d := (c[0] as Vector3).distance_to(center)
		if d <= rng:
			near.append([d, c])
	_corpses = live
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array[Vector3] = []
	for i in mini(n, near.size()):
		out.append(near[i][1][0])
		_corpses.erase(near[i][1])
	return out


## Stat bonuses that follow a run resource: Harvest of Souls (might per Soul), Girth (max HP and
## body size via ScaleStack), Unstoppable (armor per Wrath stack).
func _update_passives() -> void:
	var player: Player = ab.player
	var c: AbilityCaster = ab.get_caster(&"harvest_moon")
	_set_applied(player, &"might", souls * c.p("might_per_soul") if c else 0.0)
	var armor := 0.0
	if ab.has_synergy(&"unstoppable"):
		armor = wrath * float(ab.syn_param(&"unstoppable", "armor_per_wrath", 0.06))
	_set_applied(player, &"armor", armor)
	var hp_bonus := girth * GIRTH_HP
	var before := float(_applied.get(&"max_hp", 0.0))
	_set_applied(player, &"max_hp", hp_bonus)
	if hp_bonus > before:
		player.heal(hp_bonus - before)
	ScaleStack.set_factor(player.get_node_or_null(^"Body") as Node3D, &"girth", 1.0 + girth * GIRTH_SCALE)


func _set_applied(player: Player, stat: StringName, want: float) -> void:
	var cur := float(_applied.get(stat, 0.0))
	if is_equal_approx(want, cur):
		return
	player.set(stat, float(player.get(stat)) + want - cur)
	_applied[stat] = want
