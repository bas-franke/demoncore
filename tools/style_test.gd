extends Node3D
## Art-style showcase (res://tools/style_test.tscn): main.tscn plus a row of the shared style
## materials next to the player, for screenshots and look-dev.
##   godot --path . res://tools/style_test.tscn -- --shot=out.png --shot-time=6 [--ambient=1]
## Row (left to right): hellfire rock / lava / brand, holy halo + aura, angel with elite outline
## and holy rim, marble pillar (lit_static, chars in the blight), interact outline.

const ANGEL := "res://scenes/enemies/models/seraph_sentinel.tscn"


func _ready() -> void:
	# Keeps running while story dialogue pauses the tree, so timed screenshots show gameplay.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Wait one frame so main.tscn has spawned the player.
	await get_tree().process_frame
	var c := Game.player.global_position if Game.player else Vector3.ZERO
	var row := Node3D.new()
	Game.spawn(row, c + Vector3(0.0, 0.0, 3.2))
	Art.part(row, Art.sphere(), load(ArtStyle.MAT_HELLFIRE_ROCK), Vector3(-6.0, 0.6, 0.0), Vector3.ONE * 1.2)
	Art.part(row, Art.cylinder(0.5, 0.5), load(ArtStyle.MAT_HELLFIRE_LAVA), Vector3(-4.5, 0.1, 0.0), Vector3(1.6, 0.2, 1.6))
	Art.part(row, Art.box(), load(ArtStyle.MAT_HELLFIRE_BRAND), Vector3(-3.0, 0.7, 0.0), Vector3(0.25, 1.4, 0.25))
	Art.part(row, Art.torus(0.4, 0.5), load(ArtStyle.MAT_HOLY_HALO), Vector3(-1.5, 1.2, 0.0), Vector3.ONE * 1.0)
	Art.part(row, Art.sphere(), load(ArtStyle.MAT_HOLY_AURA), Vector3(-1.5, 0.4, 0.0), Vector3.ONE * 1.1)
	var angel: Node3D = load(ANGEL).instantiate()
	row.add_child(angel)
	angel.position = Vector3(0.5, 0.0, 0.0)
	angel.scale = Vector3.ONE * 1.4
	ArtStyle.apply_faction(angel, ArtStyle.Faction.HOLY, true)
	var pillar := Art.part(row, Art.cylinder(0.35, 0.42), load("res://assets/materials/lit_heaven_marble.tres"),
			Vector3(2.4, 1.0, -0.5), Vector3(1.0, 2.0, 1.0))
	pillar.name = "Pillar"
	var gold := Art.part(row, Art.sphere(), load("res://assets/materials/lit_heaven_gold.tres"), Vector3(4.0, 0.5, 0.0))
	ArtStyle.outline(gold, ArtStyle.INTERACT, 3.0, 0.6)
	# Hard-edged primitive: outline corners must not gap (outline_mode 1).
	var crate := Art.part(row, Art.box(), Art.mat(Art.BRONZE), Vector3(5.4, 0.5, 0.0), Vector3(0.8, 1.0, 0.8),
			Vector3(0.0, 0.6, 0.0))
	ArtStyle.outline(crate, ArtStyle.ELITE, 3.0)
	# Corruption wipes its trail when it notices the new scene (first frame); stamp after that.
	await get_tree().process_frame
	await get_tree().process_frame
	Corruption.stamp(c + Vector3(2.4, 0.0, 2.7), 2.2)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ambient="):
			Corruption.ambient = arg.substr(10).to_float()


func _process(_delta: float) -> void:
	if get_tree().paused and Dialogue.is_active():
		get_tree().paused = false
