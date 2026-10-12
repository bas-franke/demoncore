extends Node
## Story + dialogue (autoload "Dialogue"). Data-driven conversations from res://data/dialogue/*.json,
## a typewriter dialogue box with portraits and choices, non-blocking barks / narration, and story
## memory (flags, counters, seen conversations) persisted across runs in user://story.json.
## Owned by the story role; the full data format and hook list live in docs/team/story.md.
##
## API (stable):
##   Dialogue.start(&"vesper_intro")         # play one conversation (modal, pauses the game)
##   Dialogue.start_for(&"vesper")           # pick the best conversation for an NPC / pool, Hades-style
##   await Dialogue.conversation_finished    # (id) after either of the above
##   Dialogue.has_new(&"vesper")             # an unseen story conversation is waiting ("!" marker)
##   Dialogue.bark(&"boss_intro.sariel")     # non-blocking subtitle line(s) from a pool or an id
##   Dialogue.say(&"pip", "text") / Dialogue.narrate("text")   # ad-hoc lines, non-blocking
##   Dialogue.speaker_for_shop("occultist")  # -> "vesper" (speaker id for a Meta shop id)
##   Dialogue.get_var / set_var / add_var / has_flag / set_flag, is_active(), reset_story()
##   Dialogue.codex_entries() / codex_mark_read(id) / codex_new_count()   (see scripts/dialogue/codex.gd)
##   Dialogue.affinity(who) / gift_cost(who) / can_gift(who) / give_gift(who)  (affinity.gd)
## Signals: conversation_started(id), conversation_finished(id), event_triggered(name, conv_id),
##   gift_given(speaker, level), codex_unlocked(id)
##
## Automatic hooks live in child nodes: StoryHooks (scripts/dialogue/story_hooks.gd: runs, bosses,
## maps, Basecamp, the ending) and WorldBarks (scripts/dialogue/world_barks.gd: enemy chatter).

signal conversation_started(id: String)
signal conversation_finished(id: String)
## A line with {"event": "name"} was reached (e.g. "open_shop"). Lets scenes react mid-talk.
signal event_triggered(event_name: String, conv_id: String)
## An offering raised `speaker`'s affinity to `level` (1..Affinity.MAX_LEVEL).
signal gift_given(speaker: String, level: int)
## A codex entry became readable (checked at run start / Basecamp arrival).
signal codex_unlocked(id: String)

const SAVE_PATH := "user://story.json"
const BOX_SCRIPT := preload("res://scenes/dialogue/dialogue_box.gd")
const SUBTITLES_SCRIPT := preload("res://scenes/dialogue/dialogue_subtitles.gd")

var db := DialogueDB.new()
var state := StoryState.new()
## True for bot / screenshot runs: no automatic narration and nothing is saved.
var test_mode := false
var save_path := SAVE_PATH

## Non-blocking subtitle layer (barks / narration); StoryHooks uses it directly.
var subtitles: DialogueSubtitles
var hooks: StoryHooks

var _box: DialogueBox
var _active_id := ""
var _we_paused := false
## pool -> true once a story conversation was played there during this Basecamp visit, so each
## NPC tells one new story beat per visit and falls back to repeatable chatter afterwards.
var _talked_this_visit := {}
## pool -> last conversation id picked (avoid repeating the same chatter twice in a row).
var _last_pick := {}
var _regex := RegEx.create_from_string("\\{([a-z_.]+)\\}")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	db.load_all()
	_box = BOX_SCRIPT.new()
	add_child(_box)
	subtitles = SUBTITLES_SCRIPT.new()
	add_child(subtitles)
	# Bot / screenshot / headless runs (--autopilot, --shot=..., --headless) must neither pause
	# the game for story scenes nor advance the real story save. "--story" re-enables everything.
	var args := OS.get_cmdline_user_args()
	var shot := Array(args).any(func(a: String) -> bool: return a.begins_with("--shot"))
	test_mode = Game.autopilot or shot or DisplayServer.get_name() == "headless"
	if "--story" in args:
		test_mode = false
	if test_mode:
		return
	# (progression) Shared save isolation: --save-profile=<name> puts the story save in
	# user://test/<name>/ too (SaveProfile). --story-save= below still wins when given.
	save_path = preload("res://scripts/save_profile.gd").path(SAVE_PATH.get_file())
	# Dev: "--story-save=user://story_dev.json" plays against a separate save file.
	for a: String in args:
		if a.begins_with("--story-save="):
			save_path = a.substr(13)
	state.load_file(save_path)
	hooks = StoryHooks.new()
	hooks.name = "StoryHooks"
	add_child(hooks)
	var barks := WorldBarks.new()
	barks.name = "WorldBarks"
	add_child(barks)


# ---------------------------------------------------------------- public API

