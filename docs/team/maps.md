# Map design (docs/team/maps.md)

Status: round 3 landed (see "Round 3" below). Data-driven map registry (`Maps` autoload), `GameMap` base class (bounds,
colliders, nav flow field, markers, per-run variety, interactables, hazards), a run-time loader in
`main.tscn`, the endless sanctum plus **seven** hand-laid bounded maps (and the terrain role's
`gilded_isles` generator map), the Seventh Gate finale, and a headless checker.

## Owned files
| Path | What |
|---|---|
| `autoload/maps.gd` | Autoload **`Maps`**: registry, selection, live-map facade + spatial helpers |
| `data/maps/*.json` | One file per map definition (schema below) |
| `scenes/maps/game_map.gd` | `class_name GameMap`: base class every map extends |
| `scenes/maps/map_loader.gd` | Node `Main/Map` (in `scenes/main.tscn`, before Ground/Atmosphere/Player/EnemySpawner) |
| `scenes/maps/<id>/*` | outer_gardens, cathedral_city, frozen_monastery, sunlit_citadel, ashen_wastes, storm_spire, heavens_gate |
| `scenes/maps/features/*` | Interactables + hazards: `MapInteractable`, `HolyFont`, `SummoningBell`, `MapStatue` (+ model), `SeventhGate`, `LightningStorm`, `SweepingBeam`, `FissureField` |
| `tools/maps/map_check.gd/.tscn` | Headless validator: reachability, anchors, physics agents, nav PNG, probes |

Shared-file edits (all small and marked): `project.godot` autoload `Maps`; `scenes/main.tscn` node
`Map`; `scenes/enemies/enemy.gd` (`Maps.steer()` for the move direction, `_aim` kept separate for
facing / shots / attack lanes, the un-stick nudge, `Maps.spawn_position()` in `_relocate`);
`scenes/spawner/enemy_spawner.gd` (`Maps.spawn_position(pos, is_nan(angle))`, `Maps.clamp_to_bounds()`
for the boss); `autoload/run_state.gd` (`# [maps]` `map_difficulty_minutes()` in `_minutes()`).

## Maps
| order | id | Bounds | Layout idea | Hazard / interactables | diff (+min) |
|---|---|---|---|---|---|
| 0 | `ruined_sanctum` | endless | the original streamed Decor field | - | 1 (+0) |
| 1 | `outer_gardens` | circle r62 | two hedge rings with offset gaps around the Gilded Tree | 2 holy fonts, choir bell, 4 saints | 1 (+0) |
| 2 | `cathedral_city` | rect 140 | 4x4 street grid, cathedral + plaza, house blocks with alleys | 2 fonts in the plaza, bell-tower bell, 5 saints | 2 (+0.35) |
| 3 | `frozen_monastery` | polygon | rock spurs + pine groves form lanes, frozen lake, cloister | cloister bell, a font, 4 frozen saints | 3 (+0.75) |
| 4 | `sunlit_citadel` | circle r66 | two ramparts, offset gates, Sun Spire core | **SweepingBeam** from the Spire over the core, 2 fonts, war bell, 6 gilded angels | 4 (+1.0) |
| 6 | `ashen_wastes` | polygon | two lava rivers, two fords each (never aligned), angel war camp | **FissureField** (vents erupt: angels burn, demon singes), war bell, font, statues | 4 (+1.4) |
| 7 | `storm_spire` | circle r64 | three tiers, two stairs per tier, each ring turned 90 degrees: a spiral climb | **LightningStorm** + lightning rods (bolts near a rod hit the rod and arc through angels), 2 bells, font, statues | 5 (+1.6) |
| 8 | `heavens_gate` | rect 90x150 | cloud terraces with zig-zag openings up to the Seventh Gate | **SweepingBeam** x2 from the gate towers, 3 Gate Wards, fonts, bell; the **finale** | 5 (+1.75) |

Every bounded map provides objective anchors of kinds **`altar`** (3+), **`ritual`** (2+), **`relic`**
(1+) and **`boss_arena`** (1, a big open area). The checker enforces it.

