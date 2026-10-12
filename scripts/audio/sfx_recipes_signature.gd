extends RefCounted
## Round-5 procedural recipes for the Sfx autoload (owner: sfx role, docs/team/sfx.md):
## map-signature enemy mechanics (bell toll ring, mirror beam, mimic snap, harpy Ichor steal,
## revenant rising, frost shatter, djinn blink) and Nhazgul's swarm-and-chitin player sounds
## (dash_swarm, hurt_swarm, death_swarm; swapped in by Sfx.DEMON_SOUNDS) plus his movement loop
## amb_fly_buzz, and Iscariel the Turncoat's cracked-choir-and-hellfire set (*_turncoat).
## Runs on Sfx's synthesis worker thread like sfx_recipes.gd.

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

const MAX_VOICES := {
	&"bell_ring": 2, &"mirror_beam": 2, &"mimic_snap": 1, &"ichor_steal": 1, &"revenant_rise": 2,
	&"frost_shatter": 2, &"djinn_blink": 2, &"dash_swarm": 1, &"hurt_swarm": 1, &"death_swarm": 1,
	&"dash_turncoat": 1, &"hurt_turncoat": 1, &"death_turncoat": 1, &"heartbeat": 1,
	&"last_stand": 1, &"slain": 2,
}
const MIN_GAP := {
	&"bell_ring": 0.25, &"mirror_beam": 0.2, &"mimic_snap": 0.5, &"ichor_steal": 0.4,
	&"revenant_rise": 0.3, &"frost_shatter": 0.1, &"djinn_blink": 0.2, &"hurt_swarm": 0.45,
	&"death_swarm": 0.8, &"dash_swarm": 0.08, &"hurt_turncoat": 0.45, &"death_turncoat": 0.8,
	&"dash_turncoat": 0.08, &"heartbeat": 0.3, &"last_stand": 2.0, &"slain": 0.25,
}


static func build(s: Object) -> Dictionary:
	var d := {}
	var rng: RandomNumberGenerator = s._rng
	var keep := rng.state
	rng.seed = 0x5197
	d[&"bell_ring"] = _bell_ring(s)
	d[&"mirror_beam"] = _mirror_beam(s)
	d[&"mimic_snap"] = _mimic_snap(s)
	d[&"ichor_steal"] = _ichor_steal(s)
	d[&"revenant_rise"] = _revenant_rise(s)
	d[&"frost_shatter"] = _frost_shatter(s)
	d[&"djinn_blink"] = _djinn_blink(s)
	d[&"dash_swarm"] = _dash_swarm(s)
	d[&"hurt_swarm"] = _hurt_swarm(s)
	d[&"death_swarm"] = _death_swarm(s)
	d[&"dash_turncoat"] = _dash_turncoat(s)
	d[&"hurt_turncoat"] = _hurt_turncoat(s)
	d[&"death_turncoat"] = _death_turncoat(s)
	d[&"amb_fly_buzz"] = _amb_fly_buzz(s)
	d[&"heartbeat"] = _heartbeat(s)
	d[&"last_stand"] = _last_stand(s)
	d[&"slain"] = _slain(s)
	rng.state = keep
	return d


# ---------------------------------------------------------------- signature mechanics

static func _bell_ring(s: Object) -> AudioStreamWAV:
	# A hand-bell's toll thrown as a ring: a cold struck bell with a widening, glassy shimmer.
	s._begin(1.6)
	s._add(s._tpl_bell(392.0, 0.9, 1.0), 0.0, 0.7)
	s._bell(0.0, 1568.0, 0.3, 0.2)
	s._noise(0.02, 1.0, 0.25, 2400.0, 3600.0, 2.0, F_BAND, 0.05, 1.6, 8.0, 0.5)
	s._reverb(0.3, 0.82, 0.4)
	return s._finish(0.42)


static func _mirror_beam(s: Object) -> AudioStreamWAV:
	# A sun-mirror flash: a quick rising glint, then a bright lance of light with a ringing edge.
	s._begin(0.9)
	s._tone(0.0, 0.18, 900.0, 2200.0, 0.35, W_SINE, 0.15, 0.3)
	s._bell(0.17, 2637.0, 0.5, 0.1)
	s._tone(0.17, 0.6, 1318.5, 1300.0, 0.45, W_SINE, 0.005, 1.4, 7.0, 0.004, 40.0, 0.3)
	s._tone(0.17, 0.6, 659.3, 655.0, 0.3, W_TRI, 0.005, 1.6)
	s._noise(0.17, 0.55, 0.3, 3400.0, 3000.0, 1.0, F_HIGH, 0.005, 1.6)
	return s._finish(0.36)


