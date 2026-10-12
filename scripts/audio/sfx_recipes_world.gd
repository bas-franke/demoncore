extends RefCounted
## Round-2 procedural recipes for the Sfx autoload (owner: sfx role, docs/team/sfx.md):
## per-material hits and deaths, enemy voices, objective sounds, the boss stinger, weather
## (thunder, rain, gusts), dialogue blips and stereo / wide ambience beds.
## Runs on Sfx's synthesis worker thread, driving the Sfx node's buffer helpers (see
## sfx_recipes.gd); stereo streams are packed here from two independently rendered channels.

# Mirrors of Sfx's constants (kept local to avoid a cyclic preload).
const SR := 22050
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

const MATERIALS := [&"flesh", &"stone", &"glass", &"metal", &"holy"]
const VARIANTS := {
	&"hit_stone": [&"hit_stone_a", &"hit_stone_b", &"hit_stone_c"],
	&"hit_glass": [&"hit_glass_a", &"hit_glass_b", &"hit_glass_c"],
	&"hit_metal": [&"hit_metal_a", &"hit_metal_b", &"hit_metal_c"],
	&"hit_holy": [&"hit_holy_a", &"hit_holy_b", &"hit_holy_c"],
}
const ALIASES := {
	&"thunder_near": &"thunder", &"rain": &"amb_rain", &"stinger": &"stinger_boss",
	&"blip": &"blip_mid",
}
const MAX_VOICES := {
	&"hit_stone": 4, &"hit_glass": 4, &"hit_metal": 4, &"hit_holy": 4,
	&"death_flesh": 3, &"crumble": 3, &"armor_clatter": 3, &"light_burst": 3,
	&"voice_villager": 2, &"voice_zealot": 2, &"voice_roar": 1, &"voice_screech": 2,
	&"voice_whinny": 1, &"voice_grind": 1, &"voice_hum": 1, &"voice_angel": 2, &"voice_knight": 2,
	&"voice_cherub": 2, &"desecrate": 1, &"seal_break": 1, &"relic_corrupt": 1,
	&"stinger_boss": 1, &"thunder": 2, &"thunder_far": 2, &"harvest": 1,
	&"blip_low": 1, &"blip_mid": 1, &"blip_high": 1, &"blip_holy": 1, &"blip_whisper": 1,
}
const MIN_GAP := {
	&"hit_stone": 0.045, &"hit_glass": 0.045, &"hit_metal": 0.045, &"hit_holy": 0.045,
	&"death_flesh": 0.05, &"crumble": 0.06, &"armor_clatter": 0.06, &"light_burst": 0.06,
	&"voice_villager": 0.35, &"voice_zealot": 0.35, &"voice_roar": 0.8, &"voice_screech": 0.4,
	&"voice_whinny": 0.6, &"voice_grind": 0.7, &"voice_hum": 0.6, &"voice_angel": 0.35,
	&"voice_knight": 0.3, &"voice_cherub": 0.3, &"desecrate": 1.0, &"seal_break": 0.3,
	&"relic_corrupt": 1.0, &"stinger_boss": 2.0, &"thunder": 0.4, &"thunder_far": 0.4,
	&"harvest": 0.3, &"blip_low": 0.04, &"blip_mid": 0.04, &"blip_high": 0.04,
	&"blip_holy": 0.04, &"blip_whisper": 0.04,
}


