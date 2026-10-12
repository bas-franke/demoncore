class_name StoryHooks
extends Node
## The Dialogue autoload's automatic story triggers (child node "StoryHooks" of Dialogue; not
## created in test mode). Nobody needs to call into it:
##   RunState.run_started   -> run counters, beat promotion, map arrival / run-start narration
##   RunState.run_ended     -> last.* vars, deaths / victories, run-end narration, the ending
##   Game.boss_spawned / boss_phase_changed / boss_died (+ polling is_enraged / is_dying)
##                          -> boss intro, phase, rage and death lines, boss kill counters
##   Game.objective_completed -> an occasional quip from the demon
##   entering Basecamp      -> NPCs (Pip, Kesh, Malphine, the Crown), "!" markers, the prologue,
##                             the ending conversation, return narration
##   the ending             -> a victory with cause &"seventh_gate": passing the Seventh Gate on the
##                             heavens_gate map (SeventhGate, maps / objectives roles), while
##                             ending_rule.requires holds (data/dialogue/ending.json). The next
##                             Basecamp arrival loads the staged ending (scenes/dialogue/ending_stage.tscn).

## Seconds into a run when the demon may mutter a mid-run line (pool "run_mid").
const MID_RUN_TIMES: Array[float] = [95.0, 215.0, 420.0]
## Delay after Game.boss_spawned before the boss speaks (lets the descent and toast play first).
const BOSS_INTRO_DELAY := 2.8
const RUN_START_DELAY := 1.4
## Min seconds between objective quips.
const OBJECTIVE_QUIP_GAP := 40.0
## Basecamp NPCs: roster npc id -> [speaker, position, yaw, requires block or null].
const CAMP_NPCS := {
	"pip": ["pip", Vector3(3.4, 0.0, 2.4), PI, null],
	"breachwarden": ["kesh", Vector3(-3.2, 0.0, -8.3), PI - 0.5, null],
	"malphine": ["malphine", Vector3(5.6, 0.0, 1.2), PI + 0.6, {"flags": ["known.empty_throne"]}],
}
const CROWN_SPOT := Vector3(-2.6, 0.0, 2.2)
const ENDING_STAGE := "res://scenes/dialogue/ending_stage.tscn"
## Delay before the demon's own remark on a felled boss (after the boss's death line).
const BOSS_KILL_QUIP_DELAY := 4.0

var d: Node  # the Dialogue autoload (parent)
var _scene: Node
var _bosses: Array[Dictionary] = []  # {node: WeakRef, id: String, enraged: bool, dying: bool}
var _mid_index := 0
var _last_quip := -INF


func _ready() -> void:
	d = get_parent()
	Game.boss_spawned.connect(_on_boss_spawned)
	Game.boss_died.connect(_on_boss_died)
	if Game.has_signal(&"boss_phase_changed"):
		Game.connect(&"boss_phase_changed", _on_boss_phase_changed)
	# Map events without a signal of their own (the Celestial Leviathan) are spotted as they spawn.
	get_tree().node_added.connect(_on_node_added)
	if Game.has_signal(&"objective_completed"):
		Game.connect(&"objective_completed", _on_objective_completed)
	var toast := CodexToast.new()
	toast.name = "CodexToast"
	add_child(toast)
	var rs := get_node_or_null(^"/root/RunState")
	if rs:
		rs.connect(&"run_started", _on_run_started)
		rs.connect(&"run_ended", _on_run_ended)
	else:
		push_warning("StoryHooks: RunState autoload missing; run narration disabled")


func _process(_delta: float) -> void:
	var cur := get_tree().current_scene
	if cur != _scene:
		_scene = cur
		if cur and _is_basecamp(cur):
			_on_basecamp_entered.call_deferred()
	_watch_bosses()
	_watch_mid_run()


## Id of the map of the current / selected run ("" when unknown).
func map_id() -> String:
	var maps := get_node_or_null(^"/root/Maps")
	if maps == null or not maps.has_method(&"selected_def"):
		return ""
	var def: Variant = maps.call(&"selected_def")
	return str((def as Dictionary).get("id", "")) if def is Dictionary else ""


## The ending's rule: {"cause": "seventh_gate", "requires": {...}} (data/dialogue/ending.json).
func ending_rule() -> Dictionary:
	var r: Variant = d.db.extra.get("ending_rule", {})
	return r if r is Dictionary else {}


## True while the story allows the ending (the Seventh Gate victory has not happened yet).
func ending_ready() -> bool:
	return d.state.check(ending_rule().get("requires"), d.demon_id()) and not d.has_flag("ending.pending")


# ---------------------------------------------------------------- runs

