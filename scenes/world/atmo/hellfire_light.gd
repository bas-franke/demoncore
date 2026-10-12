class_name HellfireLight
extends OmniLight3D
## A flickering hellfire light: drop it on braziers, lava cracks, portals, shop forges.
##
##   var l := HellfireLight.new()
##   l.style = HellfireLight.Style.FIRE   # FIRE (lively), EMBER (slow smoulder), PULSE (sigil breathing)
##   l.base_energy = 2.5
##   add_child(l)
##
## Energy = base_energy * flicker * Atmosphere.flicker_strength() (the active preset's fx.flicker, raised
## during boss fights). Shadows are switched off below High quality. Any other OmniLight3D/SpotLight3D
## can get the same treatment without this script: add it to the group &"hellfire_flicker" (its
## light_energy at that moment becomes the base) and the Atmosphere autoload flickers it.

enum Style { FIRE, EMBER, PULSE }

@export var style := Style.FIRE
## Energy around which the light flickers.
@export var base_energy := 2.0
## 0 = steady, 1 = default, 2 = wild.
@export_range(0.0, 2.0) var flicker_amount := 1.0
## Flicker speed multiplier.
@export var speed := 1.0
## Cast shadows (only honoured at High quality and up).
@export var wants_shadow := false

var _t := 0.0
var _phase := 0.0


func _ready() -> void:
	_phase = randf() * 100.0
	if light_color == Color.WHITE:
		light_color = Color(1.0, 0.45, 0.16)
	_apply_quality()
	var settings := get_node_or_null(^"/root/Settings")
	if settings and settings.has_signal(&"graphics_changed"):
		settings.connect(&"graphics_changed", _apply_quality)


func _process(delta: float) -> void:
	_t += delta * speed
	light_energy = base_energy * flicker_at(_t + _phase, style, flicker_amount * _global_strength())


## Flicker multiplier (~0.6..1.15) for `style` at time `t` (seconds). Static so other systems can share
## the same look (e.g. Atmosphere's group flicker, emissive materials pulsing with a light).
static func flicker_at(t: float, s: int = Style.FIRE, amount: float = 1.0) -> float:
	var f := 0.0
	match s:
		Style.FIRE:
			# Layered incommensurate sines: a slow sway, a lively lick and a fast crackle.
			f = 0.1 * sin(t * 2.3) + 0.08 * sin(t * 9.1 + 1.3) * sin(t * 3.7) + 0.06 * sin(t * 23.0 + 0.7)
			# rare deeper gutters
			f -= 0.12 * pow(maxf(sin(t * 0.83 + 2.0) * sin(t * 1.37), 0.0), 6.0)
		Style.EMBER:
			f = 0.12 * sin(t * 0.9) + 0.05 * sin(t * 3.3 + 0.4)
		Style.PULSE:
			f = 0.2 * sin(t * 1.4)
	return maxf(1.0 + f * amount, 0.05)


func _global_strength() -> float:
	var atmo := get_node_or_null(^"/root/Atmosphere")
	if atmo and atmo.has_method(&"flicker_strength"):
		return atmo.flicker_strength()
	return 1.0


func _apply_quality() -> void:
	var tier := 2
	var atmo := get_node_or_null(^"/root/Atmosphere")
	if atmo and atmo.has_method(&"quality"):
		tier = atmo.quality()
	shadow_enabled = wants_shadow and tier >= 2
