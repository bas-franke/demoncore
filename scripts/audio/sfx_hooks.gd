extends Node
## Gameplay -> sound hooks (child "SfxHooks" of the Sfx autoload; owner: sfx role).
## Listens to the Game event bus and to other systems' signals so sounds follow gameplay without
## those systems calling Sfx themselves. Every optional connection is made only if the signal
## exists, so systems that are not built yet are simply skipped.
##
## Hooks:
##   Game.enemy_struck         -> positional material hit (hit_flesh / _stone / _glass / _metal /
##                                _holy, from Sfx.registry), louder for bigger hits
##                                (falls back to Game.enemy_hit -> hit_flesh if the signal is absent)
##   Game.enemy_died           -> positional material death (death_flesh, crumble, angel_shatter,
##                                armor_clatter, light_burst); now and then a &"holy_chime"
##   Game.boss_spawned         -> &"stinger_boss"
##   Enemy wind-ups            -> Sfx.play_enemy_voice (called from Enemy._set_state)
##   Weather                   -> WeatherAudio child: rain / wide gust beds from Atmosphere state
##   Abilities.synergy_activated -> &"synergy"; Abilities.ability_evolved(from, to) -> &"evolve"
##   Ability tags also cover the Sin schools and gadgets (wrath, greed, envy, pride, gluttony,
##   decoy, turret, mine, whip): <school>_cast / <school>_hit via Sfx.play_element
##   Game.boss_died            -> &"holy_chime" (MusicManager adds the victory stinger)
##   Game.boss_phase_changed   -> &"boss_roar" (phase > 0)
##   RunState.player_dashed    -> &"dash" (also Player.dashed, if a player script declares one)
##   RunState.player_dodged    -> &"holy_hit" ting (a blow slipping off the i-frames)
##   RunState.enemy_killed     -> elites get a full &"holy_chime"
##   RunState.wave_started     -> distant &"toll" when a &"surge" begins
##   (Shop purchases are voiced by ui/components/shop_panel.gd: shop_buy / shop_deny; Ichor
##   pickups by scenes/pickups/ichor_drop.gd: coin.)
##   Abilities.ability_cast(id, element, position) / element_hit(element, position) (if they exist)
##   Portal nodes (group &"portal", or a Node3D named "*Portal*") -> looping &"amb_portal" hum
##   Basecamp scenes (res://scenes/basecamp/*, or a root named "*Basecamp*") -> hub beds
##     (&"amb_hellfire", &"amb_hell_choir" on the Ambience bus), unless the scene has an
##     &"ambience" group node of its own.

const HIT_BASE_DB := -13.0
## Damage at which a hit reaches full loudness (HIT_BASE_DB + HIT_RANGE_DB).
const HIT_FULL_DAMAGE := 40.0
const HIT_RANGE_DB := 7.0
const SHATTER_DB := -10.0
const CHIME_CHANCE := 0.12
const CHIME_DB := -15.0
const PORTAL_DB := -4.0
const PORTAL_UNIT := 5.0
const HUB_FIRE_DB := -12.0
const HUB_CHOIR_DB := -20.0
const BASECAMP_DIR := "res://scenes/basecamp/"
## Autoloads whose signals we listen to when they exist: [node path, signal, handler name].
const OPTIONAL_LINKS := [
	[^"/root/RunState", &"player_dashed", &"_on_player_dashed"],
	[^"/root/RunState", &"player_dodged", &"_on_player_dodged"],
	[^"/root/RunState", &"enemy_killed", &"_on_enemy_killed"],
	[^"/root/RunState", &"wave_started", &"_on_wave_started"],
	[^"/root/Game", &"boss_phase_changed", &"_on_boss_phase_changed"],
	[^"/root/Abilities", &"ability_cast", &"_on_ability_cast"],
	[^"/root/Abilities", &"damage_dealt", &"_on_damage_dealt"],
	[^"/root/Abilities", &"element_hit", &"_on_element_hit"],
	[^"/root/Abilities", &"synergy_activated", &"_on_synergy_activated"],
	# Evolutions: Abilities.ability_evolved(from_id, to_id).
	[^"/root/Abilities", &"ability_evolved", &"_on_ability_evolved"],
]
## Element layer under an ability's own cast sound, and its (2D, quiet) hit sizzle.
const ABILITY_CAST_DB := -9.0
const ABILITY_HIT_DB := -14.0
const SURGE_TOLL_DB := -10.0
const READY_DB := -12.0

const STINGER_DB := -3.0
const WEATHER_SCRIPT := preload("res://scripts/audio/weather_audio.gd")
const MOVE_LOOP_SCRIPT := preload("res://scripts/audio/move_loop.gd")

