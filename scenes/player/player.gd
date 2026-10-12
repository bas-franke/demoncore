class_name Player
extends CharacterBody3D
## The demon. Owns stats, XP/levels, weapons and passives.
## Weapons read the multiplier stats (might, area, cooldown, ...) when they attack.
## The demon's look, perks and starting weapon come from a DemonData
## (Game.selected_character or default_character).

signal leveled_up
signal died
signal damaged(amount: float)

## Used when no demon was picked on the select screen (e.g. running main.tscn directly).
@export var default_character: DemonData
## Fallback when the demon has no starting weapon.
@export var starting_weapon: PackedScene
## Set before _ready to replace the demon's own starting weapon (Basecamp loadout, see Meta).
var starting_weapon_override: PackedScene
## Weapons that can be offered on level-up.
@export var weapon_pool: Array[PackedScene] = []
## Passives that can be offered on level-up.
@export var passive_pool: Array[PassiveData] = []
@export var max_weapons := 6

@export_group("Stats")
@export var max_hp := 100.0
@export var move_speed := 6.0
@export var pickup_radius := 2.5
## Flat reduction to each touching enemy's damage-per-second.
@export var armor := 0.0
## HP regenerated per second.
@export var regen := 0.0
@export var might := 1.0
@export var area := 1.0
## Weapon cooldown multiplier (lower is faster).
@export var cooldown := 1.0
@export var projectile_speed := 1.0
@export var bonus_projectiles := 0
## XP multiplier.
@export var xp_gain := 1.0

@export_group("Dash")
## Dash burst speed (units/s), duration (s), recharge per charge (s) and charges.
## Stats like the ones above: apply_stat(&"dash_charges", 1) etc. See PlayerDash.
@export var dash_speed := 21.0
@export var dash_time := 0.17
@export var dash_cooldown := 1.1
@export var dash_charges := 1
## Invulnerability after a discrete hit (projectile, slam, beam). Contact ticks don't trigger it.
@export var hit_mercy_time := 0.45
## Lethal blows survived at 1 HP with a hellfire burst (scenes/player/last_stand.gd). A stat:
## relics / meta can add more with apply_stat(&"last_stands", 1).
@export var last_stands := 1

var character: DemonData
var model: DemonModel
var hp: float
var level := 1
var xp := 0.0
var xp_to_next := 5
var pending_level_ups := 0
var is_dead := false
## Last non-zero movement direction, for weapons that fire "forward".
var facing := Vector3.FORWARD
var weapons: Array[Weapon] = []
var passive_levels := {}  # PassiveData -> int

var _owned_weapons := {}  # PackedScene -> Weapon
var _weapon_templates := {}  # PackedScene -> Weapon (not in tree; used for names on the level-up screen)
var _hurt_cooldown := 0.0
## Dash + i-frames component (scenes/player/player_dash.gd), created in _ready().
var dash: PlayerDash
## Knockback velocity from discrete hits, decays quickly.
var _knock := Vector3.ZERO
var _blink_t := 0.0

## The player turns to face the closest enemy within this range (else the move direction).
const FACE_RANGE := 14.0
const RETARGET_INTERVAL := 0.1
var _face_target: Enemy
var _retarget_t := 0.0
const ATTACK_ANIM_RANGE := 5.0
var _attack_anim_t := 0.0

@onready var body: Node3D = $Body
@onready var hurtbox: Area3D = $Hurtbox
@onready var pickup_area: Area3D = $PickupArea
@onready var pickup_shape: SphereShape3D = $PickupArea/CollisionShape3D.shape
@onready var weapon_root: Node3D = $Weapons


func _ready() -> void:
	pickup_shape = pickup_shape.duplicate()
	$PickupArea/CollisionShape3D.shape = pickup_shape
	pickup_area.area_entered.connect(_on_pickup_area_entered)

	character = Game.selected_character as DemonData
	if character == null:
		character = default_character
	model = DemonModel.new()
	body.add_child(model)
	if character:
		model.build(character)
		# Hellfire rim light on the demon's silhouette (docs/team/art-style.md).
		ArtStyle.apply_faction(model, ArtStyle.Faction.DEMON)
		character.apply_to(self)
		if character.starting_weapon:
			starting_weapon = character.starting_weapon
	if starting_weapon_override:
		starting_weapon = starting_weapon_override

	dash = PlayerDash.new()
	dash.name = &"Dash"
	add_child(dash)

	hp = max_hp
	xp_to_next = xp_for_level(level)
	_update_pickup_radius()
	if starting_weapon:
		add_weapon(starting_weapon)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for t in _weapon_templates.values():
			if is_instance_valid(t):
				t.free()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if Game.autopilot:
		input = _autopilot_input()
	var dir := Vector3(input.x, 0.0, input.y)
	velocity = dash.process_dash(delta, dir, dir * move_speed) + _knock
	_knock = _knock.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))
	move_and_slide()
	position.y = 0.0
	_update_mercy_blink(delta)

	# Face the closest opponent (re-targeted ~10x/s); fall back to the movement direction.
	_retarget_t -= delta
	if _retarget_t <= 0.0:
		_retarget_t = RETARGET_INTERVAL
		_face_target = Targeting.nearest_enemy(get_tree(), global_position, FACE_RANGE)
	if is_instance_valid(_face_target) and not _face_target.is_dying:
		facing = Targeting.flat_dir(global_position, _face_target.global_position)
	elif dir.length_squared() > 0.01:
		facing = dir.normalized()
	body.rotation.y = lerp_angle(body.rotation.y, atan2(-facing.x, -facing.z), 1.0 - exp(-15.0 * delta))

	model.ground_speed = velocity.length()
	model.animate(delta, velocity.length() / maxf(move_speed, 0.1))
	# Show the attack/cast animation now and then when an enemy is close and we're nearly still
	# (weapons fire on their own; this is presentation only).
	_attack_anim_t -= delta
	if _attack_anim_t <= 0.0 and is_instance_valid(_face_target) and not _face_target.is_dying \
			and velocity.length() < move_speed * 0.35 \
			and global_position.distance_to(_face_target.global_position) < ATTACK_ANIM_RANGE:
		_attack_anim_t = randf_range(1.5, 2.2)
		model.play_attack()
	_apply_contact_damage(delta)
	if regen > 0.0:
		heal(regen * delta)
	_hurt_cooldown -= delta


