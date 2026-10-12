class_name TerrainTheme
extends Resource
## Look + generation settings for a TerrainPatch (one .tres per realm in res://data/terrain/).
## Colours feed shaders/terrain/terrain.gdshader; the prop tables feed the patch's scatter pass
## (names from PropKit or Props, {name: weight}).

enum Edge { CLIFF_UP, DROP_DOWN }
enum Liquid { NONE, LAVA, WATER, CLOUD }

@export var display_name := "Realm"

@export_group("Shape")
## CLIFF_UP: the arena is a basin ringed by rising cliffs (hell). DROP_DOWN: the arena is a floating
## island whose edges fall away into the void / cloud sea (heaven).
@export var edge: Edge = Edge.CLIFF_UP
## Height of the outer cliffs (CLIFF_UP) or depth of the drop (DROP_DOWN), metres.
@export var edge_height := 6.0
## Number of terraces cut into the cliffs (0 = smooth slopes).
@export var terraces := 3
## Strength of the noise roughening walkable ground (kept tiny so feet stay on y = 0 visually).
@export var ground_bump := 0.06
## Liquid that fills rivers, pits and the space below the arena.
@export var liquid: Liquid = Liquid.LAVA
## Height of the liquid surface (below 0, the walkable level).
@export var liquid_level := -0.45

@export_group("Ground colours")
@export var ground_a := Color(0.16, 0.1, 0.085)
@export var ground_b := Color(0.09, 0.06, 0.055)
@export var path_color := Color(0.2, 0.17, 0.15)
@export var path_joint := Color(0.04, 0.03, 0.03)
@export var cliff_a := Color(0.13, 0.1, 0.095)
@export var cliff_b := Color(0.25, 0.12, 0.08)
## Accent painted into cracks / veins (hell: hot ember; heaven: gold leaf).
@export var accent := Color(1.0, 0.3, 0.06)
## Emission of the accent (0 = not glowing).
@export var accent_energy := 2.2
## 0..1 how much of the walkable ground shows accent cracks.
@export var accent_amount := 0.35
## Colour near liquids (scorched shore / damp bank / gilded rim).
@export var shore := Color(0.05, 0.02, 0.02)
@export var shore_glow := Color(1.0, 0.25, 0.05)
## Contrast of the soil grit detail (0 = smooth, 1 = very grainy).
@export var ground_grain := 0.7
## Path decals: worn centre, pebbles, cracked / missing flagstones, inlaid rosettes (0 = off).
@export var path_wear := 1.0
## Rosette inlays on paved paths.
@export var inlay_color := Color(0.83, 0.66, 0.3)
## Scales the Corruption blight on this terrain (art-style library; 1 = as designed).
@export var corruption_strength := 1.0
## Paths: 0 = beaten earth, 1 = laid flagstones (marble tiles in heaven).
@export var path_paved := 0.0

@export_group("Scatter")
## Props on the cliffs / along the island edge (outside the walkable area, no collision needed).
@export var edge_props := {}
## Big blocking props inside the arena (collision on).
@export var field_props := {}
## Small filler inside the arena (no collision).
@export var small_props := {}
## Props per 100 m^2 of walkable area.
@export var field_density := 0.35
@export var small_density := 1.2
@export var edge_density := 0.6

@export_group("Islands and plants")
## DROP_DOWN themes: small sky islands around the arena, joined by cloud stepping paths.
@export var satellites := 0
## Grass / flowers on walkable ground (TerrainFoliage): {plant type: weight}. Types from
## res://assets/models/foliage/ (grass_green, grass_dry, grass_ash, fern, flowers_pale, flowers_red,
## reeds, leaf_litter, toadstools). The weights' sum (capped at 1) is the coverage.
@export var foliage := {}
@export var foliage_density := 1.0
