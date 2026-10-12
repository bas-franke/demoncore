class_name LastStand
extends RefCounted
## "Last stand" (core-gameplay role): once per run (Player.last_stands charges) a lethal blow
## leaves the demon at 1 HP instead, with a burst of hellfire that hurls back and scorches every
## angel nearby, 1.5 s of invulnerability and a heavy hitstop. Player._receive_damage calls
## trigger(); RunState.last_stand is emitted for UI / audio (Sfx &"last_stand", sfx role).

const RADIUS := 6.5
## Burst damage: the larger of BASE x might and HP_FRACTION of the angel's max HP (so it stays
## meaningful late in a run without one-shotting elites and bosses outright).
const BASE := 80.0
const HP_FRACTION := 0.6
const KNOCKBACK := 14.0
const IFRAMES := 1.5


static func trigger(p: Player) -> void:
	var at := p.global_position
	p.dash.grant_iframes(IFRAMES)
	for e in Targeting.nearest_enemies(p.get_tree(), at, 200, RADIUS):
		if e.is_dying:
			continue
		var dmg := maxf(BASE * p.might, e.max_hp * HP_FRACTION)
		if e.is_in_group(&"boss"):
			dmg = BASE * p.might
		Enemy.hit(e, dmg, Targeting.flat_dir(at, e.global_position) * KNOCKBACK, p)
	# Presentation: the pit answers.
	EnemyModel.shockwave(at, RADIUS, Art.HELLFIRE, 0.6)
	EnemyModel.light_flash(at + Vector3(0.0, 0.8, 0.0), RADIUS * 0.6, Art.HELLFIRE, true)
	HolyFX.motes(at + Vector3(0.0, 0.6, 0.0), 30, Art.EMBER, RADIUS * 0.5, 2.5, 1.2, 0.09)
	DamageNumber.spawn_text("LAST STAND", at + Vector3(0.0, 2.4, 0.0), Color(1.0, 0.3, 0.12), 46)
	Game.hitstop(0.12, 0.02)
	p.get_tree().call_group(&"camera_rig", &"shake", 0.6)
	p.get_tree().call_group(&"camera_rig", &"zoom_punch", -0.12)
	Sfx.play(&"brimstone", 0.0, 2.0)
	Sfx.play(&"last_stand", 0.0, 0.0)
	RunState.notify_last_stand()
