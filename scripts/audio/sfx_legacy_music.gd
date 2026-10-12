extends RefCounted
## Legacy GDScript music synthesis for the Sfx autoload (menu choir + battle drums), moved out of
## autoload/sfx.gd by code-quality. Only used when the MusicManager autoload is NOT registered:
## MusicManager (docs/team/music.md) plays the real stem-based tracks, and Sfx._render_track()
## returns null before reaching this. Candidate for deletion by the music / sfx owners.
##
## Runs on Sfx's synthesis worker thread. Owns its own music buffer (`_mbuf`); borrows Sfx's
## RNG, saw table and shared templates (_tpl_choir, _tpl_bell, _to_stream).

# Mirrors of Sfx constants (kept local, like the other recipe files, to avoid a cyclic preload).
const SR := 22050
const TAB_SIZE := 4096
const PHASE_MASK := 0x0FFFFFFF  # 4096 << 16 fixed-point phase range
const V_AH := 0
const V_OH := 1

# Menu: D minor, very slow; one chord every MENU_CHORD_LEN s, 8 chords (32 s loop).
const MENU_CHORD_LEN := 4.0
## [string root, choir voices...]
const MENU_CHORDS := [
	[38, 57, 62, 65], [34, 58, 62, 65], [31, 55, 58, 62], [33, 57, 61, 64],
	[38, 57, 62, 69], [36, 60, 65, 69], [34, 55, 58, 62], [33, 52, 57, 61],
]
# Battle: D phrygian-minor, 84 BPM, 8 bars (~22.9 s).
const WAR_BPM := 84.0
## Ostinato per bar (8ths).
const WAR_OSTINATO := [
	[38, 38, 41, 38, 39, 38, 36, 38], [38, 38, 41, 38, 39, 38, 41, 43],
	[38, 38, 41, 38, 39, 38, 36, 38], [39, 39, 43, 39, 41, 39, 38, 36],
	[34, 34, 38, 34, 36, 34, 33, 34], [34, 34, 38, 34, 39, 38, 36, 34],
	[36, 36, 39, 36, 38, 36, 34, 36], [37, 37, 40, 37, 39, 40, 41, 43],
]
## Choir swells: [start bar, length in bars, notes, vowel].
const WAR_SWELLS := [
	[2, 2, [62, 65, 69], V_AH], [6, 2, [57, 61, 64, 69], V_OH],
]

var _s: Object  # the Sfx autoload
var _mbuf := PackedFloat32Array()
var _rng: RandomNumberGenerator
var _saw_tab := PackedFloat32Array()


func _init(sfx: Object) -> void:
	_s = sfx


# Same as Sfx._hz / Sfx._phase_inc (tiny pure helpers, mirrored to avoid a cyclic preload).
static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, float(midi - 69) / 12.0)


static func _phase_inc(f: float) -> int:
	return int(f * float(TAB_SIZE) * 65536.0 / SR)

## Renders one looping track ("menu" or anything else = battle) and returns it as a stream.
func render_track(track: StringName) -> AudioStreamWAV:
	# Shared, read-only oscillator state from Sfx (filled before the worker thread runs).
	_rng = _s._rng
	_saw_tab = _s._saw_tab
	if track == &"menu":
		_render_menu()
	else:
		_render_battle()
	# Normalize.
	var total := _mbuf.size()
	var peak := 0.0
	for i in total:
		peak = maxf(peak, absf(_mbuf[i]))
	if peak > 0.0:
		var k := 0.8 / peak
		for i in total:
			_mbuf[i] *= k
	return _s._to_stream(_mbuf, true)


func _alloc_music(seconds: float) -> void:
	_mbuf = PackedFloat32Array()
	_mbuf.resize(int(round(seconds * SR)))
	_mbuf.fill(0.0)


