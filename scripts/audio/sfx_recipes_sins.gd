extends RefCounted
## Round-3 procedural recipes for the Sfx autoload (owner: sfx role, docs/team/sfx.md):
## the Sin schools (wrath, greed, envy, pride, gluttony), gadgets (decoy, turret, mine, whip),
## ability evolutions, the synergy sting, relic pickups by rarity and surface footsteps
## (snow, wood, water, ash). Runs on Sfx's synthesis worker thread like sfx_recipes.gd.
##
## The schools and gadgets are played like elements: Sfx.play_element(&"greed", &"cast" | &"hit").

# Mirrors of Sfx's constants (kept local to avoid a cyclic preload).
const W_SINE := 0
const W_TRI := 1
const W_SAW := 2
const W_SOFTSQ := 3
const W_PULSE := 4
const F_LOW := 0
const F_BAND := 1
const F_HIGH := 2
const V_AH := 0
const V_OH := 1
const V_OO := 2
const V_EH := 3

## Extra "elements" (tags) with <name>_cast / <name>_hit sounds.
const SCHOOLS := [&"wrath", &"greed", &"envy", &"pride", &"gluttony",
		&"decoy", &"turret", &"mine", &"whip"]
const SCHOOL_ALIASES := {
	&"rage": &"wrath", &"avarice": &"greed", &"gold": &"greed", &"jealousy": &"envy",
	&"vanity": &"pride", &"hunger": &"gluttony", &"devour": &"gluttony", &"clone": &"decoy",
	&"lure": &"decoy", &"sentry": &"turret", &"trap": &"mine", &"lash": &"whip",
	# Tags used by data/abilities/abilities.json (round 2): Illusion and Infernal Machinery.
	&"illusion": &"decoy", &"mirror": &"decoy", &"machine": &"turret", &"construct": &"turret",
}
## When an ability carries several school tags, the more specific one wins (lower = first):
## a "machine" + "trap" ability is a mine, not a turret.
const TAG_PRIORITY := {&"trap": 0, &"mine": 0, &"whip": 1, &"lash": 1}
const RARITIES := [&"common", &"uncommon", &"rare", &"epic", &"legendary"]
const SURFACES := [&"snow", &"wood", &"water", &"ash"]

const VARIANTS := {
	&"step_snow": [&"step_snow_a", &"step_snow_b", &"step_snow_c"],
	&"step_wood": [&"step_wood_a", &"step_wood_b", &"step_wood_c"],
	&"step_water": [&"step_water_a", &"step_water_b", &"step_water_c"],
	&"step_ash": [&"step_ash_a", &"step_ash_b", &"step_ash_c"],
}
const ALIASES := {&"evolution": &"evolve", &"synergy_sting": &"synergy", &"gilded": &"gilded_drop"}
## Summon cast sound per AbilityMinion style (kind_summon.gd); other styles use necro_cast.
const SUMMON_SOUNDS := {
	&"hellhound": &"summon_hellhound", &"imp": &"summon_imps", &"hell_brute": &"summon_brute",
	&"succubus": &"summon_succubus",
}
const MAX_VOICES := {
	&"evolve": 1, &"synergy": 1, &"relic_common": 1, &"relic_uncommon": 1, &"relic_rare": 1,
	&"relic_epic": 1, &"relic_legendary": 1, &"step_snow": 2, &"step_wood": 2, &"step_water": 2,
	&"step_ash": 2, &"turret_hit": 4, &"mine_hit": 3, &"whip_cast": 2, &"whip_hit": 3,
	&"greed_hit": 4, &"summon_hellhound": 1, &"summon_imps": 1, &"summon_brute": 1,
	&"summon_succubus": 1, &"devour": 2, &"reflect": 2, &"gilded_drop": 3,
}
const MIN_GAP := {
	&"evolve": 1.0, &"synergy": 0.6, &"relic_common": 0.2, &"relic_uncommon": 0.2,
	&"relic_rare": 0.3, &"relic_epic": 0.5, &"relic_legendary": 1.0, &"step_snow": 0.12,
	&"step_wood": 0.12, &"step_water": 0.12, &"step_ash": 0.12, &"turret_hit": 0.05,
	&"mine_hit": 0.06, &"mine_cast": 0.1, &"whip_cast": 0.08, &"summon_hellhound": 0.5,
	&"summon_imps": 0.5, &"summon_brute": 0.6, &"summon_succubus": 0.5, &"devour": 0.1,
	&"reflect": 0.08, &"gilded_drop": 0.05,
}