## One-shots. Returns name -> AudioStreamWAV.
static func build(s: Object) -> Dictionary:
	var d := {}
	var rng: RandomNumberGenerator = s._rng
	var keep := rng.state
	rng.seed = 0x3A7E21A1
	for i in 3:
		d[VARIANTS[&"hit_stone"][i]] = _hit_stone(s, i)
		d[VARIANTS[&"hit_glass"][i]] = _hit_glass(s, i)
		d[VARIANTS[&"hit_metal"][i]] = _hit_metal(s, i)
		d[VARIANTS[&"hit_holy"][i]] = _hit_holy(s, i)
	d[&"death_flesh"] = _death_flesh(s)
	d[&"crumble"] = _crumble(s)
	d[&"armor_clatter"] = _armor_clatter(s)
	d[&"light_burst"] = _light_burst(s)
	d[&"voice_villager"] = _voice_villager(s)
	d[&"voice_zealot"] = _voice_zealot(s)
	d[&"voice_roar"] = _voice_roar(s)
	d[&"voice_screech"] = _voice_screech(s)
	d[&"voice_whinny"] = _voice_whinny(s)
	d[&"voice_grind"] = _voice_grind(s)
	d[&"voice_hum"] = _voice_hum(s)
	d[&"voice_knight"] = _voice_knight(s)
	d[&"voice_cherub"] = _voice_cherub(s)
	d[&"blip_low"] = _blip(s, 105.0, 520.0, 0.07)
	d[&"blip_mid"] = _blip(s, 190.0, 760.0, 0.06)
	d[&"blip_high"] = _blip(s, 330.0, 1150.0, 0.05)
	d[&"blip_holy"] = _blip_holy(s)
	d[&"blip_whisper"] = _blip_whisper(s)
	d[&"seal_break"] = _seal_break(s)
	d[&"harvest"] = _harvest(s)
	rng.state = keep
	return d


## Heavier one-shots and loops (rendered after the core ambience).
static func build_heavy(s: Object) -> Dictionary:
	var d := {}
	var rng: RandomNumberGenerator = s._rng
	var keep := rng.state
	rng.seed = 0x77E4A
	# Hub bed first: Basecamp can be reached before the rest of this batch is rendered.
	d[&"amb_hellfire_wide"] = _amb_hellfire_wide(s)
	d[&"voice_angel"] = _voice_angel(s)
	d[&"desecrate"] = _desecrate(s)
	d[&"relic_corrupt"] = _relic_corrupt(s)
	d[&"stinger_boss"] = _stinger_boss(s)
	d[&"thunder"] = _thunder(s, false)
	d[&"thunder_far"] = _thunder(s, true)
	d[&"amb_ritual"] = _amb_ritual(s)
	d[&"amb_rain"] = _amb_rain(s)
	d[&"amb_gust_wide"] = _amb_gust_wide(s)
	rng.state = keep
	return d


# ---------------------------------------------------------------- material hits

static func _hit_stone(s: Object, v: int) -> AudioStreamWAV:
	# Claw on marble: a dry, hard knock, a gritty crunch and a few pebbles skittering off.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.3)
	var f := 230.0 + v * 35.0 + rng.randf_range(-10.0, 10.0)
	s._tone(0.0, 0.07, f, f * 0.7, 1.0, W_TRI, 0.0005, 3.0)
	s._tone(0.0, 0.12, 110.0, 70.0, 0.5, W_SINE, 0.001, 2.6)
	s._noise(0.0, 0.1, 0.8, 2400.0 - v * 300.0, 900.0, 1.4, F_BAND, 0.0005, 2.4)
	s._crackle(0.01, 0.22, 0.5, 90.0 + v * 30.0)
	return s._finish(0.5)


static func _hit_glass(s: Object, v: int) -> AudioStreamWAV:
	# Stained glass struck: a bright ping, a split-second crack and a tinkle of splinters.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.5)
	var f := 2600.0 + v * 450.0 + rng.randf_range(-80.0, 80.0)
	s._bell(0.0, f, 0.9, 0.06, true)
	s._bell(0.0, f * 1.47, 0.4, 0.04, true)
	s._noise(0.0, 0.02, 0.7, 3600.0, 3600.0, 1.0, F_HIGH, 0.0002, 1.4)
	for k in 4:
		s._bell(rng.randf_range(0.02, 0.14), rng.randf_range(3000.0, 5000.0), rng.randf_range(0.15, 0.35),
				rng.randf_range(0.01, 0.03), true)
	s._tone(0.0, 0.05, 300.0, 160.0, 0.3, W_SINE, 0.0005, 2.5)
	return s._finish(0.42)