### Per-run variety
`GameMap.rng` is seeded from `(seed, variant_seed)`; `variant_seed` is random every run (`"variety":
false` in the JSON pins it; dev `--map-seed=N` reproduces one). Each map keeps its identity but rolls:
gardens (outer-gate swing, inner gate set, pool / font / parterre slots, terrace set pieces shuffled),
city (graveyard / market / bell tower cells, house blocks, fires, fonts, saints), monastery (lake and
stone circle swap sides, 4 of 6 rock spurs, grove drift), citadel (whole fortress turned by 90-degree
steps: inner gates, barracks, yard, reliquary move), ashen (ford positions, ballista side, vents),
storm spire (stair angles, rods, bastion), heaven's gate (terrace openings, ward plinths, statues).
Helpers: `pick_one(arr)`, `shuffled(arr)`.

### Interactables and hazards (`scenes/maps/features/`)
- `HolyFont`: while pure, heals angels within 7 m every 6 s. Stand in it 3 s to corrupt it: hellfire
  burst (60 to angels), the demon heals 25, then it burns angels that wander in.
- `SummoningBell`: stand under it 1.5 s: it tolls, spills 6 Ichor and calls a ring of 10 angels from the
  map's pool. Cooldown 75 s.
- `MapStatue` (an `Enemy`, group `enemies`, layer 3): weapons break it; hellfire burst, XP, Ichor.
  Variant `ward` = Gate Ward (sturdier, emits `destroyed`).
- `LightningStorm`, `SweepingBeam`, `FissureField`: see the class headers; tunable per map with the
  JSON `"hazards"` block (`{"lightning": {...}, "sweeping_beam": {...}, "fissures": {...},
  "seventh_gate": {...}}`, any exported property).
- All interactables extend `MapInteractable` (group `map_interactables`, signal `activated(feature)`,
  `radius`, `channel_time`, `cooldown`, `progress`).
- GameMap helpers: `font(pos)`, `bell(pos, rot)`, `statue(pos, variant, rot)` (spawned into
  `Game.world` once the run is live; signal `statue_spawned(statue)`), `hazard(node, pos)`,
  `tune(node, key)`.

### The Seventh Gate finale (heavens_gate)
`SeventhGate` opens when its 3 Gate Wards are broken and `bosses_required` (1) bosses fell this run.
Then the demon stands in the doorway for 4 s, which calls `RunState.end_run(true, &"seventh_gate")`.
The story role turns that cause into the ending. It requires the Dialogue flag `known.march`. Without
the flag the doors stay shut and the Gate shows a hint and pays 30 Ichor. The map's unlock also asks
for that flag (Progression `story` gate). Objectives keep Final Judgement as a fallback win there at
4 bosses (`"objectives": {"settings": {"victory_bosses": 4}}`). Dev: `--gate-open` skips the story
check; `--gate-selftest` runs the whole finale automatically and prints `GATETEST` lines.

## Navigation
Nav grid of 1.5 m cells; obstacles inflated 0.7 m (gaps under ~1.4 m close for enemies); unreachable
pockets sealed. A BFS flow field is built from the player's cell every 0.2 s (radius 140 cells,
~1.5-2.5 ms). `steer()` goes straight when the field says nothing is in the way: the BFS distance
equals the Manhattan distance, and an enemy-sized body clears the next 3 m. Otherwise it heads for
the centre of the best neighbour cell, smoothed by the field gradient. Enemies keep a separate `_aim`
straight at the player for facing, shots, charge and slam lanes, so steering never skews an attack.
**Un-stick**: a walker that pushes but barely moves for 0.5 s next to a wall gets
`Maps.unstick()`, a short nudge to the best open cell centre. Crowd jams are ignored.
`map_check` runs 24 physics capsules with the same steering and nudge per map variant: currently
24/24 arrive within 40 s on every hand-laid map.

## Camera rules
The camera looks north from the south. Tall pieces go on the north edge, and south-side dressing
stays low and outside the bounds. Map materials are private copies of the lit_static materials with a
wide occluder hole (`FADE_RADIUS` 0.2 vs 0.07 for shared decor), fed the player position every frame
by the GameMap. Walls, towers and houses between the camera and the demon dither away around it.
`--map-overview` uses its own clean camera Environment and hides the full-screen post layers, so the
Atmosphere fog and grade no longer wash it out.