static func build(s: Object) -> Dictionary:
	var d := {}
	var rng: RandomNumberGenerator = s._rng
	var keep := rng.state
	rng.seed = 0x51E5
	d[&"wrath_cast"] = _wrath_cast(s)
	d[&"wrath_hit"] = _wrath_hit(s)
	d[&"greed_cast"] = _greed_cast(s)
	d[&"greed_hit"] = _greed_hit(s)
	d[&"envy_cast"] = _envy_cast(s)
	d[&"envy_hit"] = _envy_hit(s)
	d[&"pride_cast"] = _pride_cast(s)
	d[&"pride_hit"] = _pride_hit(s)
	d[&"gluttony_cast"] = _gluttony_cast(s)
	d[&"gluttony_hit"] = _gluttony_hit(s)
	d[&"decoy_cast"] = _decoy_cast(s)
	d[&"decoy_hit"] = _decoy_hit(s)
	d[&"turret_cast"] = _turret_cast(s)
	d[&"turret_hit"] = _turret_hit(s)
	d[&"mine_cast"] = _mine_cast(s)
	d[&"mine_hit"] = _mine_hit(s)
	d[&"whip_cast"] = _whip_cast(s)
	d[&"whip_hit"] = _whip_hit(s)
	d[&"synergy"] = _synergy(s)
	for i in RARITIES.size():
		d[StringName("relic_%s" % RARITIES[i])] = _relic(s, i)
	for i in 3:
		d[VARIANTS[&"step_snow"][i]] = _step_snow(s, i)
		d[VARIANTS[&"step_wood"][i]] = _step_wood(s, i)
		d[VARIANTS[&"step_water"][i]] = _step_water(s, i)
		d[VARIANTS[&"step_ash"][i]] = _step_ash(s, i)
	d[&"evolve"] = _evolve(s)
	d[&"summon_hellhound"] = _summon_hellhound(s)
	d[&"summon_imps"] = _summon_imps(s)
	d[&"summon_brute"] = _summon_brute(s)
	d[&"summon_succubus"] = _summon_succubus(s)
	d[&"devour"] = _devour(s)
	d[&"reflect"] = _reflect(s)
	d[&"gilded_drop"] = _gilded_drop(s)
	rng.state = keep
	return d


static func _hz(m: int) -> float:
	return 440.0 * pow(2.0, float(m - 69) / 12.0)


# ---------------------------------------------------------------- sins

static func _wrath_cast(s: Object) -> AudioStreamWAV:
	# Wrath: a bellowing rage-roar over a detonating fire burst.
	s._begin(0.9)
	s._meow(0.0, 0.6, 110.0, 150.0, 90.0, 0.9, 600.0, 820.0, 420.0, 0.0, 0.0, 38.0)
	s._tone(0.0, 0.5, 90.0, 35.0, 1.0, W_SINE, 0.002, 1.8)
	s._noise(0.0, 0.6, 0.9, 400.0, 1600.0, 0.9, F_LOW, 0.005, 1.8, 17.0, 0.4)
	s._crackle(0.0, 0.6, 0.6, 120.0)
	s._lowpass(3000.0)
	return s._finish(0.55)


static func _wrath_hit(s: Object) -> AudioStreamWAV:
	# A furious blow: overdriven thud and a crunch.
	s._begin(0.36)
	s._tone(0.0, 0.18, 140.0, 45.0, 1.0, W_SOFTSQ, 0.001, 2.4)
	s._noise(0.0, 0.14, 0.8, 1800.0, 400.0, 1.0, F_BAND, 0.001, 2.2)
	s._crackle(0.0, 0.2, 0.5, 200.0)
	return s._finish(0.52)