## Plays conversation `id` in the modal box. Returns false if it does not exist or a conversation
## is already running. `pause` freezes the game while it plays.
func start(id: String, pause: bool = true) -> bool:
	var conv := db.get_conv(id)
	if conv.is_empty():
		push_warning("Dialogue: no conversation '%s'" % id)
		return false
	if is_active():
		return false
	_run(conv, pause)
	return true


## Picks the best conversation for an NPC (speaker id, shop id or pool name) and plays it.
## Returns the conversation id, or "" if nothing is eligible.
func start_for(who: String, pause: bool = true) -> String:
	var pool := resolve_pool(who)
	var id := pick(pool, true)
	if id == "" or not start(id, pause):
		return ""
	return id


## True when `who` has an unseen story conversation waiting (show a "!" above the NPC).
func has_new(who: String) -> bool:
	var pool := resolve_pool(who)
	if _talked_this_visit.has(pool):
		return false
	for id: String in db.pool(pool):
		var c := db.get_conv(id)
		if c["once"] and state.times_seen(id) == 0 and eligible(c):
			return true
	return false


## Non-blocking: shows the lines of the best conversation in pool `what` (or conversation `what`)
## as subtitles. Returns the conversation id used, or "".
func bark(what: String, interrupt: bool = false) -> String:
	var id := what if db.conversations.has(what) else pick(resolve_pool(what), false)
	if id == "":
		return ""
	if interrupt:
		subtitles.clear()
	var conv := db.get_conv(id)
	_mark(conv)
	for line: Variant in conv["lines"]:
		if not line is Dictionary or not line.has("text"):
			continue
		if not state.check(line.get("requires"), demon_id()):
			continue
		state.apply(line.get("set"), line.get("add"))
		subtitles.push(speaker(str(line.get("who", db.default_who(conv)))), format(str(line["text"])))
	save()
	return id


## One line of repeatable chatter for `who` (speaker / shop id), formatted, or "" if none.
## For greetings shown elsewhere, e.g. the subtitle of a shop panel.
func chatter(who: String) -> String:
	var pool := resolve_pool(who)
	var best_p := -INF
	var options: Array[String] = []
	for id: String in db.pool(pool):
		var c := db.get_conv(id)
		if c["once"] or not eligible(c):
			continue
		if c["priority"] > best_p:
			best_p = c["priority"]
			options = [id]
		elif c["priority"] == best_p:
			options.append(id)
	if options.size() > 1:
		options.erase(_last_pick.get(pool, ""))
	if options.is_empty():
		return ""
	var best: String = options.pick_random()
	_last_pick[pool] = best
	for line: Variant in db.get_conv(best)["lines"]:
		if line is Dictionary and line.has("text"):
			return format(str(line["text"]))
	return ""


## Ad-hoc non-blocking line from speaker `who` ("narrator" for narration).
func say(who: String, text: String) -> void:
	subtitles.push(speaker(who), format(text))


func narrate(text: String) -> void:
	say("narrator", text)


func is_active() -> bool:
	return _active_id != ""


## Speaker id that runs the shop `shop_id` (Meta / Progression shop ids), or "".
func speaker_for_shop(shop_id: String) -> String:
	return db.shops.get(shop_id, "")


## Best eligible conversation id in `pool` ("" if none). `visit_rules`: one new story beat per
## Basecamp visit per pool. Unseen "once" conversations win by priority, then file order (story
## order); otherwise a random repeatable conversation of the highest eligible priority.
func pick(pool: String, visit_rules: bool = false) -> String:
	var best_story := ""
	var best_story_p := -INF
	var repeat: Array[String] = []
	var repeat_p := -INF
	for id: String in db.pool(pool):
		var c := db.get_conv(id)
		if not eligible(c):
			continue
		var p: float = c["priority"]
		if c["once"]:
			if state.times_seen(id) == 0 and p > best_story_p:
				best_story = id
				best_story_p = p
		elif p > repeat_p:
			repeat = [id]
			repeat_p = p
		elif p == repeat_p:
			repeat.append(id)
	var story_allowed := not (visit_rules and _talked_this_visit.has(pool))
	if best_story != "" and story_allowed:
		return best_story
	if repeat.is_empty():
		return ""
	if repeat.size() > 1:
		repeat.erase(_last_pick.get(pool, ""))
	return repeat.pick_random()


# ---------------------------------------------------------------- story variables

func get_var(key: String, default: Variant = null) -> Variant:
	return state.get_var(key, default)


func set_var(key: String, value: Variant) -> void:
	state.set_var(key, value)
	save()


func add_var(key: String, amount: float = 1.0) -> void:
	state.add(key, amount)
	save()


func has_flag(key: String) -> bool:
	return state.is_flag(key)