static func _hit_metal(s: Object, v: int) -> AudioStreamWAV:
	# Armor struck: an inharmonic clang over a thud, with a short scrape.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.6)
	var f := 520.0 + v * 140.0 + rng.randf_range(-20.0, 20.0)
	s._bell(0.0, f, 1.0, 0.12, true)
	s._bell(0.0, f * 1.53, 0.5, 0.08, true)
	s._bell(0.0, f * 2.31, 0.3, 0.05, true)
	s._tone(0.0, 0.1, 140.0, 70.0, 0.7, W_SINE, 0.001, 2.6)
	s._noise(0.0, 0.08, 0.5, 3400.0, 2400.0, 2.0, F_BAND, 0.0005, 2.2)
	return s._finish(0.48)


static func _hit_holy(s: Object, v: int) -> AudioStreamWAV:
	# Hitting solid light: a hissing flare, a falling shimmer and a faint ringing tone.
	s._begin(0.42)
	var f := 1500.0 + v * 220.0
	s._noise(0.0, 0.16, 0.7, 3600.0, 3000.0, 1.0, F_HIGH, 0.001, 2.2)
	s._tone(0.0, 0.25, f, f * 0.55, 0.45, W_SINE, 0.001, 2.0, 30.0, 0.01)
	s._bell(0.0, f * 1.18, 0.25, 0.08)
	s._tone(0.0, 0.06, 180.0, 90.0, 0.4, W_SINE, 0.001, 2.4)
	return s._finish(0.4)


# ---------------------------------------------------------------- material deaths

static func _death_flesh(s: Object) -> AudioStreamWAV:
	# A body dropping: heavy thud, a wet slap, a last breath leaving.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.9)
	s._tone(0.0, 0.3, 95.0, 38.0, 1.0, W_SINE, 0.002, 2.2)
	s._noise(0.0, 0.25, 0.7, 900.0, 200.0, 1.0, F_LOW, 0.001, 2.0)
	for k in 4:
		var bf := rng.randf_range(200.0, 380.0)
		s._tone(rng.randf_range(0.02, 0.2), 0.05, bf, bf * 0.5, 0.3, W_SINE, 0.002, 2.0)
	s._meow(0.12, 0.6, 150.0, 120.0, 80.0, 0.35, 500.0, 420.0, 300.0, 0.0, 0.0, 0.0)
	s._noise(0.12, 0.6, 0.25, 800.0, 400.0, 2.0, F_BAND, 0.05, 1.6)
	s._lowpass(2600.0)
	return s._finish(0.5)


static func _crumble(s: Object) -> AudioStreamWAV:
	# A statue breaking apart: a crack, a low boom and a rockfall of chunks and grit.
	var rng: RandomNumberGenerator = s._rng
	s._begin(1.4)
	s._noise(0.0, 0.05, 0.9, 3000.0, 1500.0, 1.0, F_BAND, 0.0003, 1.8)
	s._tone(0.0, 0.6, 80.0, 30.0, 0.9, W_SINE, 0.002, 1.8)
	for k in 16:
		var t := 0.04 + pow(rng.randf(), 1.3) * 0.8
		var f := rng.randf_range(140.0, 420.0)
		s._tone(t, 0.06, f, f * 0.7, rng.randf_range(0.3, 0.7) * (1.0 - t * 0.6), W_TRI, 0.0005, 3.0)
	s._noise(0.02, 1.0, 0.45, 1400.0, 500.0, 1.0, F_BAND, 0.05, 1.8)
	s._crackle(0.02, 1.0, 0.5, 160.0)
	return s._finish(0.55)


static func _armor_clatter(s: Object) -> AudioStreamWAV:
	# Plate armor hitting the ground: a heavy fall and pieces bouncing to rest.
	var rng: RandomNumberGenerator = s._rng
	s._begin(1.3)
	s._tone(0.0, 0.25, 110.0, 45.0, 0.9, W_SINE, 0.001, 2.2)
	var t := 0.0
	var gap := 0.16
	for k in 6:
		var f := rng.randf_range(480.0, 900.0)
		s._bell(t, f, 0.9 - k * 0.12, 0.07, true)
		s._bell(t, f * 1.6, 0.4 - k * 0.05, 0.05, true)
		s._noise(t, 0.04, 0.4 - k * 0.05, 3000.0, 2200.0, 2.0, F_BAND, 0.0005, 2.0)
		t += gap
		gap *= 0.72  # bounces settle faster and faster
	return s._finish(0.5)


