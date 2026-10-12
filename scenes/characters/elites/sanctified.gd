class_name Sanctified
extends Node3D
## The "Sanctified" elite overlay (characters-new): turns ANY Enemy into a blessed elite. It adds a
## gold aura (a slow ring of light on the ground, a crown of light over the head, rising motes
## and a warm light), multiplies health and contact damage, and grants one affix. Affix ids and
## names match the objectives role's champion affixes (scenes/objectives/types/champion_objective.gd)
## so a champion and a sanctified angel of the same kind behave alike:
##   radiant    Judgement Pillars (gold) open on the demon every few seconds
##   zealous    much faster, attacks more often
##   bulwark    far more health, slower, larger
##   choir_led  keeps calling Choir Wisps to its side (max 4 alive)
##   martyr     on death, a ring of holy orbs bursts out
##   hallowed   heals angels around it every second (new)
##
##   Sanctified.apply(enemy)                # random affix
##   Sanctified.apply(enemy, "radiant")     # chosen affix; returns the overlay (null if invalid)
##   Sanctified.of(enemy) / is_sanctified(enemy)
## On death it pays a little extra Ichor (RunState.drop_currency). Group "sanctified" (on the
## enemy). Bosses are refused.

const AFFIXES: Array[String] = ["radiant", "zealous", "bulwark", "choir_led", "martyr", "hallowed"]
## Display names (prefix, epithet) per affix, shared with the champion affixes.
const AFFIX_NAMES := {
	"radiant": ["Radiant", "the Dawnbringer"],
	"zealous": ["Zealous", "the Swift Verdict"],
	"bulwark": ["Unbroken", "the Wall of Heaven"],
	"choir_led": ["Choir-led", "Voice of the Host"],
	"martyr": ["Martyred", "Who Dies Gladly"],
	"hallowed": ["Hallowed", "the Mender"],
}
const HP_MULT := 3.0
const DAMAGE_MULT := 1.3
const GOLD := Color(1.0, 0.82, 0.35)
const ICHOR_REWARD := 4

var affix := "radiant"

var _enemy: Enemy
var _aura: Node3D
var _crown: Node3D
var _ability_t := 3.0
var _mote_t := 0.0
var _wisps: Array[Node] = []
var _last_pos := Vector3.ZERO
var _size := 1.0
var _paid := false


## Sanctifies `enemy` with `affix_id` ("" = random). Returns the overlay, or null when the enemy is
## a boss, already sanctified, dying or invalid.
static func apply(enemy: Enemy, affix_id: String = "") -> Sanctified:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dying or enemy.is_in_group(&"boss"):
		return null
	if enemy.is_in_group(&"sanctified"):
		return null
	var s := Sanctified.new()
	s.name = "Sanctified"
	s.affix = affix_id if affix_id in AFFIXES else AFFIXES.pick_random()
	enemy.add_child(s)
	return s


static func of(enemy: Node) -> Sanctified:
	return enemy.get_node_or_null(^"Sanctified") as Sanctified if enemy else null


static func is_sanctified(enemy: Node) -> bool:
	return enemy != null and enemy.is_in_group(&"sanctified")


## "Radiant Seraph Sentinel, the Dawnbringer" style name for `base_name`.
static func title_for(base_name: String, affix_id: String) -> String:
	var n: Array = AFFIX_NAMES.get(affix_id, ["Sanctified", "the Blessed"])
	return "%s %s, %s" % [n[0], base_name, n[1]]


func _ready() -> void:
	_enemy = get_parent() as Enemy
	if _enemy == null:
		queue_free()
		return
	_enemy.add_to_group(&"sanctified")
	_size = _enemy.data.size if _enemy.data else 1.0
	var hp_mult := HP_MULT
	match affix:
		"zealous":
			_enemy.set_move_factor(&"sanctified", 1.45)
		"bulwark":
			hp_mult *= 1.8
			_enemy.set_move_factor(&"sanctified", 0.8)
			if _enemy.model:
				_enemy.model.scale *= 1.15
	_enemy.max_hp *= hp_mult
	_enemy.hp = _enemy.max_hp
	_enemy.damage *= DAMAGE_MULT
	_build_aura()
	# Enemy.died fires from die() before any death FX (characters-new round 5); tree_exiting is the
	# fallback for anything removed some other way while dying.
	if _enemy.has_signal(&"died"):
		_enemy.died.connect(func(_e: Enemy) -> void: _on_exiting())
	else:
		tree_exiting.connect(_on_exiting)
	_ability_t = randf_range(2.0, 4.0)


