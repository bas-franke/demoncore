extends AbilityKind
## "pride": gathers Hubris over time (faster while unhurt; a hit costs params.hurt_loss of it),
## then brings down one colossal blade on the healthiest angel in range. Damage scales up to
## params.max_charge x. Params: range, radius, charge_rate (per second), max_charge, hurt_loss.

var _charge := 0.0


func rebuild() -> void:
	if not Game.player_hit.is_connected(_on_player_hit):
		Game.player_hit.connect(_on_player_hit)


func cleanup() -> void:
	if Game.player_hit.is_connected(_on_player_hit):
		Game.player_hit.disconnect(_on_player_hit)


func tick(delta: float) -> void:
	_charge = minf(_charge + delta * p("charge_rate", 0.25), p("max_charge", 3.0))


## 0..1 of the way to full Hubris (for HUD charge display).
func charge_ratio() -> float:
	return _charge / maxf(p("max_charge", 3.0), 0.01)


func _on_player_hit(amount: float) -> void:
	if amount > 0.5:
		_charge *= 1.0 - p("hurt_loss", 0.15)


func cast() -> bool:
	var foes := AbilityCombat.enemies_in_radius(player.global_position, p("range", 12.0))
	if foes.is_empty():
		return false
	foes.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.hp > b.hp)
	var target := foes[0]
	var at := target.global_position
	var r := p("radius", 1.6) * area()
	var dmg := damage() * (1.0 + _charge)
	_charge = 0.0
	_blade(at)
	tree().create_timer(0.35, false).timeout.connect(_land.bind(at, r, dmg))
	return true


func _blade(at: Vector3) -> void:
	if Game.world == null:
		return
	var blade := Node3D.new()
	blade.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(blade, at + Vector3(0.0, 14.0, 0.0))
	Art.part(blade, Art.box(), Art.mat(Art.OBSIDIAN, 0.2, 0.9), Vector3(0.0, 2.0, 0.0), Vector3(0.5, 5.0, 0.12))
	Art.part(blade, Art.box(), Art.glow(def.color, 2.4, true, 0.8), Vector3(0.0, 2.0, 0.0), Vector3(0.62, 5.1, 0.06))
	Art.part(blade, Art.box(), Art.mat(Art.GOLD, 0.3, 1.0), Vector3(0.0, 4.6, 0.0), Vector3(1.6, 0.2, 0.25))
	var tw := blade.create_tween()
	tw.tween_property(blade, ^"position", at + Vector3(0.0, -1.2, 0.0), 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	tw.tween_interval(0.5)
	tw.tween_property(blade, ^"scale", Vector3(0.01, 1.0, 0.01), 0.25)
	tw.tween_callback(blade.queue_free)


func _land(at: Vector3, r: float, dmg: float) -> void:
	if not is_instance_valid(caster) or not is_instance_valid(player):
		return
	AbilityFx.ring(at, r * 2.0, def.color, 0.5)
	AbilityFx.pillar(at, r, def.color.lerp(Color.WHITE, 0.45), 0.25, 4.0)  # no pure-white pillar: reads holy (art-style)
	InfernalFx.burst(at + Vector3(0.0, 0.4, 0.0), def.color, 26, 6.0, 1.6)
	var src := source()
	src["origin"] = at
	src["knockback"] = 8.0
	for e in AbilityCombat.enemies_in_radius(at, r):
		AbilityCombat.hit(e, dmg, src)
	after(at)
	sfx(&"smite", 0.0)
	Game.hitstop(0.06, 0.1)
	tree().call_group(&"camera_rig", &"shake", 0.3)