## Registry schema (`data/maps/<id>.json`)
Missing keys get defaults (`Maps.DEFAULTS`). Colours are `[r, g, b]` or `"#hex"`.
```
id, name, subtitle, description, order (sort), realm, biome, difficulty (1-5), tags[]
difficulty_minutes  RunState plays this map as if that many extra minutes had passed (HP/dmg/speed)
scene        res:// .tscn whose root extends GameMap      (or)
generator    res:// .gd extending GameMap                 (neither = open endless field)
seed         layout seed (0 = random);  variety: false pins the per-run variant
decor        "sanctum" keeps Main/Decor (endless scenery), anything else removes it
atmosphere_preset   preset for the Atmosphere autoload (visuals), default = id
music, music_fallback   track ids (MusicManager)
ambience     free key for the audio worker
weather      {particles: "snow"|"petals"|"motes"|"embers"|"", particle_amount}
unlock       {default, cost, requires, + Progression keys (see below)}
spawner      {EnemySpawner property: value}  e.g. base_rate, rate_growth, surge_rate, ring_base, boss_time
hazards      {lightning|sweeping_beam|fissures|seventh_gate: {exported property: value}}
objectives   {settings, include, exclude, weights}  (objectives role)
enemy_pool   [{enemy, start, end (-1 = never), weight}];  elite, boss
env          fallback lighting (used when no Atmosphere preset applies)
ground       {ground.gdshader uniform: [r,g,b] | number}
portal       {color: [r,g,b], glyph}
```

## API (`Maps` autoload)
- Registry: `all()`, `ids()`, `has_map(id)`, `get_def(id)`, `selected_id`, `selected_def()`,
  `select(id)`, `start_run(id = &"")`, `reload()`, `enemy_pool(id)`, `portal_color(id)`,
  `load_enemy(key)`, `load_boss(key)`, `color_of(v)`.
- Signals: `map_selected(id)`, `map_loaded(map, def)` (deferred), `map_unloaded(id)`.
- Live: `current_map` (GameMap), `current_def`.
- Spatial (safe any time): `steer(from, dir)`, `unstick(from, dir)`, `spawn_position(ideal,
  allow_authored = true)`, `clamp_to_bounds(pos)`, `is_walkable(pos)`, `random_point(around, min, max)`,
  `landmarks(tag)`, `objective_points(kind)`, `enemy_spawn_points()`, `player_spawn()`.
- Markers: Marker3Ds in groups `map_landmark` (meta id / display_name / radius / tag),
  `map_objective` (meta kind / id), `map_enemy_spawn`. Fire props are in group `braziers`.
  `GameMap.landmark_discovered(id, name, marker)`.

## Making a new map
1. `scenes/maps/<id>/<id>.gd` `extends GameMap`: bounds in `_init()`, override `_build_layout()`
   (and `_dress_boundary()`).
2. Helpers:
   - Primitives: `box / cylinder / sphere / torus / prism / disc / wall` (`solid` = collider + nav).
   - Props: `prop(kind, ...)` takes any Props or PropKit name. `kit(kind, pos, rot, scale, solid)`
     builds a PropKit prop without its own collider and adds a footprint nav blocker.
   - Lights and fire: `light`, `flame`.
   - Scatter: `scatter`, `scatter_rect`.
   - Markers: `set_player_spawn`, `landmark`, `objective`, `enemy_spawn`.
   - Features: `font`, `bell`, `statue`, `hazard`, `tune`.
   - Variety: `pick_one`, `shuffled`.

   Use `rng` for every random choice.
