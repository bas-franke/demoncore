extends AbilityKind
## "hex": marks up to get_count() enemies within params.range with a sigil, a thin bolt and the
## ability's hit (statuses do the work). params.prefer "strongest" picks the healthiest; otherwise
## foes not yet suffering the first status, nearest first.


func cast() -> bool:
	var foes := AbilityCombat.enemies_in_radius(player.global_position, p("range", 9.0))
	if foes.is_empty():
		return false
	if str(caster.stats.get("prefer", "")) == "strongest":
		foes.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.hp > b.hp)
	else:
		var first_id := StringName(str((def.status[0] as Dictionary).get("id", ""))) if not def.status.is_empty() else &""
		var here := player.global_position
		foes.sort_custom(func(a: Enemy, b: Enemy) -> bool:
			var ha := StatusHost.of(a)
			var hb := StatusHost.of(b)
			var ma := ha != null and ha.has(first_id)
			var mb := hb != null and hb.has(first_id)
			if ma != mb:
				return mb
			return a.global_position.distance_squared_to(here) < b.global_position.distance_squared_to(here))
	var src := source()
	for i in mini(count(), foes.size()):
		var e := foes[i]
		AbilityFx.sigil(e.global_position + Vector3(0.0, 1.6 * (e.data.size if e.data else 1.0), 0.0), def.color)
		AbilityFx.lightning(origin(), e.global_position + Vector3(0.0, 0.8, 0.0), def.color, 0.15, 0.03)
		AbilityCombat.hit(e, damage(), src)
	sfx(&"cast", -6.0)
	return true
