class_name AbilityCombat
## Stateless damage pipeline for abilities: every ability hit, DoT tick, explosion and chain goes
## through hit(), which applies amplifiers (curses, shock, synergies, crits, execute), statuses and
## on-hit / on-kill trigger effects. Run state (mods, synergies, souls) lives on the `Abilities`
## autoload.
##
## A hit "source" is a Dictionary:
##   tags: PackedStringArray     ability tags (fire, blood, summon, ...) for amps and synergies
##   status: Array               [{"id": "burn", "stacks": 2}, ...] applied on a surviving hit
##   status_stacks: int          extra stacks added to every status above
##   on_hit / on_kill: Array     trigger effects (see run_effect)
##   crit, crit_mult: float      base crit chance / multiplier
##   knockback: float, origin: Vector3   push strength away from origin
##   heal_bonus: float           added to "heal" effects
##   dot: bool                   DoT tick (no crits, no on-hit triggers)
##   depth: int                  trigger recursion depth (capped by MAX_DEPTH)
##   color: Color                for trigger visuals
##
## Effects ({"do": ...}, optional "chance", "if_status", "if_tag"):
##   status {id, stacks} · explode {radius, damage, flat?, status?, color?} · chain {jumps, range,
##   damage} · heal {amount} · soul {stacks} · zone {radius, duration, damage, status?} ·
##   spread {status, count, range, stacks} · empower {might, duration} · ichor {amount} (drops
##   Ichor) · wrath {stacks} · raise (a thrall rises) · decoy (a mirror decoy appears)

const MAX_DEPTH := 2

## > 0 while an ability hit is calling Enemy.take_damage (so Game.enemy_struck listeners can tell
## weapon hits from ability hits).
static var in_hit := 0
## Tint of the little flash that marks a critical strike.
const CRIT_FLASH := Color(1.0, 0.95, 0.8)


