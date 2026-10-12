extends Node3D
## Run root: wires the player to the UI and advances the run timer.
##
## Dev command-line args (after "--"): --autopilot  --godmode  --boss  --demon=<id>  --shot=path.png
##   --shot-time=seconds  (parsed in Game._ready(), except --boss which is handled here).
## Debug builds: F1 = instant level-up, F2 = toggle damage numbers, F4 = win the run,
## F6 = +25 Ichor.
## Run lifecycle (start / end / return to Basecamp) lives in the RunState autoload.

@onready var player: Player = $Player
@onready var level_up_menu: CanvasLayer = $LevelUpMenu
@onready var game_over: CanvasLayer = $GameOver


func _ready() -> void:
	Game.reset()
	Game.player = player
	Game.world = $Entities
	player.leveled_up.connect(level_up_menu.open)
	RunState.run_ended.connect(_on_run_ended)
	RunState.ascension_ended.connect(_on_run_ended)
	RunState.start_run()
	# characters-new: Sanctified elite rolls + the Celestial Leviathan map event.
	add_child(RosterDirector.new())
	if "--boss" in OS.get_cmdline_user_args():
		await get_tree().create_timer(3.0, false).timeout
		$EnemySpawner.spawn_boss()


func _on_run_ended(result: Dictionary) -> void:
	if result.get("cause") == &"abandoned":
		return  # leaving the scene; no end screen
	# Let the faint (or the victory beat) play before the end screen pauses everything.
	await get_tree().create_timer(2.0 if result.get("victory", false) else 1.4, false).timeout
	if is_inside_tree():
		game_over.open()


func _process(delta: float) -> void:
	if RunState.active:
		Game.elapsed += delta


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			player.add_xp((player.xp_to_next - player.xp) / player.xp_gain + 0.01)
		KEY_F2:
			Game.show_damage_numbers = not Game.show_damage_numbers
		KEY_F4:
			RunState.end_run(true, &"victory")
		KEY_F6:
			RunState.add_currency(25)
