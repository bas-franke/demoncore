extends Node
## Game feel director: listens to Game's gameplay signals and drives the camera rig, hitstop,
## the post-process pass (res://shaders/post_fx.gdshader via group "post_fx") and a low-pass
## filter on the Master bus. Purely presentational; add one instance to the run scene.
##
##   big hits      : hard freeze-frame (fighter hitstop) + camera kick toward the impact (adaptive threshold)
##   elite kills   : freeze-frame + kick + tiny zoom punch
##   (every hit also freezes + shakes the struck enemy alone: Enemy HITFREEZE_*)
##   kill streaks  : subtle chromatic pulse that swells with the streak
##   player hit    : crimson edge flash scaled by damage; heavy hits kick from the attacker + hitstop
##   low HP        : heartbeat-paced crimson vignette, desaturation, muffled (low-passed) audio
##   boss          : intro push-in toward the descending boss, slam punch on landing, enrage /
##                   death hitstops and punches
## Camera motion respects Settings.screen_shake (the rig scales it); hitstops are rate limited.

## HP fraction at which the near-death state starts fading in (full at `low_hp_full`).
@export var low_hp_start := 0.32
@export var low_hp_full := 0.08
## Master-bus low-pass cutoff at full near-death (Hz). 20 kHz = open.
@export var muffle_cutoff := 650.0
## Minimum real seconds between "minor" hitstops (big hits, elite kills, player hits).
@export var hitstop_gap := 0.22

const OPEN_CUTOFF := 20500.0

var _mat: ShaderMaterial
var _lowpass: AudioEffectLowPassFilter
var _lowpass_idx := -1

var _low := 0.0
var _beat_phase := 0.0
var _flash := 0.0
var _chroma := 0.0
var _streak := 0.0
var _streak_tier := 0
var _hit_avg := 0.0
var _hit_count := 0
var _last_stop_ms := -100000

var _boss: Node3D
var _boss_landed := false
var _boss_enraged := false
var _boss_dying := false
var _boss_felled := false
var _boss_poll := 0.0


func _ready() -> void:
	Game.enemy_hit.connect(_on_enemy_hit)
	Game.enemy_died.connect(_on_enemy_died)
	Game.player_hit.connect(_on_player_hit)
	Game.boss_spawned.connect(_on_boss_spawned)
	Game.boss_died.connect(_on_boss_died)
	_setup_lowpass()


func _exit_tree() -> void:
	_teardown_lowpass()


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_update_low_hp(delta)
	_flash = maxf(_flash - delta * 3.2, 0.0)
	_chroma = maxf(_chroma - delta * 1.6, 0.0)
	_streak *= exp(-delta / 1.1)
	if _streak < 4.0:
		_streak_tier = 0
	_boss_poll -= delta
	if _boss_poll <= 0.0:
		_boss_poll = 0.2
		_poll_boss()
	_apply_post()
	_apply_audio()


func _update_low_hp(delta: float) -> void:
	var target := 0.0
	var p := Game.player
	if is_instance_valid(p) and p.max_hp > 0.0:
		var ratio := clampf(p.hp / p.max_hp, 0.0, 1.0)
		target = clampf((low_hp_start - ratio) / maxf(low_hp_start - low_hp_full, 0.01), 0.0, 1.0)
		target = target * target * (3.0 - 2.0 * target)
	# fade in fairly quickly, recover slowly (relief after a heal)
	var rate := 2.5 if target > _low else 0.9
	_low = move_toward(_low, target, rate * delta)
	# heartbeat: 66 -> 118 bpm as death approaches
	var bpm := lerpf(66.0, 118.0, _low)
	var next := fmod(_beat_phase + delta * bpm / 60.0, 1.0)
	# A new beat (phase wrapped): audible lub-dub when near death (Sfx &"heartbeat", sfx role).
	if next < _beat_phase and _low > 0.15 and not get_tree().paused:
		Sfx.play(&"heartbeat", 0.02, lerpf(-16.0, -3.0, _low))
	_beat_phase = next


func _heartbeat() -> float:
	var t := _beat_phase
	var lub := exp(-pow((t - 0.06) / 0.045, 2.0))
	var dub := 0.62 * exp(-pow((t - 0.27) / 0.055, 2.0))
	return clampf(lub + dub, 0.0, 1.0)


func _apply_post() -> void:
	if _mat == null:
		var rect := get_tree().get_first_node_in_group(&"post_fx") as CanvasItem
		if rect == null or not (rect.material is ShaderMaterial):
			return
		_mat = rect.material
	_mat.set_shader_parameter(&"low_hp", _low)
	_mat.set_shader_parameter(&"heartbeat", _heartbeat())
	# Settings.reduce_flashes (accessibility, UI role) keeps a faint cue instead of a full flash.
	_mat.set_shader_parameter(&"hit_flash", _flash * (0.25 if Settings.get(&"reduce_flashes") == true else 1.0))
	_mat.set_shader_parameter(&"chroma_pulse", _chroma * lerpf(0.5, 1.0, clampf(Settings.screen_shake, 0.0, 1.0)))


