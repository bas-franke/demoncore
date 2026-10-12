class_name ScaleStack
## Composable visual scale for any Node3D: several systems can each own a named factor and the
## node's scale is always base x product(factors), so nobody overwrites anybody.
## Added by the abilities role (Gluttony's Girth); characters-polish and others are welcome to use
## it for growth / shrink effects instead of writing `scale` directly. The base is captured the
## first time a factor is set (or set explicitly with set_base()).
##
##   ScaleStack.set_factor(player.body, &"girth", 1.12)   # 1.0 removes the factor
##   ScaleStack.factor(player.body, &"girth") -> 1.12
##   ScaleStack.set_base(node, Vector3.ONE * 1.1)          # the node's own scale changed

const META_BASE := &"scale_stack_base"
const META_FACTORS := &"scale_stack_factors"


static func set_factor(node: Node3D, source: StringName, f: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.has_meta(META_BASE):
		node.set_meta(META_BASE, node.scale)
	var factors: Dictionary = node.get_meta(META_FACTORS, {})
	if is_equal_approx(f, 1.0):
		factors.erase(source)
	else:
		factors[source] = f
	node.set_meta(META_FACTORS, factors)
	_apply(node)


static func factor(node: Node3D, source: StringName) -> float:
	if node == null or not node.has_meta(META_FACTORS):
		return 1.0
	return float((node.get_meta(META_FACTORS) as Dictionary).get(source, 1.0))


## Replaces the captured base scale (for systems that legitimately own the node's own scale).
static func set_base(node: Node3D, base: Vector3) -> void:
	node.set_meta(META_BASE, base)
	_apply(node)


static func _apply(node: Node3D) -> void:
	var product := 1.0
	for f: float in (node.get_meta(META_FACTORS, {}) as Dictionary).values():
		product *= f
	node.scale = (node.get_meta(META_BASE, node.scale) as Vector3) * product