static func _greed_cast(s: Object) -> AudioStreamWAV:
	# Greed: a pouring cascade of coins over a covetous low chord.
	var rng: RandomNumberGenerator = s._rng
	s._begin(1.0)
	for i in 14:
		var f := rng.randf_range(1800.0, 3000.0)
		s._bell(i * 0.04 + rng.randf_range(0.0, 0.02), f, rng.randf_range(0.25, 0.55), 0.035, true)
	s._tone(0.0, 0.8, _hz(45), _hz(45), 0.3, W_TRI, 0.05, 1.5)
	s._tone(0.0, 0.8, _hz(48), _hz(48), 0.22, W_TRI, 0.05, 1.5)
	return s._finish(0.36)


static func _greed_hit(s: Object) -> AudioStreamWAV:
	# A gilded strike: a heavy coin-thunk and one bright clink.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.35)
	s._tone(0.0, 0.08, 220.0, 120.0, 0.7, W_SINE, 0.0008, 2.6)
	var f := rng.randf_range(2000.0, 2500.0)
	s._bell(0.0, f, 0.7, 0.05, true)
	s._bell(0.01, f * 1.34, 0.35, 0.035, true)
	return s._finish(0.4)


static func _envy_cast(s: Object) -> AudioStreamWAV:
	# Envy: a sour, wavering whisper choir, two detuned voices rubbing against each other.
	s._begin(0.9)
	s._noise(0.0, 0.8, 0.7, 900.0, 2200.0, 3.0, F_BAND, 0.15, 1.4, 6.0, 0.5)
	s._tone(0.0, 0.8, 392.0, 370.0, 0.3, W_SINE, 0.15, 1.4, 5.0, 0.02)
	s._tone(0.0, 0.8, 415.3, 392.0, 0.3, W_SINE, 0.15, 1.4, 6.5, 0.02)  # a semitone of spite
	s._lowpass(2800.0)
	return s._finish(0.34)


static func _envy_hit(s: Object) -> AudioStreamWAV:
	# A corroding sting: an acid sizzle with a hissed breath.
	s._begin(0.4)
	s._noise(0.0, 0.32, 0.8, 3200.0, 2200.0, 1.4, F_BAND, 0.002, 2.0, 40.0, 0.5)
	s._noise(0.02, 0.25, 0.4, 1200.0, 900.0, 3.0, F_BAND, 0.02, 1.8)
	s._tone(0.0, 0.07, 160.0, 90.0, 0.5, W_SINE, 0.001, 2.4)
	return s._finish(0.4)


static func _pride_cast(s: Object) -> AudioStreamWAV:
	# Pride: a vainglorious brass flourish ringing off a bell.
	s._begin(1.2)
	for m: int in [50, 57, 62, 66]:
		var f := _hz(m)
		s._tone(0.0, 0.25, f, f, 0.3, W_SAW, 0.01, 1.4, 5.0, 0.004)
		s._tone(0.22, 0.6, f * 1.335, f * 1.335, 0.3, W_SAW, 0.02, 1.6, 5.0, 0.004)  # up a fourth
	s._lowpass(2200.0)
	s._bell(0.22, 1174.7, 0.5, 0.25)
	s._reverb(0.25, 0.8, 0.45)
	return s._finish(0.45)


static func _pride_hit(s: Object) -> AudioStreamWAV:
	# A haughty blow: a bright gilded clang.
	s._begin(0.6)
	s._bell(0.0, 987.8, 0.8, 0.14, true)
	s._bell(0.0, 1480.0, 0.4, 0.1)
	s._tone(0.0, 0.1, 160.0, 80.0, 0.6, W_SINE, 0.001, 2.4)
	return s._finish(0.42)


static func _gluttony_cast(s: Object) -> AudioStreamWAV:
	# Gluttony: a cavernous gulp, a wet slurp and a satisfied low rumble.
	s._begin(1.0)
	s._meow(0.0, 0.3, 220.0, 120.0, 70.0, 0.8, 500.0, 300.0, 200.0, 0.0, 0.0, 0.0)
	s._noise(0.0, 0.35, 0.6, 1600.0, 300.0, 2.0, F_BAND, 0.02, 1.4, 14.0, 0.6)
	s._tone(0.3, 0.6, 70.0, 55.0, 0.6, W_SAW, 0.05, 1.6, 0.0, 0.0, 9.0, 0.5)
	s._lowpass(1800.0)
	return s._finish(0.48)


