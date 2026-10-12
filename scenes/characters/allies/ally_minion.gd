class_name AllyMinion
extends Node3D
## A demonic ally in a run: one of the roster ally models (imp, succubus, hellhound, hell brute;
## res://data/allies/allies.json) with a simple brain - heel near the demon, hunt the nearest
## angel inside `aggro_range`, strike it every `hit_rate` s (melee roles) or throw hellfire at it
## from `attack_range` (the caster role). No physics body: it glides over the crowd, so it never
## blocks the player or the enemies, and enemies ignore it (it can't be hurt). It crumbles into
## embers after `lifetime` s (0 = stays until dismiss()).
##
##   AllyMinion.spawn(&"hellhound", Game.player.global_position)            # data defaults
##   AllyMinion.spawn(&"imp", at, {"damage": 6, "lifetime": 12, "tags": ["fire"]})
##
## Damage goes through AbilityCombat.hit (statuses, crits, synergies) when the abilities
## framework is present, else Enemy.take_damage. Groups: "allies" (shared with DamnedSoul) and
## "ally_minions". Signals: struck(enemy, amount), expired.

signal struck(enemy: Node3D, amount: float)
signal expired

const GROUP := &"ally_minions"
const RETARGET := 0.35
## Teleported back to the demon beyond this distance.
const LEASH := 18.0
const COMBAT_PATH := "res://scripts/abilities/ability_combat.gd"

var ally_id: StringName = &"imp"
var damage := 5.0
var speed := 5.0
var hit_rate := 0.6
## Strike reach (melee) or casting distance (caster).
var attack_range := 1.0
var aggro_range := 12.0
var lifetime := 0.0
var role := &"swarm"
## Ability-style source for AbilityCombat.hit: {"tags": PackedStringArray([...]), ...}.
var src := {}

var model: ProcModel
var _target: Node3D
var _retarget_t := 0.0
var _hit_t := 0.0
var _age := 0.0
var _heel := Vector3.ZERO
var _windup := 0.0
var _speed_now := 0.0
var _dying := false

static var _combat: Script


## Spawns ally `id` at `at` (world). `opts` overrides any allies.json stat (damage, speed,
## hit_rate, range, lifetime, scale, aggro) and may carry "tags" for AbilityCombat.
static func spawn(id: StringName, at: Vector3, opts: Dictionary = {}) -> AllyMinion:
	if Game.world == null:
		return null
	var def: Dictionary = CharacterRoster.allies().get(String(id), {})
	if def.is_empty():
		push_warning("AllyMinion: unknown ally '%s'" % id)
		return null
	var m := AllyMinion.new()
	m.ally_id = id
	m.role = StringName(String(opts.get("role", def.get("role", "swarm"))))
	m.damage = float(opts.get("damage", def.get("damage", 5.0)))
	m.speed = float(opts.get("speed", def.get("speed", 5.0)))
	m.hit_rate = float(opts.get("hit_rate", def.get("hit_rate", 0.6)))
	m.attack_range = float(opts.get("range", def.get("range", 1.0)))
	m.aggro_range = float(opts.get("aggro", 12.0))
	m.lifetime = float(opts.get("lifetime", 0.0))
	m.scale = Vector3.ONE * float(opts.get("scale", def.get("scale", 1.0)))
	m.src = {"tags": PackedStringArray(opts.get("tags", ["summon"]))}
	Game.spawn(m, Vector3(at.x, 0.0, at.z))
	return m


func _ready() -> void:
	add_to_group(&"allies")
	add_to_group(GROUP)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	model = CharacterRoster.make_ally(ally_id)
	if model:
		model.autoplay = false
		add_child(model)
		model.body_scale = scale.x
	var a := randf() * TAU
	_heel = Vector3(cos(a), 0.0, sin(a)) * randf_range(1.4, 2.4)
	_hit_t = randf_range(0.1, hit_rate)
	# Arrive in a burst of embers.
	EnemyModel.light_flash(global_position + Vector3(0.0, 0.4, 0.0), 0.6, Art.EMBER, false)
	EnemyModel.spawn_motes(global_position, 6, 0.8, Art.EMBER)