func _on_run_started() -> void:
	var st: StoryState = d.state
	var demon: String = d.demon_id()
	var map := map_id()
	st.add("runs")
	if demon != "":
		st.add("runs_as." + demon)
	if map != "":
		st.add("map_runs." + map)
	st.set_var("run.map", map)
	st.set_var("run.boss_kills", 0)
	_promote_beats()
	d.begin_visit()
	Affinity.apply_run_perks(d)
	_mid_index = 0
	_bosses.clear()
	_last_quip = -INF
	Codex.announce_unlocks(d)
	d.save()
	await get_tree().create_timer(RUN_START_DELAY, false).timeout
	# Runs started without passing through Basecamp (e.g. main.tscn directly) get the prologue as
	# non-blocking narration: never pause a run that is already underway.
	if st.times_seen("prologue") == 0:
		d.bark("prologue")
	elif map == "" or d.bark("map_arrival." + map) == "":
		d.bark("run_start")


## Story beats unlocked during a visit ("beat.x") become common knowledge ("known.x") at the next
## run start, so other characters react one visit later instead of in the same breath.
## Also keeps "story.act" (1..4) up to date for anyone who wants to theme things by act.
func _promote_beats() -> void:
	var st: StoryState = d.state
	for k: String in st.vars.keys():
		if k.begins_with("beat.") and st.is_flag(k):
			st.set_var("known." + k.substr(5), true)
	var act := 1
	if st.is_flag("story.ended"):
		act = 4
	elif st.is_flag("known.empty_throne"):
		act = 3
	elif st.is_flag("known.hollow_hymn"):
		act = 2
	st.set_var("story.act", act)


func _on_run_ended(result: Dictionary) -> void:
	var st: StoryState = d.state
	var cause := str(result.get("cause", ""))
	var victory := bool(result.get("victory", false))
	var died := cause == "slain"
	var t := int(float(result.get("time", 0.0)))
	var kills := int(result.get("kills", 0))
	var ending := victory and _is_ending_victory(cause)
	st.set_var("last.result", "victory" if victory else ("death" if died else "abandon"))
	st.set_var("last.died", died)
	st.set_var("last.victory", victory)
	st.set_var("last.ending", ending)
	st.set_var("last.time", t)
	st.set_var("last.kills", kills)
	st.set_var("last.boss_kills", int(result.get("bosses", 0)))
	st.set_var("last.level", int(result.get("level", 1)))
	st.set_var("last.demon", d.demon_id())
	st.set_var("last.map", st.get_var("run.map", ""))
	if died:
		st.add("deaths")
	if victory:
		st.add("victories")
	if ending:
		st.add("endings")
		st.set_var("ending.pending", true)
		st.set_var("beat.ending", true)
	st.add("kills_total", kills)
	if t > int(st.get_num("best_time")):
		st.set_var("best_time", t)
	st.set_var("pending_return", true)
	d.save()
	if died or victory:
		d.subtitles.clear()
		d.bark("run_end")


## A victory is the ending when the run ended with the finale's cause (passing the Seventh Gate)
## and the story allows it (not ended yet).
func _is_ending_victory(cause: String) -> bool:
	return ending_ready() and cause == str(ending_rule().get("cause", "seventh_gate"))


## Called by the ending stage when it is over: the story moves to act 4.
func finish_ending() -> void:
	var st: StoryState = d.state
	st.set_var("ending.pending", false)
	st.set_var("ending.return", true)
	st.set_var("story.ended", true)
	st.set_var("known.ending", true)
	st.set_var("story.act", 4)
	d.save()


# ---------------------------------------------------------------- Basecamp

func _is_basecamp(scene: Node) -> bool:
	return scene.is_in_group(&"basecamp") or scene.scene_file_path.contains("basecamp")


func _on_basecamp_entered() -> void:
	var st: StoryState = d.state
	var returning := st.is_flag("pending_return")
	st.set_var("pending_return", false)
	if returning:
		d.begin_visit()
	st.add("basecamp_visits")
	_decorate_basecamp()
	Codex.announce_unlocks(d)
	d.save()
	# Let the hub fade in before anyone talks (and the arrival banner fade out before narration).
	if st.is_flag("ending.pending"):
		# The ending is staged in its own scene; it returns here when it is over.
		await get_tree().create_timer(0.8).timeout
		get_tree().change_scene_to_file(ENDING_STAGE)
	elif st.is_flag("ending.return"):
		st.set_var("ending.return", false)
		d.save()
		await get_tree().create_timer(2.0).timeout
		d.start("ending_return")
	elif st.times_seen("prologue") == 0:
		await get_tree().create_timer(1.5).timeout
		d.start("prologue")
	elif returning:
		await get_tree().create_timer(5.5).timeout
		d.bark("basecamp_return")


