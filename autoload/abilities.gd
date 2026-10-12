extends Node
## Ability + synergy system (autoload "Abilities"). Owned by the abilities role
## (docs/team/abilities.md). Data lives in data/abilities/*.json; behaviour in scripts/abilities/.
##
## This node is the facade: registry (defs, statuses, synergies, boons, evolutions, weapon tags,
## demon affinities), run lifecycle, ownership (grant / boons / evolve) and modifiers. The parts
## live in helpers it forwards to:
##   AbilityResources (`res`)  Souls, Wrath, Greed, Girth, empower, corpses, resource passives
##   AbilitySynergies (`syn`)  active synergies and their hit hooks
##   AbilityEvents             reactions to deaths, blinks, blood spent, weapon hits
##   AbilityOffers             level-up cards (Upgrades.roll -> extend_pool / ensure_choice)
## A run starts automatically whenever a Player enters the tree.
##
##   Abilities.grant(&"inferno_nova")        # give / rank up an ability
##   Abilities.take_boon(&"kindling")        # apply a boon stack
##   Abilities.evolve(&"heart_of_gehenna")   # replace a maxed ability with its evolution
##
## Dev args: --abilities=id,id | all  --boons=id,id  --souls=N  --ability-rank=N  --evolve=evo_id
##   --ability-report (casts and damage per ability every 5 s)  --ability-bench (unarmed, no
##   level-ups, huge HP; see tools/ability_bench.sh).

signal ability_added(id: StringName)
signal ability_leveled(id: StringName, level: int)
signal ability_cast(id: StringName)
# Emitted from the scripts/abilities/ helpers, so the analyzer can't see the emits here.
@warning_ignore_start("unused_signal")
signal ability_evolved(from_id: StringName, to_id: StringName)
signal boon_taken(id: StringName, stacks: int)
signal synergy_activated(id: StringName)
signal souls_changed(souls: int)
## Every ability hit (after amplifiers). Cheap; for meters, achievements, audio.
signal damage_dealt(amount: float, tags: PackedStringArray)
@warning_ignore_restore("unused_signal")


## Total summons alive across all abilities (perf guard).
const MAX_MINIONS := 24
const SYNERGY_CHECK := 0.5
const HUD_SCRIPT := preload("res://scripts/abilities/ability_hud.gd")

var defs := {}  # StringName -> AbilityDef (evolved forms included)
var def_order: Array[StringName] = []  # offerable abilities (no evolutions)
var statuses := {}  # StringName -> Dictionary
var synergy_defs: Array[Dictionary] = []
var boon_defs := {}  # StringName -> Dictionary
var evolutions := {}  # StringName evolution id -> {from, boon, into}
var weapon_tags := {}  # String (weapon scene stem) -> Array of tags
var weapon_status := {}  # String tag -> {id, stacks, chance}
var demon_affinity := {}  # String demon id -> {school, damage, weight}
var max_abilities := 5
## Optional gate for meta unlocks: (id: StringName) -> bool. Locked abilities are never offered.
var unlock_filter: Callable
var reporting := false

# ---- run state
var player: Player
var casters := {}  # StringName -> AbilityCaster
var boon_stacks := {}  # StringName -> int
var mods := {}  # String -> float (summed boon modifiers, see docs)
var global_on_hit: Array = []
var global_on_kill: Array = []
## The current demon's favoured school ({} without one): {school, damage, weight}.
var affinity := {}
var res := AbilityResources.new(self)
var syn := AbilitySynergies.new(self)

var souls: int:
	get: return res.souls
var wrath: float:
	get: return res.wrath
	set(v): res.wrath = v
var girth: int:
	get: return res.girth
var damage_taken: float:
	get: return res.damage_taken
var active_synergies: Dictionary:
	get: return syn.active

var _holder: Node3D
var _syn_t := 0.0
var _tag_cache := {}  # String -> int, rebuilt with the synergy check
## Grants / boons requested before the run's player was bound; applied when the run starts.
var _pending_grants: Array[StringName] = []
var _pending_boons: Array[StringName] = []
var _bench := false
var _report := {}  # id -> [casts, effective damage]
var _report_t := 0.0


