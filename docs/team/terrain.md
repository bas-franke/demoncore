# Terrain and environment models (docs/team/terrain.md)

Status: **round 2 landed** and validated (terrain_check clean; map_check OK over 2-4 variants each
for `gilded_isles`, `the_breach`, `storm_spire` and `ashen_wastes`; in-game runs OK).
- Procedural prop kit: 17 realm props (`PropKit`) + 18 map-site props (`SiteProps`), all built
  from code, with collision. Variants are cached: an instance costs 10-140 us instead of 1-32 ms.
- `TerrainPatch`: a heightmap arena with cliffs or sky-island drop-offs, paths, rivers and pools
  (lava / water / sky), bridges, rock mesas, satellite islands joined by walkable cloud paths,
  grass and flowers, and scattered props (batched as MultiMeshes).
- Terrain shader: rock strata and fractures, edge wear, path decals, a tunable corruption blend.
- `ScorchTrail`: burning hoofprints behind the demon.
- Two playable terrain maps: **The Gilded Isles** and **The Breach**.
- Basecamp Hell lava-sea dressing.

## Owned files
| Path | What |
|---|---|
| `scripts/terrain/prop_builder.gd` | `PropBuilder`: procedural mesh + collision accumulator (box, slab, prism, lathe, cylinder, spike, torus, tube, blob, quad) |
| `scripts/terrain/prop_kit.gd` | `PropKit`: realm props, variant cache, shared materials, visibility ranges |
| `scripts/terrain/site_props.gd` | `SiteProps`: map-site props (storm spire, war camp, monastery, citadel, Heaven's Gate, Breach) |
| `scripts/terrain/terrain_patch.gd` | `TerrainPatch` (Node3D): bounded terrain arena with collision and queries |
| `scripts/terrain/terrain_theme.gd` | `TerrainTheme` (Resource): look + generation + scatter + foliage |
| `scripts/terrain/terrain_foliage.gd` | `TerrainFoliage`: grass / flowers on a patch (foliage models + shader, MultiMesh) |
| `scripts/terrain/scatter.gd` | `Scatter`: Poisson / jittered points, weighted placement, MultiMesh + merge batching |
| `scripts/terrain/scorch_trail.gd` | `ScorchTrail`: burning hoofprints behind the player |
| `data/terrain/{hell,heaven,sanctum,breach}.tres` | Themes |
| `shaders/terrain/terrain.gdshader` | Splat + triplanar terrain (strata, fractures, edge wear, path decals) |
| `shaders/terrain/{lava,water,cloud_sea,stained_glass,scorch}.gdshader` | Liquids, sky floor, glass, hoofprints |
| `scenes/terrain/terrain_map.gd` | `TerrainMap extends GameMap`: generator map driven by a `"terrain"` JSON block |
| `scenes/terrain/hell_dressing.gd` | `HellDressing`: spires / basalt / brimstone islets in a lava sea around a plateau |
| `scenes/terrain/terrain_showcase.tscn/.gd` | Stand-alone viewer (arena / props grid / overview), screenshots |
| `tools/terrain/terrain_check.gd` | Headless check: every prop (fresh vs cached cost) + patches |
| `data/maps/gilded_isles.json`, `data/maps/the_breach.json` | Registry entries (schema owned by maps) |

Shared-file edits (small, marked):
- `scripts/props.gd` `Props.build()`: unknown names fall through to `PropKit.build(name, rng, false)`,
  so **every PropKit / SiteProps name works anywhere a Props name does** (decor, `GameMap.prop()`
  / `kit()`, hub).
- `scenes/basecamp/basecamp.gd` `_ready()`: one line adds `HellDressing.around(...)` after
  `scenery.build()` (visual only; delete the line to opt out).
- `data/atmosphere/presets.json`: new preset `the_breach` (extends `gilded_isles`, `"cycle": []`),
  inserted before `_overlays`. Visuals: retune freely.
- The art-style role added its corruption include to `shaders/terrain/terrain.gdshader` (fine by me).

## PropKit + SiteProps
`PropKit.build(name, rng, collide := true) -> Node3D` for **every** name below. It returns an
instance of one of `PropKit.VARIANTS` (6) cached variants, built once each with a fixed seed and
packed into a PackedScene, with a random yaw. Each instance costs 10-140 us. Every instance of a
variant shares its meshes, which is what lets Scatter / GameMap batch them.
`PropKit.build_fresh(name, rng, collide)` generates unique geometry every time (1-32 ms). Set
`PropKit.use_cache = false` to make that the default. Root metas: `footprint` (radius in m) and
`prop`. With `collide`, a `StaticBody3D "Collision"` on layer 1 blocks the player and enemies.
Every mesh gets a visibility range of `PropKit.VIS_RANGE` (110 m). Overview cameras can call
`PropKit.clear_visibility_ranges(root)`.

| Holy realms | | Basecamp Hell | |
|---|---|---|---|
| `marble_column` | fluted, gilded; 35% broken with fallen drums | `obsidian_spire` | glossy spike cluster, magma shards |
| `broken_statue` | robed angel, wings, halo; 50% desecrated | `lava_pool` | animated lava in a charred rim, glow light |
| `cloud_platform` | walkable cloud top at y=0 (no collision) | `bone_heap` | bones, horned skulls, ribcage |
| `cloud_bank` | solid low cloud cluster | `chain_posts` | rusted posts, sagging chain, hanging skull |
| `golden_gate` | pearly gate, sunburst crown; 40% open | `hell_brazier` | iron tripod, hellfire + light |
| `stained_window` | ruined wall, back-lit lancet; 33% shattered | `brimstone_rock` | sulphur-crusted boulder |
| `chapel` | walk-in chapel (door local +z), back-corner bell tower | `basalt_columns` | hex organ-pipes, pale caps, magma joints |
| `holy_grave` | cross / winged stele / ledger tomb | `impaler_spikes` | ring of stakes with skulls |
| `holy_brazier` | gilded bowl, white-gold flame + light | | |

**SiteProps** (`scripts/terrain/site_props.gd`, `SiteProps.NAMES`, footprints in `SiteProps.FOOTPRINT`):
| Map | Props |
|---|---|
| Storm spire | `lightning_rod` (iron mast, copper coil, spike crown, storm-blue tip, guy cables), `bell_tower_ruin` (snapped walls, fallen cracked bell) |
| Ashen wastes war camp | `war_tent` (angelic pavilion, 1/3 burned), `siege_ladder` (never collides), `burned_cart`, `crucifix_pyre` (holy fire + light), `weapon_rack`, `supply_crates` |
| Frozen monastery | `prayer_flags` (5-colour flags on a sagging cord), `ice_pine` (snow-capped tiers, icicles), `snow_cairn` |
| Sunlit citadel | `citadel_banner` (gold pole, swallow-tail sun banner), `sun_mirror` (gold dish on a gimbal, holy glint + light) |
| Heaven's Gate | `cloud_steps` (rising cloud treads, visual), `colossal_door` (8 x 9.5 m pearl-and-gold doors under a pointed arch; 30% ajar; footprint 6) |
| The Breach | `hell_rift` (lava fissure, obsidian shards, impassable, light), `fallen_wing`, `corrupted_column` (obsidian bursting through marble, magma veins) |

Maps: `kit(&"war_tent", pos)` / `prop(...)` already accept all of these. For exact nav shapes
instead of footprint circles, see `TerrainMap._mirror_collision()`. It mirrors the prop's real
box and cylinder colliders into `_blockers`, so doorways stay open.

## TerrainPatch
The game is planar (player/enemies pinned to y = 0): the walkable area stays flat at y≈0, everything
else gets box colliders; heights outside the arena are visual.
```gdscript
var t := TerrainPatch.new()
t.theme = preload("res://data/terrain/hell.tres")   # hell / heaven / sanctum / breach
t.size = Vector2(120, 120); t.rng_seed = 42
t.auto_features = false                              # or true: arena + spokes + river + bridges + mesas (+ satellites)
t.add_open_circle(Vector2.ZERO, 30.0)                # walkable areas (also add_open_rect)
t.add_path(PackedVector2Array([Vector2(0, 0), Vector2(0, -40)]), 3.0)
t.add_river(PackedVector2Array([Vector2(-50, 10), Vector2(50, 6)]), 4.0)   # lava / water / sky rift
t.add_bridge(Vector2(0, 6), Vector2(0, 16), 4.5)     # walkable deck + bridge prop (>= 4.5 m for enemy nav)
t.add_cloud_path(PackedVector2Array([Vector2(0, -30), Vector2(0, -48)]), 4.5)  # walkable cloud steps over the void
t.add_pool(Vector2(12, -8), 3.0); t.add_block_circle(Vector2(-14, 12), 4.0)  # pool, rock mesa
add_child(t)                                          # builds in _ready (or build_on_ready=false + build())
```
Queries (safe before entering the tree): `is_walkable(pos, margin)`, `walk_distance(pos)`,
`nearest_walkable(pos)`, `height_at(pos)`, `height_local(q)`, `growth_at(q)`, `random_walkable(rng)`,
`play_radius()` (covers satellite islands), `stats()`. After build: `blocker_rects` (local Rect2s
over everything non-walkable, for nav grids), `prop_blockers`. Group `&"terrain"`,
`TerrainPatch.find(tree)`, signal `built`.

Theme fields (`TerrainTheme`):
- **Shape:** `edge` CLIFF_UP / DROP_DOWN, `edge_height`, `terraces`.
- **Liquid:** `liquid` NONE / LAVA / WATER / CLOUD. A DROP_DOWN theme with LAVA floats the island
  over a lava sea, and its rifts glow at the lips.
- **Colours:** the ground and cliff colours, `accent*`, `shore*`, `ground_grain`, `path_paved`,
  `path_wear` (path decals), `inlay_color` (path rosettes), `corruption_strength`.
- **Scatter tables:** `edge_props` / `field_props` / `small_props`, plus their densities.
- **Islands:** `satellites` (DROP_DOWN only).
- **Plants:** `foliage` ({plant type: weight}) and `foliage_density`.

## Surface (terrain.gdshader)
Splat channels:
- `COLOR.r`: path.
- `COLOR.g`: accent mask.
- `COLOR.b`: shore.
- `COLOR.a`: walkable.
- `UV.x`: baked convexity (rims > 0, hollows < 0).

Layers:
- **Cliffs:** two-scale triplanar relief, noise-warped strata beds with dark bedding seams, vertical
  fractures and grime streaks.
- **Edge wear:** pale, scuffed rims and lips; darker grime and AO in hollows and at cliff feet.
- **Paved paths:** cracked and missing flagstones, moss in the edge joints, inlaid rosettes on a
  9 m grid (gold in heaven, hellstone in hell).
- **Earth paths:** a worn centre, damp verges, pebbles and scuffs.
- **Cracks:** ember or gold cracks, plus a shore glow.
- **Corruption:** the blight is multiplied by `corruption_strength` (heaven 0.8, others 1).

## Foliage, cloud paths, scorch marks
- `TerrainFoliage.grow(patch, table, seed, density)` (called by the patch when the theme has a
  `foliage` table).
  - Uses the foliage worker's `assets/models/foliage/*.glb` and `shaders/foliage.gdshader` (wind,
    push-away around player and enemies via `Perf.enemies()`, blight withering).
  - Static: one MultiMesh per (24 m tile, type), no shadows, visibility range 70 m.
  - Grows only where `growth_at()` allows: off paths, props, liquids, cloud steps and the plaza.
  - Heaven gets ~3300 plants, about 0.1-0.2 s to build.