## Adds the story NPCs (CharacterRoster models wrapped in StoryNpc), the Crown after the ending,
## and a "!" / gift marker over every NPC with a speaker in the dialogue data.
func _decorate_basecamp() -> void:
	var camp := get_tree().current_scene
	if camp == null or not camp.has_method(&"add_interactable"):
		return
	for n: Node in get_tree().get_nodes_in_group(&"hub_interactables"):
		var shop: Variant = n.get(&"shop_id")
		if shop is String and d.speaker_for_shop(shop) != "" and n is Node3D \
				and n.find_child("StoryMarker", false, false) == null:
			StoryMarker.attach(n as Node3D, shop, float(n.get(&"prompt_height")) + 0.75)
	for npc_id: String in CAMP_NPCS:
		var def: Array = CAMP_NPCS[npc_id]
		var node_name := "Story_" + npc_id
		if camp.find_child(node_name, false, false) != null or not d.state.check(def[3], d.demon_id()):
			continue
		var npc := StoryNpc.create(npc_id, def[0])
		if npc == null:
			continue
		npc.name = node_name
		npc.position = def[1]
		npc.rest_yaw = def[2]
		camp.call(&"add_interactable", npc)
		StoryMarker.attach(npc, def[0], npc.prompt_height + 0.6)
	if d.has_flag("story.ended") and camp.find_child("Story_crown", false, false) == null:
		var crown := CrownShrine.new()
		crown.name = "Story_crown"
		crown.position = CROWN_SPOT
		camp.call(&"add_interactable", crown)


# ---------------------------------------------------------------- bosses

func _on_boss_spawned(boss: Node3D) -> void:
	var id := _boss_id(boss)
	d.state.add("boss_seen." + id)
	_bosses.append({"node": weakref(boss), "id": id, "enraged": false, "dying": false})
	d.save()
	await get_tree().create_timer(BOSS_INTRO_DELAY, false).timeout
	_boss_bark("boss_intro", id, true)


func _on_boss_phase_changed(boss: Node3D, phase: int) -> void:
	# Phase lines are optional and boss-specific: pool "boss_phase.<id>.<phase>".
	d.bark("boss_phase.%s.%d" % [_boss_id(boss), phase], true)


func _on_boss_died(_pos: Vector3) -> void:
	# The signal carries no boss: credit the first tracked boss that is dying or gone.
	var idx := -1
	for i in _bosses.size():
		var n: Object = _bosses[i]["node"].get_ref()
		if n == null or n.get(&"is_dying") == true:
			idx = i
			break
	if idx < 0:
		return
	var id: String = _bosses[idx]["id"]
	_bosses.remove_at(idx)
	d.state.add("boss_kills")
	d.state.add("boss_kills." + id)
	d.state.add("run.boss_kills")
	d.save()
	# The demon has the last word (per-demon pools demon_boss_kill.<demon>, then the generic one).
	await get_tree().create_timer(BOSS_KILL_QUIP_DELAY, false).timeout
	if d.bark("demon_boss_kill.%s.%s" % [d.demon_id(), id]) == "" 			and d.bark("demon_boss_kill." + d.demon_id()) == "":
		d.bark("demon_boss_kill")


## Polls tracked bosses for rage (is_enraged) and death (is_dying) so they can speak at once.
func _watch_bosses() -> void:
	for b in _bosses:
		var n: Object = b["node"].get_ref()
		if n == null:
			continue
		if not b["enraged"] and n.get(&"is_enraged") == true:
			b["enraged"] = true
			_boss_bark("boss_rage", b["id"])
		if not b["dying"] and n.get(&"is_dying") == true:
			b["dying"] = true
			_boss_bark("boss_death", b["id"], true)


func _boss_bark(kind: String, id: String, interrupt: bool = false) -> void:
	if d.bark("%s.%s" % [kind, id], interrupt) == "":
		d.bark(kind, interrupt)


static func _boss_id(boss: Node) -> String:
	var data: Variant = boss.get(&"data")
	if data is Resource and (data as Resource).resource_path != "":
		return (data as Resource).resource_path.get_file().get_basename()
	return str(boss.name).to_snake_case()


# ---------------------------------------------------------------- mid-run chatter

func _watch_mid_run() -> void:
	var rs := get_node_or_null(^"/root/RunState")
	if rs == null or rs.get(&"active") != true or _mid_index >= MID_RUN_TIMES.size():
		return
	if Game.elapsed < MID_RUN_TIMES[_mid_index] or get_tree().paused:
		return
	_mid_index += 1
	if _bosses.is_empty() and not d.subtitles.is_busy():
		d.bark("run_mid")


func _on_objective_completed(id: StringName, _rewards: Dictionary) -> void:
	if Game.elapsed - _last_quip < OBJECTIVE_QUIP_GAP or not _bosses.is_empty() or d.subtitles.is_busy():
		return
	_last_quip = Game.elapsed
	if d.bark("objective_done." + String(id)) == "":
		d.bark("objective_done")


## The Celestial Leviathan (characters-new map event) gets a line when it starts a pass.
func _on_node_added(node: Node) -> void:
	var sc: Script = node.get_script() as Script
	if sc and sc.resource_path.ends_with("celestial_whale.gd"):
		(func() -> void: d.bark("celestial_whale")).call_deferred()