static func _light_burst(s: Object) -> AudioStreamWAV:
	# A being of light unravelling: a swelling shimmer that pops into a bright chord and air.
	s._begin(1.6)
	s._noise(0.0, 0.3, 0.6, 1200.0, 3600.0, 1.4, F_BAND, 0.25, 0.3)
	s._tone(0.0, 0.3, 700.0, 1400.0, 0.3, W_SINE, 0.25, 0.3)
	for f: float in [1318.5, 1760.0, 2217.5]:
		s._bell(0.28, f, 0.6, 0.2)
	s._noise(0.28, 1.0, 0.25, 3600.0, 3200.0, 1.0, F_HIGH, 0.002, 2.0)
	s._reverb(0.3, 0.8, 0.4)
	return s._finish(0.38)


# ---------------------------------------------------------------- enemy voices (wind-up)

static func _voice_villager(s: Object) -> AudioStreamWAV:
	# An angry peasant's "hyaah!".
	s._begin(0.6)
	s._meow(0.0, 0.5, 150.0, 190.0, 130.0, 1.0, 650.0, 900.0, 560.0, 6.0, 0.015, 0.0)
	s._noise(0.0, 0.4, 0.2, 1200.0, 900.0, 2.0, F_BAND, 0.02, 1.6)
	return s._finish(0.42)


static func _voice_zealot(s: Object) -> AudioStreamWAV:
	# A fanatic's ragged war scream.
	s._begin(0.7)
	s._meow(0.0, 0.65, 260.0, 360.0, 290.0, 1.0, 850.0, 1250.0, 900.0, 7.0, 0.03, 42.0)
	s._noise(0.0, 0.6, 0.3, 1800.0, 1400.0, 1.5, F_BAND, 0.03, 1.4)
	return s._finish(0.42)


static func _voice_roar(s: Object) -> AudioStreamWAV:
	# A lion's roar: a deep, rough voice swelling and falling, breath noise in the throat.
	s._begin(1.2)
	s._meow(0.0, 1.1, 95.0, 120.0, 70.0, 1.0, 520.0, 700.0, 380.0, 0.0, 0.0, 30.0)
	s._noise(0.0, 1.0, 0.5, 400.0, 900.0, 1.4, F_BAND, 0.15, 1.4, 30.0, 0.5)
	s._tone(0.0, 1.0, 60.0, 45.0, 0.4, W_SAW, 0.12, 1.4)
	s._lowpass(2400.0)
	return s._finish(0.55)


static func _voice_screech(s: Object) -> AudioStreamWAV:
	# A griffon's eagle screech: a rising, rasping whistle.
	s._begin(0.6)
	s._tone(0.0, 0.55, 1700.0, 2300.0, 0.6, W_TRI, 0.04, 1.6, 23.0, 0.03)
	s._tone(0.0, 0.55, 3400.0, 4600.0, 0.15, W_SINE, 0.05, 1.8, 23.0, 0.03)
	s._noise(0.0, 0.5, 0.45, 2400.0, 3400.0, 3.0, F_BAND, 0.04, 1.6)
	return s._finish(0.36)


static func _voice_whinny(s: Object) -> AudioStreamWAV:
	# A warhorse's whinny: a bright, shaking neigh that falls off into a snort.
	s._begin(1.0)
	s._meow(0.0, 0.75, 520.0, 820.0, 420.0, 1.0, 900.0, 1400.0, 700.0, 11.0, 0.07, 0.0)
	s._noise(0.75, 0.2, 0.6, 900.0, 500.0, 1.2, F_BAND, 0.005, 2.0)
	return s._finish(0.38)


static func _voice_grind(s: Object) -> AudioStreamWAV:
	# Stone (or glass) limbs grinding into motion.
	s._begin(0.7)
	s._noise(0.0, 0.65, 0.9, 300.0, 500.0, 2.0, F_BAND, 0.1, 1.2, 26.0, 0.7)
	s._tone(0.0, 0.6, 70.0, 62.0, 0.5, W_SAW, 0.1, 1.4, 0.0, 0.0, 13.0, 0.6)
	s._crackle(0.05, 0.6, 0.3, 50.0)
	s._lowpass(2000.0)
	return s._finish(0.42)