func _physics_process(delta: float) -> void:
	if _dying:
		return
	_age += delta
	if lifetime > 0.0 and _age >= lifetime:
		dismiss()
		return
	var player := Game.player
	_retarget_t -= delta
	if _retarget_t <= 0.0 or not _valid(_target):
		_retarget_t = RETARGET
		_target = _find_target()
	var goal := global_position
	var engaging := _valid(_target)
	if engaging:
		goal = _target.global_position
	elif player:
		goal = player.global_position + _heel.rotated(Vector3.UP, _age * 0.3)
	if player and global_position.distance_to(player.global_position) > LEASH:
		global_position = player.global_position + _heel
	var to := goal - global_position
	to.y = 0.0
	var dist := to.length()
	var reach := attack_range
	if engaging and _target.get(&"data"):
		reach += 0.35 * float(_target.data.size)
	var step := Vector3.ZERO
	if engaging:
		# Casters hold at range; melee closes in.
		if dist > reach * 0.85:
			step = to / dist * speed
		elif role == &"caster" and dist < reach * 0.5:
			step = -to / dist * speed * 0.5
	elif dist > 0.3:
		step = to / dist * minf(speed, dist * 3.0)
	global_position += step * delta
	global_position.y = 0.0
	_speed_now = step.length()
	var face := to if engaging or dist > 0.3 else step
	if face.length_squared() > 0.001 and model:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-12.0 * delta))
	_hit_t -= delta
	_windup = maxf(_windup - delta, 0.0)
	if engaging and _hit_t <= 0.0 and dist <= reach:
		_hit_t = hit_rate * randf_range(0.9, 1.1)
		_attack(_target)
	_animate(delta)


## Untyped on purpose: a typed Node3D parameter errors when handed a freed enemy.
func _valid(n: Variant) -> bool:
	return is_instance_valid(n) and not bool((n as Object).get(&"is_dying"))


func _find_target() -> Node3D:
	var best: Node3D = null
	var best_d := aggro_range * aggro_range
	var origin := global_position
	if Game.player:
		# Prefer angels near the demon (bodyguard), not ones far off behind the ally.
		origin = origin.lerp(Game.player.global_position, 0.5)
	for n in Perf.enemies():  # perf: shared per-frame list
		var e := n as Node3D
		if e == null or not _valid(e):
			continue
		var d := e.global_position.distance_squared_to(origin)
		if d < best_d:
			best_d = d
			best = e
	return best


func _attack(enemy: Node3D) -> void:
	if model:
		model.play_attack()
	_windup = 0.18
	if role == &"caster":
		_cast_bolt(enemy)
	else:
		_hit(enemy, damage)


## Deals `amount` to `enemy` (AbilityCombat when available, so statuses / crits / synergies apply).
func _hit(enemy: Node3D, amount: float) -> void:
	if not _valid(enemy):
		return
	if _combat == null and ResourceLoader.exists(COMBAT_PATH):
		_combat = load(COMBAT_PATH)
	var done := false
	if _combat and get_node_or_null(^"/root/Abilities"):
		done = bool(_combat.call(&"hit", enemy, amount, src))
	if not done and enemy.has_method(&"take_damage"):
		var kb := enemy.global_position - global_position
		kb.y = 0.0
		enemy.call(&"take_damage", amount, kb.normalized() * 2.0 if kb.length_squared() > 0.001 else Vector3.ZERO)
	struck.emit(enemy, amount)


## Caster: a mote of hellfire flies to the target and bursts on it.
func _cast_bolt(enemy: Node3D) -> void:
	if Game.world == null:
		return
	var from := global_position + Vector3(0.0, 1.0 * scale.x, 0.0)
	var bolt := Art.part(Game.world, Art.sphere(), Art.glow(Color(0.95, 0.3, 0.8), 2.4), from, Vector3.ONE * 0.18)
	bolt.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var target_ref: WeakRef = weakref(enemy)
	var dist := from.distance_to(enemy.global_position)
	var tw := bolt.create_tween()
	tw.tween_method(func(k: float) -> void:
		var e := target_ref.get_ref() as Node3D
		if e and is_instance_valid(bolt):
			bolt.global_position = from.lerp(e.global_position + Vector3(0.0, 0.6, 0.0), k)
	, 0.0, 1.0, clampf(dist / 14.0, 0.08, 0.5))
	tw.tween_callback(func() -> void:
		var e := target_ref.get_ref() as Node3D
		if e and is_instance_valid(self):
			_hit(e, damage)
		EnemyModel.light_flash(bolt.global_position, 0.4, Color(0.95, 0.3, 0.8), false)
		bolt.queue_free())


func _animate(delta: float) -> void:
	if model == null:
		return
	model.ground_speed = _speed_now
	var st := EnemyModel.State.WINDUP if _windup > 0.1 else EnemyModel.State.MOVING
	model.animate(delta, clampf(_speed_now / maxf(speed, 0.01), 0.0, 1.0), st)


## Crumbles into embers and frees itself.
func dismiss() -> void:
	if _dying:
		return
	_dying = true
	remove_from_group(GROUP)
	remove_from_group(&"allies")
	expired.emit()
	EnemyModel.spawn_motes(global_position + Vector3(0.0, 0.3, 0.0), 8, 0.9, Art.EMBER)
	var tw := create_tween()
	tw.tween_property(self, "scale", scale * 0.05, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
