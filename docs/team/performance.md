# Performance (role: FPS optimizer)

Owner of: `autoload/perf.gd` (autoload **Perf**), `scripts/perf/crowd.gd` (**Crowd**),
`scripts/perf/mote_trail.gd` (**MoteTrail**), `scripts/perf/skin_bake.gd` (**SkinBake**),
`scripts/perf/glb_skin.gd` (**GlbSkin**),
`tools/perf/*`, and this file. Everything else I touched is a small, commented edit in someone
else's file (listed below); the owning role is free to change it, just keep the perf intent.

## Debug overlay and keys

Debug builds (or any build started with `-- --perf`):

| Key | What |
|---|---|
| **F9** | toggle the overlay: FPS, frame time avg/max + 2 s graph, hitches (> 33 ms), CPU process / physics time, draw calls, objects, primitives, node + orphan count, world children, enemies, gems, live corpses, damage numbers, physics pairs, RAM / VRAM |
| **F10** | stress: spawn 300 enemies around the player (random types from the run's spawn rules) |
| **Shift+F10** | free every non-boss enemy at once (no deaths, no XP) |

`--perf` turns the overlay on at start. F1-F8 belong to other roles (main.gd, spawner, objectives,
atmosphere); please don't take F9/F10.

## Benchmarks and tools (`tools/perf/`)

```bash
tools/perf/bench.sh                         # 300-enemy in-game bench + roster table
tools/perf/bench.sh game 20 300             # seconds, enemy count [, experiments]
tools/perf/bench.sh roster seraph,archon    # spawn / death cost + node counts per enemy type
tools/perf/bench.sh profile 8 300           # bench under Godot's script profiler, top functions
python tools/perf/scan_hotpaths.py          # static scan: allocations / tree scans in per-frame code
```

- **In-game bench**: `godot --path . res://scenes/main.tscn -- --autopilot --bench=20 --stress=300`
  gives the player every weapon at max level, godmode, keeps 300 enemies alive (refilled as they
  die, so deaths are part of the load), unpauses level-up / dialogue pauses, then prints
  `[PERF] frames=.. avg_ms=.. fps=.. p99_ms=.. max_ms=.. process_ms=.. physics_ms=.. draw_calls=..`
  plus a node-count-by-class dump of `Game.world`, and quits. `--bench-out=file` appends the line.
  `--bench-exp=a,b` toggles A/B experiments per enemy: `noweapons nocollide noprocess hidemodel
  noanim noshadow nocrowd spawns listeners`.
- **Roster table** (`tools/perf/spawn_cost.tscn`, headless): warm spawn and death cost, nodes,
  meshes, AnimationPlayers and lights for every `data/enemies/*.tres`, flags types over budget.
- **Profiler**: `godot -d --profiling ...` makes Godot's local debugger print per-function script
  timings; `tools/perf/profile_top.py` sums them (self / total ms per frame, calls per frame).
- `call_cost.tscn` (per-call cost of animate / flash / slide / take_damage / die) and
  `crowd_cost.tscn` (300 packed bodies: physics collisions vs `Crowd` separation) are micro benches.

After adding a new `class_name` script, run `godot --headless --path . --import` once so the global
class cache knows it (otherwise headless runs fail with "Identifier not declared").

Wall-clock numbers are noisy while other Godot instances run (we often have 20+). Compare A/B runs
back to back, or use the profiler / micro benches, which are much more stable.

## Hot-path APIs for everyone

```gdscript
for n in Perf.enemies():              # group "enemies", fetched once per frame / physics step and
    var e := n as Enemy               # shared by all callers. Read-only, never sort / erase it.
Perf.budget(&"my_fx", 4)              # true for the first 4 calls this frame: cap bursts of FX/sounds
Perf.track(node, &"my_fx", 30)        # concurrency cap: false if 30 tracked nodes are alive
Crowd.query(pos, 6.0, out_array)      # enemies within 6 m via the separation grid (no group scan)
EnemyModel.set_lod(on)                # override to pause your model's extra per-frame work off screen
Art.flash_invalidate(model)           # after swapping parts / materials of a model that flashes
DamageNumber.active_count()  EnemyModel.corpses_alive()
print(Perf.dump_world())              # node counts by class under Game.world
```

## What I changed (with measurements)

Measured on an RTX 4070 Ti box that was running ~20 other Godot instances, so treat absolute
numbers as pessimistic. Before = state when I started.

| Fix | Where | Before -> after |
|---|---|---|
| `GlbModel` keeps every model `PackedScene` cached (a node doesn't reference its PackedScene, so each spawn re-parsed the .glb scene from disk) + memoised material conversion | `scripts/glb_model.gd` | wisp spawn 3.0 -> 0.5 ms, seraph sentinel 6.6 -> 1.0 ms, archon 11-16 -> ~2.5 ms |
| `ProcModel` merge cache never hit: keyed by node path, but unnamed pivots get unique `@Node3D@1234` names per instance. Now keyed by child-index path, so every instance shares the merged ArrayMeshes | `scenes/characters/proc_model.gd` | archangel spawn 27 -> 2.6 ms; procedural roster 4-8 -> 1.5-2.5 ms; shared meshes also batch better on the GPU |
| Procedural enemies are built + merged **before** entering the tree (`EnemyModel.ensure_built()`), merged-away parts are detached at once | `enemy_model.gd`, `enemy.gd`, `proc_model.gd` | the 40-80 throwaway parts per spawn never create render instances / node_added callbacks; nodes per proc enemy roughly halved |
| `Art.flash` caches the flashable meshes per model (was a full recursive walk every frame for every flashing enemy) | `scripts/art.gd` | 50-480 us -> 8-40 us per call |
| Death FX budget: at most 4 full bursts and 3 corpses start per frame, max 32 corpses alive; corpse copies (Blender models) are pooled and reused | `enemy_model.gd` | death 1-8 ms -> 0.2-0.5 ms (elites always get the full show) |
| Damage numbers pooled (Label3D reuse) | `scripts/damage_number.gd` | no node churn per hit |
| `InfernalFx.burst` emitters pooled, max 48 alive / 8 new per frame | `scenes/weapons/infernal_fx.gd` | no CPUParticles3D allocation per hit |
| **Crowd separation** replaces enemy-vs-enemy physics collisions (enemies keep colliding with the world). One grid solve per tick (every other tick above 120 enemies) | `scripts/perf/crowd.gd`, `enemy.gd` | 300 packed enemies: ~16-19 -> ~10 ms per physics tick |
| Off-screen LOD: a `VisibleOnScreenNotifier3D` per enemy; off screen the model's AnimationPlayer + CharacterMotion pause, `animate()` is skipped, and walking enemies further than 9 m think every other tick (delta folded in) | `enemy.gd`, `enemy_model.gd` | static-crowd test: animation cost 18 -> 9 ms/frame; AI+physics of the off-screen half halved |
| Shared enemy list (`Perf.enemies()`) in Targeting, foliage pushers, game feel, chain, cleave, ability combat, minimap; `_allies_within` uses `Crowd.query` | various | fewer 300-element array copies per frame; ward/heal ally scans ~350 -> ~50 us |
| Minimap dots drawn as rects (draw_circle tessellates per call) | `ui/components/minimap.gd` | 3 ms -> 0.25 ms per redraw at 300 enemies |
| Projectile trails (holy orb, holy bolt) were a new MeshInstance3D + tween every 0.05-0.06 s per projectile; now one world-space particle trail each (`MoteTrail.attach`) | `holy_orb.gd`, `holy_bolt.gd` | ~16 node create/free per second per projectile -> 0 |
| `Enemy._summon_ai`: typed-array assignment and typed lambda on freed summons spammed errors every attack | `enemy.gd` | fixed (`assign()`, untyped lambda param) |

Overall (300-enemy bench, all weapons maxed, same busy machine): ~180 ms/frame (5.5 fps) ->
~67 ms (15 fps); 200 enemies ~43 ms; script time per frame ~73 -> ~25-35 ms. With the machine to
itself expect roughly 2-3x better. The rest is engine-side (render instances, transforms,
animation; see below), i.e. content structure rather than code.

## Round 2 (render instances, hitches, gate)

Measured with `tools/perf/ab.sh` (interleaved runs, medians) and the profiler; the box had 8-25
other Godot instances running, so read the deltas, not the absolute numbers.

| Change | Where | Effect |
|---|---|---|
| **SkinBake**: horde ProcModel types fold all static parts into 1-2 skinned meshes, one rigid bone per registered pivot; bones copied from the pivots each animate tick; meshes + Skin shared per type | `scripts/perf/skin_bake.gd`, `proc_model.gd` (`SKIN_BAKE_TYPES`, marked) | cherub 13 -> 2 instances, ophan 18 -> 3, villager 8 -> 2, holy_knight 6 -> 1. Proc-horde wave of 300: render CPU 8.9 -> 5.8 ms, frame 24.8 -> 19.2 ms (median of 4) |
| Off-screen enemies hide their whole model (on-screen box padded 3 m for long shadows) | `enemy_model.gd` `set_lod`, `enemy.gd` | no render / shadow instances for the spawn ring; ~7 % in the standard bench (most of a crowd is on screen) |
| Round 1 + 2 together vs round-1 state on the standard mixed bench | | 103 -> 83 ms median on a loaded box (-20 %) |
| Shader / pipeline warm-up now actually runs: `Warmup` lived only in the unused title scene; Perf starts it on the demon-select screen and in Basecamp, and it now also builds one of every `data/enemies` model (proc builds, skin bakes, holy rim, elite outline) | `perf.gd`, `scenes/menu/warmup.gd` (marked) | ~150 models / 53 shaders warmed in ~8 s in the background before the first run |
| Icons background-loaded at the same time | `perf.gd` | no lazy icon loads on the first level-up / shop card |
| Objective type scripts background-loaded at run start | `objective_director.gd` `_prewarm_scripts` | no 3-5 ms compile hitch when a new objective type first appears |
| Level-up menu builds one invisible card set 1.5 s into a run | `level_up_menu.gd` `_prewarm` | first open was ~40 ms (fonts / styles on first use); later opens ~1 ms, so caching the cards would not have helped |
| Elite death: counts x2 instead of x3 and capped, feathers + debris start the next frame | `enemy_model.gd` `death_burst` | archon death 8.5 -> 4.6 ms, split over two frames |
| New code moved off `get_nodes_in_group("enemies")`: `ProcModel.enemies_near` (Crowd grid), ally minions, sanctified elites, profane ground, music manager (was scanning every child of the world) | various, marked `perf` | |
| QA gate: `perf_gate` (headless `--fixed-fps 60`, 300 enemies, fail > 25 ms; today ~9.5 ms) and `perf_roster` (fail > 8 ms spawn or > 80 meshes per type) | `tools/qa/run_all.sh`, `perf.gd --bench-gate`, `spawn_cost.gd --gate` | |
| Render CPU / GPU time in the overlay and bench (`render_cpu_ms`, `render_gpu_ms`) | `perf.gd` | |

Enemy shadows on Low / Medium are owned by visuals (`AtmoEvents._update_enemy_shadows`, off below
the High preset); I removed my duplicate so the two don't fight over `cast_shadow`. Props already
have visibility ranges (terrain `PropKit.VIS_RANGE`); decor chunks only exist around the player.

### Tools added in round 2
- `tools/perf/ab.sh <runs> <enemies> <secs> "exp,a" "exp,b"` interleaved A/B with medians.
- `--bench-exp=` new switches: `noskinbake allskin nolodhide nointerp fewmeshes modelnointerp`.
- `tools/perf/skin_compare.tscn` (merged vs baked side by side), `model_tree.tscn` (node dump of an
  enemy), `die_cost.tscn` (death cost per type, profiler-friendly).
- The bench quits itself (`[PERF] TIMEOUT`, exit 3) if it never finishes.

### Next big wins (proposals)
- (done in round 3: Blender horde types skinned by GlbSkin, decor streaming sliced.)
- Elites / bosses with CharacterMotion (archon, bosses) are still node rigs; converting them needs
  CharacterMotion to offset bones instead of joint nodes (characters-polish).

## Round 3 (Blender horde skinning, interpolation, decor streaming)

| Change | Where | Effect |
|---|---|---|
| **GlbSkin**: the six Blender horde types (seraph_sentinel, choir_wisp, dawn_lancer, ophanim, penitent_statue, thurible_priest) are converted when loaded: every joint becomes a bone of one Skeleton3D, every part one skinned mesh, and the clips are retargeted from node tracks to bone tracks, so the AnimationPlayer drives the skeleton natively. Built once per model file, shared | `scripts/perf/glb_skin.gd`, `GlbModel.setup` / `joint()`, `EnemyModel.glb_node()` (marked) | seraph sentinel 60 nodes / 24 meshes -> 11 / 1; ophanim 26 -> 1, wisp 10 -> 1. 300 enemies without weapons 41.6 -> 29.1 ms, standard bench 59.4 -> 46.4 ms (medians of 3) |
| Visual check of the conversion: identical poses in idle / walk / fly / attack for all six | `tools/perf/skin_compare.tscn -- --types=<id> --anim=<clip> --row=0/1` | |
| Physics interpolation per enemy: with interpolation off for enemies only, 43.7 -> 35.4 ms before GlbSkin, but **28.6 vs 29.1 ms after it** (the cost was the node count). Interpolation stays ON for everything, no 30 Hz stutter | measured with `--bench-exp=enemynointerp` | not needed |
| Sanctum decor streaming is time-sliced: chunks build over several physics ticks (2.5 ms per tick), and every prop kind is prebuilt when the decor starts (also in the menus) | `scenes/world/decor.gd` (marked), `Perf.prewarm_props_now()` | longest uninterrupted chunk work 41 ms -> 6-8 ms; the 6-46 ms first-use builds per prop kind moved to load time |
| Decor fix found on the way: lights of freed chunks were read for up to 0.25 s ("previously freed instance" errors) | `decor.gd` `_process` | |
| perf_roster hard limits tightened to 5 ms spawn / 60 meshes (worst today 1.7 ms / 49); perf_gate stays at 25 ms (headless baseline still ~7-10 ms: GlbSkin mostly saves render-side work) | `spawn_cost.gd`, `run_all.sh` | |

GlbSkin rules for model code: joints are bones, so use `EnemyModel.glb_node(name)` /
`GlbModel.joint(name)` (a BoneAttachment3D that follows the bone) instead of `find_child` on
`scene_root`; value tracks on joints (e.g. visibility) are dropped by the conversion. CharacterMotion
is only attached to models of size >= 1.5, which none of the converted types are. Add a model to
`GlbSkin.TYPES` after checking it with skin_compare; remove it to opt out.

## Budgets / guidelines (please follow)

**Per enemy type** (check with `tools/perf/bench.sh roster`):
- Spawn < 1.5 ms warm. Build geometry once and share it (`ProcModel.finish()`, cached meshes and
  materials via `Art.mat` / `Art.glow`); never `load()` or create materials per spawn.
- <= 30 MeshInstances, 0 lights for regular enemies (lights only on elites/bosses, small range,
  no shadows). Every mesh node is a render instance and a transform to update each tick.
- Keep `build()` independent of the scene tree (no `get_tree()`, `global_*`, `Game.*`): procedural
  models are built before they enter it.

**Per frame code**:
- Never call `get_tree().get_nodes_in_group(&"enemies")` in `_process` / `_physics_process`; use
  `Perf.enemies()`, `Targeting.*`, or `Crowd.query()` for "who is near me".
- No `load()`, `X.new()` of materials / meshes / nodes, `instantiate()`, `duplicate()` or string
  formatting in per-frame paths. Cache in `static var`s keyed by the parameters (see `Art.glow`).
- Throttle UI and polling (10-15 Hz is plenty for minimaps, nearest-target searches, HUD text).
- Don't call setters that propagate transforms (position, rotation, scale) on deep model trees when
  nothing changed.

**Spawned effects**:
- Anything that can fire per hit or per death needs a cap: `Perf.budget(&"key", n)` per frame
  and/or a fixed pool (see `CombatVFX`, `InfernalFx.burst`, `DamageNumber`, corpse pool).
- Particles: `CPUParticles3D` one-shots should be pooled; scale `amount` by
  `Settings.particle_density`; no shadows on particles / glows (`Art.no_shadows`).
- Trails behind projectiles: `MoteTrail.attach(self, material, size, lifetime, every, sink)` -
  one particle system, never a node per mote.
- Pooled nodes live in `Game.world` so they are freed with the run; check
  `p.get_parent() == Game.world` before reuse (pattern in `damage_number.gd`).

**Physics**:
- Enemies are on layer 3 and do NOT collide with each other (mask = world only) - `Crowd.push()`
  separates them. Don't add physics bodies per projectile when an `Area3D` with a small shape
  will do, and keep monitorable/monitoring off where not needed.

## Hotspots reported by other roles (owner fixes; numbers from their docs)

| Cost | Owner / details | Notes |
|---|---|---|
| Map flow-field BFS rebuild: 1.5-2.5 ms every 0.2 s (radius 140 cells) | maps (`scenes/maps/game_map.gd`, docs/team/maps.md) | periodic hitch, not per frame. Ideas: rebuild only when the player changes cell (already partly), smaller radius, or spread the BFS over several ticks / run it on a WorkerThreadPool task with a double-buffered `_dist`. Per-enemy `Maps.steer()` itself is cheap (5 grid lookups). |
| SFX startup synthesis | sfx (`autoload/sfx.gd`) | runs on a worker thread and is now cached on disk; it only competed for CPU in the first seconds after boot. My perf tools wait for it before measuring. |
| Atmosphere presets: ~0.05 ms GPU on Low, ~0.2-0.6 ms High/Ultra (volumetric fog and particle layers are the biggest) | visuals (docs/team/visuals.md, `tools/atmo_bench.sh`) | scales with Settings; fine. |
| Corruption / blight shading: ~0.2 ms (player trail) to ~0.4 ms (whole screen) GPU at 720p on a 4070 Ti, a few ms at 1080p on low-end GPUs | art-style (docs/team/art-style.md section 3, `tools/style_perf.tscn`) | `Corruption.quality` follows the preset (Low = crust only). |

For context: at 300 enemies the frame is CPU-bound (scripts + render instance/transform work), so
these GPU items don't matter there; they matter on weak GPUs with few enemies.

## Known issues / next steps

- **Node count per enemy is the main remaining cost**: Blender node-rig enemies are 25-60 mesh
  nodes, each moved and culled separately; at 300 enemies that's ~7000 render instances and ~5000
  draw calls. Biggest future win: skinned single-mesh exports (one MeshInstance + Skeleton per
  enemy) or merging static sub-meshes per joint at import. (art / characters roles)
- Moving a CharacterBody3D with a deep model costs ~10 us in transform propagation alone; a
  fully custom (non-physics) mover for enemies on open maps would remove `move_and_slide`.
- `LevelUpMenu.open` costs ~5-15 ms (UI build each time; could reuse the cards). (UI role)
- `ObjectiveDirector._script_for` loads objective scripts lazily at run time (~3-5 ms hitch the
  first time each type appears): preload them at run start. (objectives role)
- Elite deaths still cost 3-5 ms (full burst x3, shockwave material per call, chalice drop).
- Enemy shadows: every enemy part casts into 2 directional cascades. Turning enemy shadows off on
  Low/Medium graphics presets would roughly halve draw calls in big waves. (visuals role: DONE in
  round 3: `AtmoEvents._update_enemy_shadows` sweeps group `enemies` twice a second and switches
  `cast_shadow` off on Low/Medium, restoring each mesh's own mode on High/Ultra; live with settings.)
- The HUD/abilities `_synergy_met` runs ~700x per frame (cheap now, worth caching).

## Maps: flow field (maps role, round 3)
`GameMap` (scenes/maps/game_map.gd) rebuilds the enemy flow field ONLY when the demon changes nav cell
(1.5 m), and time-slices the BFS into a back buffer (`FLOW_BUDGET` = 1500 cells per physics tick,
swapped in when complete; a cold / very stale field is built at once). Measured by
`tools/maps/map_check.tscn`: a full rebuild was 1.4-2.6 ms in one tick; now it is 2-5 ticks at a
worst 0.5-0.7 ms each, with no work at all while the demon stands still in a cell.
`steer()` per enemy is a handful of grid lookups (no allocation).

## From terrain (round 2)
- `PropKit.build()` now instances cached variants (6 per prop, PackedScene): 10-140 us per prop vs
  1-32 ms fresh (`tools/terrain/terrain_check.gd` prints both). Breakable / runtime-spawned scenery
  can use it freely; `PropKit.build_fresh()` is the slow unique path.
- Shared meshes per variant let `Scatter.merge()` emit MultiMeshInstance3Ds (>= 3 instances per
  24 m tile) instead of copying vertices; prop meshes carry `visibility_range_end` 110 m, foliage 70 m.
- `TerrainFoliage` (grass / flowers on terrain maps): static MultiMesh per (tile, type), no shadows,
  ~3300 instances on the Gilded Isles; push-away uses `Perf.enemies()` every other frame.
- `ScorchTrail`: one MultiMesh (96-instance ring buffer), one uniform write per frame.
