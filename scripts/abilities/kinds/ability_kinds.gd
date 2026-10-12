class_name AbilityKinds
## Registry: AbilityDef.kind -> kind script (scripts/abilities/kinds/kind_*.gd).
## Add a kind: write kind_<name>.gd extending AbilityKind, then add it here.

const SCRIPTS := {
	&"bolt": preload("res://scripts/abilities/kinds/kind_bolt.gd"),
	&"nova": preload("res://scripts/abilities/kinds/kind_nova.gd"),
	&"aura": preload("res://scripts/abilities/kinds/kind_aura.gd"),
	&"zone": preload("res://scripts/abilities/kinds/kind_zone.gd"),
	&"chain": preload("res://scripts/abilities/kinds/kind_chain.gd"),
	&"strike": preload("res://scripts/abilities/kinds/kind_strike.gd"),
	&"summon": preload("res://scripts/abilities/kinds/kind_summon.gd"),
	&"orbit": preload("res://scripts/abilities/kinds/kind_orbit.gd"),
	&"cone": preload("res://scripts/abilities/kinds/kind_cone.gd"),
	&"line": preload("res://scripts/abilities/kinds/kind_line.gd"),
	&"hook": preload("res://scripts/abilities/kinds/kind_hook.gd"),
	&"blink": preload("res://scripts/abilities/kinds/kind_blink.gd"),
	&"hex": preload("res://scripts/abilities/kinds/kind_hex.gd"),
	&"buff": preload("res://scripts/abilities/kinds/kind_buff.gd"),
	&"corpse": preload("res://scripts/abilities/kinds/kind_corpse.gd"),
	&"harvest": preload("res://scripts/abilities/kinds/kind_harvest.gd"),
	&"retaliate": preload("res://scripts/abilities/kinds/kind_retaliate.gd"),
	&"reflect": preload("res://scripts/abilities/kinds/kind_reflect.gd"),
	&"mimic": preload("res://scripts/abilities/kinds/kind_mimic.gd"),
	&"pride": preload("res://scripts/abilities/kinds/kind_pride.gd"),
	&"devour": preload("res://scripts/abilities/kinds/kind_devour.gd"),
	&"turret": preload("res://scripts/abilities/kinds/kind_construct.gd"),
	&"mine": preload("res://scripts/abilities/kinds/kind_construct.gd"),
	&"decoy": preload("res://scripts/abilities/kinds/kind_construct.gd"),
	&"whip": preload("res://scripts/abilities/kinds/kind_whip.gd"),
}


static func has(kind: StringName) -> bool:
	return SCRIPTS.has(kind)


## A new kind instance bound to `caster`, or null (with a warning) for an unknown kind.
static func create(kind: StringName, caster: AbilityCaster) -> AbilityKind:
	if not SCRIPTS.has(kind):
		push_warning("Ability '%s' has unknown kind '%s'" % [caster.def.id, kind])
		return null
	var k: AbilityKind = (SCRIPTS[kind] as GDScript).new()
	k.caster = caster
	return k