# ---------------------------------------------------------------- audio muffle

func _setup_lowpass() -> void:
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = OPEN_CUTOFF
	_lowpass.resonance = 0.6
	# Before Master's limiter (index 0) so the limiter still catches the filtered mix.
	AudioServer.add_bus_effect(0, _lowpass, 0)
	_lowpass_idx = 0
	AudioServer.set_bus_effect_enabled(0, _lowpass_idx, false)


func _teardown_lowpass() -> void:
	if _lowpass == null:
		return
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _lowpass:
			AudioServer.remove_bus_effect(0, i)
			break
	_lowpass = null
	_lowpass_idx = -1


func _apply_audio() -> void:
	if _lowpass == null:
		return
	# Another system may have added effects since; re-find ours if the slot moved.
	if _lowpass_idx >= AudioServer.get_bus_effect_count(0) or AudioServer.get_bus_effect(0, _lowpass_idx) != _lowpass:
		_lowpass_idx = -1
		for i in AudioServer.get_bus_effect_count(0):
			if AudioServer.get_bus_effect(0, i) == _lowpass:
				_lowpass_idx = i
				break
		if _lowpass_idx < 0:
			_lowpass = null
			return
	var amount := _low * (0.92 + 0.08 * _heartbeat())
	# exponential sweep sounds even across the range
	_lowpass.cutoff_hz = OPEN_CUTOFF * pow(muffle_cutoff / OPEN_CUTOFF, amount)
	var on := amount > 0.01
	if AudioServer.is_bus_effect_enabled(0, _lowpass_idx) != on:
		AudioServer.set_bus_effect_enabled(0, _lowpass_idx, on)


# ---------------------------------------------------------------- events

func _on_enemy_hit(pos: Vector3, amount: float) -> void:
	# Adaptive "big hit": well above the running average of recent hits.
	_hit_count += 1
	_hit_avg = amount if _hit_count == 1 else lerpf(_hit_avg, amount, 0.04)
	if _hit_count < 15 or amount < maxf(_hit_avg * 3.0, 25.0):
		return
	# Scaled by how far above the average the hit is: a 3x hit barely stops, a 10x hit lands hard.
	# A near-total freeze (2D-fighter hitstop: ~3-7 frames at 60 fps), not a slow-mo dip. Every hit
	# also freezes the struck enemy itself (Enemy HITFREEZE_*).
	var k := clampf((amount / maxf(_hit_avg, 1.0) - 3.0) / 7.0, 0.0, 1.0)
	_kick_toward(pos, lerpf(0.3, 0.7, k))
	_shake(lerpf(0.06, 0.2, k))
	_try_hitstop(lerpf(0.05, 0.11, k), 0.02)


func _on_enemy_died(pos: Vector3, data: Resource) -> void:
	_streak += 1.0
	if _streak >= 5.0:
		_chroma = maxf(_chroma, minf((_streak - 5.0) * 0.025, 0.22))
	var tier := 0
	if _streak >= 30.0:
		tier = 3
	elif _streak >= 18.0:
		tier = 2
	elif _streak >= 9.0:
		tier = 1
	if tier > _streak_tier:
		_streak_tier = tier
		_chroma = maxf(_chroma, 0.25 + 0.15 * tier)
	var ed := data as EnemyData
	if ed and ed.xp_value >= Enemy.ELITE_XP:
		_kick_toward(pos, 0.55)
		_zoom_punch(-0.05)
		_chroma = maxf(_chroma, 0.3)
		_try_hitstop(0.09, 0.02)
		_kill_confirm(pos, ed)


## Elite kill confirm: a hellfire ring on the ground, a gold "SLAIN" word over the corpse and a
## low toll, so a big kill reads even in a crowded fight. (gameplay)
func _kill_confirm(pos: Vector3, ed: EnemyData) -> void:
	var h := ed.size * 1.6 + ed.hover + 0.6
	DamageNumber.spawn_text("SLAIN", pos + Vector3(0.0, h, 0.0), DamageNumber.GOLD, 44)
	EnemyModel.shockwave(pos, 2.4 * ed.size, Art.HELLFIRE, 0.5)
	Sfx.play_at(&"slain", pos, 0.04, -5.0)  # short dark kill-confirm bell (sfx), not the long holy toll