## Live enemies within `radius` of `center` on the ground plane.
static func enemies_in_radius(center: Vector3, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return out
	for node in Perf.enemies():
		var e := node as Enemy
		if e == null or e.is_dying:
			continue
		var d := e.global_position - center
		d.y = 0.0
		# Big enemies are easier to catch: pad the radius by their size.
		var pad := 0.35 * e.data.size if e.data else 0.35
		if d.length_squared() <= (radius + pad) * (radius + pad):
			out.append(e)
	return out


## Enemies within `half_width` of the segment a -> b (ground plane).
static func enemies_on_segment(a: Vector3, b: Vector3, half_width: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var len2 := maxf(ab.length_squared(), 0.0001)
	for node in Perf.enemies():
		var e := node as Enemy
		if e == null or e.is_dying:
			continue
		var ap := Vector2(e.global_position.x - a.x, e.global_position.z - a.z)
		var t := clampf(ap.dot(ab) / len2, 0.0, 1.0)
		var pad := 0.35 * e.data.size if e.data else 0.35
		if (ap - ab * t).length() <= half_width + pad:
			out.append(e)
	return out


## Deals `amount` to `enemy` from `src`. Returns true if the hit killed it.
static func hit(enemy: Enemy, amount: float, src: Dictionary) -> bool:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dying or amount <= 0.0:
		return false
	var tags: PackedStringArray = src.get("tags", PackedStringArray())
	var host := StatusHost.of(enemy)
	var dot: bool = src.get("dot", false)
	var amp := 1.0 + Abilities.damage_amp_against(enemy, host, tags, dot)
	var crit := false
	if not dot:
		var chance := float(src.get("crit", 0.0)) + Abilities.crit_chance(tags, host)
		if chance > 0.0 and randf() < chance:
			crit = true
			amp *= float(src.get("crit_mult", 2.0)) + Abilities.mod("crit_mult")
	var final := amount * amp
	var kb := Vector3.ZERO
	var kbs := float(src.get("knockback", 0.0)) * (1.0 + Abilities.mod("knockback"))
	if kbs > 0.0 and src.has("origin"):
		kb = Targeting.flat_dir(src["origin"], enemy.global_position) * kbs
	# Snapshot statuses before the hit: a killing blow still counts what the foe was suffering.
	var had := host.snapshot() if host else {}
	var pos := enemy.global_position
	var hp_before := enemy.hp
	in_hit += 1
	enemy.take_damage(final, kb)
	in_hit -= 1
	Abilities.damage_dealt.emit(final, tags)
	# Always tallied (cheap): the end screen shows damage per source (UI role). Effective damage
	# (overkill excluded), so one-shot nukes don't look stronger than they are.
	Abilities.report_damage("dot" if dot else str(src.get("id", "effect")), clampf(hp_before - enemy.hp, 0.0, final))
	if crit:
		InfernalFx.flash_sphere(pos + Vector3(0.0, 0.9, 0.0), CRIT_FLASH, 0.45, 0.12, 3.0)
	var killed := enemy.is_dying
	var depth: int = src.get("depth", 0)
	var ctx := {"pos": pos, "enemy": enemy, "damage": final, "src": src, "had": had, "killed": killed}
	if not killed:
		var extra: int = src.get("status_stacks", 0)
		for s: Dictionary in src.get("status", []):
			apply_status(enemy, StringName(str(s.get("id", ""))), int(s.get("stacks", 1)) + extra)
		for s: Dictionary in Abilities.synergy_statuses(tags):
			apply_status(enemy, StringName(str(s["id"])), int(s["stacks"]))
		if not dot and depth < MAX_DEPTH:
			for fx: Dictionary in src.get("on_hit", []):
				run_effect(fx, ctx)
			for fx: Dictionary in Abilities.global_on_hit:
				run_effect(fx, ctx)
			for fx: Dictionary in Abilities.synergy_effects(tags, false):
				run_effect(fx, ctx)
	else:
		Abilities.notify_ability_kill(pos, tags, had)
		if depth < MAX_DEPTH:
			for fx: Dictionary in src.get("on_kill", []):
				run_effect(fx, ctx)
			for fx: Dictionary in Abilities.global_on_kill:
				run_effect(fx, ctx)
			for fx: Dictionary in Abilities.synergy_effects(tags, true):
				run_effect(fx, ctx)
	return killed


static func apply_status(enemy: Enemy, id: StringName, stacks: int) -> void:
	if stacks <= 0 or not Abilities.statuses.has(id) or enemy == null or enemy.is_dying:
		return
	StatusHost.ensure(enemy).add(id, stacks)


## Runs one trigger effect. ctx: pos, enemy, damage, src, had (status snapshot), killed.
static func run_effect(fx: Dictionary, ctx: Dictionary) -> void:
	if fx.has("chance") and randf() >= float(fx["chance"]):
		return
	var src: Dictionary = ctx.get("src", {})
	var tags: PackedStringArray = src.get("tags", PackedStringArray())
	if fx.has("if_status") and not (ctx.get("had", {}) as Dictionary).has(StringName(str(fx["if_status"]))):
		return
	if fx.has("if_tag") and not tags.has(str(fx["if_tag"])):
		return
	var pos: Vector3 = ctx.get("pos", Vector3.ZERO)
	var color := Color.from_string(str(fx.get("color", "")), src.get("color", Art.EMBER))
	# "status" is a list of {id, stacks} for damaging effects ("spread" uses it as a plain id).
	var fx_status: Variant = fx.get("status", [])
	var sub := child_source(src, fx_status if fx_status is Array else [])
	match str(fx.get("do", "")):
		"status":
			var e := ctx.get("enemy") as Enemy
			if is_instance_valid(e) and not e.is_dying:
				apply_status(e, StringName(str(fx.get("id", ""))), int(fx.get("stacks", 1)))
		"explode":
			var dmg := float(fx.get("damage", 0.5))
			if not fx.get("flat", false):
				dmg *= float(ctx.get("damage", 0.0))
			else:
				dmg *= Abilities.player_might()
			explode(pos, float(fx.get("radius", 2.0)) * Abilities.area_mult(), dmg, sub, color)
		"chain":
			var dmg := float(fx.get("damage", 0.5)) * float(ctx.get("damage", 0.0))
			chain(pos, ctx.get("enemy") as Enemy, int(fx.get("jumps", 2)), float(fx.get("range", 4.5)), dmg, sub, color)
		"heal":
			Abilities.heal_player(float(fx.get("amount", 1.0)) + float(src.get("heal_bonus", 0.0)))
		"soul":
			Abilities.add_souls(int(fx.get("stacks", 1)))
		"zone":
			var dmg := float(fx.get("damage", 0.1)) * maxf(float(ctx.get("damage", 0.0)), 10.0)
			AbilityZone.spawn(pos, float(fx.get("radius", 1.5)) * Abilities.area_mult(),
				float(fx.get("duration", 2.0)) * Abilities.duration_mult(), 0.5, dmg, sub, color, &"pool")
		"empower":
			Abilities.empower(float(fx.get("might", 0.02)), float(fx.get("duration", 6.0)))
		"ichor":
			Abilities.drop_ichor(pos, int(fx.get("amount", 1)))
		"wrath":
			Abilities.add_wrath(float(fx.get("stacks", 1)))
		"raise":
			Abilities.raise_thrall(pos)
		"decoy":
			Abilities.spawn_decoy(pos)
		"spread":
			spread(pos, StringName(str(fx.get("status", ""))), int(fx.get("count", 2)),
				float(fx.get("range", 3.0)), int(fx.get("stacks", 1)), ctx.get("enemy") as Enemy)


## Source for damage caused by a trigger: same tags and color, one level deeper, no triggers.
static func child_source(src: Dictionary, status: Array = []) -> Dictionary:
	return {
		"tags": src.get("tags", PackedStringArray()),
		"status": status,
		"color": src.get("color", Art.EMBER),
		"depth": int(src.get("depth", 0)) + 1,
		"origin": src.get("origin", Vector3.ZERO),
	}


## Damages everything in `radius` around `at`, with a flash, ring and embers.
static func explode(at: Vector3, radius: float, damage: float, src: Dictionary, color: Color) -> void:
	AbilityFx.ring(at, radius, color, 0.35)
	InfernalFx.flash_sphere(at + Vector3(0.0, 0.4, 0.0), color, radius * 0.45, 0.2, 2.5)
	InfernalFx.burst(at + Vector3(0.0, 0.3, 0.0), color, 12, radius * 2.0, 1.0)
	var s := src.duplicate()
	s["origin"] = at
	s["knockback"] = 3.0
	for e in enemies_in_radius(at, radius):
		hit(e, damage, s)


## Lightning that leaps from `from` (optionally starting at `first`) through up to `jumps` + 1
## enemies, each within `jump_range` of the last. Returns the enemies struck.
static func chain(from: Vector3, first: Enemy, jumps: int, jump_range: float, damage: float,
		src: Dictionary, color: Color) -> Array[Enemy]:
	var struck: Array[Enemy] = []
	var seen := {}
	if is_instance_valid(first):
		seen[first] = true  # the source enemy itself is not struck again
	var at := from
	var target: Enemy = null
	for i in jumps + 1:
		target = _nearest_unseen(at, jump_range, seen)
		if target == null:
			break
		seen[target] = true
		var to := target.global_position + Vector3(0.0, 0.9, 0.0)
		AbilityFx.lightning(at + Vector3(0.0, 0.9, 0.0), to, color)
		at = target.global_position
		struck.append(target)
		hit(target, damage, src)
	return struck


static func _nearest_unseen(at: Vector3, max_range: float, seen: Dictionary) -> Enemy:
	var best: Enemy = null
	var best_d := max_range * max_range
	for e in enemies_in_radius(at, max_range):
		if seen.has(e):
			continue
		var d := e.global_position.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = e
	return best


## Gives `stacks` of `status` to up to `count` enemies near `at` (excluding `except`).
static func spread(at: Vector3, status: StringName, count: int, rng: float, stacks: int, except: Enemy) -> void:
	var n := 0
	for e in enemies_in_radius(at, rng):
		if e == except:
			continue
		apply_status(e, status, stacks)
		AbilityFx.lightning(at + Vector3(0.0, 0.6, 0.0), e.global_position + Vector3(0.0, 0.6, 0.0),
			Abilities.status_color(status), 0.18, 0.04)
		n += 1
		if n >= count:
			break