func set_flag(key: String, on: bool = true) -> void:
	set_var(key, on)


func save() -> void:
	if not test_mode:
		state.save(save_path)


## Forgets everything (new game).
func reset_story() -> void:
	state = StoryState.new()
	_talked_this_visit.clear()
	save()


## A new Basecamp visit begins: every NPC may tell one new story beat again.
func begin_visit() -> void:
	_talked_this_visit.clear()


# ---------------------------------------------------------------- codex + affinity (delegates)

## Every codex entry: {id, category, title, text, unlocked: bool, is_new: bool}. Locked entries
## keep their title as "???" and text "". Data: res://data/dialogue/codex.json.
func codex_entries() -> Array[Dictionary]:
	return Codex.entries(self)


func codex_mark_read(id: String) -> void:
	Codex.mark_read(self, id)


func codex_new_count() -> int:
	return Codex.new_count(self)


## Affinity 0..Affinity.MAX_LEVEL with a Basecamp NPC (speaker / shop id).
func affinity(who: String) -> int:
	return Affinity.level(self, who)


## Souls an offering to `who` costs now (-1 = maxed out or does not take gifts).
func gift_cost(who: String) -> int:
	return Affinity.cost(self, who)


func can_gift(who: String) -> bool:
	return Affinity.can_gift(self, who)


## Spends the souls, raises affinity and plays the gift conversation. False if not possible.
func give_gift(who: String) -> bool:
	return Affinity.give(self, who)


## Id of the current demon ("lilaeth", ...), or "" if none is chosen.
func demon_id() -> String:
	var d: Resource = Game.selected_character
	if d == null and is_instance_valid(Game.player):
		d = Game.player.character
	return d.resource_path.get_file().get_basename() if d else ""


## Replaces {demon}, {demon_title} and {any.story.var} in `text`.
func format(text: String) -> String:
	if text.find("{") < 0:
		return text
	var out := text
	for m in _regex.search_all(text):
		var key := m.get_string(1)
		var val := ""
		match key:
			"demon":
				val = str(speaker("player")["name"])
			"demon_title":
				val = str(speaker("player")["title"])
			_:
				val = str(state.get_var(key, 0))
		out = out.replace(m.get_string(), val)
	return out


# ---------------------------------------------------------------- conversation runner

func _run(conv: Dictionary, pause: bool) -> void:
	var id: String = conv["id"]
	_active_id = id
	_we_paused = pause and not get_tree().paused
	if _we_paused:
		get_tree().paused = true
	_mark(conv)
	if conv["once"]:
		_talked_this_visit[conv["pool"]] = true
	_last_pick[conv["pool"]] = id
	conversation_started.emit(id)
	_box.open()
	await ConversationRunner.play(self, _box, conv)
	_box.close()
	if _we_paused:
		get_tree().paused = false
	_we_paused = false
	_active_id = ""
	save()
	conversation_finished.emit(id)


## Called by Codex when an entry unlocks.
func notify_codex_unlocked(id: String) -> void:
	codex_unlocked.emit(id)


## Called by Affinity after an offering.
func notify_gift(who: String, level: int) -> void:
	gift_given.emit(who, level)


## Called by ConversationRunner for lines with an "event".
func notify_event(event_name: String, conv_id: String) -> void:
	event_triggered.emit(event_name, conv_id)


## Marks a conversation seen and applies its conversation-level "set" / "add".
func _mark(conv: Dictionary) -> void:
	state.mark_seen(conv["id"])
	state.apply(conv.get("set"), conv.get("add"))


func eligible(conv: Dictionary) -> bool:
	return state.check(conv.get("requires"), demon_id())


## Speaker dict for an id. "player" is the current demon; unknown ids get a plain name plate.
func speaker(id: String) -> Dictionary:
	if id == "player":
		var d: Resource = Game.selected_character
		if d == null and is_instance_valid(Game.player):
			d = Game.player.character
		var dd := d as DemonData
		if dd == null:
			return {"id": "player", "name": "The Demon", "title": "", "color": Color("ff7a3a"), "glyph": "D"}
		return {"id": "player", "name": dd.display_name, "title": dd.title,
				"color": dd.glow_color.lerp(Color.WHITE, 0.25), "glyph": dd.display_name.left(1)}
	if id == "narrator" or id == "":
		return {"id": "narrator"}
	var s := db.speaker(id)
	if s.is_empty():
		return {"id": id, "name": id.capitalize(), "title": "", "color": Color("e8d6a6"), "glyph": id.left(1).to_upper()}
	return s


## Accepts a pool name, a speaker id or a shop id and returns the pool to pick from.
func resolve_pool(who: String) -> String:
	if db.has_pool(who):
		return who
	var sp := speaker_for_shop(who)
	return sp if sp != "" else who