static func _voice_hum(s: Object) -> AudioStreamWAV:
	# A light being drawing power: a trembling major chord swelling with a shimmer.
	s._begin(0.9)
	for f: float in [523.25, 659.25, 783.99]:
		s._tone(0.0, 0.85, f * 0.98, f, 0.3, W_SINE, 0.4, 0.8, 0.0, 0.0, 9.0, 0.5)
	s._noise(0.0, 0.85, 0.12, 3200.0, 3600.0, 1.0, F_HIGH, 0.4, 0.8)
	return s._finish(0.32)


static func _voice_angel(s: Object) -> AudioStreamWAV:
	# A short war-cry of the Host: a sharp choral shout.
	s._begin(1.1)
	s._add(s._tpl_choir([57, 64, 69], 0.7, 0.03, 0.35, V_EH, 0.97, 1.02, 0.15, 2), 0.0, 1.0)
	s._reverb(0.25, 0.75, 0.5)
	return s._finish(0.4)


static func _voice_knight(s: Object) -> AudioStreamWAV:
	# A gruff battle grunt and the rattle of mail.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.6)
	s._meow(0.0, 0.35, 120.0, 140.0, 100.0, 1.0, 560.0, 700.0, 450.0, 0.0, 0.0, 0.0)
	for k in 7:
		s._bell(rng.randf_range(0.0, 0.3), rng.randf_range(2000.0, 3400.0), rng.randf_range(0.1, 0.25),
				0.015, true)
	return s._finish(0.42)


static func _voice_cherub(s: Object) -> AudioStreamWAV:
	# A cherub's backwards-hymn giggle: quick bright chirps.
	s._begin(0.6)
	for k in 4:
		var f := 900.0 + k * 90.0
		s._meow(k * 0.11, 0.1, f, f * 1.2, f * 0.9, 0.7, 1500.0, 2000.0, 1400.0, 0.0, 0.0, 0.0)
	return s._finish(0.32)


# ---------------------------------------------------------------- dialogue blips

static func _blip(s: Object, f: float, formant: float, dur: float) -> AudioStreamWAV:
	# One syllable of murmured speech: a tiny voiced chirp through a formant.
	s._begin(dur + 0.02)
	s._meow(0.0, dur, f, f * 1.12, f * 0.94, 1.0, formant, formant * 1.25, formant * 0.9, 0.0, 0.0, 0.0)
	return s._finish(0.3)


static func _blip_holy(s: Object) -> AudioStreamWAV:
	# Angelic speech: a soft bell-like syllable.
	s._begin(0.2)
	s._bell(0.0, 880.0, 0.6, 0.04)
	s._meow(0.0, 0.06, 440.0, 494.0, 440.0, 0.4, 900.0, 1100.0, 900.0, 0.0, 0.0, 0.0)
	return s._finish(0.26)


static func _blip_whisper(s: Object) -> AudioStreamWAV:
	# Narration / occult speech: a breathy whispered syllable.
	s._begin(0.1)
	s._noise(0.0, 0.08, 1.0, 1200.0, 1800.0, 3.0, F_BAND, 0.01, 1.8)
	return s._finish(0.22)


# ---------------------------------------------------------------- objectives

static func _seal_break(s: Object) -> AudioStreamWAV:
	# A holy seal shattering: a ringing metal-and-glass crack over a low blow.
	var rng: RandomNumberGenerator = s._rng
	s._begin(1.4)
	s._noise(0.0, 0.05, 1.0, 3600.0, 2500.0, 1.0, F_HIGH, 0.0003, 1.6)
	s._bell(0.0, 1046.5, 0.8, 0.25, true)
	s._bell(0.0, 1480.0, 0.5, 0.18, true)
	for k in 10:
		s._bell(rng.randf_range(0.0, 0.3), rng.randf_range(2600.0, 4800.0), rng.randf_range(0.15, 0.4),
				rng.randf_range(0.02, 0.05), true)
	s._tone(0.0, 0.5, 90.0, 35.0, 0.9, W_SINE, 0.002, 2.0)
	s._reverb(0.3, 0.8, 0.45)
	return s._finish(0.55)