var _last_dash := -10.0
var _dash_charges := 0
# Position of the last enemy struck and the frame it happened in: ability hits (damage_dealt)
# arrive right after the take_damage() that emitted enemy_struck, so this makes them positional.
var _struck_pos := Vector3.ZERO
var _struck_frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Game.has_signal(&"enemy_struck"):
		Game.connect(&"enemy_struck", _on_enemy_struck)
	else:
		Game.enemy_hit.connect(_on_enemy_hit)
	Game.enemy_died.connect(_on_enemy_died)
	Game.boss_died.connect(_on_boss_died)
	Game.boss_spawned.connect(_on_boss_spawned)
	var weather: Node = WEATHER_SCRIPT.new()
	weather.name = &"WeatherAudio"
	add_child(weather)
	get_tree().node_added.connect(_on_node_added)
	# Other autoloads may be registered after Sfx: link them once the tree is up.
	_link_optional.call_deferred()


func _link_optional() -> void:
	for link: Array in OPTIONAL_LINKS:
		var src := get_node_or_null(link[0] as NodePath)
		if src == null or not src.has_signal(link[1]):
			continue
		var cb := Callable(self, link[2])
		if not src.is_connected(link[1], cb):
			src.connect(link[1], cb)


# ---------------------------------------------------------------- combat

func _on_enemy_hit(pos: Vector3, amount: float) -> void:
	var k := clampf(amount / HIT_FULL_DAMAGE, 0.0, 1.0)
	Sfx.play_at(&"hit_flesh", pos + Vector3(0.0, 0.6, 0.0), 0.1, HIT_BASE_DB + HIT_RANGE_DB * k)


func _on_enemy_struck(enemy: Node3D, amount: float) -> void:
	if not is_instance_valid(enemy):
		return
	var pos := enemy.global_position + Vector3(0.0, 0.6, 0.0)
	_struck_pos = pos
	_struck_frame = Engine.get_process_frames()
	var k := clampf(amount / HIT_FULL_DAMAGE, 0.0, 1.0)
	var data: Variant = enemy.get(&"data")
	Sfx.play_material_hit(Sfx.registry.material_of(data as Object), pos, HIT_BASE_DB + HIT_RANGE_DB * k)


func _on_enemy_died(pos: Vector3, data: Resource) -> void:
	var at := pos + Vector3(0.0, 0.8, 0.0)
	Sfx.play_material_death(Sfx.registry.material_of(data), at, SHATTER_DB)
	if randf() < CHIME_CHANCE:
		Sfx.play_at(&"holy_chime", at, 0.06, CHIME_DB)


func _on_boss_spawned(_boss: Node3D) -> void:
	Sfx.play(&"stinger_boss", 0.0, STINGER_DB)


func _on_boss_died(_pos: Vector3) -> void:
	Sfx.play(&"holy_chime", 0.0, -4.0)


func _on_boss_phase_changed(_boss: Node3D, phase: int) -> void:
	if phase > 0:
		Sfx.play(&"boss_roar", 0.03, -2.0)


## Default args: tolerates both RunState.player_dashed(direction) and a bare Player.dashed().
func _on_player_dashed(_a: Variant = null, _b: Variant = null) -> void:
	# Both sources may fire for the same dash: voice it once.
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_dash < 0.08:
		return
	_last_dash = now
	Sfx.play(&"dash", 0.08)


func _on_player_dodged(_amount: float) -> void:
	Sfx.play(&"holy_hit", 0.15, -10.0)


func _on_enemy_killed(pos: Vector3, _data: Resource, elite: bool) -> void:
	# Elites already get game_feel's "SLAIN" bell and Enemy's choir; keep the chime underneath.
	if elite:
		Sfx.play_at(&"holy_chime", pos + Vector3(0.0, 0.8, 0.0), 0.04, -12.0)


func _on_wave_started(_index: int, kind: StringName) -> void:
	if kind == &"surge":
		Sfx.play(&"toll", 0.05, SURGE_TOLL_DB)


## Abilities.ability_cast(id) [+ optional element, position]: the element comes from the
## ability's tags (data/abilities/abilities.json) unless the emitter passes one.
func _on_ability_cast(id: Variant = null, element: Variant = null, position: Variant = null) -> void:
	var e := &""
	if element is StringName or element is String:
		e = StringName(element)
	elif id != null:
		var abilities := get_node_or_null(^"/root/Abilities")
		var defs: Variant = abilities.get(&"defs") if abilities else null
		if defs is Dictionary and (defs as Dictionary).has(id):
			var tags: Variant = (defs[id] as Object).get(&"tags")
			if tags is PackedStringArray:
				e = _element_from_tags(tags)
	if e != &"":
		Sfx.play_element(e, &"cast", position, ABILITY_CAST_DB)


## Abilities.damage_dealt(amount, tags): every ability hit carries element tags.
func _on_damage_dealt(_amount: float, tags: PackedStringArray) -> void:
	if tags.has("dot"):
		return  # damage-over-time ticks would drone
	var e := _element_from_tags(tags)
	if e == &"":
		return
	# Position only when the hit landed this frame (null = non-positional).
	var at: Variant = null
	if _struck_frame == Engine.get_process_frames():
		at = _struck_pos
	Sfx.play_element(e, &"hit", at, ABILITY_HIT_DB + (4.0 if at != null else 0.0), 0.12)


