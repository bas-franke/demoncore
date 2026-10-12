class_name AbilityCaster
extends Node3D
## Runtime instance of one owned ability. Lives under the player's "Abilities" node (so it moves
## with the demon), counts down its cooldown and casts automatically. The behaviour itself lives
## in an AbilityKind (scripts/abilities/kinds/kind_*.gd, picked by AbilityDef.kind through
## AbilityKinds); this node owns the numbers: stats per rank, cooldown, damage scaling, costs.
##
## Damage scales with the player's might, Abilities boons (damage_mult), and optional params:
## soul_scale (per Soul), wrath_scale (per Wrath stack), greed_scale (per Ichor held).
## Costs: hp_cost (fraction of max HP, blood magic) and params.ichor_cost (run currency, Greed).

## When a cast finds nothing to do, retry after this long instead of every frame.
const RETRY := 0.15
## Blood magic never takes the demon below this fraction of max HP.
const HP_FLOOR := 0.25
## Unleash (manual cast on the ability key): allowed once this much of the cooldown has passed,
## and the early cast hits this much harder.
const UNLEASH_READY := 0.5
const UNLEASH_POWER := 1.5

var def: AbilityDef
var level := 1
var player: Player
var stats := {}  # String -> Variant, AbilityDef.stats_at(level)
var cooldown_left := 0.4
var kind: AbilityKind

var _empower := 1.0


func setup(p_def: AbilityDef, p_player: Player) -> void:
	def = p_def
	player = p_player
	name = String(def.id)
	kind = AbilityKinds.create(def.kind, self)


func _ready() -> void:
	_recompute()


func _exit_tree() -> void:
	if kind:
		kind.cleanup()


func _physics_process(delta: float) -> void:
	if player == null or player.is_dead or kind == null:
		return
	kind.tick(delta)
	cooldown_left -= delta
	if cooldown_left > 0.0:
		return
	if not _can_pay():
		cooldown_left = RETRY * 4.0
		return
	if kind.cast():
		_pay()
		cooldown_left = get_cooldown()
		Abilities.ability_cast.emit(def.id)
	else:
		cooldown_left = RETRY


## Manual cast from the ability key: fires early (once UNLEASH_READY of the cooldown has passed)
## with UNLEASH_POWER damage, then restarts the full cooldown. Persistent kinds (aura, orbit)
## can't be unleashed. Returns true if it fired.
func unleash() -> bool:
	if player == null or player.is_dead or kind == null or not kind.can_unleash():
		return false
	if cooldown_ratio() < UNLEASH_READY or not _can_pay():
		return false
	_empower = UNLEASH_POWER
	var fired := kind.cast()
	_empower = 1.0
	if fired:
		_pay()
		cooldown_left = get_cooldown()
		InfernalFx.flash_sphere(player.global_position + Vector3(0.0, 0.8, 0.0), def.color, 1.1, 0.2, 3.0)
		Abilities.ability_cast.emit(def.id)
	return fired


# ---------------------------------------------------------------- stats

func level_up() -> void:
	if is_max_level():
		return
	level += 1
	_recompute()


func is_max_level() -> bool:
	return level >= def.max_level()


func p(key: String, default: float = 0.0) -> float:
	return float(stats.get(key, default))


func get_cooldown() -> float:
	return maxf(def.cooldown * p("cooldown_mult", 1.0) * player.cooldown * Abilities.cooldown_mult(def), 0.12)


## 0..1 progress of the current cooldown (1 = ready), for the HUD.
func cooldown_ratio() -> float:
	return 1.0 - clampf(cooldown_left / maxf(get_cooldown(), 0.01), 0.0, 1.0)


func get_damage() -> float:
	var scl := 1.0 + Abilities.souls * p("soul_scale") + Abilities.wrath * p("wrath_scale") \
		+ Abilities.greed() * p("greed_scale")
	return def.damage * p("damage_mult", 1.0) * player.might * Abilities.damage_mult(def) * scl * _empower


func get_count() -> int:
	var n := int(p("count", 1.0)) + Abilities.count_bonus(def)
	if p("per_souls") > 0.0:
		n += int(Abilities.souls / maxf(p("per_souls"), 1.0))
	return maxi(n, 1)


## Hit source for AbilityCombat.hit (see its doc).
func source() -> Dictionary:
	return {
		"tags": def.tags, "status": def.status, "on_hit": def.on_hit, "on_kill": def.on_kill,
		"status_stacks": int(p("status_stacks")), "crit": p("crit"), "crit_mult": p("crit_mult", 2.0),
		"knockback": p("knockback"), "heal_bonus": p("heal_bonus"), "color": def.color,
		"origin": player.global_position, "id": def.id,
	}


## Runs the ability's "after" effects (lingering craters etc.) and Magma Forge at `at`.
func run_after(at: Vector3) -> void:
	var ctx := {"pos": at, "damage": get_damage(), "src": source()}
	for fx: Dictionary in def.after:
		AbilityCombat.run_effect(fx, ctx)
	if def.has_tag("brute") and Abilities.has_synergy(&"magma_forge"):
		var sp: Dictionary = Abilities.synergy_params(&"magma_forge")
		AbilityZone.spawn(at, float(sp.get("radius", 1.6)) * Abilities.area_mult(),
			float(sp.get("duration", 2.5)) * Abilities.duration_mult(), 0.5,
			get_damage() * float(sp.get("damage", 0.12)),
			AbilityCombat.child_source(source(), [{"id": "burn", "stacks": 1}]), Art.HELLFIRE, &"pool")


func _recompute() -> void:
	stats = def.stats_at(level)
	if kind and is_inside_tree():
		kind.rebuild()


# ---------------------------------------------------------------- costs

func _hp_cost() -> float:
	return def.hp_cost * player.max_hp * Abilities.hp_cost_mult()


func _ichor_cost() -> int:
	return int(p("ichor_cost"))


func _can_pay() -> bool:
	if def.hp_cost > 0.0 and player.hp - _hp_cost() < player.max_hp * HP_FLOOR:
		return false
	return _ichor_cost() <= 0 or Abilities.ichor() >= _ichor_cost()


func _pay() -> void:
	if _ichor_cost() > 0:
		Abilities.spend_ichor(_ichor_cost())
	if def.hp_cost <= 0.0:
		return
	var cost := _hp_cost()
	if not Game.godmode:
		player.hp -= cost
	InfernalFx.burst(player.global_position + Vector3(0.0, 1.0, 0.0), Art.BLOOD, 8, 2.0, 0.8)
	Abilities.on_life_spent(cost)
