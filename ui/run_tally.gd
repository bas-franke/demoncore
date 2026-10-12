class_name RunTally
extends Node
## Per-run statistics the end-screen breakdown needs and no other system keeps (UI role):
## total damage dealt (Game.enemy_struck) and kills per enemy type (RunState.enemy_killed).
## The HUD adds one instance per run; the data is static so the end screen can read it after the
## run ended (it stays until the next run starts). Ability damage per id comes from
## Abilities.damage_report(); weapons are "everything else".
##
##   RunTally.total_damage   RunTally.kills_by_type  # display name -> [count, elite count]

static var total_damage := 0.0
static var kills_by_type := {}
static var biggest_hit := 0.0


func _ready() -> void:
	reset()
	Game.enemy_struck.connect(_on_struck)
	var rs := get_node_or_null(^"/root/RunState")
	if rs and rs.has_signal(&"enemy_killed"):
		rs.connect(&"enemy_killed", _on_killed)


static func reset() -> void:
	total_damage = 0.0
	kills_by_type = {}
	biggest_hit = 0.0


func _on_struck(_enemy: Node3D, amount: float) -> void:
	total_damage += amount
	biggest_hit = maxf(biggest_hit, amount)


func _on_killed(_pos: Vector3, data: Resource, elite: bool) -> void:
	var kind := "Unknown"
	if data:
		var dn: Variant = data.get(&"display_name")
		kind = str(dn) if dn != null and str(dn) != "" else data.resource_path.get_file().get_basename().capitalize()
	var row: Array = kills_by_type.get(kind, [0, 0])
	row[0] += 1
	if elite:
		row[1] += 1
	kills_by_type[kind] = row