func _ready() -> void:
	AbilityData.load_into(self)
	get_tree().node_added.connect(_on_node_added)
	Game.enemy_died.connect(_on_enemy_died)
	Game.player_hit.connect(_on_player_hit)
	Game.enemy_struck.connect(_on_enemy_struck)
	var args := OS.get_cmdline_user_args()
	_bench = "--ability-bench" in args
	reporting = "--ability-report" in args or _bench
	if reporting:
		ability_cast.connect(func(id: StringName) -> void: _report_entry(String(id))[0] += 1)


func _process(delta: float) -> void:
	_syn_t -= delta
	if not is_instance_valid(player):
		if player != null:
			_end_run()
		# Fallback for players that entered the tree before this autoload was listening.
		if _syn_t <= 0.0:
			_syn_t = SYNERGY_CHECK
			var p := get_tree().get_first_node_in_group(&"player") as Player
			if p and p.is_node_ready():
				_begin_run(p)
		return
	res.tick(delta)
	if _syn_t <= 0.0:
		_syn_t = SYNERGY_CHECK
		_tag_cache.clear()  # weapons may have been added since the last check
		syn.refresh(owned_tags())
		res.slow_tick()
	if reporting:
		_report_t += delta
		if _report_t >= 5.0:
			_report_t = 0.0
			AbilityDev.print_report(self)


# ---------------------------------------------------------------- run lifecycle

func _on_node_added(node: Node) -> void:
	if node is Player:
		# Deferred: the player's _ready (stats, demon perks) has run by then.
		_begin_run.call_deferred(node)


func _begin_run(p: Player) -> void:
	if not is_instance_valid(p) or p == player:
		return
	_end_run()
	player = p
	affinity = affinity_for(demon_id(p))
	_holder = Node3D.new()
	_holder.name = "Abilities"
	p.add_child(_holder)
	var hud: CanvasLayer = HUD_SCRIPT.new()
	hud.name = "AbilityHud"
	(p.get_parent() if p.get_parent() else p).add_child(hud)
	var grants := _pending_grants.duplicate()
	var boons := _pending_boons.duplicate()
	_pending_grants.clear()
	_pending_boons.clear()
	for id in grants:
		grant(id)
	for id in boons:
		take_boon(id)
	AbilityDev.apply(self, p, _bench)


func _end_run() -> void:
	# QA: after a scene change `player` is a freed instance; passing it to the typed `reset(Player)`
	# errored and aborted _end_run, so `casters` kept freed casters into the hub and the next run
	# (15k+ "freed object" errors per hub -> run -> hub cycle in ability_hud / owned_tags).
	res.reset(player if is_instance_valid(player) else null)
	player = null
	_holder = null
	casters.clear()
	boon_stacks.clear()
	mods.clear()
	global_on_hit.clear()
	global_on_kill.clear()
	_report.clear()  # per-run damage tally (UI end-screen breakdown reads damage_report())
	syn.clear()
	_tag_cache.clear()
	affinity = {}


# ---------------------------------------------------------------- ownership

func has_ability(id: StringName) -> bool:
	return casters.has(id)


func get_caster(id: StringName) -> AbilityCaster:
	return casters.get(id) as AbilityCaster


func ability_count() -> int:
	return casters.size()


## Gives the ability, or ranks it up if already owned. Before the run's player is bound, the
## grant is queued and applied when the run starts.
func grant(id: StringName) -> void:
	if not defs.has(id):
		push_warning("Unknown ability '%s'" % id)
		return
	if not is_instance_valid(player) or _holder == null:
		_pending_grants.append(id)
		return
	if casters.has(id):
		var c: AbilityCaster = casters[id]
		c.level_up()
		ability_leveled.emit(id, c.level)
		return
	var caster := AbilityCaster.new()
	caster.setup(defs[id], player)
	_holder.add_child(caster)
	casters[id] = caster
	_tag_cache.clear()
	ability_added.emit(id)
	syn.refresh(owned_tags())


