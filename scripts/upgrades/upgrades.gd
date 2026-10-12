class_name Upgrades
## Builds the random level-up choices from the player's weapon and passive pools.
## Each option's title is the plain name; the rank it rises to is stored as meta &"rank"
## (a Roman numeral string) for the level-up cards.

## Kept for callers of Upgrades.roman(); the shared implementation lives in TextFormat.
static func roman(n: int) -> String:
	return TextFormat.roman(n)


static func roll(player: Player, count: int) -> Array[UpgradeOption]:
	var pool: Array[UpgradeOption] = []

	for w in player.weapons:
		if not w.is_max_level():
			var up := UpgradeOption.new(w.display_name, w.get_next_level_description(), w.color,
				w.level_up)
			up.icon = w.icon
			up.set_meta(&"rank", roman(w.level + 1))
			pool.append(up)

	if player.weapons.size() < player.max_weapons:
		for scene in player.weapon_pool:
			if not player.has_weapon(scene):
				var t := player.get_weapon_template(scene)
				var fresh := UpgradeOption.new(t.display_name, t.description, t.color,
					player.add_weapon.bind(scene))
				fresh.icon = t.icon
				fresh.is_new = true
				fresh.set_meta(&"rank", roman(1))
				pool.append(fresh)

	for pd in player.passive_pool:
		var lv: int = player.passive_levels.get(pd, 0)
		if lv < pd.max_level:
			var passive := UpgradeOption.new(pd.display_name, pd.description, pd.color,
				player.add_passive.bind(pd))
			passive.icon = pd.icon
			passive.set_meta(&"rank", roman(lv + 1))
			_roll_rarity(passive, player, pd)
			pool.append(passive)

	# Abilities: new abilities, ability ranks and ability boons (autoload/abilities.gd).
	Abilities.extend_pool(player, pool)

	# Progression: options banished this run never come back.
	var kept: Array[UpgradeOption] = []
	for o in pool:
		if not Progression.is_banished(o.title):
			kept.append(o)
	pool = kept
	pool.shuffle()
	var picks: Array[UpgradeOption] = []
	for i in mini(count, pool.size()):
		picks.append(pool[i])
	Abilities.ensure_choice(player, picks, pool)
	if picks.is_empty():
		var blood := UpgradeOption.new("Taste of Blood", "Recover 30 HP.", Color(0.62, 0.1, 0.08),
			player.heal.bind(30.0))
		blood.icon = "∇"
		picks.append(blood)
	return picks


## Progression rarity for passive boons: rolls a tier with the run's luck; above Common the
## pick adds the passive's amount once more, scaled by Rarity.BOON_POWER (e.g. Rare = x1.6 total).
## The tier is stored as meta &"rarity" (int, Rarity.COMMON..LEGENDARY) for the cards.
## Integer stats (projectile counts) are left Common: fractional extras would be truncated.
static func _roll_rarity(option: UpgradeOption, player: Player, pd: PassiveData) -> void:
	var tier: int = Rarity.COMMON
	if typeof(player.get(pd.stat)) == TYPE_FLOAT:
		tier = Rarity.roll(Progression.get_luck())
	option.set_meta(&"rarity", tier)
	if tier == Rarity.COMMON:
		return
	var extra: float = pd.amount_per_level * (Rarity.BOON_POWER[tier] - 1.0)
	option.apply = func() -> void:
		player.add_passive(pd)
		player.apply_stat(pd.stat, extra)
	option.description += "\n%s: x%s potency" % [Rarity.display_name(tier), str(Rarity.BOON_POWER[tier])]
