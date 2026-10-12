extends Objective
## "Slay the Champion": a holy standard marks where a champion of Heaven keeps vigil. When the
## demon comes within `wake_radius` it descends in a column of light: one of the `bases` angels,
## grown (`size_mult`), hardened (`hp_mult`) and crowned, with one random affix:
##   radiant   Judgement Pillars open around the demon every few seconds
##   zealous   much faster, attacks far more often
##   bulwark   huge HP, immovable, slower
##   choir_led keeps calling Choir Wisps to its side
##   martyr    on death, bursts into a ring of holy orbs (dodge them)
## params: wake_radius, bases (enemy ids), hp_mult, size_mult, damage_mult, affixes.

const AFFIX_NAMES := {
	"radiant": ["Radiant", "the Dawnbringer"],
	"zealous": ["Zealous", "the Swift Verdict"],
	"bulwark": ["Unbroken", "the Wall of Heaven"],
	"choir_led": ["Choir-led", "Voice of the Host"],
	"martyr": ["Martyred", "Who Dies Gladly"],
}

var _champion: Enemy
var _affix := "radiant"
var _ability_t := 0.0
var _crown: Node3D
var _zone: BossTelegraph
var _standard: Node3D
var _champion_name := "Champion"
var _last_pos := Vector3.ZERO


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_standard = Props.banner(rng)
	_standard.rotation.y = rng.randf() * TAU
	add_child(_standard)
	Art.part(self, Art.cylinder(), Art.mat(Art.GOLD, 0.3, 1.0, 0.2, false), Vector3(0.0, 0.03, 0.0),
			Vector3(1.6, 0.06, 1.6))
	_zone = ObjectiveFX.zone(self)
	var affixes: Array = param("affixes", ["radiant"])
	_affix = str(affixes.pick_random()) if not affixes.is_empty() else "radiant"
	status_text = "Approach"


func marker_position() -> Vector3:
	if _champion and is_instance_valid(_champion):
		return _champion.global_position
	return global_position


func _tick(delta: float) -> void:
	if state == State.DORMANT:
		_zone.show_disc(global_position, 2.2, Art.HOLY, 0.0, 0.5 + 0.2 * sin(age * 3.0), 1.0)
		if _player_distance() <= float(param("wake_radius", 15.0)):
			activate()
		return
	if _champion == null or not is_instance_valid(_champion) or _champion.is_dying:
		complete()
		return
	_last_pos = _champion.global_position
	progress = 1.0 - clampf(_champion.hp / maxf(_champion.max_hp, 1.0), 0.0, 1.0)
	status_text = "%d%%" % roundi((1.0 - progress) * 100.0)
	if _crown:
		_crown.rotate_y(delta * 1.5)
	_ability_t -= delta
	if _ability_t <= 0.0:
		_use_ability()


func _on_activated() -> void:
	_zone.hide_now()
	var bases: Array = param("bases", ["archon"])
	var base := ObjectiveFX.enemy_data(str(bases.pick_random())) if not bases.is_empty() else null
	if base == null:
		fail()
		return
	var d := base.duplicate() as EnemyData
	var names: Array = AFFIX_NAMES.get(_affix, ["Holy", "the Faithful"])
	_champion_name = "%s %s, %s" % [names[0], base.display_name, names[1]]
	d.display_name = _champion_name
	d.size = base.size * float(param("size_mult", 1.5))
	d.damage = base.damage * float(param("damage_mult", 1.4))
	d.xp_value = maxi(base.xp_value * 5, 40)
	d.knockback_scale = base.knockback_scale * 0.3
	var hp_mult := float(param("hp_mult", 14.0))
	match _affix:
		"zealous":
			d.speed = base.speed * 1.5
			d.attack_cooldown = base.attack_cooldown * 0.55
			d.windup_time = base.windup_time * 0.8
		"bulwark":
			hp_mult *= 1.6
			d.size *= 1.15
			d.speed = base.speed * 0.8
			d.knockback_scale = 0.0
	_champion = ObjectiveFX.spawn_enemy_data(d, global_position, hp_mult)
	_minimap_follow(_champion)
	_champion.add_to_group(&"champions")
	# A crown of light over its head (on the body, not the scaled model, so it stays round).
	_crown = Art.pivot(_champion, Vector3(0.0, d.size * 1.55 + d.hover, 0.0))
	HolyFX.glow_part(_crown, Art.torus(0.82, 1.0), Art.GOLD, 2.4, Vector3.ZERO, Vector3.ONE * 0.45 * d.size)
	for i in 5:
		var a := TAU * float(i) / 5.0
		HolyFX.glow_part(_crown, Art.cone(0.5), Art.HOLY, 2.6,
				Vector3(cos(a), 0.12, sin(a)) * 0.45 * d.size, Vector3(0.06, 0.22, 0.06) * d.size)
	HolyFX.column(global_position, 1.2, 26.0, 1.0, Art.HOLY, 2.0)
	HolyFX.flash(global_position + Vector3(0.0, 1.0, 0.0), 3.0, 0.5, Art.HOLY_WHITE, 2.5)
	Sfx.play(&"boss_intro", 0.0, -6.0)
	Sfx.play(&"stinger_boss", 0.0, -5.0)
	_toast(_champion_name.to_upper(), Color("f2c66b"))
	_ability_t = 3.0
	_standard.hide()


func _use_ability() -> void:
	var p := Game.player
	if p == null or p.is_dead:
		_ability_t = 1.0
		return
	match _affix:
		"radiant":
			_ability_t = 4.2
			JudgementPillar.cast(p.global_position, 1.5, 1.2, 16.0)
			for i in 2:
				JudgementPillar.cast(ObjectiveFX.ring_point(p.global_position, 2.8), 1.5, 1.35, 16.0)
		"choir_led":
			_ability_t = 6.0
			for i in 3:
				_spawn_enemy("choir_wisp", ObjectiveFX.ring_point(_champion.global_position, 2.5), 0.8)
			Sfx.play(&"choir", 0.1, -4.0)
		_:
			_ability_t = 999.0


func _on_finished(completed: bool) -> void:
	_zone.hide_now()
	if not completed:
		return
	var at := _last_pos
	global_position = Vector3(at.x, 0.0, at.z)  # rewards and the fading beacon at the corpse
	reset_physics_interpolation()
	if _affix == "martyr":
		for i in 14:
			var a := TAU * float(i) / 14.0
			var dir := Vector3(cos(a), 0.0, sin(a))
			SarielOrb.fire(at + dir * 1.2 + Vector3(0.0, 0.6, 0.0), dir * 3.2, 14.0, 6.0)
		_toast("Its martyrdom lashes out", Color("fff4cf"))
	ObjectiveFX.corruption_burst(at, 0.8)
