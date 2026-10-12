extends Objective
## "Altar of Temptation": a black altar offers one of `deals`. Its terms float above it. Kneel at
## it (stand inside `radius`) for `accept_time` s to accept: the curse binds at once (a permanent,
## for-this-run Player stat penalty) and the reward is paid on the spot. Walk away to refuse (it
## fades in its own time). A deal: {"name", "curse_text", "curse": {stat: amount}, "rewards": {..}}.
## params: radius, accept_time, deals.

var _deal: Dictionary = {}
var _accept := 0.0
var _zone: BossTelegraph
var _label: Label3D
var _flame_mat: StandardMaterial3D


func _build() -> void:
	var deals: Array = param("deals", [])
	_deal = deals.pick_random() if not deals.is_empty() else {}
	# The terms are the reward: the director pays this deal's rewards on completion. (Own copy:
	# `def` may be the director's shared definition.)
	def = def.duplicate(true)
	def["rewards"] = _deal.get("rewards", def.get("rewards", {}))
	var obsidian := Art.mat(Art.OBSIDIAN, 0.4, 0.2, 0.3, false, 0.0, &"stone")
	Art.part(self, Art.box(), obsidian, Vector3(0.0, 0.5, 0.0), Vector3(1.4, 1.0, 0.8))
	Art.part(self, Art.box(), Art.mat(Art.CRIMSON.darkened(0.4), 0.9, 0.0, 0.3, false, 0.0, &"cloth"),
			Vector3(0.0, 1.02, 0.0), Vector3(1.5, 0.04, 0.5))
	for sx: float in [-0.5, 0.5]:
		var f := HolyFX.glow_part(self, Art.cone(0.5), Color(0.6, 0.2, 1.0), 2.0, Vector3(sx, 1.3, 0.0), Vector3(0.18, 0.4, 0.18))
		_flame_mat = f.material_override as StandardMaterial3D
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font = UIPalette.serif()
	_label.font_size = 40
	_label.outline_size = 10
	_label.pixel_size = 0.012
	_label.modulate = Color("e8c8ff")
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_label.text = "%s\n%s\nfor %s" % [str(_deal.get("name", "A Bargain")), str(_deal.get("curse_text", "")),
			str(_deal.get("reward_text", "great power"))]
	_label.position = Vector3(0.0, 3.0, 0.0)
	add_child(_label)
	_zone = ObjectiveFX.zone(self)
	title = "Temptation: %s" % str(_deal.get("name", "A Bargain"))
	status_text = "Kneel to accept"


func _tick(delta: float) -> void:
	var r := float(param("radius", 2.0))
	var near := _player_distance() <= r
	_label.visible = _player_distance() < 14.0
	_accept = clampf(_accept + (delta if near else -delta * 2.0) / maxf(float(param("accept_time", 2.5)), 0.1), 0.0, 1.0)
	_zone.show_disc(global_position, r, Color(0.6, 0.2, 1.0), _accept, 0.5 + 0.4 * _accept, 1.2)
	_flame_mat.albedo_color = HolyFX.scaled(Color(0.6, 0.2, 1.0), 2.0 + _accept * 2.0)
	progress = _accept
	status_text = "Kneel to accept" if _accept <= 0.0 else "%d%%" % roundi(_accept * 100.0)
	if state == State.ACTIVE and _player_distance() > 18.0:
		# Walked away: the offer goes back to sleep (it still fades in its own time).
		state = State.DORMANT
	# Coming close wakes the altar (its terms are shown); kneeling seals the deal.
	if state == State.DORMANT and _player_distance() <= r + 4.0:
		activate()
	if _accept >= 1.0 and state == State.ACTIVE:
		_bind_curse()
		complete()


func _bind_curse() -> void:
	var p := Game.player
	if p == null:
		return
	var curse: Dictionary = _deal.get("curse", {})
	for k: String in curse:
		var stat := StringName(k)
		if stat in p:
			p.apply_stat(stat, float(curse[k]))
	p.hp = maxf(p.hp, 1.0)
	HolyFX.motes(p.global_position + Vector3(0.0, 0.8, 0.0), 24, Color(0.6, 0.2, 1.0), 0.8, 2.0, 1.4)
	Sfx.play(&"unmade", 0.0, -6.0)
	_toast("CURSED: %s" % str(_deal.get("curse_text", "")), Color("c46bff"))
	get_tree().call_group(&"objective_director", &"note_curse", str(_deal.get("name", "")))


func _on_finished(_completed: bool) -> void:
	_zone.hide_now()
	_label.hide()