3. A 3-line `.tscn` and `data/maps/<id>.json`.
4. Run `godot --headless --fixed-fps 30 --path . res://tools/maps/map_check.tscn -- --map=<id>
   --variants=3 --png=<dir>`; it must say OK. Debug a spot with `--probe=x,z` (grid and flow
   around it) or `--trace=x,z` (one physics agent's path).
   Visual: `main.tscn -- --map=<id> --godmode --shot=x.png --shot-time=8 [--map-overview] [--map-seed=N]`.

## Hooks for other roles
- **Basecamp / Meta / Progression**: `Maps.all()/select()/start_run()`; unlock data in each JSON.
- **Objectives**: anchors via `Maps.objective_points(kind)`; `RunState.end_run(true, &"seventh_gate")`
  comes from the map's SeventhGate. Bell rings and font corruptions are `MapInteractable.activated`
  signals (group `map_interactables`) if you want to count them as objectives.
- **Story**: the Seventh Gate ends the run with cause `seventh_gate` on `heavens_gate`; see the request
  in docs/team/story.md (move `ending_rule.map` to `heavens_gate`, or raise its `boss_kills`).
- **Visuals**: presets used are `sanctum_dusk`, `outer_gardens`, `cathedral_city`, `frozen_reliquary`,
  `sunlit_citadel`, `ashen_wastes`, `storm_spire`, `heavens_gate` and `gilded_isles` (visuals pointed
  `gilded_isles.json` at its own new preset: cloud wisps over the rift, cycling into a soft holy rain;
  `sunlit_citadel` now has its own high-noon look too). `LightningStorm` calls
  `Atmosphere.strike_lightning(at, 0.15, false)` (bolt + flash lights, no extra sound; added by
  visuals). Each preset can flavour the run's storm with a `run_storm_local` overlay
  (rain in the city, blizzard in the monastery, ash storm in the wastes); see docs/team/visuals.md.
- **Gameplay**: `RunState.map_difficulty_minutes()`; see the note in docs/team/gameplay.md.
- **Music**: new keys `battle_wastes`, `battle_spire` and `battle_gate` fall back to existing tracks.

## QA notes (from docs/team/qa.md)
- `--map=<id>` was silently overridden: `Meta._sync_map()` (deferred, after `Maps._ready`) re-selected
  the saved map. Fixed by QA in `autoload/meta.gd` (`# QA:`): the dev arg now wins for the session.
  `tools/qa/flow_smoke.gd -- --autopilot --map=<id>` asserts it.


## Note from progression (round 2): map gating
Map `unlock` blocks accept extra optional keys, evaluated by `Progression.map_gate(id)` and enforced by
`Meta.map_requirement()` / `unlock_map()`:
`"progress": {"stat": "<Progression stat>", "min": N, "hint": "text"}`, `"cleared": "<map id>"` (a boss slain
or a run won there), `"mastery": N` (any demon), `"story": "<Dialogue flag>", "story_hint": "text"`.
I set: Cathedral City (default false, 60 Souls, 2 runs), Gilded Isles (+3 relics found), Frozen Monastery
(+1 boss slain), Sunlit Citadel (+conquer the Monastery, mastery IV). Per-map stats:
`Progression.map_stats(id) -> {runs, victories, bosses, best_time}` (from `Maps.current_def` at run end).
- (QA, open) `heavens_gate` kills a fresh autopilot demon at ~37-49 s (100+ enemies, no kills in the
  first ~30 s); fine only if the finale is gated behind progression. `map_check` now takes > 10 min
  on a loaded machine (9 maps x 2 variants, 40 s agent sims); a `--fast` mode would help the suite.

## Note from the objectives role (round 2)
- heavens_gate: when the Seventh Gate's last ward breaks, the ObjectiveDirector summons Azrafel
  (`gate_archon`) and raises the Gate's `bosses_required` to (bosses killed + 1, +1 more if a boss is
  up), so the doors open on his death. Turn it off with `"objectives": {"settings": {"warden_always": false}}`.
- Per-map objective taste lives in `data/objectives/objectives.json` `map_preferences` (by type) and
  mid-run event weights in `data/objectives/events.json` `map_weights`; edit freely. New anchor kinds
  the round-2 objectives look for: `chapel` (bishop procession), `boss_arena`/`arena` (bell towers),
  `relic` (escort, coffer), `shrine` (font), `ritual` (carnage), `altar` (temptation).

## Round 3 (maps)
- **Statues are not angels**: `MapStatue.die()` no longer emits `Game.enemy_died` / bumps `Game.kills`
  (no "Angels slain", no kill-count objectives, no RunState drops); group `map_features` is subtracted
  from the spawner cap and `ObjectiveFX.spawn_enemy`'s cap (`# [maps]` edits).
- **Flow field**: rebuilt only when the demon changes nav cell, time-sliced (`FLOW_BUDGET` 1500 cells
  per tick) into a back buffer: worst tick 0.5-0.7 ms instead of a 1.5-2.6 ms spike every 0.2 s.
  See docs/team/performance.md.
- **Interactables in objectives**: objective type `interactables` (`profane_fonts`, `toll_the_bell`),
  see docs/team/objectives.md. **Minimap / overview**: interactables and landmarks are minimap markers;
  the overview draws interactables and statues (docs/team/ui.md).
