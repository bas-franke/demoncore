extends DemonKit
## "The Infernal Bar" (Basecamp prop + NPC): Sable the succubus barkeep (succubus.gd with
## barkeep = true) behind a counter of black basalt topped with brass, a back shelf of bottles
## glowing in sin-colours, a keg of something molten, two bone stools in front and a hanging sign.
## The counter is solid (StaticBody3D). Forward (-Z) faces the customers; Sable stands behind
## (+Z). talk() makes her slide a drink across (gesture 0).

const W := 2.4

var _sable: ProcModel


func build() -> void:
	mote_count = 0
	var basalt := m_stone(Color(0.13, 0.1, 0.1))
	var brass := Art.mat(Art.BRONZE.lightened(0.2), 0.35, 0.6, 0.2, true, 0.2, &"gold")
	var wood := m_wood()
	var bone := Art.mat(Art.BONE, 0.6, 0.0, 0.4, true, 0.0, &"bone")
	# Counter: basalt body, brass top, a glowing ember seam along the front.
	Art.part(self, Art.box(), basalt, Vector3(0.0, 0.5, 0.0), Vector3(W, 1.0, 0.5))
	Art.part(self, Art.box(), brass, Vector3(0.0, 1.02, -0.02), Vector3(W + 0.1, 0.05, 0.6))
	Art.part(self, Art.box(), Art.glow(Art.EMBER, 1.4), Vector3(0.0, 0.2, -0.255), Vector3(W - 0.2, 0.02, 0.01))
	# Drinks on the counter.
	for k in 3:
		var x := -0.8 + k * 0.55
		Art.part(self, Art.cylinder(0.5, 0.35), Art.mat(Color(0.1, 0.05, 0.08), 0.1, 0.0, 0.0, true, 0.9, &"crystal"), Vector3(x, 1.11, -0.1), Vector3(0.07, 0.13, 0.07))
		Art.part(self, Art.cylinder(0.5, 0.5), Art.glow([Color(0.9, 0.15, 0.25), Color(0.4, 0.9, 0.3), Color(0.7, 0.3, 1.0)][k], 1.6), Vector3(x, 1.15, -0.1), Vector3(0.06, 0.01, 0.06))
	# Back shelf with bottles.
	Art.part(self, Art.box(), wood, Vector3(0.0, 0.9, 1.25), Vector3(W, 1.8, 0.2))
	for row in 3:
		Art.part(self, Art.box(), wood, Vector3(0.0, 0.6 + row * 0.45, 1.1), Vector3(W - 0.1, 0.04, 0.3))
		for k in 7:
			var x := -1.0 + k * 0.33 + 0.05 * float(row % 2)
			var col: Color = [Color(0.9, 0.15, 0.25), Color(0.4, 0.9, 0.3), Color(0.7, 0.3, 1.0), Color(1.0, 0.6, 0.15)][(k + row) % 4]
			Art.part(self, Art.cylinder(0.3, 0.5), Art.emissive(col.darkened(0.6), col, 0.9, 0.1), Vector3(x, 0.74 + row * 0.45, 1.1), Vector3(0.09, 0.24, 0.09))
	# Keg of something molten on the counter end.
	Art.part(self, Art.cylinder(0.5, 0.5), wood, Vector3(1.0, 1.3, 0.1), Vector3(0.35, 0.45, 0.35), Vector3(0.0, 0.0, PI * 0.5))
	Art.part(self, Art.cylinder(0.5, 0.5), Art.glow(Art.HELLFIRE, 1.6), Vector3(0.78, 1.3, 0.1), Vector3(0.12, 0.02, 0.12), Vector3(0.0, 0.0, PI * 0.5))
	# Two bone stools in front.
	for x: float in [-0.6, 0.5]:
		limb(self, Vector3(x, 0.0, -0.75), Vector3(x, 0.6, -0.75), 0.04, bone)
		Art.part(self, Art.cylinder(0.5, 0.5), Art.mat(Color(0.35, 0.05, 0.06), 0.6, 0.0, 0.2, true, 0.3, &"leather"), Vector3(x, 0.63, -0.75), Vector3(0.36, 0.06, 0.36))
	# Hanging sign: a horned skull over the bar.
	limb(self, Vector3(-W * 0.5, 0.0, 1.3), Vector3(-W * 0.5, 2.3, 1.3), 0.04, wood)
	limb(self, Vector3(-W * 0.5, 2.3, 1.3), Vector3(-W * 0.5, 2.3, -0.2), 0.03, wood)
	Art.part(self, Art.box(), wood, Vector3(-W * 0.5, 2.0, -0.15), Vector3(0.05, 0.4, 0.5))
	Art.part(self, Art.sphere(), bone, Vector3(-W * 0.5 - 0.04, 2.0, -0.15), Vector3(0.1, 0.16, 0.16))
	Art.light(self, Color(1.0, 0.45, 0.35), 1.4, 5.0, Vector3(0.0, 1.9, -0.4))
	finish()
	_sable = (load("res://scenes/characters/allies/succubus.tscn") as PackedScene).instantiate() as ProcModel
	_sable.set(&"barkeep", true)
	_sable.position = Vector3(0.0, 0.0, 0.62)
	add_child(_sable)


func _ready() -> void:
	super._ready()
	if bool(autoplay):
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		for c: Array in [[Vector3(0.0, 0.6, 0.0), Vector3(W + 0.1, 1.2, 0.6)], [Vector3(0.0, 0.9, 1.25), Vector3(W, 1.8, 0.3)]]:
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = c[1]
			cs.shape = box
			cs.position = c[0]
			sb.add_child(cs)
		add_child(sb)


## Sable slides a drink across the counter.
func talk() -> void:
	if _sable:
		_sable.gesture(0, 1.6)
