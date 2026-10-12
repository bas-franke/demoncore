extends RefCounted
## Extra procedural sound recipes for the Sfx autoload (owner: sfx role, docs/team/sfx.md).
## Runs on Sfx's synthesis worker thread: every recipe drives the Sfx node's buffer helpers
## (_begin / _tone / _noise / _crackle / _bell / _meow / _lowpass / _reverb / _finish ...), so it
## must not touch the scene tree. Sfx merges the tables below into its own voice/gap/alias tables.
##
## Sounds added here (all played with Sfx.play / Sfx.play_at / Sfx.play_element):
##   Elements, `<element>_cast` and `<element>_hit` for fire, blood, shadow, plague, lightning, necro
##   hit_flesh (3 variants), angel_shatter, holy_chime, dash, pickup_item, coin, shop_buy, shop_deny,
##   portal_open, portal_enter, unlock, ability_ready
##   Loops: amb_portal (portal hum, 6 s), amb_hellfire (Basecamp Hell roar + lava, 8 s),
##   amb_hell_choir (low profane chant drone, 16 s)

# Mirrors of Sfx's oscillator / filter constants (kept local to avoid a cyclic preload).
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

const ELEMENTS := [&"fire", &"blood", &"shadow", &"plague", &"lightning", &"necro"]
## Alternative element names other systems might use -> canonical element.
const ELEMENT_ALIASES := {
	&"hellfire": &"fire", &"flame": &"fire", &"burn": &"fire", &"infernal": &"fire",
	&"bleed": &"blood", &"crimson": &"blood", &"dark": &"shadow", &"void": &"shadow",
	&"umbral": &"shadow", &"curse": &"shadow", &"poison": &"plague", &"rot": &"plague",
	&"disease": &"plague",
	&"toxic": &"plague", &"shock": &"lightning", &"storm": &"lightning", &"electric": &"lightning",
	&"thunder": &"lightning", &"necrotic": &"necro", &"death": &"necro", &"bone": &"necro",
	&"soul": &"necro",
}

const VARIANTS := {
	&"hit_flesh": [&"hit_flesh_a", &"hit_flesh_b", &"hit_flesh_c"],
}
const ALIASES := {
	&"flesh": &"hit_flesh", &"shatter": &"angel_shatter", &"chime": &"holy_chime",
	&"buy": &"shop_buy", &"deny": &"shop_deny", &"error": &"shop_deny", &"portal": &"portal_open",
	&"teleport": &"portal_enter", &"item": &"pickup_item",
}
const MAX_VOICES := {
	&"hit_flesh": 4, &"angel_shatter": 3, &"holy_chime": 2, &"dash": 2, &"pickup_item": 2,
	&"coin": 4, &"shop_buy": 1, &"shop_deny": 1, &"portal_open": 1, &"portal_enter": 1,
	&"unlock": 1, &"ability_ready": 1,
	&"fire_cast": 3, &"fire_hit": 3, &"blood_cast": 2, &"blood_hit": 3, &"shadow_cast": 2,
	&"shadow_hit": 3, &"plague_cast": 2, &"plague_hit": 3, &"lightning_cast": 2,
	&"lightning_hit": 3, &"necro_cast": 2, &"necro_hit": 3,
}
const MIN_GAP := {
	&"hit_flesh": 0.045, &"angel_shatter": 0.05, &"holy_chime": 0.08, &"dash": 0.12,
	&"pickup_item": 0.06, &"coin": 0.035, &"shop_buy": 0.25, &"shop_deny": 0.25,
	&"portal_open": 1.0, &"portal_enter": 1.0, &"unlock": 0.5, &"ability_ready": 0.3,
	&"fire_hit": 0.05, &"blood_hit": 0.05, &"shadow_hit": 0.05, &"plague_hit": 0.05,
	&"lightning_hit": 0.05, &"necro_hit": 0.05,
	&"fire_cast": 0.05, &"blood_cast": 0.06, &"shadow_cast": 0.06, &"plague_cast": 0.06,
	&"lightning_cast": 0.06, &"necro_cast": 0.06,
}
const LOOPS := [&"amb_portal", &"amb_hellfire", &"amb_hell_choir"]