func _build_aura() -> void:
	var s := _size
	_aura = Art.pivot(self, Vector3(0.0, 0.05, 0.0))
	Art.part(_aura, Art.torus(0.86, 1.0), Art.glow(GOLD, 1.8), Vector3.ZERO, Vector3.ONE * 0.75 * s)
	Art.part(_aura, Art.cylinder(0.5, 0.5), Art.glow(GOLD, 0.35, true, 0.6), Vector3.ZERO, Vector3(1.5 * s, 0.01, 1.5 * s))
	for k in 6:
		var a := TAU * float(k) / 6.0
		Art.part(_aura, Art.box(), Art.glow(GOLD, 2.0), Vector3(cos(a), 0.0, sin(a)) * 0.95 * s, Vector3(0.05, 0.02, 0.2) * s, Vector3(0.0, -a, 0.0))
	var hover := _enemy.data.hover if _enemy.data else 0.0
	_crown = Art.pivot(self, Vector3(0.0, s * 1.5 + hover, 0.0))
	Art.part(_crown, Art.torus(0.82, 1.0), Art.glow(GOLD, 2.4), Vector3.ZERO, Vector3.ONE * 0.28 * s)
	for k in 5:
		var a := TAU * float(k) / 5.0
		Art.part(_crown, Art.cone(0.5), Art.glow(Art.HOLY_WHITE, 2.4), Vector3(cos(a), 0.1, sin(a)) * 0.28 * s, Vector3(0.04, 0.14, 0.04) * s)
	var l := Art.light(self, GOLD, 1.2, 3.5 * s, Vector3(0.0, 1.0 * s, 0.0))
	l.shadow_enabled = false


func _process(delta: float) -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	_last_pos = _enemy.global_position
	_aura.rotate_y(delta * 0.8)
	_crown.rotate_y(-delta * 1.5)
	_crown.position.y = _size * 1.5 + (_enemy.data.hover if _enemy.data else 0.0) + sin(Time.get_ticks_msec() * 0.003) * 0.05
	_mote_t -= delta
	if _mote_t <= 0.0:
		_mote_t = 0.35
		EnemyModel.spawn_motes(_enemy.global_position + Vector3(0.0, 0.2, 0.0), 1, 0.6 * _size, GOLD)
	if _enemy.is_dying:
		return
	_ability_t -= delta
	if _ability_t <= 0.0:
		_use_ability()


func _use_ability() -> void:
	var p := Game.player
	if p == null or p.is_dead:
		_ability_t = 1.0
		return
	match affix:
		"radiant":
			_ability_t = 4.5
			HolyFX.hazard_tint = GOLD
			JudgementPillar.cast(p.global_position, 1.4, 1.2, 14.0)
			HolyFX.hazard_tint = Art.HOLY
		"choir_led":
			_ability_t = 7.0
			var alive: Array[Node] = []
			for w in _wisps:
				if is_instance_valid(w):
					alive.append(w)
			_wisps = alive
			if _wisps.size() < 4:
				for i in 2:
					var w := ObjectiveFX.spawn_enemy("choir_wisp", ObjectiveFX.ring_point(_enemy.global_position, 2.0), 0.6)
					if w:
						_wisps.append(w)
		"hallowed":
			_ability_t = 1.0
			for n in Perf.enemies():  # perf: shared per-frame list
				var e := n as Enemy
				if e and e != _enemy and not e.is_dying and e.global_position.distance_squared_to(_enemy.global_position) < 25.0:
					e.heal(e.max_hp * 0.04, &"sanctified_hallowed", false)
		_:
			_ability_t = 999.0


## The enemy is leaving the tree: if it died, pay out and (martyr) burst.
func _on_exiting() -> void:
	if _enemy == null or not _enemy.is_dying or _paid:
		return
	_paid = true
	_last_pos = _enemy.global_position
	_on_death.call_deferred(_last_pos, affix, _size)


static func _on_death(at: Vector3, affix_id: String, s: float) -> void:
	if Game.world == null:
		return
	var rs := (Engine.get_main_loop() as SceneTree).root.get_node_or_null(^"RunState")
	if rs and rs.has_method(&"drop_currency"):
		rs.call(&"drop_currency", at, ICHOR_REWARD, 2)
	EnemyModel.light_flash(at + Vector3(0.0, 0.6, 0.0), 1.2 * s, GOLD, true)
	if affix_id == "martyr":
		for i in 12:
			var a := TAU * float(i) / 12.0
			var dir := Vector3(cos(a), 0.0, sin(a))
			HolyFX.hazard_tint = GOLD
			SarielOrb.fire(at + dir * 1.0 + Vector3(0.0, 0.6, 0.0), dir * 3.0, 12.0, 5.0)
			HolyFX.hazard_tint = Art.HOLY
