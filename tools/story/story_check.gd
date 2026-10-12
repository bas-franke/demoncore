extends SceneTree
## Story data lint + progression simulation (story role, docs/team/story.md).
##   godot --headless --path . --script res://tools/story/story_check.gd
## 1. Lints every res://data/dialogue/*.json: unknown keys, unknown speakers, broken gotos,
##    unknown condition keys, conversations no pool or id refers to.
## 2. Simulates 30 runs of a player who visits every Basecamp NPC once per visit and kills the
##    Herald now and then, and prints when each story beat unlocks. Uses a throwaway StoryState,
##    so the real user://story.json is never touched.
## Exits with code 1 when the lint finds errors.

const CONV_KEYS := ["id", "pool", "once", "priority", "requires", "set", "add", "lines", "who", "labels", "_doc"]
const LINE_KEYS := ["who", "text", "choices", "label", "goto", "end", "set", "add", "requires", "event"]
const CHOICE_KEYS := ["text", "goto", "end", "set", "add", "requires"]
const REQ_KEYS := ["min", "max", "eq", "flags", "not_flags", "seen", "not_seen", "demon", "not_demon", "any", "chance"]
const NPC_POOLS := ["grimmaul", "vesper", "clerk", "ossek", "pip", "kesh", "malphine"]
const DEMONS := ["lilaeth", "morvane", "skarn", "vharok", "ysolde", "nhazgul", "iscariel"]

var _errors := 0
var _db := DialogueDB.new()


func _initialize() -> void:
	_db.load_all()
	print("story_check: %d speakers, %d conversations, %d pools" % [_db.speakers.size(),
			_db.conversations.size(), _db.pools.size()])
	_lint()
	_simulate()
	print("story_check: %d error(s)" % _errors)
	quit(1 if _errors > 0 else 0)


func _err(msg: String) -> void:
	_errors += 1
	printerr("  ERROR: " + msg)


func _lint() -> void:
	for e: Variant in _db.extra.get("codex", []):
		if not e is Dictionary or str(e.get("id", "")) == "" or not e.has("text"):
			_err("codex: entry without id / text: %s" % str(e))
			continue
		_lint_req("codex:" + str(e["id"]), e.get("requires"))
	if not _db.extra.has("ending_rule"):
		_err("ending.json: ending_rule missing")
	for id: String in _db.conversations:
		var c: Dictionary = _db.conversations[id]
		for k: Variant in c:
			if not str(k) in CONV_KEYS:
				_err("%s: unknown key '%s'" % [id, k])
		if c["pool"] == "" and id != "prologue":
			print("  note: %s has no pool (only reachable via Dialogue.start)" % id)
		_lint_req(id, c.get("requires"))
		var labels: Dictionary = c["labels"]
		for line: Variant in c["lines"]:
			if not line is Dictionary:
				_err("%s: line is not an object" % id)
				continue
			var l: Dictionary = line
			for k: Variant in l:
				if not str(k) in LINE_KEYS:
					_err("%s: unknown line key '%s'" % [id, k])
			_lint_who(id, str(l.get("who", _db.default_who(c))), l.has("text"))
			_lint_req(id, l.get("requires"))
			if l.has("goto") and not labels.has(str(l["goto"])):
				_err("%s: goto '%s' has no label" % [id, l["goto"]])
			for ch: Variant in l.get("choices", []):
				for k: Variant in ch:
					if not str(k) in CHOICE_KEYS:
						_err("%s: unknown choice key '%s'" % [id, k])
				if ch.has("goto") and not labels.has(str(ch["goto"])):
					_err("%s: choice goto '%s' has no label" % [id, ch["goto"]])
				_lint_req(id, ch.get("requires"))


func _lint_who(id: String, who: String, has_text: bool) -> void:
	if not has_text or who in ["player", "narrator"]:
		return
	if not _db.speakers.has(who):
		_err("%s: unknown speaker '%s'" % [id, who])