func take_boon(id: StringName) -> void:
	var b: Dictionary = boon_defs.get(id, {})
	if b.is_empty():
		push_warning("Unknown boon '%s'" % id)
		return
	if not is_instance_valid(player):
		_pending_boons.append(id)
		return
	boon_stacks[id] = int(boon_stacks.get(id, 0)) + 1
	var m: Dictionary = b.get("mods", {})
	for key: String in m:
		mods[key] = mod(key) + float(m[key])
	global_on_hit.append_array(b.get("on_hit", []))
	global_on_kill.append_array(b.get("on_kill", []))
	boon_taken.emit(id, boon_stacks[id])
	for c: AbilityCaster in casters.values():
		c._recompute()  # area / count boons change persistent visuals


func boon_name(id: StringName) -> String:
	return str((boon_defs.get(id, {}) as Dictionary).get("name", id))


## Meta gate: Progression's unlock catalog (kind "ability"), plus the optional unlock_filter.
func is_unlocked(id: StringName) -> bool:
	var prog := get_node_or_null(^"/root/Progression")
	if prog and prog.has_method(&"is_ability_unlocked") and not bool(prog.call(&"is_ability_unlocked", id)):
		return false
	return not unlock_filter.is_valid() or bool(unlock_filter.call(id))


# ---------------------------------------------------------------- demon affinity

## Demon id of a player ("vharok", ...): its DemonData file name.
static func demon_id(p: Player) -> String:
	if p == null or p.character == null:
		return ""
	return p.character.resource_path.get_file().get_basename()


## A demon's favoured school from abilities.json "demon_affinity" ({} if none).
func affinity_for(id: String) -> Dictionary:
	return demon_affinity.get(id, {})


func is_favoured(def: AbilityDef) -> bool:
	return not affinity.is_empty() and def.school == str(affinity.get("school", ""))


func affinity_damage() -> float:
	return float(affinity.get("damage", 0.1))


func affinity_weight() -> float:
	return float(affinity.get("weight", 3.0))


# ---------------------------------------------------------------- modifiers

func mod(key: String) -> float:
	return float(mods.get(key, 0.0))


func player_might() -> float:
	return player.might if is_instance_valid(player) else 1.0


func area_mult() -> float:
	return (player.area if is_instance_valid(player) else 1.0) * (1.0 + mod("area"))


func duration_mult() -> float:
	return 1.0 + mod("duration")


func damage_mult(def: AbilityDef) -> float: return AbilityModifiers.damage_mult(self, def)
func cooldown_mult(def: AbilityDef) -> float: return AbilityModifiers.cooldown_mult(self, def)
func count_bonus(def: AbilityDef) -> int: return AbilityModifiers.count_bonus(self, def)
func summon_bonus() -> int: return AbilityModifiers.summon_bonus(self)
func summon_amp() -> float: return AbilityModifiers.summon_amp(self)
func hp_cost_mult() -> float: return AbilityModifiers.hp_cost_mult(self)
func crit_chance(tags: PackedStringArray, host: StatusHost) -> float: return AbilityModifiers.crit_chance(self, tags, host)
func damage_amp_against(enemy: Enemy, host: StatusHost, tags: PackedStringArray, _dot: bool) -> float:
	return AbilityModifiers.damage_amp_against(self, enemy, host, tags)


func status_color(id: StringName) -> Color:
	return Color.from_string(str((statuses.get(id, {}) as Dictionary).get("color", "#ffffff")), Color.WHITE)


## Tag -> count over owned abilities plus owned weapons (via weapon_tags).
func owned_tags() -> Dictionary:
	if not _tag_cache.is_empty() or not is_instance_valid(player):
		return _tag_cache
	for c: AbilityCaster in casters.values():
		for t in c.def.tags:
			_tag_cache[t] = int(_tag_cache.get(t, 0)) + 1
	for w in player.weapons:
		if is_instance_valid(w):
			for t: Variant in weapon_tags.get(w.scene_file_path.get_file().get_basename(), []):
				_tag_cache[str(t)] = int(_tag_cache.get(str(t), 0)) + 1
	return _tag_cache


# ---------------------------------------------------------------- forwarders (stable API)