static func _harvest(s: Object) -> AudioStreamWAV:
	# Souls pulled in from everywhere: an inward rushing breath and a low welcoming chord.
	s._begin(1.0)
	s._noise(0.0, 0.7, 0.9, 3000.0, 400.0, 2.0, F_BAND, 0.4, 0.4)
	s._tone(0.3, 0.6, 146.8, 146.8, 0.35, W_TRI, 0.2, 1.6)
	s._tone(0.3, 0.6, 220.0, 220.0, 0.25, W_SINE, 0.2, 1.6)
	return s._finish(0.38)


static func _desecrate(s: Object) -> AudioStreamWAV:
	# A shrine defiled: its holy tone bends and cracks, a profane chord roars up, fire bursts.
	s._begin(3.0)
	s._bell(0.0, 880.0, 0.7, 0.3)
	s._tone(0.0, 0.8, 880.0, 440.0, 0.4, W_SINE, 0.01, 1.4)  # the holy note sags
	s._noise(0.35, 0.06, 1.0, 3000.0, 1400.0, 1.0, F_BAND, 0.0003, 1.6)
	s._tone(0.35, 1.0, 70.0, 28.0, 1.0, W_SINE, 0.002, 1.6)
	for m: int in [38, 39, 45, 50]:  # a dissonant low cluster
		var f := 440.0 * pow(2.0, float(m - 69) / 12.0)
		s._tone(0.4, 2.4, f, f * 0.98, 0.3, W_SAW, 0.3, 1.4, 5.0, 0.006)
	s._noise(0.4, 2.2, 0.8, 300.0, 1400.0, 1.0, F_LOW, 0.2, 1.2, 9.0, 0.3)
	s._crackle(0.4, 2.0, 0.5, 60.0)
	s._lowpass(3000.0)
	s._reverb(0.3, 0.84, 0.45)
	return s._finish(0.68)


static func _relic_corrupt(s: Object) -> AudioStreamWAV:
	# A relic turned: a pure chord descends and distorts into a growling drone.
	s._begin(3.0)
	var n := int(2.6 * SR)
	var buf: PackedFloat32Array = s._buf
	var ph := [0.0, 0.0, 0.0]
	var freqs := [659.25, 830.6, 987.8]
	for i in n:
		var x := float(i) / float(n)
		var drive := 1.0 + x * x * 9.0  # the purity overdrives into grit
		var glide := pow(0.25, x)  # two octaves down
		var v := 0.0
		for k in 3:
			ph[k] += freqs[k] * glide / SR
			v += sin(TAU * ph[k])
		var env := minf(1.0, float(i) / 800.0) * pow(1.0 - x, 0.8)
		buf[i] += tanh(v * 0.4 * drive) * env * 0.6
	s._buf = buf  # packed arrays are copy-on-write: hand the edited copy back
	s._tone(1.8, 1.1, 55.0, 41.0, 0.8, W_SAW, 0.05, 1.6)
	s._lowpass(2600.0)
	s._reverb(0.3, 0.84, 0.45)
	return s._finish(0.6)


static func _stinger_boss(s: Object) -> AudioStreamWAV:
	# Boss stinger: a brassy minor stab over taiko and a cymbal swell, then a ringing tail.
	s._begin(3.0)
	for m: int in [26, 38, 45, 50, 53, 57]:
		var f := 440.0 * pow(2.0, float(m - 69) / 12.0)
		s._tone(0.0, 2.2, f, f, 0.35, W_SAW, 0.015, 1.6, 5.0, 0.004)
		s._tone(0.0, 2.2, f * 1.004, f * 1.004, 0.25, W_SAW, 0.015, 1.6)  # chorus detune
	s._lowpass(1800.0)
	s._tone(0.0, 1.0, 90.0, 32.0, 1.4, W_SINE, 0.001, 1.8)
	s._noise(0.0, 0.25, 0.8, 900.0, 150.0, 0.8, F_LOW, 0.001, 2.0)
	s._noise(0.0, 1.8, 0.35, 3600.0, 3200.0, 1.0, F_HIGH, 0.001, 1.8)
	s._reverb(0.35, 0.86, 0.4)
	return s._finish(0.8)