- Satellites: in DROP_DOWN themes, 1-2 small islands on the side away from the rift, each joined by
  a 4.5 m cloud path. Cloud platforms are laid along the path with tops at y = 0. The ground under
  the path keeps falling away; the path is walkable and nav-reachable.
- `ScorchTrail.new()`: cloven hoofprints every 0.75 m of player travel, alternating sides. They
  glow ember-hot, cool to a red rim, then fade to char over 18 s. One MultiMesh, a 96-print ring
  buffer, one uniform per frame. TerrainMap adds it automatically. **Any map or the hub can add
  one** (`add_child(ScorchTrail.new())`).

## Scatter
- Placement: `Scatter.poisson(...)`, `Scatter.jittered(...)`,
  `Scatter.place(parent, points, {name: weight}, rng, collide, height_fn, scale_range)`,
  `Scatter.build_any(name, rng, collide)`.
- Batching: `Scatter.merge(root, tile)`.
  - Meshes shared by 3 or more instances in a tile (cached variants, Props models) become one
    `MultiMeshInstance3D`; the rest are merged per (tile, material).
  - Visibility ranges are set on everything it creates.
  - Patch scatter went from 150-400 ms to 40-70 ms.

## Maps: TerrainMap, The Gilded Isles, The Breach
JSON: `"generator": "res://scenes/terrain/terrain_map.gd"` and
`"terrain": {"theme", "size", "arena_radius", "landmarks", "corruption"}`.