func has_synergy(id: StringName) -> bool: return syn.has(id)
func synergy_params(id: StringName) -> Dictionary: return syn.params(id)
func syn_param(id: StringName, key: String, default: Variant) -> Variant: return syn.param(id, key, default)
func synergy_statuses(tags: PackedStringArray) -> Array: return syn.statuses_for(tags)
func synergy_effects(tags: PackedStringArray, kill: bool) -> Array: return syn.effects_for(tags, kill)
func synergies_unlocked_by(extra: PackedStringArray) -> Array[String]: return syn.unlocked_by(owned_tags(), extra)
func soul_cap() -> int: return res.soul_cap()
func add_souls(n: int) -> void: res.add_souls(n)
func add_wrath(stacks: float) -> void: res.add_wrath(stacks)
func add_girth(n: int) -> void: res.add_girth(n)
func ichor() -> int: return res.ichor()
func spend_ichor(n: int) -> bool: return res.spend_ichor(n)
func drop_ichor(at: Vector3, n: int) -> void: res.drop_ichor(at, n)
func greed() -> float: return res.greed()
func empower(amount: float, seconds: float) -> void: res.empower(amount, seconds)
func take_corpses(center: Vector3, rng: float, n: int) -> Array[Vector3]: return res.take_corpses(center, rng, n)
func on_blink(from: Vector3, dest: Vector3) -> void: AbilityEvents.on_blink(self, from, dest)
func spawn_decoy(at: Vector3) -> void: AbilityEvents.spawn_decoy(self, at)
func raise_thrall(pos: Vector3) -> void: AbilityEvents.raise_thrall(self, pos)
func evolve(evo_id: StringName) -> void: AbilityOffers.evolve(self, evo_id)
func ready_evolutions() -> Array[StringName]: return AbilityOffers.ready_evolutions(self)
func evolution_for(ability_id: StringName) -> Dictionary: return AbilityOffers.evolution_for(self, ability_id)


func on_status_enemy_died(pos: Vector3, st: Dictionary) -> void: AbilityEvents.on_status_enemy_died(self, pos, st)
func on_minion_expired(m: AbilityMinion) -> void: AbilityEvents.on_minion_expired(self, m)
func on_life_spent(cost: float) -> void: AbilityEvents.on_life_spent(self, cost)


func heal_player(amount: float) -> void:
	if is_instance_valid(player) and not player.is_dead and amount > 0.0:
		player.heal(amount)


func minions_of(id: StringName) -> Array[AbilityMinion]: return AbilityEvents.minions_of(self, id)
func notify_ability_kill(pos: Vector3, tags: PackedStringArray, had: Dictionary) -> void:
	AbilityEvents.notify_ability_kill(self, pos, tags, had)


func _on_enemy_died(pos: Vector3, _data: Resource) -> void:
	if not is_instance_valid(player):
		return
	res.on_enemy_died(pos)
	if has_synergy(&"lord_of_the_pit") and randf() < float(syn_param(&"lord_of_the_pit", "raise_chance", 0.08)):
		raise_thrall(pos)


func _on_player_hit(amount: float) -> void:
	if amount > 0.0 and is_instance_valid(player):
		res.on_player_hit(amount)


func _on_enemy_struck(enemy: Node3D, _amount: float) -> void:
	AbilityEvents.on_enemy_struck(self, enemy, null)


# ---------------------------------------------------------------- level-up options

func extend_pool(p: Player, pool: Array[UpgradeOption]) -> void:
	if p == player:
		AbilityOffers.extend_pool(self, pool)


func ensure_choice(p: Player, picks: Array[UpgradeOption], pool: Array[UpgradeOption]) -> void:
	if p == player:
		AbilityOffers.ensure_choice(self, picks, pool)


# ---------------------------------------------------------------- damage report

## Called by AbilityCombat.hit: effective damage per ability id ("dot" for status ticks).
func report_damage(id: String, amount: float) -> void:
	_report_entry(id)[1] += amount


## Damage dealt this run per ability id (plus "dot" for status ticks, "effect" for on-hit /
## synergy effects): id -> [casts (only counted with --ability-report), damage]. Read by the UI
## role's end-screen breakdown (scenes/ui/run_breakdown.gd).
func damage_report() -> Dictionary:
	return _report


func _report_entry(id: String) -> Array:
	if not _report.has(id):
		_report[id] = [0, 0.0]
	return _report[id]