static func _gluttony_hit(s: Object) -> AudioStreamWAV:
	# Chomp: two crunching bites in quick succession.
	s._begin(0.4)
	for k in 2:
		var t := k * 0.12
		s._tone(t, 0.06, 260.0, 120.0, 0.8, W_TRI, 0.0005, 2.6)
		s._noise(t, 0.08, 0.7, 2200.0, 900.0, 1.4, F_BAND, 0.0005, 2.2)
		s._crackle(t, 0.08, 0.5, 300.0)
	return s._finish(0.48)


# ---------------------------------------------------------------- gadgets

static func _decoy_cast(s: Object) -> AudioStreamWAV:
	# A double appears: a smoky puff and a mocking little laugh.
	s._begin(0.8)
	s._noise(0.0, 0.3, 0.8, 600.0, 1800.0, 1.2, F_BAND, 0.01, 2.0)
	for k in 3:
		var f := 260.0 - k * 20.0
		s._meow(0.25 + k * 0.12, 0.1, f, f * 1.25, f * 0.9, 0.6, 700.0, 950.0, 600.0, 0.0, 0.0, 0.0)
	return s._finish(0.36)


static func _decoy_hit(s: Object) -> AudioStreamWAV:
	# The decoy bursts: a hollow pop into smoke.
	s._begin(0.4)
	s._tone(0.0, 0.08, 520.0, 120.0, 0.8, W_SINE, 0.0005, 2.0)
	s._noise(0.0, 0.3, 0.6, 1400.0, 500.0, 1.0, F_BAND, 0.002, 1.8)
	return s._finish(0.4)


static func _turret_cast(s: Object) -> AudioStreamWAV:
	# A hellforged sentry deployed: iron legs slam down, a ratchet winds, a latch locks.
	s._begin(0.9)
	s._tone(0.0, 0.15, 120.0, 60.0, 0.9, W_SINE, 0.001, 2.4)
	s._bell(0.0, 610.0, 0.6, 0.06, true)
	for k in 8:
		s._noise(0.2 + k * 0.045, 0.02, 0.6, 2600.0, 2000.0, 3.0, F_BAND, 0.0005, 2.0)
	s._tone(0.6, 0.06, 300.0, 180.0, 0.8, W_SOFTSQ, 0.0005, 3.0)
	s._bell(0.6, 880.0, 0.4, 0.05, true)
	return s._finish(0.42)


static func _turret_hit(s: Object) -> AudioStreamWAV:
	# A turret shot: a compressed thunk and a fizzing bolt.
	s._begin(0.3)
	s._tone(0.0, 0.06, 180.0, 90.0, 0.9, W_SINE, 0.0005, 2.6)
	s._noise(0.0, 0.05, 0.6, 3000.0, 1500.0, 1.4, F_BAND, 0.0005, 2.0)
	s._noise(0.02, 0.2, 0.3, 3600.0, 2800.0, 1.0, F_HIGH, 0.01, 2.0)
	return s._finish(0.38)


static func _mine_cast(s: Object) -> AudioStreamWAV:
	# A mine arms: a click and a two-tone infernal ping.
	s._begin(0.5)
	s._noise(0.0, 0.01, 0.8, 3000.0, 3000.0, 4.0, F_BAND, 0.0002, 2.0)
	s._tone(0.05, 0.08, 1320.0, 1320.0, 0.5, W_SINE, 0.002, 1.8)
	s._tone(0.15, 0.12, 990.0, 990.0, 0.5, W_SINE, 0.002, 1.8)
	return s._finish(0.28)


static func _mine_hit(s: Object) -> AudioStreamWAV:
	# The mine goes off: a sharp blast, a deep boom and falling debris.
	s._begin(1.0)
	s._noise(0.0, 0.05, 1.0, 3600.0, 2000.0, 1.0, F_HIGH, 0.0003, 1.6)
	s._tone(0.0, 0.6, 85.0, 28.0, 1.0, W_SINE, 0.001, 1.8)
	s._noise(0.0, 0.6, 0.9, 1200.0, 150.0, 0.8, F_LOW, 0.001, 1.8)
	s._crackle(0.05, 0.6, 0.5, 120.0)
	return s._finish(0.6)


