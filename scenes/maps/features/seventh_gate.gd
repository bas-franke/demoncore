class_name SeventhGate
extends MapInteractable
## The Seventh Gate (map heavens_gate): the finale of the story (docs/team/story.md "ending",
## docs/team/maps.md). Sealed by its Gate Wards (MapStatue variant "ward") and by a guardian:
## once every ward is broken AND `bosses_required` bosses fell this run, the doors grind open and a
## circle of light appears on the threshold. Stand in it for `channel_time` s and the run ends in
## victory with cause &"seventh_gate" (RunState.end_run), which the story role turns into the ending.
##
## Story gate: only a demon who has learned of the March (Dialogue flag "known.march") may pass.
## Before that, breaking the seals pays out but the doors stay shut (a hint toast). Dev:
## `--gate-open` skips the story requirement.

signal seals_changed(remaining: int)
signal opened

@export var bosses_required := 1

var wards: Array[MapStatue] = []

var _left: Node3D
var _right: Node3D
var _open := 0.0  # 0 shut .. 1 open
var _opening := false
var _hinted := false
var _light: OmniLight3D
var _veil_mat: StandardMaterial3D


func _build() -> void:
	display_name = "The Seventh Gate"
	channel_time = 4.0
	radius = 3.4
	tint = Color(1.0, 0.95, 0.75)
	var gold := Art.mat(Art.GOLD, 0.25, 1.0, 0.15, false, 0.0, &"metal")
	var pearl := Art.mat(Color(0.93, 0.92, 0.88), 0.3, 0.1, 0.1, false, 0.0, &"marble")
	_left = Art.pivot(self, Vector3(-4.5, 0, 0))
	_right = Art.pivot(self, Vector3(4.5, 0, 0))
	for door: Node3D in [_left, _right]:
		var s := -1.0 if door == _left else 1.0
		Art.part(door, Art.box(), pearl, Vector3(-s * 2.25, 4.0, 0), Vector3(4.4, 8.0, 0.6))
		for y: float in [1.5, 4.0, 6.5]:
			Art.part(door, Art.box(), gold, Vector3(-s * 2.25, y, 0.32), Vector3(4.2, 0.25, 0.1))
		Art.part(door, Art.sphere(), gold, Vector3(-s * 0.6, 4.0, 0.4), Vector3(0.5, 0.5, 0.2))
	_veil_mat = StandardMaterial3D.new()
	_veil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_veil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_veil_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_veil_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_veil_mat.albedo_color = Color(0, 0, 0, 0)
	Art.part(self, Art.box(), _veil_mat, Vector3(0, 4.0, -0.4), Vector3(8.6, 8.0, 0.05))
	_light = Art.light(self, Art.HOLY_WHITE, 0.0, 16.0, Vector3(0, 3.0, 3.0))


func _ready() -> void:
	super()
	if "--gate-selftest" in OS.get_cmdline_user_args():
		_selftest.call_deferred()


## Dev: `-- --map=heavens_gate --godmode --gate-open --gate-selftest` breaks the wards, counts a boss,
## walks the demon into the Gate and prints GATETEST lines (the run should end as seventh_gate).
func _selftest() -> void:
	await get_tree().create_timer(4.0, false).timeout
	print("GATETEST wards=%d" % remaining_wards())
	for w in wards.duplicate():
		if is_instance_valid(w):
			w.die()
	RunState.bosses_killed = maxi(RunState.bosses_killed, bosses_required)
	await get_tree().create_timer(5.0, false).timeout
	print("GATETEST open=%.2f" % _open)
	RunState.run_ended.connect(func(r: Dictionary) -> void:
		print("GATETEST ended victory=%s cause=%s" % [r.get("victory"), r.get("cause")]))
	for i in 300:
		if Game.player and not RunState.run_won():
			Game.player.global_position = global_position + Vector3(0, 0, 1.0)
		await get_tree().physics_frame
	print("GATETEST done won=%s" % RunState.run_won())


func remaining_wards() -> int:
	var n := 0
	for w in wards:
		if is_instance_valid(w) and not w.is_dying:
			n += 1
	return n


func add_ward(w: MapStatue) -> void:
	wards.append(w)
	w.destroyed.connect(_on_ward_destroyed)


func story_allows() -> bool:
	if "--gate-open" in OS.get_cmdline_user_args():
		return true
	var d := get_node_or_null(^"/root/Dialogue")
	if d and d.has_method(&"has_flag"):
		return bool(d.call(&"has_flag", "known.march"))
	return true


func can_activate() -> bool:
	return _open >= 0.95


func _on_ward_destroyed(_w: MapStatue) -> void:
	# the statue's die() runs before it leaves the group: count the others
	var left := 0
	for w in wards:
		if is_instance_valid(w) and not w.is_dying and w != _w:
			left += 1
	seals_changed.emit(left)
	if left > 0:
		toast("A seal of the Seventh Gate breaks. %d remain." % left, Color(1.0, 0.85, 0.55))
	else:
		toast("The last seal breaks.", Color(1.0, 0.85, 0.55))


func _tick(delta: float) -> void:
	if not _opening and remaining_wards() == 0 and not wards.is_empty() \
			and RunState.bosses_killed >= bosses_required:
		if story_allows():
			_opening = true
			opened.emit()
			refresh_marker()
			toast("THE SEVENTH GATE OPENS", Color(1.0, 0.95, 0.75))
			Sfx.play(&"triumph", 0.0, 0.0)
			get_tree().call_group(&"camera_rig", &"shake", 0.5)
		elif not _hinted:
			_hinted = true
			toast("The Gate does not know your name. Not yet.", Color(0.85, 0.8, 0.95))
			RunState.drop_currency(global_position + Vector3(0, 0.5, 4.0), 30, 6)
	if _opening and _open < 1.0:
		_open = minf(_open + delta / 4.0, 1.0)
		var e := ease(_open, -2.0)
		_left.rotation.y = -e * 1.4
		_right.rotation.y = e * 1.4
		_veil_mat.albedo_color = Color(1.0, 0.95, 0.8, 0.6 * e) * 2.0
		_light.light_energy = 4.0 * e


func _activate() -> void:
	HolyFX.flash(global_position + Vector3(0, 2.0, 2.0), 8.0, 1.2, Art.HOLY_WHITE, 4.0)
	ObjectiveFX.corruption_burst(global_position + Vector3(0, 0, 3.0), 2.0)
	toast("You pass the Seventh Gate.", Color(1.0, 0.95, 0.8))
	RunState.end_run(true, &"seventh_gate")
