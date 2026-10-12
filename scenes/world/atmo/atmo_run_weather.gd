class_name AtmoRunWeather
extends Node
## Weather and time progression over a run: child node "RunWeather" of the Atmosphere autoload.
## Every map preset is the run's starting sky; this layers weighted overlays on top of it:
##   run_calm   full at the start, gone by ~40 % escalation (clear skies, light wind)
##   run_storm  weight = escalation (RunState.difficulty_tier() / ESCALATION_FULL_TIER): the sun
##              sinks and reddens, clouds close in, gusts, lightning; plus the preset's own
##              optional "run_storm_local" (rain in the city, a blizzard in the monastery, ...)
##   surge / lull   RunState.wave_started: darker and stormier during a surge, a breather in the lull
##   final_dawn the last boss of the run (ObjectiveDirector's victory_bosses): a blinding holy dawn
##              breaks low over the battlefield; it stays for the victory
##   run_lost   on death: the world drains of colour
## All overlays live in data/atmosphere/presets.json ("_overlays", or a preset's "overlays").

## Difficulty tier (minutes survived + heat) at which the storm is at full strength.
const ESCALATION_FULL_TIER := 12.0
const ESCALATION_BLEND := 20.0
const WAVE_BLEND := 6.0
const DAWN_BLEND := 6.0

## The Atmosphere autoload (set by it before adding this node).
var director: Node
## 0 = calm start .. 1 = full storm.
var escalation := 0.0
var final_dawn := false

var _in_run := false


func _ready() -> void:
	# Deferred: autoloads registered after Atmosphere are not in the tree yet during _ready.
	_connect_all.call_deferred()


func _connect_all() -> void:
	_connect(^"/root/RunState", &"run_started", _on_run_state_run_started)
	_connect(^"/root/RunState", &"run_ended", _on_run_state_run_ended)
	_connect(^"/root/RunState", &"wave_started", _on_run_state_wave_started)
	_connect(^"/root/RunState", &"difficulty_changed", _on_run_state_difficulty_changed)
	_connect(^"/root/Game", &"boss_spawned", _on_game_boss_spawned)
	# A map preset arriving after run_started (Maps.map_loaded is deferred) has its own
	# run_storm_local: re-apply so it is picked up.
	director.preset_changed.connect(func(_p: String) -> void:
		if _in_run:
			apply_escalation(0.0))
	# The first run scene may have started its run before these connections existed.
	var rs := get_node_or_null(^"/root/RunState")
	if rs and bool(rs.get(&"active")):
		_on_run_state_run_started()


## Called by the director whenever it binds a new scene (its overlay stack starts empty): restores
## the run's overlays if a run is active, else forgets the run.
func reset() -> void:
	final_dawn = false
	var rs := get_node_or_null(^"/root/RunState")
	_in_run = rs != null and bool(rs.get(&"active"))
	escalation = _tier_escalation() if _in_run else 0.0
	if _in_run:
		apply_escalation(0.0)


## (Re)applies the escalation overlays at the current weight.
func apply_escalation(blend: float) -> void:
	print_verbose("Atmosphere: run escalation %.2f" % escalation)
	director.push_overlay(&"run_calm", "run_calm", blend, clampf(1.0 - escalation * 2.5, 0.0, 1.0))
	director.push_overlay(&"run_storm", "run_storm", blend, escalation)
	if director.has_overlay_def("run_storm_local"):
		director.push_overlay(&"run_storm_local", "run_storm_local", blend, escalation)


func _on_run_state_run_started() -> void:
	final_dawn = false
	_in_run = true
	escalation = _tier_escalation()
	apply_escalation(0.0)


func _on_run_state_difficulty_changed(_tier: int) -> void:
	var e := _tier_escalation()
	if absf(e - escalation) < 0.001:
		return
	escalation = e
	apply_escalation(ESCALATION_BLEND)


func _on_run_state_wave_started(index: int, kind: StringName) -> void:
	print_verbose("Atmosphere: wave %d %s" % [index, kind])
	match kind:
		&"surge":
			director.pop_overlay(&"lull", WAVE_BLEND)
			director.push_overlay(&"surge", "surge", WAVE_BLEND, 0.6 + 0.4 * escalation)
			# A distant rumble announces the surge once the sky has turned.
			if escalation > 0.25:
				director.strike_lightning(Vector3.INF, 0.75)
		&"lull":
			director.pop_overlay(&"surge", WAVE_BLEND + 2.0)
			director.push_overlay(&"lull", "lull", WAVE_BLEND)
		_:
			director.pop_overlay(&"surge", WAVE_BLEND)
			director.pop_overlay(&"lull", WAVE_BLEND)


func _on_game_boss_spawned(_boss: Node3D) -> void:
	if final_dawn or not _is_final_boss():
		return
	final_dawn = true
	# Deferred so the dawn sits above the boss overlay pushed in the same frame.
	(func() -> void:
		director.push_overlay(&"final_dawn", "final_dawn", DAWN_BLEND)
		director.flash(Color(1.0, 0.86, 0.6), 0.35, 0.8)).call_deferred()


func _on_run_state_run_ended(result: Dictionary) -> void:
	_in_run = false
	director.pop_overlay(&"surge", 4.0)
	if bool(result.get("victory", false)):
		if not final_dawn:
			final_dawn = true
			director.push_overlay(&"final_dawn", "final_dawn", DAWN_BLEND)
	else:
		director.push_overlay(&"run_lost", "run_lost", 2.5)


func _tier_escalation() -> float:
	var rs := get_node_or_null(^"/root/RunState")
	var tier := float(rs.call(&"difficulty_tier")) if rs and rs.has_method(&"difficulty_tier") else 0.0
	return clampf(tier / ESCALATION_FULL_TIER, 0.0, 1.0)


## True when this boss is the last one the run needs (ObjectiveDirector.settings.victory_bosses).
func _is_final_boss() -> bool:
	var d := get_tree().get_first_node_in_group(&"objective_director")
	if d == null:
		return false
	var settings: Variant = d.get(&"settings")
	var need := int((settings as Dictionary).get("victory_bosses", 0)) if settings is Dictionary else 0
	var slain := int(d.get(&"bosses_slain")) if &"bosses_slain" in d else 0
	return need > 0 and slain + 1 >= need


func _connect(path: NodePath, sig: StringName, cb: Callable) -> void:
	var n := get_node_or_null(path)
	if n and n.has_signal(sig):
		n.connect(sig, cb)