static func _whip_cast(s: Object) -> AudioStreamWAV:
	# The whip: a rising swish that ends in a supersonic crack.
	s._begin(0.4)
	s._noise(0.0, 0.18, 0.7, 500.0, 3000.0, 1.6, F_BAND, 0.15, 0.4)
	s._noise(0.17, 0.02, 1.0, 3600.0, 3600.0, 1.0, F_HIGH, 0.0001, 1.2)
	s._crackle(0.17, 0.05, 0.9, 600.0)
	return s._finish(0.48)


static func _whip_hit(s: Object) -> AudioStreamWAV:
	# A lash landing on skin: a slap with a stinging tail.
	s._begin(0.3)
	s._noise(0.0, 0.03, 1.0, 3000.0, 1800.0, 1.0, F_BAND, 0.0002, 1.6)
	s._tone(0.0, 0.06, 300.0, 160.0, 0.5, W_TRI, 0.0005, 2.4)
	s._noise(0.02, 0.2, 0.3, 3600.0, 3000.0, 1.0, F_HIGH, 0.005, 2.0)
	return s._finish(0.44)


# ---------------------------------------------------------------- progression stings

static func _synergy(s: Object) -> AudioStreamWAV:
	# Synergy: two powers lock together, a dark-to-bright two-chord stab with a shimmer.
	s._begin(1.6)
	for m: int in [50, 53, 57]:
		s._tone(0.0, 0.3, _hz(m), _hz(m), 0.3, W_SAW, 0.005, 1.6)
	for m: int in [50, 54, 57, 62]:
		s._tone(0.18, 0.9, _hz(m), _hz(m), 0.28, W_SAW, 0.01, 1.6, 5.0, 0.004)
	s._lowpass(2400.0)
	s._bell(0.18, 1174.7, 0.5, 0.2)
	s._bell(0.22, 1760.0, 0.3, 0.16)
	s._noise(0.18, 0.8, 0.15, 3400.0, 3600.0, 1.0, F_HIGH, 0.05, 1.8)
	s._reverb(0.28, 0.8, 0.45)
	return s._finish(0.5)


static func _relic(s: Object, tier: int) -> AudioStreamWAV:
	# Relic pickup, escalating with rarity: chimes (common) -> arpeggio -> gong + choir (legendary).
	var dur := 0.9 + tier * 0.6
	s._begin(dur)
	var base: float = [587.3, 659.3, 698.5, 784.0, 880.0][tier]
	var steps := [0, 7, 12, 16, 19, 24]
	for i in 2 + tier:
		s._bell(i * 0.07, base * pow(2.0, float(steps[mini(i, steps.size() - 1)]) / 12.0),
				0.8 - i * 0.08, 0.14 + tier * 0.03)
	if tier >= 2:
		s._add(s._tpl_bell(146.8 if tier < 4 else 98.0, 1.2 + tier * 0.4, 0.8), 0.0, 0.5)
	if tier >= 3:
		s._add(s._tpl_choir([62, 66, 69, 74] if tier == 4 else [62, 69, 74], dur - 0.4, 0.15, 0.9,
				V_AH, 1.0, 1.0, 0.08, 2), 0.1, 0.6 + 0.15 * (tier - 3))
	s._reverb(0.25 + tier * 0.03, 0.8, 0.45)
	return s._finish(0.3 + tier * 0.08)


static func _evolve(s: Object) -> AudioStreamWAV:
	# An ability evolves: a reversed swell sucks inward, a gong strikes, a choir resolves upward.
	s._begin(3.4)
	s._noise(0.0, 0.9, 0.9, 200.0, 3000.0, 1.6, F_BAND, 0.85, 0.15)
	s._tone(0.0, 0.9, 55.0, 220.0, 0.4, W_SAW, 0.85, 0.15)
	s._add(s._tpl_bell(73.4, 2.2, 1.0), 0.88, 0.8)
	s._tone(0.88, 1.2, 80.0, 30.0, 1.0, W_SINE, 0.002, 1.8)
	s._add(s._tpl_choir([50, 57, 62, 66, 69], 2.2, 0.08, 1.0, V_AH, 0.94, 1.0, 0.08, 2), 0.9, 0.85)
	s._reverb(0.32, 0.86, 0.42)
	return s._finish(0.7)