# ---------------------------------------------------------------- weather

## Thunder (stereo one-shot): a crack (near only), then rolling rumble that wanders L/R.
static func _thunder(s: Object, far: bool) -> AudioStreamWAV:
	var rng: RandomNumberGenerator = s._rng
	var dur := 5.0
	var chans: Array[PackedFloat32Array] = []
	var seed0 := rng.randi()
	for side in 2:
		rng.seed = seed0 + side * 7919
		s._begin(dur)
		if not far:
			# Kept modest: the crack would otherwise set the normalization and bury the roll.
			s._noise(0.0, 0.08, 0.35, 3600.0, 2000.0, 1.0, F_HIGH, 0.0005, 1.4)
			s._crackle(0.0, 0.25, 0.35, 300.0)
		var t0 := 0.05 if not far else 0.3
		# Rolling: several overlapping low bursts at random times per channel.
		for k in 6:
			var t := t0 + rng.randf_range(0.0, 1.8)
			var length := rng.randf_range(1.2, 2.8)
			s._noise(t, length, rng.randf_range(0.5, 1.0), rng.randf_range(260.0, 500.0), 70.0, 0.8,
					F_LOW, rng.randf_range(0.05, 0.3), 1.6)
		s._tone(t0, 3.0, 55.0, 30.0, 0.5, W_SINE, 0.1, 1.5)
		if far:
			s._lowpass(500.0)
		chans.append((s._buf as PackedFloat32Array).duplicate())
	return _pack_stereo(chans[0], chans[1], 0.0, 0.7 if not far else 0.5)


## Rain on stone and leaves (8 s stereo loop): hiss, dense patter, the odd fat drip.
static func _amb_rain(s: Object) -> AudioStreamWAV:
	var rng: RandomNumberGenerator = s._rng
	var chans: Array[PackedFloat32Array] = []
	for side in 2:
		rng.seed = 0x4A1 + side * 31
		s._begin(8.6)
		s._noise(0.0, 8.6, 0.35, 3600.0, 3600.0, 1.0, F_HIGH, 0.01, 0.0, 0.21, 0.25)
		s._noise(0.0, 8.6, 0.25, 1400.0, 1400.0, 0.8, F_BAND, 0.01, 0.0, 0.13, 0.3)
		for k in 17:
			s._crackle(k * 0.5, 0.5, 0.35, 260.0)
		for k in 40:
			var f := rng.randf_range(1800.0, 3400.0)
			s._tone(rng.randf_range(0.0, 8.5), 0.025, f, f * 0.7, rng.randf_range(0.08, 0.2), W_SINE,
					0.0005, 3.0)
		chans.append((s._buf as PackedFloat32Array).duplicate())
	return _pack_stereo(chans[0], chans[1], 8.0, 0.5)


## Wide wind gusts (20 s stereo loop): independent gust curves per side for a broad image.
static func _amb_gust_wide(s: Object) -> AudioStreamWAV:
	var chans: Array[PackedFloat32Array] = []
	for side in 2:
		s._begin(21.5)
		# Gust rates are multiples of 1/20 Hz so the loop stays seamless.
		s._wind_layer(1.0, 140.0, 520.0, 2.0, 0.1, side * 2.3)
		s._wind_layer(0.5, 400.0, 1400.0, 1.4, 0.15, 1.1 + side * 1.7)
		s._wind_layer(0.12, 1500.0, 3000.0, 5.0, 0.25, 3.0 + side * 0.9)
		chans.append((s._buf as PackedFloat32Array).duplicate())
	return _pack_stereo(chans[0], chans[1], 20.0, 0.6)