## Short sounds (combat, UI, pickups). Returns name -> AudioStreamWAV.
static func build(s: Object) -> Dictionary:
	var d := {}
	var rng: RandomNumberGenerator = s._rng
	var keep := rng.state
	rng.seed = 0xDE40C0  # own seed so these never shift the older recipes
	for i in 3:
		d[VARIANTS[&"hit_flesh"][i]] = _hit_flesh(s, i)
	d[&"fire_cast"] = _fire_cast(s)
	d[&"fire_hit"] = _fire_hit(s)
	d[&"blood_cast"] = _blood_cast(s)
	d[&"blood_hit"] = _blood_hit(s)
	d[&"shadow_cast"] = _shadow_cast(s)
	d[&"shadow_hit"] = _shadow_hit(s)
	d[&"plague_cast"] = _plague_cast(s)
	d[&"plague_hit"] = _plague_hit(s)
	d[&"lightning_cast"] = _lightning_cast(s)
	d[&"lightning_hit"] = _lightning_hit(s)
	d[&"necro_cast"] = _necro_cast(s)
	d[&"necro_hit"] = _necro_hit(s)
	d[&"angel_shatter"] = _angel_shatter(s)
	d[&"holy_chime"] = _holy_chime(s)
	d[&"dash"] = _dash(s)
	d[&"pickup_item"] = _pickup_item(s)
	d[&"coin"] = _coin(s)
	d[&"shop_buy"] = _shop_buy(s)
	d[&"shop_deny"] = _shop_deny(s)
	d[&"portal_open"] = _portal_open(s)
	d[&"portal_enter"] = _portal_enter(s)
	d[&"unlock"] = _unlock(s)
	d[&"ability_ready"] = _ability_ready(s)
	rng.state = keep
	return d


## Long looping beds (rendered after the core ambience).
static func build_loops(s: Object) -> Dictionary:
	var d := {}
	var rng: RandomNumberGenerator = s._rng
	var keep := rng.state
	rng.seed = 0xB45EC4
	d[&"amb_portal"] = _amb_portal(s)
	d[&"amb_hellfire"] = _amb_hellfire(s)
	d[&"amb_hell_choir"] = _amb_hell_choir(s)
	rng.state = keep
	return d


# ---------------------------------------------------------------- hits

static func _hit_flesh(s: Object, v: int) -> AudioStreamWAV:
	# Blade/claw into flesh: a meaty low knock, a wet smack and a short tearing rasp.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.24)
	var f := 140.0 + v * 22.0 + rng.randf_range(-8.0, 8.0)
	s._tone(0.0, 0.14, f, f * 0.36, 1.0, W_SINE, 0.0008, 2.8)
	s._noise(0.0, 0.06, 0.8, 1600.0 - v * 200.0, 380.0, 1.6, F_BAND, 0.0008, 2.6)
	s._noise(0.008, 0.09, 0.3, 2600.0, 1900.0, 2.4, F_BAND, 0.004, 2.2, 90.0 + v * 25.0, 0.7)
	# A couple of wet "slap" blips.
	for k in 2:
		var bf := rng.randf_range(240.0, 420.0)
		s._tone(rng.randf_range(0.0, 0.03), 0.035, bf, bf * 0.55, 0.3, W_TRI, 0.001, 2.0)
	return s._finish(0.5)


# ---------------------------------------------------------------- elements

static func _fire_cast(s: Object) -> AudioStreamWAV:
	# Ignition: a gas "whumpf", a hissing flare and a spray of embers.
	s._begin(0.6)
	s._tone(0.0, 0.18, 110.0, 48.0, 0.9, W_SINE, 0.004, 2.2)
	s._noise(0.0, 0.22, 0.9, 240.0, 900.0, 0.9, F_LOW, 0.012, 2.0)
	s._noise(0.02, 0.5, 0.6, 1200.0, 3200.0, 1.2, F_BAND, 0.05, 1.9, 13.0, 0.3)
	s._crackle(0.03, 0.5, 0.55, 90.0)
	return s._finish(0.4)