# ---------------------------------------------------------------- footsteps

static func _step_snow(s: Object, v: int) -> AudioStreamWAV:
	# Clawed foot in packed snow: a muffled thump and a squeaky crunch.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.4)
	var f := 70.0 + v * 6.0 + rng.randf_range(-3.0, 3.0)
	s._tone(0.0, 0.2, f, f * 0.5, 0.7, W_SINE, 0.004, 2.4)
	s._noise(0.0, 0.22, 0.6, 1800.0 + v * 200.0, 2600.0, 2.0, F_BAND, 0.02, 1.6, 45.0 + v * 8.0, 0.6)
	s._crackle(0.01, 0.18, 0.25, 220.0)
	return s._finish(0.42)


static func _step_wood(s: Object, v: int) -> AudioStreamWAV:
	# A heavy step on planks: a hollow, resonant knock and a slight creak.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.45)
	var f := 150.0 + v * 18.0 + rng.randf_range(-5.0, 5.0)
	s._tone(0.0, 0.18, f, f * 0.85, 0.9, W_TRI, 0.001, 2.2)
	s._tone(0.0, 0.25, f * 0.5, f * 0.45, 0.6, W_SINE, 0.002, 2.0)
	s._noise(0.0, 0.05, 0.4, 1600.0, 900.0, 2.0, F_BAND, 0.0008, 2.2)
	if v == 1:
		s._tone(0.05, 0.25, 420.0, 380.0, 0.08, W_SAW, 0.05, 1.6, 0.0, 0.0, 30.0, 0.7)  # creak
	s._lowpass(3200.0)
	return s._finish(0.46)


static func _step_water(s: Object, v: int) -> AudioStreamWAV:
	# Wading: a splash and a couple of drips.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.5)
	s._noise(0.0, 0.25, 0.8, 900.0 + v * 150.0, 2600.0, 1.2, F_BAND, 0.01, 2.0)
	s._tone(0.0, 0.1, 90.0, 50.0, 0.5, W_SINE, 0.002, 2.4)
	for k in 3:
		var f := rng.randf_range(600.0, 1300.0)
		s._tone(rng.randf_range(0.03, 0.3), 0.04, f, f * 1.8, 0.2, W_SINE, 0.002, 2.0)
	return s._finish(0.42)


static func _step_ash(s: Object, v: int) -> AudioStreamWAV:
	# Ash and cinders: a soft, powdery thud with a dry crunch of embers.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.4)
	var f := 64.0 + v * 5.0 + rng.randf_range(-3.0, 3.0)
	s._tone(0.0, 0.2, f, f * 0.5, 0.75, W_SINE, 0.006, 2.4)
	s._noise(0.0, 0.18, 0.45, 700.0, 300.0, 0.9, F_LOW, 0.01, 2.0)
	s._crackle(0.0, 0.15, 0.3, 160.0 + v * 30.0)
	return s._finish(0.42)


# ---------------------------------------------------------------- round 4: summons and specials

static func _summon_hellhound(s: Object) -> AudioStreamWAV:
	# The pack is called: a rising hellhound howl and two snarling barks.
	s._begin(1.4)
	s._meow(0.0, 0.9, 260.0, 420.0, 330.0, 0.9, 700.0, 1000.0, 650.0, 5.0, 0.02, 0.0)
	for k in 2:
		var t := 0.85 + k * 0.2
		s._meow(t, 0.14, 170.0, 210.0, 120.0, 0.9, 650.0, 800.0, 500.0, 0.0, 0.0, 45.0)
	s._noise(0.0, 1.2, 0.2, 500.0, 900.0, 1.5, F_BAND, 0.1, 1.4)
	s._reverb(0.25, 0.78, 0.5)
	return s._finish(0.45)


