class_name XPGem
extends Pickup
## Experience pickup: a "soul shard", a small faceted crystal of condensed sin with a light
## burning inside it. Sits still until the player's PickupArea touches it, then flies to the
## player. Looks follow `value`: a dim red sliver (< 5), a bright crimson-violet shard (< 25),
## or a radiant golden-red relic cluster (>= 25). Setting `value` re-tiers it (gems merge).

## Per tier: crystal body color, inner glow color, glow energy, scale.
const TIER_BODY := [Color(0.22, 0.02, 0.04), Color(0.34, 0.03, 0.14), Color(0.55, 0.2, 0.06)]
const TIER_GLOW := [Color(0.75, 0.06, 0.08), Color(1.0, 0.12, 0.38), Color(1.0, 0.42, 0.14)]
const TIER_ENERGY := [1.1, 2.4, 3.2]
const TIER_AURA := [0.0, 0.35, 0.6]
const TIER_SCALES := [0.75, 1.0, 1.35]

## Blender models per tier (dim red sliver, crimson-violet shard, golden-red relic cluster with a band).
const SHARD_MODELS := ["res://assets/models/pickups/soul_shard_0.glb", "res://assets/models/pickups/soul_shard_1.glb",
		"res://assets/models/pickups/soul_shard_2.glb"]
static var _aura_mats := {}

@export var value := 1:
	set(v):
		value = v
		if is_node_ready():
			_apply_tier()

var _t := 0.0
var _tier := -1
var _pop := 0.0
var _model: Node3D
var _spin: Node3D
var _ring: Node3D


## Visual tier (0..2) for an XP value: sliver, shard, relic cluster.
static func tier_for(v: int) -> int:
	return 0 if v < 5 else (1 if v < 25 else 2)


func _ready() -> void:
	_t = randf() * TAU
	_apply_tier()


func _physics_process(delta: float) -> void:
	_t += delta
	_animate(delta)
	_home(delta)


func _collect(player: Player) -> void:
	Sfx.play(&"soul", 0.08, -2.0 if _tier == 2 else (-6.0 if _tier == 1 else -9.0))
	player.add_xp(value)


func _animate(delta: float) -> void:
	if _model == null:
		return
	if _pop < 1.0:
		_pop = minf(_pop + delta * 4.0, 1.0)
	var s: float = TIER_SCALES[_tier] * maxf(_ease_out_back(_pop), 0.01)
	_model.scale = Vector3.ONE * s
	_model.position.y = 0.08 + sin(_t * 2.4) * 0.06
	var spin_speed := 6.0 if _target else 0.9
	_spin.rotation.y += spin_speed * delta
	_spin.rotation.z = sin(_t * 1.6) * 0.12
	if _ring:
		_ring.rotation.y -= 1.4 * delta
		_ring.rotation.x = 0.35 + sin(_t * 1.2) * 0.1


func _apply_tier() -> void:
	var tier := tier_for(value)
	if tier == _tier:
		_pop = minf(_pop, 0.6)  # small swell when merged into
		return
	_tier = tier
	if _model:
		remove_child(_model)
		_model.queue_free()
	_build_shard(tier)
	_pop = 0.0
	_animate(0.0)


func _build_shard(tier: int) -> void:
	var glow: Color = TIER_GLOW[tier]
	_model = Node3D.new()
	_model.name = &"Model"
	add_child(_model)
	_spin = Art.pivot(_model)
	# Blender-made faceted crystal (tools/blender/models/pickups/soul_shard_N.py); non-flashable
	# materials: shards come in crowds.
	var glb := GlbModel.create(SHARD_MODELS[tier], false)
	_spin.add_child(glb)
	_ring = null
	if glb.scene_root:
		_ring = glb.scene_root.find_child("band", true, false) as Node3D
	# Soft light around brighter shards (additive, so it reads as an inner glow bleeding out).
	var aura_e: float = TIER_AURA[tier]
	if aura_e > 0.0:
		Art.part(_model, Art.sphere(), _aura(glow, aura_e), Vector3(0.0, 0.0, 0.0), Vector3.ONE * (0.42 + 0.12 * float(tier)))
	Art.no_shadows(_model)


static func _aura(color: Color, energy: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), energy]
	if not _aura_mats.has(key):
		_aura_mats[key] = HolyFX.additive(color, energy)
	return _aura_mats[key]