static func _fire_hit(s: Object) -> AudioStreamWAV:
	# Searing contact: a thump, a sharp sizzle that falls away, embers.
	s._begin(0.42)
	s._tone(0.0, 0.1, 160.0, 70.0, 0.6, W_SINE, 0.001, 2.5)
	s._noise(0.0, 0.38, 0.7, 3600.0, 2400.0, 1.0, F_HIGH, 0.002, 2.4)
	s._noise(0.0, 0.18, 0.5, 700.0, 300.0, 1.0, F_BAND, 0.002, 2.0)
	s._crackle(0.0, 0.35, 0.5, 120.0)
	return s._finish(0.42)


static func _blood_cast(s: Object) -> AudioStreamWAV:
	# Blood magic: a heavy heartbeat under a wet, rising slosh of bubbles.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.62)
	s._tone(0.0, 0.12, 70.0, 44.0, 1.0, W_SINE, 0.003, 2.4)
	s._tone(0.16, 0.12, 64.0, 40.0, 0.75, W_SINE, 0.003, 2.4)
	s._noise(0.02, 0.45, 0.55, 300.0, 900.0, 2.4, F_BAND, 0.1, 1.6, 9.0, 0.5)
	for i in 9:
		var f := rng.randf_range(200.0, 460.0)
		s._tone(rng.randf_range(0.04, 0.48), 0.05, f, f * rng.randf_range(1.6, 2.4),
				rng.randf_range(0.2, 0.45), W_SINE, 0.003, 2.0)
	s._lowpass(2600.0)
	return s._finish(0.46)


static func _blood_hit(s: Object) -> AudioStreamWAV:
	# Splat: low thud, a burst of wet noise and quick falling bubbles.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.36)
	s._tone(0.0, 0.14, 120.0, 46.0, 1.0, W_SINE, 0.001, 2.6)
	s._noise(0.0, 0.16, 0.9, 1200.0, 260.0, 1.3, F_LOW, 0.001, 2.2)
	s._noise(0.0, 0.08, 0.35, 2200.0, 1100.0, 2.0, F_BAND, 0.001, 2.4)
	for i in 5:
		var f := rng.randf_range(260.0, 520.0)
		s._tone(rng.randf_range(0.01, 0.2), 0.04, f, f * 0.5, rng.randf_range(0.2, 0.4), W_SINE,
				0.002, 2.0)
	s._lowpass(3000.0)
	return s._finish(0.5)


static func _shadow_cast(s: Object) -> AudioStreamWAV:
	# Shadow: a reversed swell (breath drawn backward) cut off by a dark detuned drone.
	s._begin(0.7)
	s._noise(0.0, 0.42, 0.9, 200.0, 1400.0, 2.0, F_BAND, 0.4, 0.15)
	s._tone(0.0, 0.42, 73.4, 73.4, 0.35, W_SAW, 0.38, 0.2)
	s._tone(0.38, 0.3, 73.4, 55.0, 0.6, W_SAW, 0.004, 2.0)
	s._tone(0.38, 0.3, 77.8, 58.3, 0.45, W_SAW, 0.004, 2.0)
	s._tone(0.38, 0.28, 146.8, 98.0, 0.35, W_SINE, 0.003, 2.2)
	s._lowpass(1400.0)
	s._reverb(0.25, 0.8, 0.55)
	return s._finish(0.42)


static func _shadow_hit(s: Object) -> AudioStreamWAV:
	# A muffled, swallowing thump with a breathy downward smear.
	s._begin(0.45)
	s._tone(0.0, 0.25, 140.0, 38.0, 1.0, W_SINE, 0.002, 2.0)
	s._tone(0.0, 0.25, 280.0, 70.0, 0.25, W_TRI, 0.002, 2.4)
	s._noise(0.0, 0.32, 0.55, 1400.0, 180.0, 1.6, F_BAND, 0.006, 1.8)
	s._lowpass(1600.0)
	return s._finish(0.48)