static func _mimic_snap(s: Object) -> AudioStreamWAV:
	# The chest wakes: a hinge creak, the lid slamming open, a wet tongue and a low growl.
	s._begin(1.0)
	s._tone(0.0, 0.25, 380.0, 520.0, 0.15, W_SAW, 0.05, 1.4, 0.0, 0.0, 34.0, 0.7)  # creak
	s._tone(0.24, 0.1, 180.0, 80.0, 1.0, W_TRI, 0.0005, 2.4)  # lid slam
	s._noise(0.24, 0.06, 0.8, 1800.0, 700.0, 1.4, F_BAND, 0.0005, 2.2)
	s._bell(0.24, 1760.0, 0.3, 0.05, true)  # gilt rattle
	s._noise(0.32, 0.25, 0.4, 900.0, 1500.0, 2.0, F_BAND, 0.02, 1.6, 16.0, 0.6)  # slurp
	s._meow(0.4, 0.55, 95.0, 110.0, 80.0, 0.7, 450.0, 520.0, 380.0, 0.0, 0.0, 28.0)
	return s._finish(0.5)


static func _ichor_steal(s: Object) -> AudioStreamWAV:
	# A harpy snatches Ichor: coins flicked upward and away, and a mocking screech.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.9)
	for i in 5:
		s._bell(i * 0.04, 1900.0 + i * 260.0 + rng.randf_range(-60.0, 60.0), 0.45 - i * 0.05, 0.035, true)
	s._noise(0.0, 0.3, 0.5, 900.0, 3000.0, 1.6, F_BAND, 0.05, 1.6)
	s._tone(0.2, 0.45, 1600.0, 2300.0, 0.4, W_TRI, 0.03, 1.6, 24.0, 0.03)
	return s._finish(0.4)


static func _revenant_rise(s: Object) -> AudioStreamWAV:
	# A burned crusader rises: embers sucked upward, a groan from the ashes, armor clanking upright.
	s._begin(1.6)
	s._noise(0.0, 0.8, 0.8, 200.0, 1600.0, 1.2, F_BAND, 0.6, 0.4)
	s._crackle(0.0, 0.9, 0.5, 80.0)
	s._meow(0.5, 0.9, 85.0, 105.0, 70.0, 0.8, 420.0, 520.0, 330.0, 3.0, 0.02, 20.0)
	s._bell(0.75, 640.0, 0.5, 0.08, true)
	s._bell(0.95, 590.0, 0.4, 0.08, true)
	s._lowpass(2600.0)
	return s._finish(0.5)


static func _frost_shatter(s: Object) -> AudioStreamWAV:
	# Ice tomb bursting: a deep crack, then crystalline shards scattering outward.
	var rng: RandomNumberGenerator = s._rng
	s._begin(1.1)
	s._noise(0.0, 0.05, 1.0, 3000.0, 1200.0, 1.0, F_BAND, 0.0003, 1.6)
	s._tone(0.0, 0.4, 120.0, 40.0, 0.8, W_SINE, 0.001, 2.0)
	for i in 18:
		var x := pow(rng.randf(), 1.2)
		s._bell(x * 0.5, rng.randf_range(1500.0, 3800.0), rng.randf_range(0.2, 0.5) * (1.0 - x * 0.5),
				rng.randf_range(0.02, 0.05), true)
	s._noise(0.0, 0.5, 0.3, 3600.0, 3000.0, 1.0, F_HIGH, 0.002, 2.4)
	return s._finish(0.48)


static func _djinn_blink(s: Object) -> AudioStreamWAV:
	# A storm djinn bursts apart and re-forms: an inward gust, a thunder pop, a crackling arrival.
	s._begin(0.9)
	s._noise(0.0, 0.25, 0.8, 3000.0, 400.0, 1.6, F_BAND, 0.2, 0.4)
	s._noise(0.25, 0.03, 1.0, 3600.0, 3600.0, 1.0, F_HIGH, 0.0002, 1.4)
	s._tone(0.25, 0.35, 110.0, 40.0, 0.8, W_SINE, 0.001, 2.0)
	s._crackle(0.25, 0.4, 0.8, 350.0)
	s._noise(0.3, 0.4, 0.4, 600.0, 2200.0, 1.4, F_BAND, 0.05, 1.6)
	return s._finish(0.44)


# ---------------------------------------------------------------- Nhazgul, the Plague Hive

