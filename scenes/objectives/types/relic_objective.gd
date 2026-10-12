extends Objective
## "Corrupt the Holy Relic": a gilded reliquary floating over a marble dais, bound by `seals`
## turning rings of light. Stand within `radius` to corrupt it: each seal takes `seal_time`
## seconds (progress drains at `decay` x speed outside). The relic defends itself: every
## `pulse_interval` s Judgement Pillars open under (and ahead of) the demon, and each broken seal
## calls a guardian. Done: the reliquary bleeds black, shatters and spills its blessing as sin.
## params: radius, seals, seal_time, decay, pulse_interval, pillar_damage, guardians (enemy ids).

var _radius := 4.6
var _seals := 3
var _seal_time := 4.5
var _broken := 0
var _seal_progress := 0.0
var _pulse_t := 0.0
var _zone: BossTelegraph
var _float_root: Node3D
var _box_mat: ShaderMaterial
var _rings: Array[Node3D] = []
var _core_mat: StandardMaterial3D
var _light: OmniLight3D
var _inside := false
var _end_t := 0.0


func _build() -> void:
	_radius = float(param("radius", 4.6))
	_seals = maxi(int(param("seals", 3)), 1)
	_seal_time = maxf(float(param("seal_time", 4.5)), 0.5)
	var marble := Art.mat(Art.IVORY, 0.55, 0.0, 0.35, false, 0.0, &"marble")
	Art.part(self, Art.cylinder(), marble, Vector3(0.0, 0.12, 0.0), Vector3(2.2, 0.24, 2.2))
	Art.part(self, Art.cylinder(0.45, 0.6), marble, Vector3(0.0, 0.55, 0.0), Vector3(1.0, 0.7, 1.0))
	Art.part(self, Art.torus(0.9, 1.0), Art.mat(Art.GOLD, 0.3, 1.0, 0.2, false), Vector3(0.0, 0.25, 0.0),
			Vector3.ONE * 1.12)
	_float_root = Art.pivot(self, Vector3(0.0, 1.9, 0.0))
	# The reliquary: a gold casket with a cross on its lid and a glowing heart.
	var gold := Art.mat(Art.GOLD, 0.28, 1.0, 0.15, true, 0.0, &"gold")
	_box_mat = gold
	Art.part(_float_root, Art.box(), gold, Vector3.ZERO, Vector3(0.8, 0.5, 0.5))
	Art.part(_float_root, Art.prism(), gold, Vector3(0.0, 0.38, 0.0), Vector3(0.84, 0.26, 0.54))
	Art.part(_float_root, Art.box(), gold, Vector3(0.0, 0.72, 0.0), Vector3(0.07, 0.42, 0.07))
	Art.part(_float_root, Art.box(), gold, Vector3(0.0, 0.8, 0.0), Vector3(0.26, 0.07, 0.07))
	var core := HolyFX.glow_part(_float_root, Art.sphere(), Art.HOLY_WHITE, 2.0, Vector3(0.0, 0.0, 0.26),
			Vector3(0.2, 0.2, 0.06))
	_core_mat = core.material_override as StandardMaterial3D
	_light = Art.light(_float_root, Art.HOLY, 2.0, 7.0, Vector3(0.0, 0.4, 0.0))
	# Seal rings, each on its own tilted axis.
	for i in _seals:
		var ring := Art.pivot(_float_root, Vector3.ZERO, Vector3(0.6 + 0.5 * i, TAU * float(i) / _seals, 0.0))
		HolyFX.glow_part(ring, Art.torus(0.94, 1.0), Art.HOLY, 1.8, Vector3.ZERO, Vector3.ONE * (0.9 + 0.18 * i))
		_rings.append(ring)
	_zone = ObjectiveFX.zone(self)
	status_text = "Seals %d" % _seals