static func _plague_cast(s: Object) -> AudioStreamWAV:
	# A swarm lifting off: detuned buzzing drones with fast wingbeat flutter and a wet hiss.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.75)
	for i in 6:
		var f := rng.randf_range(170.0, 270.0)
		s._tone(rng.randf_range(0.0, 0.1), 0.6, f, f * rng.randf_range(0.9, 1.15), 0.22, W_PULSE,
				0.08, 1.4, rng.randf_range(5.0, 9.0), 0.03, rng.randf_range(80.0, 130.0), 0.6)
	s._noise(0.0, 0.6, 0.35, 1800.0, 2600.0, 3.0, F_BAND, 0.1, 1.6, 7.0, 0.5)
	s._lowpass(2800.0)
	return s._finish(0.36)


static func _plague_hit(s: Object) -> AudioStreamWAV:
	# A sick, bubbling gurgle with a spatter of hiss.
	s._begin(0.42)
	s._tone(0.0, 0.32, 210.0, 120.0, 0.6, W_TRI, 0.004, 1.8, 26.0, 0.18)
	s._tone(0.0, 0.1, 110.0, 60.0, 0.6, W_SINE, 0.002, 2.4)
	s._noise(0.0, 0.3, 0.45, 2400.0, 1400.0, 2.4, F_BAND, 0.004, 2.0, 22.0, 0.6)
	s._crackle(0.0, 0.25, 0.2, 60.0)
	s._lowpass(3000.0)
	return s._finish(0.44)


static func _lightning_cast(s: Object) -> AudioStreamWAV:
	# Charge-and-release zap: a rising whine, then a dense electric crackle and buzz.
	s._begin(0.6)
	s._tone(0.0, 0.14, 600.0, 2400.0, 0.25, W_SAW, 0.12, 0.3)
	s._tone(0.12, 0.42, 2200.0, 180.0, 0.5, W_SAW, 0.001, 1.8, 0.0, 0.0, 60.0, 0.7)
	s._noise(0.12, 0.4, 0.7, 3600.0, 2800.0, 1.0, F_HIGH, 0.001, 2.0, 50.0, 0.6)
	s._crackle(0.12, 0.42, 0.9, 400.0)
	s._tone(0.12, 0.3, 60.0, 58.0, 0.35, W_SAW, 0.002, 1.6)
	return s._finish(0.36)


static func _lightning_hit(s: Object) -> AudioStreamWAV:
	# Thunderclap snap: a broadband crack, sizzling sparks and a short low boom.
	s._begin(0.5)
	s._noise(0.0, 0.03, 1.0, 3600.0, 3600.0, 1.0, F_HIGH, 0.0002, 1.4)
	s._crackle(0.0, 0.3, 1.0, 500.0)
	s._noise(0.0, 0.25, 0.5, 3200.0, 2600.0, 1.0, F_HIGH, 0.001, 2.4, 70.0, 0.5)
	s._tone(0.0, 0.4, 90.0, 34.0, 0.8, W_SINE, 0.001, 2.0)
	s._noise(0.0, 0.3, 0.4, 500.0, 120.0, 0.8, F_LOW, 0.002, 2.0)
	return s._finish(0.48)


static func _necro_cast(s: Object) -> AudioStreamWAV:
	# A ghost's moan rising out of a rattle of bones.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.9)
	s._meow(0.0, 0.8, 220.0, 330.0, 196.0, 0.8, 500.0, 820.0, 380.0, 5.5, 0.02, 0.0)
	s._tone(0.0, 0.8, 440.0, 392.0, 0.15, W_SINE, 0.15, 1.5, 6.0, 0.012)
	for i in 8:
		s._bell(rng.randf_range(0.0, 0.3), rng.randf_range(700.0, 1300.0), rng.randf_range(0.2, 0.45),
				rng.randf_range(0.01, 0.022), true)
	s._lowpass(2600.0)
	s._reverb(0.3, 0.8, 0.5)
	return s._finish(0.38)