TerrainMap:
- Builds the patch under `scenery` and sets bounds from `play_radius()`.
- Mirrors `blocker_rects` and every prop collider (real shapes) into the nav grid.
- Hides the stock `ground` plane.
- Places per-theme landmarks (`TerrainMap.LANDMARKS`), all required objective kinds and rim spawns.
- Moves any marker that ends up in a sealed pocket to the nearest reachable cell (`_finalize`
  override).
- Adds a ScorchTrail.
- Sets `Corruption.ambient` from `"corruption"`.

The maps:
- **The Gilded Isles** (`gilded_isles`): heaven, size 156, arena 40, 2 satellite islands, grass
  and flowers.
- **The Breach** (`the_breach`): theme `breach`, a heaven island torn open over hell's lava sea.
  - Holy props mixed with hell props, ember cracks, obsidian edge spires, 1 satellite island.
  - Corruption ambient 0.45, preset `the_breach`.
  - Landmarks: The Wound, Severed Wing, Toppled Gate, Pillar of Ash.
  - Unlock: 200 souls after gilded_isles. Difficulty 3.

## Basecamp: HellDressing
`HellDressing.around(area: Rect2, lava_y, seed)` places 60-90 visual-only pieces in the lava sea
2-16 m beyond the plateau: tall spires and basalt to the north and sides, only low pieces on the
camera side. They are batched per 24 m tile.