# ---------------------------------------------------------------- health

func _apply_contact_damage(delta: float) -> void:
	if dash.is_invulnerable():
		return
	var dps := 0.0
	for b in hurtbox.get_overlapping_bodies():
		var e := b as Enemy
		if e and not e.is_dying:
			dps += maxf(e.damage - armor, 1.0)
	if dps > 0.0:
		_receive_damage(dps * delta)


## A discrete hit (projectile, slam, beam, pillar...). Negated by dash i-frames (a "dodge"),
## otherwise grants `hit_mercy_time` of invulnerability and knocks the demon away from `source`
## (a world position; when omitted the nearest enemy within 3 units is used).
func take_damage(amount: float, source := Vector3.INF) -> void:
	if is_dead or Game.godmode or RunState.run_won():
		return
	if dash and dash.absorb_hit(amount):
		return
	if source == Vector3.INF:
		var e := Targeting.nearest_enemy(get_tree(), global_position, 3.0)
		if e:
			source = e.global_position
	if source != Vector3.INF:
		var away := global_position - source
		away.y = 0.0
		if away.length_squared() > 0.0001:
			_knock += away.normalized() * clampf(4.0 + amount * 0.25, 4.0, 11.0)
	if dash and hit_mercy_time > 0.0:
		dash.grant_iframes(hit_mercy_time)
	model.hit_source = source  # characters-polish: exact flinch direction (DemonModel.play_hurt)
	_receive_damage(amount)
	if not is_dead:
		DamageNumber.spawn(amount, global_position + Vector3(0.0, 1.9, 0.0), DamageNumber.PLAYER_HIT)


func _receive_damage(amount: float) -> void:
	if is_dead or Game.godmode or RunState.run_won():
		return
	hp -= amount
	damaged.emit(amount)
	Game.player_hit.emit(amount)
	if _hurt_cooldown <= 0.0:
		_hurt_cooldown = 0.25
		model.play_hurt()
		Sfx.play(&"hurt", 0.1)
	if hp <= 0.0 and last_stands > 0:
		last_stands -= 1
		hp = 1.0
		LastStand.trigger(self)
		return
	if hp <= 0.0:
		hp = 0.0
		is_dead = true
		body.visible = true
		model.play_faint()
		Sfx.play(&"faint", 0.0)
		died.emit()


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)


## Blinks the body while post-hit mercy frames run.
func _update_mercy_blink(delta: float) -> void:
	if dash.in_mercy():
		_blink_t += delta
		body.visible = fmod(_blink_t, 0.12) < 0.08
	elif not body.visible or _blink_t != 0.0:
		_blink_t = 0.0
		body.visible = true


# ---------------------------------------------------------------- xp / levels

func xp_for_level(lv: int) -> int:
	return int(5 + (lv - 1) * 7 + pow(lv - 1, 1.6))


func add_xp(amount: float) -> void:
	if is_dead:
		return
	xp += amount * xp_gain
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = xp_for_level(level)
		pending_level_ups += 1
	if pending_level_ups > 0 and not get_tree().paused:
		leveled_up.emit()


func _on_pickup_area_entered(area_node: Area3D) -> void:
	if area_node.has_method(&"attract"):
		area_node.attract(self)


func _update_pickup_radius() -> void:
	pickup_shape.radius = pickup_radius


# ---------------------------------------------------------------- weapons / passives

func has_weapon(scene: PackedScene) -> bool:
	return _owned_weapons.has(scene)


## A not-in-tree instance used to read a weapon's name/description before it's owned.
func get_weapon_template(scene: PackedScene) -> Weapon:
	if not _weapon_templates.has(scene):
		_weapon_templates[scene] = scene.instantiate()
	return _weapon_templates[scene]


func add_weapon(scene: PackedScene) -> void:
	if has_weapon(scene):
		return
	var w: Weapon = _weapon_templates.get(scene)
	if w:
		_weapon_templates.erase(scene)
	else:
		w = scene.instantiate()
	w.player = self
	weapon_root.add_child(w)
	weapons.append(w)
	_owned_weapons[scene] = w


func add_passive(p: PassiveData) -> void:
	passive_levels[p] = passive_levels.get(p, 0) + 1
	apply_stat(p.stat, p.amount_per_level)


## Adds `amount` to the numeric property `stat`, then handles side effects.
func apply_stat(stat: StringName, amount: float) -> void:
	if not stat in self:
		push_warning("Player has no stat '%s'" % stat)
		return
	set(stat, get(stat) + amount)
	match stat:
		&"max_hp":
			heal(amount)
		&"pickup_radius":
			_update_pickup_radius()
		&"cooldown":
			cooldown = maxf(cooldown, 0.3)


# ---------------------------------------------------------------- dev

## Dev bot steering (--autopilot); the brain lives in scripts/autopilot.gd.
func _autopilot_input() -> Vector2:
	return Autopilot.move_input(self)