static func _dash_swarm(s: Object) -> AudioStreamWAV:
	# The hive lunges: a rush of a thousand wings and a dry chitin rattle.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.5)
	for i in 6:
		var f := rng.randf_range(180.0, 300.0)
		s._tone(0.0, 0.42, f, f * 1.15, 0.18, W_PULSE, 0.04, 1.6, 0.0, 0.0, rng.randf_range(90.0, 140.0), 0.7)
	s._noise(0.0, 0.35, 0.8, 600.0, 2600.0, 1.6, F_BAND, 0.05, 2.0, 110.0, 0.4)
	s._crackle(0.0, 0.3, 0.4, 260.0)
	s._lowpass(3200.0)
	return s._finish(0.4)


static func _hurt_swarm(s: Object) -> AudioStreamWAV:
	# The hive is struck: a chitin crack and an angry burst of buzzing.
	var rng: RandomNumberGenerator = s._rng
	s._begin(0.5)
	s._noise(0.0, 0.03, 0.9, 2800.0, 1600.0, 1.4, F_BAND, 0.0003, 1.8)
	s._crackle(0.0, 0.1, 0.7, 400.0)
	s._tone(0.0, 0.12, 120.0, 60.0, 0.6, W_SINE, 0.001, 2.4)
	for i in 4:
		var f := rng.randf_range(220.0, 340.0)
		s._tone(0.03, 0.4, f * 1.2, f, 0.2, W_PULSE, 0.01, 1.8, 0.0, 0.0, rng.randf_range(100.0, 150.0), 0.7)
	s._lowpass(3400.0)
	return s._finish(0.46)


static func _death_swarm(s: Object) -> AudioStreamWAV:
	# The hive collapses: the shell splits, the swarm screams up and scatters, then dwindles away.
	var rng: RandomNumberGenerator = s._rng
	s._begin(3.2)
	s._noise(0.0, 0.06, 1.0, 2600.0, 1200.0, 1.2, F_BAND, 0.0003, 1.6)
	s._crackle(0.0, 0.4, 0.8, 300.0)
	s._tone(0.0, 1.6, 90.0, 28.0, 0.9, W_SINE, 0.002, 1.6)
	for i in 10:
		var f := rng.randf_range(160.0, 360.0)
		s._tone(rng.randf_range(0.05, 0.4), rng.randf_range(1.6, 2.6), f, f * rng.randf_range(0.6, 1.4), 0.12,
				W_PULSE, 0.15, 1.2, 0.0, 0.0, rng.randf_range(80.0, 160.0), 0.7)
	s._noise(0.05, 2.6, 0.4, 900.0, 300.0, 1.4, F_BAND, 0.2, 1.4, 120.0, 0.4)
	s._lowpass(3000.0)
	s._reverb(0.3, 0.84, 0.45)
	return s._finish(0.6)


# ---------------------------------------------------------------- Iscariel, the Turncoat

## A choir chord with one voice a semitone sour: the "cracked" holy half of Iscariel.
static func _cracked_choir(s: Object, notes: Array, t0: float, dur: float, atk: float, rel: float,
		gain: float, sag: float) -> void:
	s._add(s._tpl_choir(notes, dur, atk, rel, V_AH, 1.0, sag, 0.12, 2), t0, gain)
	s._add(s._tpl_choir([int(notes[notes.size() - 1]) + 1], dur, atk, rel, V_EH, 1.0, sag * 0.97, 0.2, 1),
			t0, gain * 0.45)


static func _dash_turncoat(s: Object) -> AudioStreamWAV:
	# One wing of light, one of fire: a feathered whoosh, a sour choir flick, a hellfire flare.
	s._begin(0.6)
	s._noise(0.0, 0.3, 0.9, 400.0, 2400.0, 1.6, F_BAND, 0.05, 2.0)
	_cracked_choir(s, [69, 76], 0.0, 0.35, 0.02, 0.2, 0.45, 0.94)
	s._noise(0.05, 0.4, 0.5, 260.0, 900.0, 0.8, F_LOW, 0.02, 1.8, 13.0, 0.3)
	s._crackle(0.05, 0.35, 0.4, 120.0)
	return s._finish(0.4)


static func _hurt_turncoat(s: Object) -> AudioStreamWAV:
	# Struck: a choir note that cracks and drops, over a hiss of fire.
	s._begin(0.6)
	_cracked_choir(s, [64, 71], 0.0, 0.45, 0.005, 0.25, 0.8, 0.8)
	s._tone(0.0, 0.12, 120.0, 60.0, 0.5, W_SINE, 0.001, 2.4)
	s._noise(0.0, 0.4, 0.45, 900.0, 600.0, 1.0, F_BAND, 0.005, 1.8)
	s._crackle(0.0, 0.3, 0.35, 100.0)
	return s._finish(0.46)


