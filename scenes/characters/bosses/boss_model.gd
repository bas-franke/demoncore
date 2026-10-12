class_name BossModel
extends ProcModel
## Base for the procedural boss models driven by ProcBoss (characters-new). ProcBoss writes the
## fields below; subclasses read them in pose() (smoothed copies `rise_w`, `kneel_w`, plus the
## per-attack weight helpers). Bosses are built at ~1/2.2 scale (EnemyData.size scales them up).

## Attack being told / released (ProcBoss kinds: lanes, cross, chase, rain, pyre, sweep, bells,
## orbs, charge, summon), &"" when idle.
var attack_kind := &""
## 0-based phase (ProcBoss.phase_index).
var boss_phase := 0
## 0..1 while rising through a phase change.
var rise := 0.0
## 0..1 while dying.
var kneel := 0.0

var rise_w := 0.0
var kneel_w := 0.0


func animate(delta: float, move_ratio: float, state: int) -> void:
	rise_w = damp(rise_w, rise, 6.0, delta)
	kneel_w = damp(kneel_w, kneel, 3.0, delta)
	super.animate(delta, move_ratio, state)


## 0..1: how much the current attack is `kind` (wind-up or strike), for pose blending.
func act(kinds: Array) -> float:
	if not (attack_kind in kinds):
		return 0.0
	return maxf(windup_w, maxf(strike_w, recover_w * 0.6))


func _ready() -> void:
	super._ready()
	# Bosses keep their body through the death sequence (ProcBoss shrinks it at the end).
	death_style = &"none"
	corpse_on_death = false