static func _necro_hit(s: Object) -> AudioStreamWAV:
	# Bone crunch: dry splintering clicks over a hollow knock, a faint ghostly tail.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.5)
	s._tone(0.0, 0.08, 320.0, 160.0, 0.7, W_TRI, 0.0008, 2.6)
	s._crackle(0.0, 0.12, 0.9, 260.0)
	for i in 5:
		s._bell(rng.randf_range(0.0, 0.08), rng.randf_range(900.0, 1700.0), rng.randf_range(0.2, 0.4),
				rng.randf_range(0.008, 0.016), true)
	s._tone(0.05, 0.4, 523.0, 466.0, 0.12, W_SINE, 0.05, 1.6, 5.0, 0.01)
	return s._finish(0.44)


# ---------------------------------------------------------------- angels and loot

static func _angel_shatter(s: Object) -> AudioStreamWAV:
	# A light-forged body breaking: a crack, then a cascade of falling glass shards.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.9)
	s._noise(0.0, 0.04, 0.9, 3600.0, 3000.0, 1.0, F_HIGH, 0.0003, 1.6)
	for i in 22:
		# Shards land later and lower as the cascade settles.
		var x := pow(rng.randf(), 1.4)
		s._bell(x * 0.45, rng.randf_range(2400.0, 5600.0) * (1.0 - x * 0.3), rng.randf_range(0.2, 0.6)
				* (1.0 - x * 0.5), rng.randf_range(0.015, 0.05), true)
	s._noise(0.0, 0.4, 0.4, 3600.0, 3200.0, 1.0, F_HIGH, 0.001, 2.6)
	s._tone(0.0, 0.08, 220.0, 120.0, 0.25, W_SINE, 0.001, 2.4)
	return s._finish(0.38)


static func _holy_chime(s: Object) -> AudioStreamWAV:
	# The soul of an angel escaping: a pure rising chime arpeggio dissolving into air.
	s._begin(1.6)
	var notes := [1046.5, 1318.5, 1568.0, 2093.0]
	for i in notes.size():
		s._bell(i * 0.06, float(notes[i]), 0.9 - i * 0.12, 0.18)
	s._noise(0.05, 0.9, 0.12, 3000.0, 3600.0, 1.0, F_HIGH, 0.3, 1.5)
	s._reverb(0.35, 0.8, 0.4)
	return s._finish(0.3)


static func _dash(s: Object) -> AudioStreamWAV:
	# A demon lunge: a fast cloth-and-wing whoosh with a dark sub drop at its tail.
	s._begin(0.38)
	s._noise(0.0, 0.3, 1.0, 500.0, 2600.0, 1.8, F_BAND, 0.06, 2.2)
	s._noise(0.0, 0.25, 0.35, 3000.0, 3600.0, 1.0, F_HIGH, 0.04, 2.6)
	s._tone(0.0, 0.3, 120.0, 45.0, 0.45, W_SINE, 0.02, 2.0)
	return s._finish(0.38)


static func _pickup_item(s: Object) -> AudioStreamWAV:
	# A relic snatched up: a dark two-note chime with a low breath.
	s._begin(0.9)
	s._bell(0.0, 622.25, 0.7, 0.14, true)
	s._bell(0.07, 932.33, 0.6, 0.16, true)
	s._noise(0.0, 0.2, 0.3, 400.0, 1200.0, 3.0, F_BAND, 0.04, 1.6)
	s._tone(0.0, 0.2, 155.6, 155.6, 0.3, W_SINE, 0.01, 2.0)
	s._reverb(0.2, 0.7, 0.5)
	return s._finish(0.3)