## Menu: a slow mournful choir over low strings, a distant bell and cold wind.
func _render_menu() -> void:
	var chords := MENU_CHORDS.size()
	var length := MENU_CHORD_LEN * chords
	_alloc_music(length)
	var hold := MENU_CHORD_LEN + 2.4
	var strings := {}  # midi -> template
	for c in chords:
		var chord: Array = MENU_CHORDS[c]
		var t := c * MENU_CHORD_LEN
		var voices: Array = chord.slice(1)
		var vowel := V_AH if c % 2 == 0 else V_OH
		_mix(_s._tpl_choir(voices, hold, 1.8, 2.4, vowel, 1.0, 1.0, 0.07, 2), int(t * SR), 0.55)
		# Low strings: root and octave, slow bowing.
		var root: int = chord[0]
		if not strings.has(root):
			strings[root] = _tpl_string(root, hold, 1.4, 2.2, 520.0, 0.0)
		if not strings.has(root + 12):
			strings[root + 12] = _tpl_string(root + 12, hold, 1.8, 2.2, 700.0, 0.0)
		_mix(strings[root], int(t * SR), 0.36)
		_mix(strings[root + 12], int(t * SR), 0.16)
	# Distant bell: D on the first and fifth chord, A beneath on the third and seventh.
	var bell_d := _distant(_s._tpl_bell(_hz(62), 2.4, 0.6), 1600.0)
	var bell_a := _distant(_s._tpl_bell(_hz(57), 2.0, 0.5), 1400.0)
	_mix(bell_d, int(0.6 * SR), 0.16)
	_mix(bell_d, int((4.0 * MENU_CHORD_LEN + 0.6) * SR), 0.13)
	_mix(bell_a, int((2.0 * MENU_CHORD_LEN + 1.4) * SR), 0.08)
	_mix(bell_a, int((6.0 * MENU_CHORD_LEN + 1.4) * SR), 0.08)
	# Cold wind.
	_mix(_tpl_wind(_mbuf.size(), 420.0, 2), 0, 0.05)


## Battle: tense dark ambient with taiko-like drums, a low ostinato and choir swells.
func _render_battle() -> void:
	var beat := 60.0 / WAR_BPM
	var bar := beat * 4.0
	var bars := WAR_OSTINATO.size()
	_alloc_music(bar * bars)
	var total := _mbuf.size()

	# Drone: low D and A, crossfaded around the loop point.
	_mix(_tpl_drone(_hz(26), total, 300.0), 0, 0.22)
	_mix(_tpl_drone(_hz(33), total, 260.0), 0, 0.1)
	_mix(_tpl_wind(total, 300.0, 3), 0, 0.04)

	# Ostinato (spiccato low strings in 8ths, doubled an octave up, quieter).
	var cache := {}
	for b in bars:
		var row: Array = WAR_OSTINATO[b]
		for e in row.size():
			var m: int = row[e]
			if not cache.has(m):
				cache[m] = _tpl_pluck(m, 0.36, 7.5, 950.0)
			if not cache.has(m + 12):
				cache[m + 12] = _tpl_pluck(m + 12, 0.3, 9.0, 1300.0)
			var t := (b * 4.0 + e * 0.5) * beat
			var accent := 1.0 if e == 0 or e == 4 else (0.8 if e % 2 == 0 else 0.62)
			_mix(cache[m], int(t * SR), 0.3 * accent)
			_mix(cache[m + 12], int(t * SR), 0.1 * accent)

	# Drums.
	var taiko := _tpl_taiko(96.0, 44.0, 4.2, 0.5)
	var taiko_lo := _tpl_taiko(70.0, 34.0, 3.0, 0.35)
	var rim := _tpl_taiko(240.0, 170.0, 22.0, 0.9)
	for b in bars:
		var b0 := b * 4.0
		_mix(taiko_lo, int((b0 * beat) * SR), 0.6)
		_mix(taiko, int((b0 * beat) * SR), 0.35)
		_mix(taiko, int(((b0 + 1.5) * beat) * SR), 0.3)
		_mix(taiko, int(((b0 + 2.0) * beat) * SR), 0.45 if b % 2 == 1 else 0.32)
		_mix(taiko, int(((b0 + 2.75) * beat) * SR), 0.2)
		for e in 8:
			if e % 2 == 1:
				_mix(rim, int(((b0 + e * 0.5) * beat) * SR), 0.06)
		if b % 4 == 3:
			# Gathering roll into the next phrase.
			for s in 4:
				_mix(taiko, int(((b0 + 3.0 + s * 0.25) * beat) * SR), 0.22 + 0.12 * s)

	# Choir swells.
	for sw: Array in WAR_SWELLS:
		var start_bar: int = sw[0]
		var len_bars: int = sw[1]
		var dur := len_bars * bar + 1.0
		var tpl: PackedFloat32Array = _s._tpl_choir(sw[2], dur, len_bars * bar * 0.85, 1.0, int(sw[3]), 1.0, 1.0, 0.09, 2)
		_mix(tpl, int(start_bar * bar * SR), 0.42)

	# High dissonant string tremolo in the second half.
	var trem := _tpl_string(74, bar * 4.0 + 0.6, bar * 2.0, 0.6, 2400.0, 11.0)
	var trem2 := _tpl_string(75, bar * 4.0 + 0.6, bar * 2.5, 0.6, 2400.0, 11.0)
	_mix(trem, int(4.0 * bar * SR), 0.05)
	_mix(trem2, int(4.0 * bar * SR), 0.035)


