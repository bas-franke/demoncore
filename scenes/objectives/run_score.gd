class_name RunScore
extends Node
## Run-end scoring (child of the ObjectiveDirector). When the run ends (RunState.run_ended) it
## scores the run from the objectives side, grades it D..S and pays a grade bonus:
##   score = objectives done x100 (+50 per variant, +80 per event survived) + bosses x250
##           + minutes x25 + kills / 4 - failed x30 + victory 600 (+400 for the Seventh Gate)
##   grade: S >= 2600, A >= 1700, B >= 1000, C >= 450, else D (thresholds: GRADES)
##   bonus: Souls (GRADE_SOULS) via Progression / Meta, Sin Shards for A and S.
## The report goes into the run result (`result["objectives"]`, read by the end screen's
## RunLedger) and into Meta.pending_summary ("objectives", and "souls" includes the bonus), so the
## banked-souls counter shows it. API: report() -> Dictionary (live, any time).

const GRADES := [["S", 2600], ["A", 1700], ["B", 1000], ["C", 450], ["D", 0]]
const GRADE_SOULS := {"S": 120, "A": 70, "B": 35, "C": 15, "D": 0}
const GRADE_SHARDS := {"S": 3, "A": 1}

var director: ObjectiveDirector
## The last report built at run end (empty until then).
var final_report: Dictionary = {}

var _variants_done := 0
var _events_done := 0
var _done_titles: Array[String] = []


func _ready() -> void:
	var rs := get_tree().root.get_node_or_null(^"RunState")
	if rs and rs.has_signal(&"run_ended"):
		rs.connect(&"run_ended", _on_run_ended)
	if director:
		director.objective_completed.connect(_on_completed)


func _on_completed(obj: Objective) -> void:
	if bool(obj.def.get("event", false)):
		_events_done += 1
	elif obj.def.has("variant"):
		_variants_done += 1
	if _done_titles.size() < 12:
		_done_titles.append(obj.title)


## The run's objective report so far: {score, grade, completed, failed, variants, events, bosses,
## curses, titles, bonus_souls, bonus_shards}.
func report(victory: bool = false, cause: String = "") -> Dictionary:
	var d := director
	var completed := d.completed_count if d else 0
	var failed := d.failed_count if d else 0
	var bosses := d.bosses_slain if d else 0
	var score := completed * 100 + _variants_done * 50 + _events_done * 80 + bosses * 250
	@warning_ignore("integer_division")
	score += int(Game.elapsed / 60.0 * 25.0) + Game.kills / 4 - failed * 30
	if victory:
		score += 600 + (400 if cause == "seventh_gate" else 0)
	score = maxi(score, 0)
	var grade := "D"
	for g: Array in GRADES:
		if score >= int(g[1]):
			grade = str(g[0])
			break
	return {
		"score": score, "grade": grade, "completed": completed, "failed": failed,
		"variants": _variants_done, "events": _events_done, "bosses": bosses,
		"curses": d.curses.duplicate() if d else [], "titles": _done_titles.duplicate(),
		"bonus_souls": int(GRADE_SOULS.get(grade, 0)), "bonus_shards": int(GRADE_SHARDS.get(grade, 0)),
	}


func _on_run_ended(result: Dictionary) -> void:
	if str(result.get("cause", "")) == "abandoned":
		return
	final_report = report(bool(result.get("victory", false)), str(result.get("cause", "")))
	# RunState passes its own last_result: the end screen (opened ~2 s later) reads this key.
	result["objectives"] = final_report
	var souls := int(final_report.bonus_souls)
	var shards := int(final_report.bonus_shards)
	var prog := get_tree().root.get_node_or_null(^"Progression")
	var meta := get_tree().root.get_node_or_null(^"Meta")
	if souls > 0:
		if prog and prog.has_method(&"add_currency"):
			prog.call(&"add_currency", &"souls", souls)
		elif meta and meta.has_method(&"add_souls"):
			meta.call(&"add_souls", souls)
	if shards > 0 and prog and prog.has_method(&"add_currency"):
		prog.call(&"add_currency", &"sin_shards", shards)
	# Meta built its summary (souls banked) before us: fold the bonus in so the counter shows it.
	if meta and meta.get(&"pending_summary") is Dictionary:
		var summary: Dictionary = meta.get(&"pending_summary")
		if not summary.is_empty():
			summary["objectives"] = final_report
			summary["souls"] = int(summary.get("souls", 0)) + souls
