class_name Affinity
extends RefCounted
## Offerings (gifts) to Basecamp NPCs, paid in Souls (Meta.spend). Each offering raises the NPC's
## affinity by one (story var "affinity.<speaker>", 0..MAX_LEVEL), plays the best conversation of
## pool "gift.<speaker>" (story beats gated on the new level, then thanks), and is limited to one
## per NPC per Basecamp visit. Affinity-gated lines elsewhere use
## "requires": {"min": {"affinity.vesper": 3}}. Used through the Dialogue autoload (`d`).
## Milestone rewards ("affinity_rewards" in data/dialogue/gifts.json) go through Progression:
## currencies and unlocks once when the level is reached, stat perks at every run start.

const MAX_LEVEL := 5
## Soul cost of the offering that raises affinity from level i to i + 1.
const COSTS: Array[int] = [20, 40, 70, 110, 160]


## Speaker id for `who` if it takes offerings (has a "gift.<speaker>" pool), else "".
static func speaker_of(d: Node, who: String) -> String:
	var sp: String = d.speaker_for_shop(who)
	if sp == "":
		sp = who
	return sp if d.db.has_pool("gift." + sp) else ""


## Current affinity (0..MAX_LEVEL) of the NPC `who` (speaker id or alias). `d` is the Dialogue autoload.
static func level(d: Node, who: String) -> int:
	var sp := speaker_of(d, who)
	return int(d.state.get_num("affinity." + sp)) if sp != "" else 0


## Souls the next offering to `who` costs, or -1 when `who` is unknown or already at MAX_LEVEL.
static func cost(d: Node, who: String) -> int:
	var sp := speaker_of(d, who)
	if sp == "":
		return -1
	var lv := level(d, sp)
	return COSTS[lv] if lv < MAX_LEVEL else -1


## True when an offering to `who` is possible right now: not maxed, no conversation running,
## not already gifted this Basecamp visit, and the player can afford it.
static func can_gift(d: Node, who: String) -> bool:
	var c := cost(d, who)
	if c < 0 or d.is_active():
		return false
	var sp := speaker_of(d, who)
	if d.state.get_num("gift.visit." + sp) == d.state.get_num("basecamp_visits"):
		return false  # one offering per NPC per visit
	return _souls(d) >= c


## Spends the Souls (Meta.spend) and raises `who`'s affinity by one. Returns false if not allowed.
static func give(d: Node, who: String) -> bool:
	if not can_gift(d, who):
		return false
	var sp := speaker_of(d, who)
	var meta := d.get_node_or_null(^"/root/Meta")
	if meta == null or not bool(meta.call(&"spend", cost(d, sp))):
		return false
	d.state.add("affinity." + sp)
	d.state.set_var("gift.visit." + sp, d.state.get_num("basecamp_visits"))
	d.state.add("gifts_given")
	var lv := level(d, sp)
	if lv >= MAX_LEVEL:
		d.state.set_var("bond." + sp, true)
	_grant_milestone(d, sp, lv)
	d.save()
	var sfx := d.get_node_or_null(^"/root/Sfx")
	if sfx:
		sfx.call(&"play", &"soul", 0.05)
	d.notify_gift(sp, lv)
	if d.start_for("gift." + sp) != "":
		_follow_with_keepsake(d, sp)
	return true


## Right after the offering that unlocks an NPC's keepsake, they hand it over (keepsake_<speaker>).
static func _follow_with_keepsake(d: Node, sp: String) -> void:
	var id := "keepsake_" + sp
	await d.conversation_finished
	var c: Dictionary = d.db.get_conv(id)
	if not c.is_empty() and d.state.times_seen(id) == 0 and d.eligible(c):
		d.start(id)


static func _souls(d: Node) -> int:
	var meta := d.get_node_or_null(^"/root/Meta")
	return int(meta.get(&"souls")) if meta else 0


## The reward block for `sp` at `lv` ({} if none).
static func reward(d: Node, sp: String, lv: int) -> Dictionary:
	var all: Variant = d.db.extra.get("affinity_rewards", {})
	var per: Variant = (all as Dictionary).get(sp, {}) if all is Dictionary else {}
	var r: Variant = (per as Dictionary).get(str(lv), {}) if per is Dictionary else {}
	return r if r is Dictionary else {}


## One-time rewards for reaching `lv` (currencies, unlocks) plus the announcement.
static func _grant_milestone(d: Node, sp: String, lv: int) -> void:
	var r := reward(d, sp, lv)
	if r.is_empty() or d.state.is_flag("affinity.granted.%s.%d" % [sp, lv]):
		return
	d.state.set_var("affinity.granted.%s.%d" % [sp, lv], true)
	var prog := d.get_node_or_null(^"/root/Progression")
	var currency: Variant = r.get("currency", {})
	if r.has("unlock") and prog:
		var id := StringName(str(r["unlock"]))
		var owned: bool = prog.has_method(&"is_unlocked") and bool(prog.call(&"is_unlocked", id))
		if owned:
			currency = r.get("fallback", {})
		else:
			prog.call(&"grant_unlock", id)
	if currency is Dictionary and prog:
		for c: Variant in currency:
			prog.call(&"add_currency", StringName(str(c)), int(currency[c]))
	if r.has("text"):
		d.narrate(str(r["text"]))


## Applies every earned stat perk (affinity >= its level) to the demon. Called at run start.
static func apply_run_perks(d: Node) -> void:
	var game := d.get_node_or_null(^"/root/Game")
	var p: Node = game.get(&"player") if game else null
	if not is_instance_valid(p):
		return
	var all: Variant = d.db.extra.get("affinity_rewards", {})
	if not all is Dictionary:
		return
	for sp: Variant in all:
		var lv := int(d.state.get_num("affinity." + str(sp)))
		var per: Variant = all[sp]
		if not per is Dictionary:
			continue
		for key: Variant in per:
			var stat: Variant = (per[key] as Dictionary).get("stat") if per[key] is Dictionary else null
			if int(str(key)) <= lv and stat is Dictionary:
				for st: Variant in stat:
					if StringName(str(st)) in p:
						p.call(&"apply_stat", StringName(str(st)), float(stat[st]))