## Adds `tpl` into the music buffer at sample `at`, wrapping around the loop end.
func _mix(tpl: PackedFloat32Array, at: int, gain: float) -> void:
	var size := _mbuf.size()
	if size == 0:
		return
	var pos := posmod(at, size)
	for j in tpl.size():
		_mbuf[pos] += tpl[j] * gain
		pos += 1
		if pos >= size:
			pos = 0


## Muffles a template (for distant sounds).
func _distant(tpl: PackedFloat32Array, cut: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cut / SR)
	var y := 0.0
	for i in tpl.size():
		y += (tpl[i] - y) * a
		tpl[i] = y
	return tpl


## Bowed string: two detuned saws, two-pole lowpass, vibrato, optional tremolo.
func _tpl_string(m: int, dur: float, atk: float, rel: float, cut: float, trem_hz: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var f := _hz(m)
	var b0 := f * float(TAB_SIZE) * 65536.0 / SR
	var q0 := 0
	var q1 := _rng.randi() & PHASE_MASK
	var d0 := int(b0 * 0.9975)
	var d1 := int(b0 * 1.0025)
	var lc := 1.0 - exp(-TAU * cut / SR)
	var y1 := 0.0
	var y2 := 0.0
	var atk_n := maxf(atk * SR, 1.0)
	var rel_n := maxf(rel * SR, 1.0)
	var rel_start := float(n) - rel_n
	for i in n:
		if (i & 31) == 0:
			var vib := 1.0 + 0.004 * sin(TAU * 4.7 * float(i) / SR)
			d0 = int(b0 * 0.9975 * vib)
			d1 = int(b0 * 1.0025 * vib)
		q0 = (q0 + d0) & PHASE_MASK
		q1 = (q1 + d1) & PHASE_MASK
		var s := (_saw_tab[q0 >> 16] + _saw_tab[q1 >> 16]) * 0.5
		y1 += (s - y1) * lc
		y2 += (y1 - y2) * lc
		var env := 1.0
		if i < atk_n:
			var u := float(i) / atk_n
			env = u * u * (3.0 - 2.0 * u)
		if i > rel_start:
			env *= 1.0 - (float(i) - rel_start) / rel_n
		if trem_hz > 0.0:
			env *= 0.6 + 0.4 * sin(TAU * trem_hz * float(i) / SR)
		a[i] = y2 * env
	return a


## Short spiccato string note (for the ostinato).
func _tpl_pluck(m: int, dur: float, decay_rate: float, cut: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var f := _hz(m)
	var d0 := _phase_inc(f * 0.998)
	var d1 := _phase_inc(f * 1.002)
	var q0 := 0
	var q1 := 0x0300000
	var y1 := 0.0
	var y2 := 0.0
	var e := 1.0
	var k := exp(-decay_rate / SR)
	@warning_ignore("integer_division")  # intentional truncation
	var tail := n / 6
	for i in n:
		q0 = (q0 + d0) & PHASE_MASK
		q1 = (q1 + d1) & PHASE_MASK
		var s := (_saw_tab[q0 >> 16] + _saw_tab[q1 >> 16]) * 0.5
		# The filter opens with the bow bite and closes as it decays.
		var lc := 1.0 - exp(-TAU * (cut * (0.35 + 0.65 * e)) / SR)
		y1 += (s - y1) * lc
		y2 += (y1 - y2) * lc
		var env := minf(1.0, float(i) / 90.0) * e
		if i > n - tail:
			env *= float(n - i) / float(tail)
		a[i] = y2 * env
		e *= k
	return a


## Loop-length drone with crossfaded ends (mix at 0; the tail wraps over the head).
func _tpl_drone(f: float, loop_n: int, cut: float) -> PackedFloat32Array:
	var xf := int(1.5 * SR)
	var n := loop_n + xf
	var a := PackedFloat32Array()
	a.resize(n)
	var p0 := 0.0
	var p1 := 0.37
	var p2 := 0.71
	var i0 := f / SR
	var i1 := f * 1.004 / SR
	var i2 := f * 2.003 / SR
	var lc := 1.0 - exp(-TAU * cut / SR)
	var y1 := 0.0
	var y2 := 0.0
	var swell_w := TAU * 2.0 / float(loop_n)
	for i in n:
		p0 += i0
		p1 += i1
		p2 += i2
		p0 -= floorf(p0)
		p1 -= floorf(p1)
		p2 -= floorf(p2)
		var s := _saw_tab[int(p0 * TAB_SIZE) & (TAB_SIZE - 1)] + _saw_tab[int(p1 * TAB_SIZE) & (TAB_SIZE - 1)] \
			+ 0.3 * _saw_tab[int(p2 * TAB_SIZE) & (TAB_SIZE - 1)]
		y1 += (s - y1) * lc
		y2 += (y1 - y2) * lc
		var env := 0.75 + 0.25 * sin(swell_w * float(i))
		if i < xf:
			env *= float(i) / float(xf)
		elif i >= loop_n:
			env *= 1.0 - float(i - loop_n) / float(xf)
		a[i] = y2 * env * 0.4
	return a


## Loop-length filtered wind with slow gusts (crossfaded like the drone).
func _tpl_wind(loop_n: int, cut: float, gusts: int) -> PackedFloat32Array:
	var xf := int(1.5 * SR)
	var n := loop_n + xf
	var a := PackedFloat32Array()
	a.resize(n)
	var low := 0.0
	var band := 0.0
	var gw := TAU * float(gusts) / float(loop_n)
	for i in n:
		var gust := 0.55 + 0.45 * sin(gw * float(i))
		var fc := cut * (0.7 + 0.6 * gust)
		var g := 2.0 * sin(PI * fc / SR)
		var w := _rng.randf() * 2.0 - 1.0
		low += g * band
		var high := w - low - 0.6 * band
		band += g * high
		var env := gust
		if i < xf:
			env *= float(i) / float(xf)
		elif i >= loop_n:
			env *= 1.0 - float(i - loop_n) / float(xf)
		a[i] = band * env
	return a


## Taiko-like drum: a falling low body, a second membrane mode and a skin slap.
func _tpl_taiko(f_hi: float, f_lo: float, decay_rate: float, slap: float) -> PackedFloat32Array:
	var n := int(minf(4.5 / decay_rate + 0.05, 1.4) * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var phase := 0.0
	var phase2 := 0.0
	var e := 1.0
	var e2 := 1.0
	var k := exp(-decay_rate / SR)
	var k2 := exp(-decay_rate * 2.6 / SR)
	var lp := 0.0
	var slap_n := int(0.03 * SR)
	for i in n:
		var x := float(i) / float(n)
		var f := f_lo + (f_hi - f_lo) * exp(-x * 9.0)
		phase += f / SR
		phase2 += f * 1.59 / SR
		var v := sin(TAU * phase) * e + 0.35 * sin(TAU * phase2) * e2
		if i < slap_n:
			var w := _rng.randf() * 2.0 - 1.0
			lp += (w - lp) * 0.35
			v += lp * slap * (1.0 - float(i) / slap_n)
		var fade := minf(1.0, float(n - i) / 256.0)
		a[i] = v * minf(1.0, float(i) / 12.0) * fade
		e *= k
		e2 *= k2
	return a
