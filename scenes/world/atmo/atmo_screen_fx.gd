class_name AtmoScreenFX
extends CanvasLayer
## Screen-space touches of the Atmosphere rig, on CanvasLayer 0 (above the post pass at -1, below
## every UI layer):
##   - corruption vignette: tendrils of dark creeping in from the edges with the gloom (all tiers;
##     a plain overlay, no screen read)
##   - holy bloom: radial chromatic split + golden glow around a charging boss telegraph (Medium+;
##     reads the screen, so the rect is hidden whenever it has nothing to do)
##   - flash: full-screen additive flash (lightning, boss arrivals, deaths)

const VIGNETTE_SHADER := preload("res://shaders/atmo/corruption_vignette.gdshader")
const BLOOM_SHADER := preload("res://shaders/atmo/holy_bloom.gdshader")

var quality := 2

var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _bloom: ColorRect
var _bloom_mat: ShaderMaterial
var _flash: ColorRect
var _flash_v := 0.0
var _flash_decay := 4.0


func _ready() -> void:
	layer = 0
	_bloom_mat = ShaderMaterial.new()
	_bloom_mat.shader = BLOOM_SHADER
	_bloom = _rect("HolyBloom", _bloom_mat)
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = VIGNETTE_SHADER
	_vignette = _rect("CorruptionVignette", _vignette_mat)
	_flash = _rect("Flash", null)
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash.material = cm


func _process(delta: float) -> void:
	if _flash_v > 0.0:
		_flash_v = maxf(_flash_v - delta * _flash_decay, 0.0)
		_flash.color.a = _flash_v
		_flash.visible = _flash_v > 0.002


## Gloom 0..1.5 and its colour.
func set_corruption(gloom: float, color: Color) -> void:
	_vignette.visible = gloom > 0.02
	if _vignette.visible:
		_vignette_mat.set_shader_parameter(&"strength", gloom)
		_vignette_mat.set_shader_parameter(&"color", color)


## Holy bloom around `center` (screen UV 0..1) at `intensity` 0..1.
func set_holy_bloom(center: Vector2, intensity: float) -> void:
	_bloom.visible = intensity > 0.01 and quality >= 1
	if _bloom.visible:
		_bloom_mat.set_shader_parameter(&"center", center)
		_bloom_mat.set_shader_parameter(&"intensity", intensity)


## Full-screen additive flash (`strength` ~0.1..0.6, already accessibility-scaled by the caller).
func flash(color: Color, strength: float, decay: float) -> void:
	_flash_v = maxf(_flash_v, strength)
	_flash_decay = maxf(decay, 0.1)
	_flash.color = Color(color.r, color.g, color.b, _flash_v)
	_flash.visible = true


func _rect(n: String, mat: Material) -> ColorRect:
	var r := ColorRect.new()
	r.name = n
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.material = mat
	r.visible = false
	add_child(r)
	return r