static func _summon_imps(s: Object) -> AudioStreamWAV:
	# An imp rabble bursts out: a scatter of squeaky cackles over a puff of brimstone.
	var rng: RandomNumberGenerator = s._rng
	s._begin(1.0)
	s._noise(0.0, 0.3, 0.6, 500.0, 1600.0, 1.2, F_BAND, 0.01, 2.0)
	for k in 9:
		var f := rng.randf_range(420.0, 760.0)
		s._meow(rng.randf_range(0.05, 0.7), rng.randf_range(0.07, 0.13), f, f * 1.3, f * 0.85,
				rng.randf_range(0.3, 0.6), 1200.0, 1700.0, 1100.0, 0.0, 0.0, rng.randf_range(0.0, 30.0))
	return s._finish(0.38)


static func _summon_brute(s: Object) -> AudioStreamWAV:
	# A pit brute lands: a ground-shaking stomp, rubble, and a deep bellow.
	s._begin(1.5)
	s._tone(0.0, 0.7, 70.0, 26.0, 1.0, W_SINE, 0.001, 1.8)
	s._noise(0.0, 0.5, 0.8, 900.0, 120.0, 0.8, F_LOW, 0.001, 2.0)
	s._crackle(0.02, 0.5, 0.4, 120.0)
	s._meow(0.35, 1.0, 80.0, 105.0, 65.0, 1.0, 450.0, 600.0, 330.0, 0.0, 0.0, 26.0)
	s._lowpass(2200.0)
	return s._finish(0.6)


static func _summon_succubus(s: Object) -> AudioStreamWAV:
	# A succubus double: a breathy, amused sigh with a mirrored shimmer.
	s._begin(1.2)
	s._meow(0.05, 0.8, 330.0, 280.0, 240.0, 0.6, 800.0, 650.0, 550.0, 4.0, 0.01, 0.0)
	s._noise(0.0, 0.9, 0.4, 1600.0, 2400.0, 3.0, F_BAND, 0.2, 1.4)
	for f: float in [1568.0, 1975.5, 2349.3]:
		s._bell(0.1, f, 0.25, 0.15)
	s._reverb(0.3, 0.8, 0.45)
	return s._finish(0.36)


static func _devour(s: Object) -> AudioStreamWAV:
	# Devour: jaws slam shut, bones crunch, a heavy swallow.
	s._begin(0.9)
	s._tone(0.0, 0.08, 200.0, 90.0, 1.0, W_TRI, 0.0005, 2.4)
	s._noise(0.0, 0.08, 0.9, 2400.0, 1000.0, 1.4, F_BAND, 0.0005, 2.0)
	s._crackle(0.05, 0.25, 0.8, 260.0)
	s._meow(0.35, 0.35, 160.0, 90.0, 60.0, 0.8, 420.0, 260.0, 180.0, 0.0, 0.0, 0.0)
	s._tone(0.35, 0.4, 90.0, 45.0, 0.6, W_SINE, 0.02, 1.8)
	s._lowpass(2800.0)
	return s._finish(0.55)


static func _reflect(s: Object) -> AudioStreamWAV:
	# Stolen Radiance: holy light caught, a reversed chime and a whoosh flung back.
	s._begin(0.7)
	s._tone(0.0, 0.25, 1046.5, 1568.0, 0.4, W_SINE, 0.22, 0.2)  # swells in, like a reversed bell
	s._bell(0.24, 1568.0, 0.6, 0.08, true)
	s._noise(0.24, 0.35, 0.7, 3000.0, 600.0, 1.6, F_BAND, 0.005, 1.8)
	return s._finish(0.38)


static func _gilded_drop(s: Object) -> AudioStreamWAV:
	# A Gilded foe spills its Ichor: a quick spray of coins and one ringing gold note.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.8)
	for i in 6:
		s._bell(i * 0.03 + rng.randf_range(0.0, 0.015), rng.randf_range(2000.0, 3200.0),
				rng.randf_range(0.3, 0.55), 0.035, true)
	s._bell(0.02, 1318.5, 0.5, 0.18)
	return s._finish(0.34)