static func _coin(s: Object) -> AudioStreamWAV:
	# A single cursed coin: tight metallic clink.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.3)
	var f := rng.randf_range(1900.0, 2300.0)
	s._bell(0.0, f, 0.8, 0.05, true)
	s._bell(0.0, f * 1.34, 0.4, 0.035, true)
	s._noise(0.0, 0.008, 0.4, 3600.0, 3600.0, 1.0, F_HIGH, 0.0002, 1.5)
	return s._finish(0.26)


static func _shop_buy(s: Object) -> AudioStreamWAV:
	# A pact sealed: coins poured, an iron latch, a low minor chord.
	var rng: RandomNumberGenerator = s._rng
	s._begin(1.6)
	for i in 7:
		var f := rng.randf_range(1700.0, 2600.0)
		s._bell(i * 0.035 + rng.randf_range(0.0, 0.015), f, rng.randf_range(0.3, 0.6), 0.04, true)
	s._tone(0.24, 0.05, 240.0, 140.0, 0.8, W_SINE, 0.0005, 3.0)
	s._noise(0.24, 0.02, 0.6, 2000.0, 1500.0, 5.0, F_BAND, 0.0003, 2.0)
	s._bell(0.26, 293.66, 0.6, 0.35, true)
	s._bell(0.26, 349.23, 0.4, 0.3, true)
	s._bell(0.26, 440.0, 0.35, 0.28, true)
	s._reverb(0.25, 0.78, 0.45)
	return s._finish(0.4)


static func _shop_deny(s: Object) -> AudioStreamWAV:
	# Not enough souls: two low, dull, dissonant knocks.
	s._begin(0.4)
	for k in 2:
		var t := k * 0.12
		s._tone(t, 0.1, 150.0, 110.0, 0.8, W_SOFTSQ, 0.001, 2.5)
		s._tone(t, 0.1, 159.0, 117.0, 0.5, W_SOFTSQ, 0.001, 2.5)
	s._lowpass(1500.0)
	return s._finish(0.34)


static func _portal_open(s: Object) -> AudioStreamWAV:
	# The veil tears: a rising roar into a deep boom and a whirling hum.
	s._begin(2.4)
	s._noise(0.0, 1.1, 0.9, 150.0, 1800.0, 1.6, F_BAND, 1.0, 0.2)
	s._tone(0.0, 1.1, 40.0, 110.0, 0.5, W_SAW, 1.0, 0.2)
	s._tone(1.05, 1.3, 70.0, 30.0, 1.0, W_SINE, 0.002, 1.6)
	s._noise(1.05, 0.7, 0.7, 900.0, 120.0, 0.8, F_LOW, 0.002, 2.0)
	s._tone(1.05, 1.3, 110.0, 110.0, 0.35, W_SAW, 0.05, 1.4, 0.0, 0.0, 6.0, 0.6)
	s._lowpass(2400.0)
	s._reverb(0.35, 0.85, 0.45)
	return s._finish(0.6)


static func _portal_enter(s: Object) -> AudioStreamWAV:
	# Pulled through: a sucking downward sweep that collapses into a thud.
	s._begin(1.5)
	s._noise(0.0, 0.8, 1.0, 3000.0, 200.0, 2.0, F_BAND, 0.25, 0.6)
	s._tone(0.0, 0.8, 440.0, 55.0, 0.4, W_SAW, 0.2, 0.8)
	s._tone(0.78, 0.6, 90.0, 30.0, 1.0, W_SINE, 0.002, 2.0)
	s._noise(0.78, 0.4, 0.6, 700.0, 120.0, 0.8, F_LOW, 0.002, 2.0)
	s._lowpass(2600.0)
	s._reverb(0.35, 0.85, 0.45)
	return s._finish(0.58)


static func _unlock(s: Object) -> AudioStreamWAV:
	# A meta-upgrade awakened: a gong and a grave choir chord.
	s._begin(2.6)
	s._add(s._tpl_bell(110.0, 1.8, 0.9), 0.0, 0.7)
	s._add(s._tpl_choir([45, 52, 57, 60], 1.9, 0.2, 0.8, V_OH, 0.94, 1.0, 0.08, 2), 0.05, 0.8)
	s._reverb(0.3, 0.84, 0.45)
	return s._finish(0.55)