static func _death_turncoat(s: Object) -> AudioStreamWAV:
	# The Turncoat falls: the holy chord sours and sinks, a bell cracks, the hellfire roars over it.
	s._begin(4.0)
	_cracked_choir(s, [57, 64, 69], 0.0, 3.0, 0.05, 1.6, 0.8, 0.7)
	s._bell(0.4, 880.0, 0.5, 0.3, true)
	s._noise(0.4, 0.05, 0.6, 3000.0, 1500.0, 1.0, F_BAND, 0.0003, 1.6)  # the crack
	s._noise(0.6, 3.2, 0.9, 200.0, 700.0, 0.8, F_LOW, 0.5, 1.2, 7.0, 0.35)
	s._crackle(0.6, 3.0, 0.45, 60.0)
	s._tone(0.0, 2.8, 70.0, 26.0, 0.8, W_SINE, 0.05, 1.5)
	s._lowpass(3000.0)
	s._reverb(0.35, 0.86, 0.45)
	return s._finish(0.62)


# ---------------------------------------------------------------- Nhazgul's movement loop

## The hive's flies (2 s loop, MoveLoop under the player): many detuned wingbeat buzzes whose
## rates are whole cycles per loop, with a slow swirl, so the cloud never sounds like one note.
static func _amb_fly_buzz(s: Object) -> AudioStreamWAV:
	var rng: RandomNumberGenerator = s._rng
	s._begin(2.3)
	for i in 9:
		var f: float = round(rng.randf_range(170.0, 290.0) * 2.0) / 2.0  # whole cycles per 2 s
		s._tone(0.0, 2.3, f, f, 0.14, W_PULSE, 0.01, 0.0, rng.randf_range(2.0, 5.0), 0.02,
				float(rng.randi_range(1, 4)) * 0.5, 0.5)
	s._noise(0.0, 2.3, 0.25, 900.0, 900.0, 2.0, F_BAND, 0.01, 0.0, 1.5, 0.6)
	s._lowpass(2600.0)
	return s._finish_loop(2.0, 0.5)


# ---------------------------------------------------------------- player state (gameplay hooks)

static func _heartbeat(s: Object) -> AudioStreamWAV:
	# Low-HP pulse (game_feel.gd plays one per beat, up to 118 bpm, so it fits in 0.45 s):
	# a deep "lub" and a softer "dub", felt more than heard. Dry and unducked on purpose.
	s._begin(0.45)
	s._tone(0.0, 0.14, 62.0, 40.0, 1.0, W_SINE, 0.004, 2.2)
	s._noise(0.0, 0.05, 0.25, 300.0, 120.0, 0.8, F_LOW, 0.002, 2.2)
	s._tone(0.17, 0.13, 56.0, 38.0, 0.65, W_SINE, 0.004, 2.4)
	s._noise(0.17, 0.04, 0.15, 260.0, 110.0, 0.8, F_LOW, 0.002, 2.2)
	s._lowpass(500.0)
	return s._finish(0.6)


static func _last_stand(s: Object) -> AudioStreamWAV:
	# Once-per-run lethal save: a hellfire detonation, then the demon's defiant roar over the flames.
	s._begin(2.6)
	s._tone(0.0, 0.8, 90.0, 26.0, 1.0, W_SINE, 0.001, 1.6)
	s._noise(0.0, 0.08, 0.9, 3000.0, 1400.0, 1.0, F_BAND, 0.0003, 1.6)
	s._noise(0.0, 1.8, 0.9, 300.0, 1200.0, 0.9, F_LOW, 0.01, 1.4, 9.0, 0.35)
	s._crackle(0.0, 1.6, 0.6, 110.0)
	s._meow(0.25, 1.6, 110.0, 150.0, 95.0, 1.0, 560.0, 820.0, 430.0, 4.0, 0.02, 34.0)
	s._tone(0.25, 1.4, 55.0, 49.0, 0.4, W_SAW, 0.08, 1.4)
	s._lowpass(3000.0)
	s._reverb(0.3, 0.84, 0.45)
	return s._finish(0.72)


static func _slain(s: Object) -> AudioStreamWAV:
	# Elite kill confirm ("SLAIN"): one short, dark iron bell struck once with a hellfire breath;
	# shorter and lower than the holy `toll`, so it reads as the demon's triumph and clears fast.
	s._begin(1.6)
	s._add(s._tpl_bell(110.0, 0.9, 0.8), 0.0, 0.8)
	s._tone(0.0, 0.25, 80.0, 40.0, 0.6, W_SINE, 0.001, 2.0)
	s._noise(0.0, 0.6, 0.35, 300.0, 900.0, 1.0, F_LOW, 0.02, 1.6)
	s._lowpass(2400.0)
	return s._finish(0.48)