## Viewing / testing
- `godot --path . res://scenes/terrain/terrain_showcase.tscn -- --theme=breach --view=arena`.
  - Views: `--view=props|overview`.
  - Prop sets for the props view: `--set=holy|hell|site`.
  - Options: `--seed=N`, `--at=x,z`, `--zoom=f`, `--yaw=deg`, `--tshot=out.png`.
  - Controls: WASD pan, wheel zoom, Q/E orbit, R reroll.
- `godot --headless --path . --script res://tools/terrain/terrain_check.gd`: every prop (fresh
  vs cached cost), plus both patches.
- `godot --headless --fixed-fps 30 --path . res://tools/maps/map_check.tscn -- --map=the_breach --variants=3`.
- In game: `godot --path . res://scenes/main.tscn -- --map=the_breach --godmode`.

## Known issues / next steps
- Cliff shadows from a low sun are long; hell arenas read dark under neutral light (the presets tint
  them).
- `terrain_map.gd` (like every GameMap) needs the Game autoload: it compiles in full runs and
  map_check, not under `--script`.
- One liquid kind per patch. Cloud paths are straight-ish polylines (3 points).
- Ideas: drifting cloud platforms, a hell-basin run map with the `hell` theme, foliage
  push-away on more than 8 bodies, decals for wheel ruts along earth paths.