static func _ability_ready(s: Object) -> AudioStreamWAV:
	# Cooldown done: a soft dark ping.
	s._begin(0.6)
	s._bell(0.0, 783.99, 0.6, 0.12, true)
	s._tone(0.0, 0.3, 196.0, 196.0, 0.3, W_SINE, 0.005, 2.0)
	return s._finish(0.22)


# ---------------------------------------------------------------- loops

static func _amb_portal(s: Object) -> AudioStreamWAV:
	# Portal hum: beating low saws (whose beat periods divide the loop), a slow swirling band of
	# noise and a faint high shimmer. 6 s loop; rendered 6.5 s so _finish_loop can crossfade.
	s._begin(6.5)
	s._tone(0.0, 6.5, 55.0, 55.0, 0.5, W_SAW, 0.01, 0.0)
	s._tone(0.0, 6.5, 55.5, 55.5, 0.5, W_SAW, 0.01, 0.0)  # 0.5 Hz beat
	s._tone(0.0, 6.5, 110.0, 110.0, 0.3, W_SINE, 0.01, 0.0, 0.0, 0.0, 1.0, 0.5)
	s._tone(0.0, 6.5, 164.8, 164.8, 0.12, W_TRI, 0.01, 0.0, 0.0, 0.0, 0.5, 0.7)
	s._noise(0.0, 6.5, 0.35, 400.0, 400.0, 3.0, F_BAND, 0.01, 0.0, 0.333, 0.8)
	s._noise(0.0, 6.5, 0.08, 3200.0, 3200.0, 1.0, F_HIGH, 0.01, 0.0, 1.5, 0.7)
	s._lowpass(2000.0)
	return s._finish_loop(6.0, 0.55)


static func _amb_hellfire(s: Object) -> AudioStreamWAV:
	# Basecamp Hell: a wall of roaring flame, rumbling deep earth, lava bubbles and fat pops.
	var rng: RandomNumberGenerator = s._rng
	s._begin(8.6)
	s._noise(0.0, 8.6, 0.7, 180.0, 220.0, 0.8, F_LOW, 0.01, 0.0, 0.37, 0.4)
	s._noise(0.0, 8.6, 0.25, 700.0, 900.0, 1.0, F_BAND, 0.01, 0.0, 2.3, 0.45)
	s._noise(0.0, 8.6, 0.4, 60.0, 70.0, 0.7, F_LOW, 0.01, 0.0, 0.125, 0.5)
	for k in 17:
		s._crackle(k * 0.5, 0.5, rng.randf_range(0.35, 0.8), rng.randf_range(25.0, 60.0))
	# Lava: slow fat bubbles rising in pitch, then bursting.
	for k in 11:
		var t := rng.randf_range(0.0, 8.0)
		var f := rng.randf_range(60.0, 110.0)
		s._tone(t, 0.25, f, f * 2.4, rng.randf_range(0.25, 0.5), W_SINE, 0.08, 1.4)
		s._noise(t + 0.24, 0.05, 0.3, 900.0, 400.0, 1.0, F_LOW, 0.001, 2.0)
	return s._finish_loop(8.0, 0.6)


static func _amb_hell_choir(s: Object) -> AudioStreamWAV:
	# A low, distant chant of the damned: two male chords swapping in a dim drone (16 s loop).
	s._begin(18.0)
	s._add(s._tpl_choir([38, 45, 50], 10.0, 0.02, 3.0, V_OO, 1.0, 1.0, 0.05, 2), 0.0, 0.6)
	s._add(s._tpl_choir([37, 44, 49], 10.0, 3.0, 0.02, V_AH, 1.0, 1.0, 0.05, 2), 7.0, 0.55)
	s._lowpass(1200.0)
	return s._finish_loop(16.0, 0.6)
