class_name Codex
extends RefCounted
## The lore codex: entries from "codex" in res://data/dialogue/codex.json, each unlocked by a
## story condition block ("requires", same rules as conversations). Read through the Dialogue
## autoload (`d`): Dialogue.codex_entries(), codex_mark_read(id), codex_new_count().
## Story vars: "codex.known.<id>" (unlock already announced), "codex.read.<id>" (opened in the UI).


## Raw codex definitions ("codex" array of the dialogue data files), unfiltered.
static func defs(d: Node) -> Array:
	var c: Variant = d.db.extra.get("codex", [])
	return c if c is Array else []


## Every entry in file order: {id, category, title, text, unlocked, is_new}.
static func entries(d: Node) -> Array[Dictionary]:
	var st: StoryState = d.state
	var out: Array[Dictionary] = []
	for e: Variant in defs(d):
		if not e is Dictionary:
			continue
		var id := str(e.get("id", ""))
		var open := is_unlocked(d, e)
		out.append({
			"id": id,
			"category": str(e.get("category", "Lore")),
			"title": str(e.get("title", id)) if open else "???",
			"text": d.format(str(e.get("text", ""))) if open else "",
			"unlocked": open,
			"is_new": open and not st.is_flag("codex.read." + id),
		})
	return out


## True when entry `e`'s "requires" condition holds for the current story state and demon.
static func is_unlocked(d: Node, e: Dictionary) -> bool:
	return d.state.check(e.get("requires"), d.demon_id())


## Marks entry `id` as read (clears its "new" badge) and saves the story state.
static func mark_read(d: Node, id: String) -> void:
	d.state.set_var("codex.read." + id, true)
	d.save()


## Number of unlocked entries not read yet (the "new" badge count).
static func new_count(d: Node) -> int:
	var n := 0
	for e in entries(d):
		if e["is_new"]:
			n += 1
	return n


## Emits Dialogue.codex_unlocked for entries that became readable since the last check.
static func announce_unlocks(d: Node) -> void:
	for e: Variant in defs(d):
		if not e is Dictionary:
			continue
		var id := str(e.get("id", ""))
		if not d.state.is_flag("codex.known." + id) and is_unlocked(d, e):
			d.state.set_var("codex.known." + id, true)
			d.notify_codex_unlocked(id)
