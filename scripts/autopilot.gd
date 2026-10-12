class_name Autopilot
extends RefCounted
## Dev bot brain for --autopilot runs (core-gameplay role, docs/team/gameplay.md). Static and
## stateless apart from a small per-player memory, so the Player, PlayerDash and the level-up menu
## can all ask it questions:
##   Autopilot.move_input(player) -> Vector2      steering (replaces the move keys)
##   Autopilot.wants_dash(player) -> bool         dash out of telegraphs / crowds / at low HP
##   Autopilot.pick_upgrade(options) -> int       level-up card index (abilities first)
## Goal: survive like a cautious player and exercise many systems (abilities, dash, pickups,
## objectives), not to play perfectly.

## How far the bot looks for threats / pickups.
const THREAT_RANGE := 5.5
const GEM_RANGE := 14.0
const OBJECTIVE_RANGE := 40.0
## Dash when this many enemies are within CROWD_RADIUS.
const CROWD_COUNT := 4
const CROWD_RADIUS := 2.2
## Below this weapon reach (m) the kit counts as melee (Cleave ~2.6, Wailing Souls ~2.6).
const MELEE_REACH := 4.0


## Longest reach among the demon's weapons (duck-typed on their range exports, scaled by area).
## Ranged weapons (bolts, chains, scythes) return their targeting range; no weapon -> 8.
static func weapon_reach(player: Player) -> float:
	var best := 0.0
	for w in player.weapons:
		if not is_instance_valid(w):
			continue
		var r := 0.0
		if &"target_range" in w:
			r = float(w.get(&"target_range"))
		elif &"base_range" in w:
			r = float(w.get(&"base_range")) * w.get_area()
		elif &"base_reach" in w:
			r = float(w.get(&"base_reach")) * w.get_area()
		elif &"base_radius" in w:
			r = float(w.get(&"base_radius")) * w.get_area()
		else:
			r = 8.0
		best = maxf(best, r)
	return best if best > 0.0 else 8.0


static func move_input(player: Player) -> Vector2:
	var tree := player.get_tree()
	var pos := player.global_position
	var t := Game.elapsed
	# Idle wander so it never parks.
	var v := Vector2(cos(t * 0.6), sin(t * 0.9)) * 0.35

	# 1. Pickups: nearest gem / ichor / chalice (chalice preferred when hurt).
	var hurt := player.hp < player.max_hp * 0.6
	var best := GEM_RANGE
	var target := Vector3.INF
	for group: StringName in [&"gems", &"currency_drops"]:
		for n in tree.get_nodes_in_group(group):
			var g := n as Node3D
			var d := g.global_position.distance_to(pos)
			if d < best:
				best = d
				target = g.global_position
	if hurt:
		for n in tree.get_nodes_in_group(&"pickups"):
			var c := n as Node3D
			if c and c.global_position.distance_to(pos) < GEM_RANGE * 1.5:
				target = c.global_position
				break
	# 2. Otherwise drift toward an open objective now and then (exercises objectives).
	if target == Vector3.INF and int(t / 20.0) % 2 == 0:
		var od := 1e9
		for n in tree.get_nodes_in_group(&"objectives"):
			var o := n as Node3D
			if o == null:
				continue
			var d := o.global_position.distance_to(pos)
			if d < OBJECTIVE_RANGE and d < od and d > 1.0:
				od = d
				target = o.global_position
	# 2b. Melee kits (short weapon reach) close in on the nearest angel while healthy enough,
	# instead of kiting them out of reach (QA: Vharok / Iscariel killed nothing).
	var reach := weapon_reach(player)
	var melee := reach < MELEE_REACH
	if melee and target == Vector3.INF and player.hp > player.max_hp * 0.4:
		var prey := Targeting.nearest_enemy(tree, pos, 16.0)
		if prey and prey.global_position.distance_to(pos) > reach * 0.7:
			target = prey.global_position
	if target != Vector3.INF:
		var to := target - pos
		v = Vector2(to.x, to.z).normalized()

	# 3. Threats: push away from nearby enemies, weighted by closeness. The comfort distance follows
	# the kit's reach: ranged kits keep THREAT_RANGE, melee kits stay just inside their reach.
	var threat_range := THREAT_RANGE if not melee else clampf(reach * 0.55, 1.2, THREAT_RANGE)
	var push := Vector2.ZERO
	for e in Targeting.nearest_enemies(tree, pos, 8, threat_range):
		var away := pos - e.global_position
		var d := maxf(away.length(), 0.3)
		push += Vector2(away.x, away.z) / d * (threat_range - d) / threat_range
	v += push * (2.2 if not melee else 1.4)

	# 4. Telegraphs, boss hazards and incoming shots (scripts/danger.gd): step out of them.
	var threat := Danger.threat_at(tree, pos, 0.8)
	if threat != Vector3.ZERO:
		v += Vector2(threat.x, threat.z) * 3.0
	return v.limit_length(1.0)


static func wants_dash(player: Player) -> bool:
	if player.dash == null or player.dash.charges <= 0 or player.dash.is_dashing():
		return false
	var pos := player.global_position
	var tree := player.get_tree()
	# Only telegraphs / hazards (not passing shots: sidestepping handles those).
	for n in tree.get_nodes_in_group(&"danger_zones"):
		var z := n as HolyTelegraph
		if z and z.contains(pos, 0.3):
			return true
	for n in tree.get_nodes_in_group(&"boss_hazards"):
		if not (&"velocity" in n):  # orbs are sidestepped by steering instead
			if Danger._push(n as Node3D, pos, 0.2) != Vector3.ZERO:
				return true
	var close := Targeting.nearest_enemies(tree, pos, CROWD_COUNT, CROWD_RADIUS)
	if close.size() >= CROWD_COUNT:
		return true
	# Low HP and something is touching us: bail out.
	return player.hp < player.max_hp * 0.35 and not close.is_empty() and randf() < 0.2


## Level-up choice: new ability > ability rank > new weapon > ability boon > anything, with a
## little randomness so runs differ.
static func pick_upgrade(options: Array) -> int:
	var best := 0
	var best_score := -1.0
	for i in options.size():
		var o: Object = options[i]
		var score := randf() * 0.5
		match String(o.get_meta(&"ability_option", "")):
			"new":
				score += 4.0
			"rank":
				score += 3.0
			"boon":
				score += 1.5
		if bool(o.get(&"is_new")):
			score += 2.0
		if score > best_score:
			best_score = score
			best = i
	return best
