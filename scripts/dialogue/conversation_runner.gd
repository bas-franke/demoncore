class_name ConversationRunner
extends RefCounted
## Steps through one conversation's lines in a DialogueBox: conditions, "set"/"add", events,
## text, choices, labels / goto / end. Used by the Dialogue autoload (`d`), which owns the setup
## (pausing, marking seen) and the teardown. A coroutine: `await ConversationRunner.play(...)`.


## Plays `conv` line by line in `box` (a coroutine: await it). Evaluates conditions, applies
## "set"/"add" effects and fires events on the Dialogue autoload `d` as it goes.
static func play(d: Node, box: DialogueBox, conv: Dictionary) -> void:
	var state: StoryState = d.state
	var id: String = conv["id"]
	var lines: Array = conv["lines"]
	var labels: Dictionary = conv["labels"]
	var default_who: String = d.db.default_who(conv)
	var demon: String = d.demon_id()
	var i := 0
	var guard := 0
	while i < lines.size() and guard < 1000:
		guard += 1  # protects against goto loops in bad data
		var line: Variant = lines[i]
		i += 1
		if not line is Dictionary:
			continue
		var l: Dictionary = line
		if not state.check(l.get("requires"), demon):
			continue
		state.apply(l.get("set"), l.get("add"))
		if l.has("event"):
			d.notify_event(str(l["event"]), id)
		if l.has("text"):
			box.show_line(d.speaker(str(l.get("who", default_who))), d.format(str(l["text"])))
			if not l.has("choices"):
				await box.advanced
		if l.has("choices"):
			var target := await _ask(d, box, l["choices"])
			if target == "<end>":
				break
			if target != "":
				i = labels.get(target, lines.size())
			continue
		if l.get("end", false):
			break
		if l.has("goto"):
			i = labels.get(str(l["goto"]), lines.size())


## Shows the eligible choices and returns the chosen one's "goto" label ("" = continue,
## "<end>" = end the conversation). Applies the choice's "set" / "add".
static func _ask(d: Node, box: DialogueBox, raw: Variant) -> String:
	var state: StoryState = d.state
	var options: Array[Dictionary] = []
	if raw is Array:
		for c: Variant in raw:
			if c is Dictionary and state.check(c.get("requires"), d.demon_id()):
				options.append(c)
	if options.is_empty():
		return ""
	var texts: Array = []
	for c in options:
		texts.append(d.format(str(c.get("text", "..."))))
	box.show_choices(texts)
	var idx: int = await box.chosen
	var picked := options[idx]
	state.apply(picked.get("set"), picked.get("add"))
	if picked.get("end", false):
		return "<end>"
	return str(picked.get("goto", ""))