func _tick(delta: float) -> void:
	_inside = _player_distance() <= _radius
	if state == State.DORMANT and _inside:
		activate()
	_animate(delta)
	var tint := Art.HOLY.lerp(Art.SOUL, progress)
	_zone.show_disc(global_position, _radius, tint, _seal_progress, 0.85 if _inside else 0.5, 1.2)
	if state != State.ACTIVE:
		return
	if _inside:
		_seal_progress += delta / _seal_time
		if randf() < delta * 10.0:
			HolyFX.motes(_float_root.global_position, 1, Art.SOUL, 0.5, -1.0, 0.7)
	else:
		_seal_progress = maxf(_seal_progress - delta * float(param("decay", 0.25)) / _seal_time, 0.0)
	if _seal_progress >= 1.0:
		_break_seal()
	progress = (float(_broken) + clampf(_seal_progress, 0.0, 1.0)) / float(_seals)
	status_text = "Seal %d / %d%s" % [mini(_broken + 1, _seals), _seals, "" if _inside else "  return!"]
	_pulse_t -= delta
	if _pulse_t <= 0.0 and _player_distance() < _radius + 6.0:
		_pulse_t = float(param("pulse_interval", 3.4)) * (1.0 - 0.15 * _broken)
		_purifying_pulse()
	if _broken >= _seals:
		complete()


func _animate(delta: float) -> void:
	_float_root.position.y = 1.9 + sin(age * 1.6) * 0.12
	_float_root.rotate_y(delta * (0.4 + 1.2 * progress))
	for i in _rings.size():
		var r := _rings[i]
		if r.visible:
			r.rotate_object_local(Vector3.UP, delta * (1.2 + 0.5 * i) * (1.0 + 2.0 * progress))
	var throb := 0.8 + 0.2 * sin(age * (3.0 + 8.0 * progress))
	_core_mat.albedo_color = HolyFX.scaled(Art.HOLY_WHITE.lerp(Art.SOUL, progress), 2.2 * throb)
	_light.light_color = Art.HOLY.lerp(Art.SOUL, progress)


## Pillars of light open under the demon and where it is heading.
func _purifying_pulse() -> void:
	var p := Game.player
	if p == null:
		return
	var dmg := float(param("pillar_damage", 18.0))
	var at := p.global_position
	JudgementPillar.cast(at, 1.5, 1.15, dmg)
	var lead := p.velocity
	lead.y = 0.0
	if lead.length() > 0.5:
		JudgementPillar.cast(at + lead.normalized() * 3.0, 1.5, 1.3, dmg)
	if _broken >= 1:
		JudgementPillar.cast(ObjectiveFX.ring_point(at, 3.2), 1.5, 1.4, dmg)
	Sfx.play(&"choir", 0.1, -6.0)


func _break_seal() -> void:
	_seal_progress = 0.0
	if _broken < _rings.size():
		var ring := _rings[_broken]
		HolyFX.flash(ring.global_position, 1.8, 0.4, Art.HOLY_WHITE, 2.5)
		HolyFX.feathers(ring.global_position, 6, 0.8, 1.4)
		ring.hide()
	_broken += 1
	Sfx.play(&"smite", 0.05, -6.0)
	Sfx.play(&"seal_break", 0.04, 0.0)
	get_tree().call_group(&"camera_rig", &"shake", 0.2)
	var ids: Array = param("guardians", [])
	if not ids.is_empty() and _broken < _seals:
		_spawn_enemy(str(ids[mini(_broken - 1, ids.size() - 1)]), ObjectiveFX.ring_point(global_position, _radius + 3.0))


func _on_activated() -> void:
	_pulse_t = 1.5
	_toast("The relic burns with sanctity")


func _on_finished(completed: bool) -> void:
	if not completed:
		_zone.hide_now()
		return
	_end_t = 0.0
	ObjectiveFX.corruption_burst(_float_root.global_position, 1.0)
	HolyFX.feathers(_float_root.global_position, 14, 1.6, 2.4)
	_box_mat = Art.mat(Art.OBSIDIAN, 0.5, 0.7, 0.4, true)
	for c in _float_root.get_children():
		var mi := c as MeshInstance3D
		if mi and mi.material_override is ShaderMaterial:
			mi.material_override = _box_mat
	Sfx.play(&"brimstone", 0.0, -1.0)
	Sfx.play(&"relic_corrupt", 0.0, 0.0)


func _tick_finished(delta: float) -> void:
	if state != State.COMPLETED:
		_zone.hide_now()
		return
	_end_t += delta
	_float_root.position.y = maxf(1.9 - _end_t * 1.6, 0.4)
	_float_root.rotate_y(delta * 6.0 * maxf(1.0 - _end_t, 0.0))
	_core_mat.albedo_color = HolyFX.scaled(Art.SOUL, 2.5 * maxf(1.0 - _end_t / LINGER, 0.0))
	_zone.show_disc(global_position, _radius, Art.SOUL, 1.0, clampf(1.0 - _end_t / LINGER, 0.0, 1.0), 1.2)