- **Difficulty curve.** Probe: `tools/maps/balance_run.tscn` runs the autopilot bot with no godmode
  and prints one line per 30 s of game time (`-- --map=<id> --minutes=5`).
  - First pass: difficulty_minutes was far too steep. On Heaven's Gate the bot died at 83 s with 20
    kills, because the angels' HP head start outran a level-1 demon.
  - Tuned (difficulty_minutes / notes):
    - gardens 0: hedge gaps widened 7 -> 9.5 m, gentler spawns
    - city 0.35: lower base rate
    - monastery 0.75
    - citadel 1.0: Spire lance starts at 20 s
    - ashen 1.4: fissures 6 player damage, every 4 s
    - storm 1.6: lightning 13 to the demon / 38 to angels; it used to help the bot too much
    - gate 1.75: lances 8 damage, first at 30 s / 60 s; lancers from 30 s
  - Bot median survival with the final values, in s (3 runs each; > = the bot survived the cap):
    gardens ~230, city >160-300, monastery ~210, citadel ~185, ashen ~260+, storm ~100-300+,
    gate ~110.
  - The bot is very noisy (random level-up picks; it gets cornered in tight maps), so treat these as
    rough. A human-played pass should follow.
- Tests: `tools/maps/feature_check.tscn` (statue not a kill, fonts objective, bell summons),
  `tools/maps/map_check.tscn` (now also reports the sliced rebuild cost), `balance_run.tscn`.

## From terrain (round 2, docs/team/terrain.md)
- **18 new site props** for your swaps, all usable in `kit()` / `prop()` (cached variants, ~10-140 us):
  storm spire `lightning_rod`, `bell_tower_ruin`; ashen war camp `war_tent`, `siege_ladder`,
  `burned_cart`, `crucifix_pyre`, `weapon_rack`, `supply_crates`; monastery `prayer_flags`,
  `ice_pine`, `snow_cairn`; citadel `citadel_banner`, `sun_mirror`; Heaven's Gate `cloud_steps`,
  `colossal_door` (8 m wide, footprint 6); Breach `hell_rift`, `fallen_wing`, `corrupted_column`.
  Footprints: `PropKit.footprint(name)`. Build with `collide = true` and copy
  `TerrainMap._mirror_collision()` if you want the exact collider shapes in `_blockers`
  (door gaps stay open) instead of a footprint circle.
- New map **`the_breach`** (`data/maps/the_breach.json`, generator `terrain_map.gd`, theme `breach`,
  order 9, unlock 200 souls after gilded_isles). Retune the registry fields freely.
- `gilded_isles` now has satellite islands on 4.5 m walkable cloud paths (size 156, arena 40).
- `--map-overview`: props carry visibility ranges (110 m). Calling `PropKit.clear_visibility_ranges(map)`
  in `_overview_camera()` keeps them visible from the high camera.
- `ScorchTrail` (burning hoofprints) is on terrain maps; add `add_child(ScorchTrail.new())` to any
  GameMap if you want it everywhere.

## Difficulty knobs: who owns what (agreed by gameplay, round 3; reply in docs/team/gameplay.md)
To avoid double-tuning, each knob has one owner:
| knob | where | owner |
|---|---|---|
| global time curve: enemy HP / damage / speed per minute, boss HP per minute, heat weight, Ascension | `autoload/run_state.gd` exports | **gameplay** |
| global spawner defaults: `base_rate`, `rate_growth`, wave shape (`surge_*`, `lull_rate`, `build_rate_*`), ring defaults, `max_enemies` | `scenes/spawner/enemy_spawner.gd` exports | **gameplay** |
| per-map offsets: `difficulty_minutes`, the `"spawner"` block (overrides of the above), `enemy_pool`, `elite`, `boss`, hazards | `data/maps/*.json` | **maps** |
| enemy stats | `data/enemies/*.tres` | characters-new (gameplay retunes behaviour numbers) |
Rule of thumb: gameplay tunes the **ruined_sanctum** baseline (no overrides, `difficulty_minutes` 0);
maps express every other map *relative* to it. When gameplay moves a global default, it re-measures the
maps and posts the numbers here rather than editing the map JSONs; maps decides the per-map response.
Gameplay round 3 changed the globals: `base_rate` 0.8 -> 0.9, `rate_growth` 0.025 -> 0.028,
HP growth 0.25 -> 0.28 per minute (+0.025 m^2). Maps with explicit `base_rate` / `rate_growth`
overrides are unaffected by the first two. Per-map bot survival: see "Per-map pressure" in
docs/team/gameplay.md.