## Basecamp Hell wide: two independently crackling walls of flame over a shared rumble (8 s).
static func _amb_hellfire_wide(s: Object) -> AudioStreamWAV:
	var rng: RandomNumberGenerator = s._rng
	var chans: Array[PackedFloat32Array] = []
	for side in 2:
		rng.seed = 0xF14E + side * 101
		s._begin(8.6)
		s._noise(0.0, 8.6, 0.7, 180.0, 220.0, 0.8, F_LOW, 0.01, 0.0, 0.25 + side * 0.125, 0.4)
		s._noise(0.0, 8.6, 0.25, 700.0, 900.0, 1.0, F_BAND, 0.01, 0.0, 2.0 + side * 0.5, 0.45)
		s._tone(0.0, 8.6, 41.0, 41.0, 0.25, W_SINE, 0.01, 0.0, 0.0, 0.0, 0.25, 0.5)
		for k in 17:
			s._crackle(k * 0.5, 0.5, rng.randf_range(0.35, 0.8), rng.randf_range(25.0, 60.0))
		for k in 7:
			var t := rng.randf_range(0.0, 8.0)
			var f := rng.randf_range(60.0, 110.0)
			s._tone(t, 0.25, f, f * 2.4, rng.randf_range(0.25, 0.5), W_SINE, 0.08, 1.4)
			s._noise(t + 0.24, 0.05, 0.3, 900.0, 400.0, 1.0, F_LOW, 0.001, 2.0)
		chans.append((s._buf as PackedFloat32Array).duplicate())
	return _pack_stereo(chans[0], chans[1], 8.0, 0.6)


## Shrine ritual (6 s mono loop): a heartbeat throb on a low drone and whispering breath.
static func _amb_ritual(s: Object) -> AudioStreamWAV:
	s._begin(6.5)
	s._tone(0.0, 6.5, 55.0, 55.0, 0.5, W_TRI, 0.01, 0.0, 0.0, 0.0, 1.0, 0.8)
	s._tone(0.0, 6.5, 82.4, 82.4, 0.25, W_SAW, 0.01, 0.0, 0.0, 0.0, 0.5, 0.6)
	s._noise(0.0, 6.5, 0.4, 900.0, 900.0, 3.0, F_BAND, 0.01, 0.0, 0.333, 0.8)
	for k in 6:  # heartbeats, one per second
		s._tone(k * 1.0, 0.12, 60.0, 40.0, 0.7, W_SINE, 0.004, 2.4)
		s._tone(k * 1.0 + 0.22, 0.12, 55.0, 38.0, 0.5, W_SINE, 0.004, 2.4)
	s._lowpass(1800.0)
	return s._finish_loop(6.0, 0.55)


# ---------------------------------------------------------------- stereo packing

## Packs two channels into one stereo 16-bit AudioStreamWAV. loop_s > 0: the tail beyond loop_s is
## folded over the head with an equal-power crossfade (seamless loop); 0: one-shot with a fade.
static func _pack_stereo(l: PackedFloat32Array, r: PackedFloat32Array, loop_s: float,
		peak: float) -> AudioStreamWAV:
	var n := mini(l.size(), r.size())
	var out_n := n
	if loop_s > 0.0:
		out_n = mini(int(loop_s * SR), n)
		var xf := n - out_n
		for i in xf:
			var t := float(i) / float(xf)
			l[i] = l[i] * sqrt(t) + l[out_n + i] * sqrt(1.0 - t)
			r[i] = r[i] * sqrt(t) + r[out_n + i] * sqrt(1.0 - t)
	var m := 0.0
	for i in out_n:
		m = maxf(m, maxf(absf(l[i]), absf(r[i])))
	var k := peak / m if m > 0.0 else 0.0
	@warning_ignore("integer_division")  # fade length in whole samples
	var fade := mini(512, out_n / 4)
	var bytes := PackedByteArray()
	bytes.resize(out_n * 4)
	for i in out_n:
		var g := k
		if loop_s <= 0.0 and i >= out_n - fade:
			g *= float(out_n - 1 - i) / float(fade)
		bytes.encode_s16(i * 4, int(clampf(l[i] * g, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(r[i] * g, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = SR
	st.stereo = true
	st.data = bytes
	if loop_s > 0.0:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = out_n
	return st
