class_name AbilityDev
## Dev / balance helpers for the Abilities autoload (`ab`): command-line grants and the bench.
##   --abilities=id,id | all  --boons=id,id  --souls=N  --evolve=evo_id  --ability-rank=N
##   --ability-bench   unarmed demon, no level-ups, 100k HP (still takes hits, so Wrath and blood
##                     costs behave as in play); see tools/ability_bench.sh
##   --ability-report  prints casts and effective damage per ability every 5 s


## Applied when a run starts (after queued grants).
static func apply(ab: Node, p: Player, bench: bool) -> void:
	if bench:
		p.xp_gain = 0.0
		p.max_hp = 100000.0
		p.hp = p.max_hp
		for w in p.weapons:
			w.queue_free()
		p.weapons.clear()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--abilities=all":
			ab.max_abilities = ab.def_order.size()
			for id: StringName in ab.def_order:
				ab.grant(id)
		elif arg.begins_with("--abilities="):
			var ids := arg.substr(12).split(",", false)
			ab.max_abilities = maxi(ab.max_abilities, ids.size())
			for id in ids:
				ab.grant(StringName(id))
		elif arg.begins_with("--boons="):
			for id in arg.substr(8).split(",", false):
				ab.take_boon(StringName(id))
		elif arg.begins_with("--souls="):
			ab.add_souls(arg.substr(8).to_int())
	for arg in args:
		if arg.begins_with("--evolve="):
			ab.evolve(StringName(arg.substr(9)))
		elif arg.begins_with("--ability-rank="):
			for c: AbilityCaster in ab.casters.values():
				while c.level < arg.substr(15).to_int() and not c.is_max_level():
					c.level_up()


static func print_report(ab: Node) -> void:
	var report: Dictionary = ab.damage_report()
	var total := 0.0
	var parts: Array[String] = []
	var ids := report.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return float(report[a][1]) > float(report[b][1]))
	for id: String in ids:
		total += float(report[id][1])
		parts.append("%s:%d/%.0f" % [id, int(report[id][0]), float(report[id][1])])
	print("[abilities] t=%.0f kills=%d dmg=%.0f wrath=%.0f taken=%.0f souls=%d synergies=%d | %s" % [
		Game.elapsed, Game.kills, total, ab.wrath, ab.damage_taken, ab.souls, ab.syn.active.size(), " ".join(parts)])