## Note from characters-new (round 4): signature enemies per map
Each map's `enemy_pool` now ends with its two signature enemies (only that map uses them):
frozen_monastery icebound_penitent + bell_ringer_monk, cathedral_city watch_pikeman + rooftop_archer,
outer_gardens thorn_guardian + hummingbird_cherub, sunlit_citadel sun_priest + golden_legionary,
ashen_wastes crusader_revenant + carrion_angel, storm_spire rod_acolyte + cloud_djinn, gilded_isles
mimic_reliquary + gilded_harpy, heavens_gate gate_warden + honour_guard. Start times 20 / 50 / 110 s
by tier; retune freely. (The cloud djinn re-forms behind the demon via `ObjectiveFX.walkable`.)
- (QA, done) `map_check` was slow only because its agent sim awaits physics frames in real time: run it with `--fixed-fps 60 --disable-vsync` (all 10 maps x 2 variants: ~12 min -> ~20 s). QA also added `-- --fast` (1 variant, 12 agents; ~9 s) to `tools/maps/map_check.gd` for `run_all.sh --quick`. Agent sim length stays 40 s: at 25 s agents get stranded on gilded_isles / the_breach.
- Measured per-map bot survival (gameplay round 3), table in docs/team/gameplay.md "Per-map pressure".
  Out of line with the ratings: ashen_wastes (3) 93-183 s (too hard), gilded_isles (2) 164-218 s
  (harder than cathedral_city), sunlit_citadel (4) 539-720+ s (too easy). Your call on the fix.

## Note from performance (round 3): sanctum decor streaming
`scenes/world/decor.gd` (Main/Decor, kept by the `ruined_sanctum` map) now builds streamed chunks
time-sliced (`SLICE_US` = 2.5 ms of work per physics tick, one chunk at a time; the initial ring is
still built at once during load) and prebuilds every prop kind in `_ready` (`_prewarm_kinds`,
`Perf.prewarm_props_now`). Longest uninterrupted chunk work went from ~41 ms to 6-8 ms. Edits are
marked `perf`. The light loop also skips lights of chunks freed since the last `_pick_lights()`.

## Round 4 (maps): retunes after gameplay's global spawner change
Applied gameplay's per-map pressure findings (docs/team/gameplay.md "Per-map pressure"):
- `ashen_wastes` (rated 3, was too hard): `difficulty` 4 -> 3, `difficulty_minutes` 1.4 -> 1.0,
  `base_rate` 0.95 -> 0.9, `rate_growth` 0.031 -> 0.03, `surge_rate` 2.3 -> 2.2, fissures every 4.5 s,
  dawn lancers from 45 s, flagellants from 40 s.
- `gilded_isles` (rated 2, harder than the city): `difficulty_minutes` 0 (explicit),
  `base_rate` 0.9 -> 0.8, `rate_growth` 0.028 -> 0.026, `surge_rate` 2.0, `ring_base` 7, early pool
  trimmed (cherub from 30 s at weight 3, pegasus 75 s, harpy 80 s, lamb 70 s, herald 110 s,
  gryphon rider 130 s).
- `sunlit_citadel` (rated 4, was too easy): `difficulty_minutes` 1.0 -> 1.5, `base_rate` 1.15,
  `rate_growth` 0.036.
Re-measured with `tools/maps/balance_run.tscn` (5 runs each, cap 480 s; median):

| map | median survival (s) |
|---|---|
| cathedral_city (2) | 201 |
| gilded_isles (2) | 290 |
| ashen_wastes (3) | 324 |
| sunlit_citadel (4) | 246 |

The cathedral_city figure is the reference from the same batch. The bot is bimodal: every map has
some runs that survive the cap and some that die at 100-200 s. So these are medians, not guarantees.
- `heavens_gate` cannot be reached early. `tools/maps/gate_lock_check.tscn` checks it read-only:
  - On a fresh unlock state the Gate is locked behind storm_spire (which needs sunlit_citadel, and so
    on down the chain), and it costs 600 Souls.
  - With storm_spire bought it still needs the story flag `known.march`.
  - Only the dev arg `--map=` bypasses this.
- (QA, open, minor) `tools/maps/feature_check.tscn` "breaking a statue is not a kill" is flaky: failed once (kills 0 -> 1) in the 00:13 suite run and passed 3/3 alone. Most likely a spawned angel died to the same blow or to the weapon. Pause the spawner / count kills only from the statue.
- (QA, round 3, done) `tools/maps/feature_check.gd` statue check made deterministic (`# QA:`): spawner paused, demon weapons disabled, all non-statue enemies freed, then it counts `RunState.enemy_killed` events whose data is the statue's (plus `Game.kills`); spawner and weapons are restored for the font / bell checks. 5/5 consecutive runs PASS.