## First tag that names an element or a sin / gadget school (directly or through the alias
## tables of RECIPES / SINS), else &"".
## Specific tags beat generic ones (SINS.TAG_PRIORITY: "trap" over "machine"), else tag order.
func _element_from_tags(tags: PackedStringArray) -> StringName:
	var best := &""
	var best_rank := 99
	for t in tags:
		var tag := StringName(t)
		var e: StringName = Sfx.RECIPES.ELEMENT_ALIASES.get(tag, Sfx.SINS.SCHOOL_ALIASES.get(tag, tag))
		if not (Sfx.RECIPES.ELEMENTS.has(e) or Sfx.SINS.SCHOOLS.has(e)):
			continue
		var rank: int = Sfx.SINS.TAG_PRIORITY.get(tag, 5)
		if rank < best_rank:
			best = e
			best_rank = rank
	return best


func _on_synergy_activated(_id: Variant = null) -> void:
	Sfx.play(&"synergy", 0.0, -2.0)


func _on_ability_evolved(_from_id: StringName, _to_id: StringName) -> void:
	Sfx.play(&"evolve", 0.0, -1.0)


func _on_element_hit(element: Variant = null, position: Variant = null) -> void:
	if element is StringName or element is String:
		Sfx.play_element(StringName(element), &"hit", position, -6.0)


# ---------------------------------------------------------------- scene watchers

func _on_node_added(node: Node) -> void:
	if node.get_parent() == get_tree().root:
		if node.scene_file_path.begins_with(BASECAMP_DIR) or String(node.name).containsn("basecamp"):
			_add_hub_beds.call_deferred(node)
		return
	if node is Player:
		# Player dash: deferred, so a `dashed` signal added by a script set up in _ready counts.
		_link_dash.call_deferred(node)
	elif node is Node3D and (String(node.name).containsn("portal") or node.is_in_group(&"portal")) \
			and not (node is Light3D or node is AudioStreamPlayer3D or node is GPUParticles3D
				or node is CPUParticles3D):
		_add_portal_hum.call_deferred(node)


func _add_portal_hum(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or node.has_meta(&"sfx_hum"):
		return
	# Name match alone is not enough for children like "PortalRing": only hum on the outermost.
	var p := node.get_parent()
	while p:
		if p.has_meta(&"sfx_hum"):
			return
		p = p.get_parent()
	node.set_meta(&"sfx_hum", true)
	Sfx.play_loop(&"amb_portal", node, PORTAL_DB, Sfx.SFX_BUS, PORTAL_UNIT)


func _add_hub_beds(scene: Node) -> void:
	if not is_instance_valid(scene) or scene.has_meta(&"sfx_beds"):
		return
	for n in get_tree().get_nodes_in_group(&"ambience"):
		if scene.is_ancestor_of(n):
			return
	scene.set_meta(&"sfx_beds", true)
	# 2D beds: the hub is a single space, so they sit everywhere at a constant level.
	var holder := Node.new()
	holder.name = &"SfxHubBeds"
	scene.add_child(holder)
	Sfx.play_loop(&"amb_hellfire_wide", holder, HUB_FIRE_DB, Sfx.AMB_BUS)  # stereo
	Sfx.play_loop(&"amb_hell_choir", holder, HUB_CHOIR_DB, Sfx.AMB_BUS)


func _link_dash(node: Node) -> void:
	if not is_instance_valid(node):
		return
	# Demon sound identity (Sfx.DEMON_SOUNDS, e.g. Nhazgul's swarm): keyed by DemonData.model_id.
	var ch: Variant = node.get(&"character")
	var demon := str((ch as Object).get(&"model_id")) if ch is Object else ""
	Sfx.set_demon(demon)
	# Demons that carry a sound while moving (Nhazgul's flies): a MoveLoop under the player.
	if Sfx.DEMON_LOOPS.has(demon) and node.get_node_or_null(^"SfxMoveLoop") == null:
		var ml: Node = MOVE_LOOP_SCRIPT.new()
		ml.name = &"SfxMoveLoop"
		ml.set(&"sound", Sfx.DEMON_LOOPS[demon])
		node.add_child(ml)
	if node.has_signal(&"dashed") and not node.is_connected(&"dashed", _on_player_dashed):
		node.connect(&"dashed", _on_player_dashed)
	# PlayerDash component (player.dash): a soft ping whenever a dash charge comes back.
	var dash := node.get(&"dash") as Object
	if dash and dash.has_signal(&"charges_changed"):
		var c: Variant = dash.get(&"charges")
		_dash_charges = int(c) if c != null else 0
		if not dash.is_connected(&"charges_changed", _on_dash_charges_changed):
			dash.connect(&"charges_changed", _on_dash_charges_changed)


func _on_dash_charges_changed(charges: int, _max_charges: int) -> void:
	if charges > _dash_charges:
		Sfx.play(&"ability_ready", 0.03, READY_DB)
	_dash_charges = charges
