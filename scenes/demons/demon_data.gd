class_name DemonData
extends Resource
## A playable demon: looks (used by DemonModel), lore, starting weapon and stat tweaks.

## Body plan. Sets proportions, posture and whether the legs hide under a robe.
enum Build {
	BRUTE,    ## Hulking, hunched, broad plate armor.
	SERAPH,   ## Tall and slender, upright, fitted armor and a long tattered skirt.
	WARLOCK,  ## Robed to the ground, high collar.
	WARDEN,   ## Heavy armored jailer, square shoulders.
	REAPER,   ## Gaunt, hovering, ragged robe with no visible legs.
}
enum HornStyle { NONE, RAM, SWEPT, ANTLER, THORN_CROWN }
enum HeadStyle { BARE, CAGE_HELM, HOOD_MASK }
enum WingStyle { NONE, FEATHERED, MEMBRANE }

@export var display_name := "Demon"
## Epithet shown under the name, e.g. "the Horned Ravager".
@export var title := ""
## One short, serious line of lore for the select screen.
@export_multiline var lore := ""
## Perks summary for the select screen.
@export_multiline var perk_text := ""

@export_group("Looks")
## Blender model id: res://assets/models/demons/<model_id>.glb (built from
## tools/blender/models/demons/<model_id>.py). Empty = display_name in lower case.
@export var model_id := ""
@export var skin_color := Color(0.32, 0.12, 0.1)
## Plate / bone / metal parts.
@export var armor_color := Color(0.06, 0.055, 0.06)
## Capes, robes, loincloths, wings.
@export var cloth_color := Color(0.13, 0.11, 0.12)
## Eyes, runes, cracks of hellfire.
@export var glow_color := Color(1.0, 0.3, 0.06)
@export var horn_color := Color(0.72, 0.68, 0.58)
@export var build: Build = Build.SERAPH
@export var horn_style: HornStyle = HornStyle.SWEPT
@export var head_style: HeadStyle = HeadStyle.BARE
@export var wing_style: WingStyle = WingStyle.NONE
## Overall scale; 1.0 = ~2 units to the top of the head.
@export_range(0.8, 1.3, 0.01) var height := 1.0
## Width multiplier on top of the build's own proportions.
@export_range(0.7, 1.5, 0.01) var bulk := 1.0
## 0 = no cape, 1 = cape down to the calves.
@export_range(0.0, 1.0, 0.05) var cape_length := 0.7
## Chains wrapped around the torso and hanging from the wrists.
@export var chains := false
## A floating grimoire at the demon's side.
@export var grimoire := false

@export_group("Gameplay")
@export var starting_weapon: PackedScene
## StringName -> float, each applied with Player.apply_stat(stat, amount).
@export var stat_mods: Dictionary = {}


## Path of the Blender-made model used by DemonModel.
func get_model_path() -> String:
	var id := model_id if model_id != "" else display_name.to_lower()
	return "res://assets/models/demons/%s.glb" % id


## Applies every stat modifier to `player` (expects an `apply_stat(StringName, float)` method).
func apply_to(player: Node) -> void:
	for stat: Variant in stat_mods:
		player.call(&"apply_stat", StringName(stat), float(stat_mods[stat]))


## A stat_mods entry by name (keys may be String or StringName); 0 when absent.
func get_stat_mod(stat: StringName) -> float:
	for key: Variant in stat_mods:
		if StringName(key) == stat:
			return float(stat_mods[key])
	return 0.0