func _on_player_hit(amount: float) -> void:
	var p := Game.player
	if not is_instance_valid(p) or p.max_hp <= 0.0:
		return
	var frac := amount / p.max_hp
	# Contact damage arrives as tiny per-frame ticks; those barely register. Real blows flash.
	_flash = minf(_flash + frac * 5.5, 0.85)
	if frac >= 0.06:
		_flash = maxf(_flash, minf(0.35 + frac * 2.5, 0.85))
		var src := _nearest_enemy(p.global_position)
		if src != Vector3.INF:
			_kick_toward(src, clampf(frac * 6.0, 0.3, 1.0))
		_shake(clampf(frac * 1.5, 0.1, 0.3))
		if frac >= 0.12:
			_try_hitstop(clampf(0.04 + frac * 0.15, 0.04, 0.08), 0.06)


func _on_boss_spawned(boss: Node3D) -> void:
	_track_boss(boss)


func _on_boss_died(_pos: Vector3) -> void:
	_boss_felled_fx()


# ---------------------------------------------------------------- boss

func _poll_boss() -> void:
	if not is_instance_valid(_boss):
		if _boss != null and not _boss_felled and _boss_dying:
			_boss_felled_fx()
		_boss = null
		var b := get_tree().get_first_node_in_group(&"boss") as Node3D
		if b:
			_track_boss(b)
		return
	if not _boss_landed and (bool(_boss.get(&"_landed")) or int(_boss.get(&"phase")) != 0):
		_boss_landed = true
		_on_boss_landed()
	if not _boss_enraged and bool(_boss.get(&"is_enraged")):
		_boss_enraged = true
		_zoom_punch(-0.1)
		_chroma = maxf(_chroma, 0.6)
		_kick_toward(_boss.global_position, 0.6)
		Game.hitstop(0.07, 0.04)
	if not _boss_dying and bool(_boss.get(&"is_dying")):
		_boss_dying = true
		_zoom_punch(-0.1)
		_set_cam(&"set_focus_bias", [_boss.global_position, 0.3])
		Game.hitstop(0.08, 0.03)
	if _boss_dying and not _boss_felled and _boss.get(&"phase") != null:
		# Boss.Phase.FELLED: the final flash
		if int(_boss.get(&"phase")) == Boss.Phase.FELLED:
			_boss_felled_fx()


func _track_boss(boss: Node3D) -> void:
	if boss == null or boss == _boss:
		return
	_boss = boss
	_boss_landed = false
	_boss_enraged = bool(boss.get(&"is_enraged"))
	_boss_dying = false
	_boss_felled = false
	# Intro: slow push-in, leaning toward the descending herald.
	_set_cam(&"set_zoom", [0.84, 1.1])
	_set_cam(&"set_focus_bias", [boss.global_position, 0.35])


func _on_boss_landed() -> void:
	# Slam: punch in hard, then breathe back out to the normal framing.
	_zoom_punch(-0.16)
	_chroma = maxf(_chroma, 0.45)
	Game.hitstop(0.07, 0.04)
	_set_cam(&"set_zoom", [1.0, 1.6])
	await get_tree().create_timer(0.8, false).timeout
	_set_cam(&"set_focus_bias", [Vector3.ZERO, 0.0])


func _boss_felled_fx() -> void:
	if _boss_felled:
		return
	_boss_felled = true
	_zoom_punch(0.12)  # punch out with the blast
	_chroma = maxf(_chroma, 0.7)
	Game.hitstop(0.08, 0.03)
	await get_tree().create_timer(1.0, false).timeout
	_set_cam(&"set_focus_bias", [Vector3.ZERO, 0.0])


# ---------------------------------------------------------------- helpers

func _try_hitstop(duration: float, scale: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_stop_ms < int(hitstop_gap * 1000.0):
		return
	_last_stop_ms = now
	Game.hitstop(duration, scale)


func _kick_toward(world_pos: Vector3, strength: float) -> void:
	var p := Game.player
	if not is_instance_valid(p):
		return
	var dir := world_pos - p.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	_set_cam(&"kick", [dir.normalized(), strength])


func _zoom_punch(amount: float) -> void:
	_set_cam(&"zoom_punch", [amount])


func _shake(amount: float) -> void:
	get_tree().call_group(&"camera_rig", &"shake", amount)


func _set_cam(method: StringName, args: Array) -> void:
	for rig in get_tree().get_nodes_in_group(&"camera_rig"):
		if rig.has_method(method):
			rig.callv(method, args)


func _nearest_enemy(from: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := 6.0 * 6.0
	for n in Perf.enemies():
		var e := n as Node3D
		if e == null:
			continue
		var d := e.global_position.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = e.global_position
	# hazards (pillars, orbs) also hurt; fall back to them
	if best == Vector3.INF:
		for n in get_tree().get_nodes_in_group(&"boss_hazards"):
			var h := n as Node3D
			if h and h.global_position.distance_squared_to(from) < best_d:
				best_d = h.global_position.distance_squared_to(from)
				best = h.global_position
	return best