func _lint_req(id: String, req: Variant) -> void:
	if req == null:
		return
	if not req is Dictionary:
		_err("%s: requires is not an object" % id)
		return
	for k: Variant in req:
		if not str(k) in REQ_KEYS:
			_err("%s: unknown requires key '%s'" % [id, k])
	for c: Variant in req.get("seen", []) + req.get("not_seen", []):
		if not _db.conversations.has(str(c)):
			_err("%s: requires unknown conversation '%s'" % [id, c])
	for d: Variant in ([req["demon"]] if req.get("demon") is String else req.get("demon", [])):
		if not str(d) in DEMONS:
			_err("%s: unknown demon '%s'" % [id, d])
	for sub: Variant in req.get("any", []):
		_lint_req(id, sub)


# ---------------------------------------------------------------- simulation

func _simulate() -> void:
	var st := StoryState.new()
	var demon := "lilaeth"
	print("\n-- simulated campaign as %s (a Herald kill on every third run from run 3) --" % demon)
	for run in range(1, 31):
		# Basecamp visit: each NPC tells at most one new story beat.
		var told: Array[String] = []
		for pool: String in NPC_POOLS:
			var id := _pick_story(st, pool, demon)
			if id != "":
				_play(st, id, demon)
				told.append(id)
		# The run itself (Dialogue._promote_beats runs at run start).
		for k: String in st.vars.keys():
			if k.begins_with("beat.") and st.is_flag(k):
				st.set_var("known." + k.substr(5), true)
		st.add("runs")
		var kill := run >= 3 and run % 3 == 0
		st.set_var("last.boss_kills", 1 if kill else 0)
		st.set_var("last.result", "death")
		st.add("deaths")
		if kill:
			st.add("boss_kills")
			st.add("boss_kills.sariel")
		if run == 5:
			st.add("boss_seen.grand_inquisitor")
		# One offering to every NPC each visit from visit 4 (affinity caps at 5).
		if run >= 4:
			for sp: String in NPC_POOLS:
				if _db.has_pool("gift." + sp) and st.get_num("affinity." + sp) < Affinity.MAX_LEVEL:
					st.add("affinity." + sp)
					var gid := _pick_story(st, "gift." + sp, demon)
					if gid != "":
						_play(st, gid, demon)
		# The first run on the Seventh Gate road once the march is known wins the ending.
		if st.is_flag("known.march") and not st.is_flag("story.ended") and run >= 16:
			st.set_var("story.ended", true)
			st.set_var("known.ending", true)
			_play(st, "ending", demon)
			print("          ENDING reached on visit %d" % run)
		var beats: Array[String] = []
		for k: String in st.vars:
			if k.begins_with("beat.") and st.is_flag(k):
				beats.append(k.substr(5))
		print("visit %2d: %s" % [run, ", ".join(told) if not told.is_empty() else "(chatter only)"])
		if run == 30 or beats.has("empty_throne") and not st.is_flag("_printed"):
			print("          beats: %s" % ", ".join(beats))
			if beats.has("empty_throne"):
				st.set_var("_printed", true)
	if not st.is_flag("beat.empty_throne"):
		_err("simulation: the Empty Throne beat was never reached in 30 runs")
	if not st.is_flag("story.ended"):
		_err("simulation: the ending was never reached in 30 runs")
	for sp: String in NPC_POOLS:
		if _db.has_pool("gift." + sp) and st.times_seen("gift_%s_5" % sp) == 0:
			_err("simulation: %s never reached affinity 5" % sp)


## Same rule as Dialogue.pick() for a fresh visit: the highest-priority unseen eligible story beat.
func _pick_story(st: StoryState, pool: String, demon: String) -> String:
	var best := ""
	var best_p := -INF
	for id: String in _db.pool(pool):
		var c := _db.get_conv(id)
		if c["once"] and st.times_seen(id) == 0 and float(c["priority"]) > best_p and st.check(c.get("requires"), demon):
			best = id
			best_p = c["priority"]
	return best


## Marks the conversation seen and applies its sets (always taking the first eligible choice).
func _play(st: StoryState, id: String, demon: String) -> void:
	var c := _db.get_conv(id)
	st.mark_seen(id)
	st.apply(c.get("set"), c.get("add"))
	for line: Variant in c["lines"]:
		if st.check(line.get("requires"), demon):
			st.apply(line.get("set"), line.get("add"))
