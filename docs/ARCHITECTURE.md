# DemonCore architecture

DemonCore (window title "SINBOUND") is a 3D Vampire-Survivors-style roguelite in Godot 4.7.
You play a demon; the enemies are angels and other holy forces. Everything is authored as text:
GDScript, `.tscn`/`.tres`, shaders and JSON. Models are built procedurally in code or by the
Blender scripts in `tools/blender/` (outputs in `assets/models/`), audio is synthesized at startup.

Coding conventions live in [`docs/team/code-quality.md`](team/code-quality.md) (CODE_STYLE); the
how-to for running, testing and adding content is [`docs/CONTRIBUTING.md`](CONTRIBUTING.md).
Each feature owner documents their API in `docs/team/<role>.md`; this file is the map that ties
them together. Keep it short and update it when you add a top-level system.

---

## 1. Scene flow

```
title.tscn ──> demon_select.tscn ──> basecamp/ (Basecamp Hell hub, shopkeepers, portal)
                                          │  Meta.start_run()
                                          v
                                     main.tscn (a run)
                                          │  RunState.end_run() -> game over / victory
                                          v
                              RunState.return_to_basecamp()  ──> basecamp
```

- `project.godot` `run/main_scene` is the entry screen (currently `scenes/menu/demon_select.tscn`).
- `scenes/menu/warmup.gd` (`Warmup`) pre-compiles shaders behind the menus so the first run
  does not stutter.
- A run is `scenes/main.tscn`; `scenes/main.gd` resets the global state (`Game.reset()`,
  `RunState.start_run()`), wires the player to the UI, advances `Game.elapsed` while
  `RunState.active`, and opens the end screen on `RunState.run_ended`.

## 2. The run scene (`scenes/main.tscn`)

| Node | Script | Role |
|---|---|---|
| `WorldEnvironment`, `Sun` | – | Lighting; tuned at runtime by `Graphics` and the weather/atmosphere systems |
| `Map` | `scenes/maps/map_loader.gd` | Builds the selected `GameMap` (from `Maps`) under itself (see maps.md) |
| `Ground` | `scenes/world/ground.gd` | World-space shaded plane that follows the player |
| `Decor` | `scenes/world/decor.gd` | Streams visual-only scenery chunks (uses `Props`) |
| `Atmosphere` | `scenes/world/atmosphere.gd` | Fog, motes, fade-focus around the player |
| `Entities` | – | `Game.world`: parent of everything spawned at runtime |
| `Player` | `scenes/player/player.gd` (`Player`) | The demon: stats, XP, weapons, passives |
| `CameraRig` | `scenes/camera/camera_rig.gd` | Follow camera, shake, zoom kicks |
| `EnemySpawner` | `scenes/spawner/enemy_spawner.gd` | Spawns enemies from `SpawnRule`s off screen; spawns the boss |
| `HUD`, `BossBar`, `LevelUpMenu`, `PauseMenu`, `GameOver` | `scenes/ui/*` | UI (CanvasLayers) |
| `CombatVFX` | `scenes/vfx/combat_vfx.gd` | Hit / death VFX, driven by `Game` signals |
| `GameFeel` | `scenes/world/game_feel.gd` | Hitstop, camera shake, flashes, driven by `Game` signals |
| `ObjectiveDirector` | `scenes/objectives/objective_director.gd` | Places and tracks map objectives (`data/objectives/`) |

Other in-run systems attach themselves at runtime (weather, ground marks, foliage, atmosphere rig,
ability casters under the player); see the owning team doc.

## 3. Autoloads (global singletons)

Registered in `project.godot` `[autoload]`. Only global, session-long state belongs here (see
CODE_STYLE §5). Load order matters: an autoload may only use autoloads listed above it in `_ready()`.

| Autoload | File | Owner doc | Purpose |
|---|---|---|---|
| `Game` | `autoload/game.gd` | core | Low-level run state (`player`, `world`, `elapsed`, `kills`), dev flags from the command line, `Game.spawn()`, `hitstop()`, and the raw combat **event bus** (`enemy_died`, `enemy_hit`, `player_hit`, `boss_spawned`, `boss_died`). |
| `Maps` | `autoload/maps.gd` | maps.md | Map registry (`data/maps/*.json`) and live-map facade (spawn points, bounds). |
| `RunState` | `autoload/run_state.gd` | gameplay | Run lifecycle (`start_run`, `end_run`, `return_to_basecamp`, `restart_run`), run currency (Ichor) and the **gameplay event hub** (`run_started`, `run_ended`, `enemy_killed`, `player_damaged`, `currency_changed`, `wave_started`, ...). Prefer these signals over `Game`'s for gameplay features. |
| `Meta` | `autoload/meta.gd` | basecamp.md | Between-run layer 1: Souls, shopkeeper upgrades, map unlocks / chosen map, `start_run()`, `go_to_basecamp()`. Saves `user://meta_save.json`. |
| `Progression` | `autoload/progression.gd` | progression.md | Between-run layer 2: Sin Shards, Hellstone, upgrade tree, unlocks, pacts (heat); per-run relics and loot quality. Saves `user://progression.json`. |
| `Sfx` | `autoload/sfx.gd` (+ `scripts/audio/`: recipes incl. per-map signatures, hooks, cache, surface probe, weather audio, legacy music) | sfx.md | Procedurally synthesized sound effects, buses, `Sfx.play(&"name", pitch_jitter, volume_db)`. |
| `MusicManager` | `autoload/music_manager.gd` | music.md | Adaptive stem-based music (layers by combat intensity, boss enrage). |
| `Settings` | `autoload/settings.gd` | ui.md | User options persisted in `user://settings.cfg`; `Graphics` (`scripts/graphics.gd`) applies them. |
| `Perf` | `autoload/perf.gd` | perf | Debug performance overlay, stress / benchmark tooling. |
| `Corruption` | `autoload/corruption.gd` | art-style.md | Visual-only blight trail painted into a global shader texture. |
| `Dialogue` | `autoload/dialogue.gd` | story.md | Data-driven conversations (`data/dialogue/*.json`), story flags, the dialogue box. |
| `Atmosphere` | `autoload/atmosphere_director.gd` | visuals.md | Per-map lighting, sky, fog, grade and weather presets (`data/atmosphere/presets.json`). |
| `Abilities` | `autoload/abilities.gd` | abilities.md | Ability / synergy / boon registry and run state (`data/abilities/*.json`, `scripts/abilities/`). |

Per-demon sound sets: `Sfx.DEMON_SOUNDS` maps a demon's `model_id` to replacements for the generic
player sounds (hurt / faint / dash) and `Sfx.DEMON_LOOPS` adds a movement loop (`SfxMoveLoop`),
so `player.gd` never names a sound per demon (details in sfx.md, "Demon sound identity").

The `[autoload]` section of `project.godot` is the source of truth; keep this table in sync when
you add one. Many autoloads hook themselves up through `SceneTree.node_added` (e.g. applying
upgrades when a `Player` enters the tree), so features work without edits to `player.gd`.

### Event layers
1. **Local signals** on a node (`Player.died`, `Player.leveled_up`, `Weapon` level changes):
   for its direct owner.
2. **`Game` signals**: raw, high-frequency combat events for presentation (VFX, decals, game feel,
   audio).
3. **`RunState` signals**: gameplay-level events with context (elite flag, HP after damage, run
   result) for objectives, abilities, meta progression and UI.

## 4. Gameplay building blocks

| Concept | Base class / data | Where |
|---|---|---|
| Player | `Player` (CharacterBody3D) + `PlayerDash` and `LastStand` components, look from `DemonData` via `DemonModel` (7 demons) | `scenes/player/`, `scenes/demons/`, `data/demons/*.tres` |
| Enemies | `Enemy` driven by `EnemyData`; model `EnemyModel` subclasses | `scenes/enemies/`, `data/enemies/*.tres` |
| Procedural characters | `ProcModel` (extends `EnemyModel`) | `scenes/characters/` |
| Bosses | `Boss` (Sariel, extends `Enemy`); `PhasedBoss` = shared multi-phase skeleton (new bosses extend it: `ArchonBoss`, `InquisitorBoss`); code-built `ProcBoss` bosses in `scenes/characters/bosses/`; `BossTelegraph`, `HolyFX` | `scenes/bosses/`, `data/bosses/*.tres`, `data/bosses/bosses.json` |
| Spawning | `EnemySpawner` + `SpawnRule` resources | `scenes/spawner/` |
| Weapons | `Weapon` (override `attack()` / `_on_level_changed()`), `Projectile` | `scenes/weapons/<weapon>/` |
| Level-up | `Upgrades` (`Upgrades.roll()`) -> `UpgradeOption`s; `PassiveData` | `scripts/upgrades/`, `data/passives/` |
| Pickups | `Pickup` base (homing + collect) -> `XPGem`, `BloodChalice`; `IchorDrop` | `scenes/pickups/` |
| Objectives | `Objective`, `ObjectiveDirector`; mid-run `RunEvents` (crusade / eclipse / reaper); run-end `RunScore` | `scenes/objectives/`, `data/objectives/` (`objectives.json`, `events.json`) |
| Maps | `GameMap` base + per-map scenes, `MapLoader` | `scenes/maps/`, `data/maps/*.json` |
| Hub | `HubInteractable`, `HubShopkeeper`, `basecamp.tscn` | `scenes/basecamp/` |
| Abilities | `AbilityDef`, `AbilityCaster`, `StatusHost` | `scripts/abilities/`, `data/abilities/` |
| Dialogue | `DialogueBox`, `DialogueDB`, `StoryState` | `scenes/dialogue/`, `scripts/dialogue/`, `data/dialogue/` |

Data comes in two flavours: typed **Resources** (`.tres`, for things edited in the inspector and
referenced by scenes: enemies, demons, passives, spawn rules) and **JSON** (`data/**/*.json`, for
large tables: abilities, upgrades, objectives, dialogue, atmosphere presets).

### Where the other classes live (by feature)

| Feature | Classes |
|---|---|
| Hub (`scenes/basecamp/`) | `Basecamp` (scene root), `HubScenery` (built environment), `HubAvatar` (walking demon), `HubInteractable` -> `HubShopkeeper`, `HubShopUI`; shop screen `ShopPanel` (`ui/components/`) |
| Bosses (`scenes/bosses/`, `scenes/characters/bosses/`) | `PhasedBoss` (phase table, intro / transitions / enrage; `scenes/bosses/phased_boss.gd`), `ArchonBoss` (Azrafel, the finale, `archon/`), `ProcBoss` + `*_model.gd` (Frost Abbot, Verdant Matriarch, Dawn Wyrm, War Chariot, Storm Archon, Gilded Seraph, Cantor); `Boss` (Sariel) with `SarielModel`, `SarielOrb`, `RadiantBeam`, `JudgementPillar`, `BossTelegraph`, `HolyFX`; `InquisitorBoss` + `InquisitorModel`, `InquisitorLane`, `PyreBurst`, `BellRing` (`inquisitor/`); reward `ReliquaryOfSin` |
| Enemies (`scenes/enemies/`, `scenes/characters/`) | `Enemy`, `EnemyData`, `EnemyModel` (Blender angels) and `ProcModel` (code-built roster, `CharacterRoster`, `HolyHorse`, `DemonKit`); projectiles `HolyOrb`, `HolySmoke`, `HolyBolt`; `HolyTelegraph` |
| Objectives (`scenes/objectives/`) | `ObjectiveDirector`, `Objective` + `types/*`, `RunEvents` (mid-run events, `--event=<id>`), `RunScore` (run-end score / daily trial best), `ObjectiveTracker`, `ObjectiveFX`, `DamnedSoul`, `PylonEnemy`/`PylonModel`, `SaintEnemy` |
| Abilities (`scripts/abilities/`) | `AbilityDef`, `AbilityCaster`, `AbilityCombat` (damage pipeline), `StatusHost`, `AbilityBolt`, `AbilityZone`, `AbilityMinion`, `AbilityFx`; the `Abilities` autoload's helpers `ability_events`, `ability_modifiers`, `ability_synergies`, `ability_offers`, `ability_resources`, `ability_data`, `ability_dev`; one behaviour class per ability kind in `kinds/` (`AbilityKind` subclasses: aura, blink, bolt, ...) |
| Dialogue / story (`scripts/dialogue/`, `scenes/dialogue/`) | `DialogueDB`, `StoryState`, `ConversationRunner`, `StoryHooks`, `WorldBarks`, `Codex`, `Affinity`; UI `DialogueBox`, `DialoguePortrait`, `DialogueSubtitles`; hub `StoryNpc`, `StoryMarker`, `CrownShrine` |
| Atmosphere (`scenes/world/atmo/`) | `AtmoRig` (in-scene half of the `Atmosphere` autoload), `AtmoPresets`, `AtmoLayers`, `AtmoLightning`, `AtmoEvents` (boss lighting, gameplay-driven gloom, enemy-shadow quality switch), `AtmoScene`, `HellfireLight` |
| World (`scenes/world/`) | `GroundMarks`, `FoliageField`; terrain arenas `TerrainPatch` + `TerrainTheme`, `Scatter` (`scripts/terrain/`) |
| Characters polish (`scripts/characters/`) | `CharacterMotion` (procedural secondary motion), `DemonSkins`, `SkinPicker` |
| Performance (`scripts/perf/`, `autoload/perf.gd`) | `SkinBake` (collapses a code-built model's rigid parts into one skinned mesh), `GlbSkin` (same for Blender node-rig models), `Perf.enemies()` / `Perf.budget()`; budgets in `docs/team/performance.md` |
| Saves | `SaveProfile` (`scripts/save_profile.gd`): every save file path goes through `SaveProfile.path("<file>")`; tests / bots use `user://test/<profile>/` (`--save-profile=<name>`) so they never touch the player's saves |
| UI (`scenes/ui/`, `ui/`) | `MainMenu`, `HudWidgets`, `RunLedger`, `SettingsControlsPage`; components `InfernalBar`, `CooldownSlot`, `CurrencyCounter`, `Minimap`; `Keybinds`, `UIFit` |
| Weapons (`scenes/weapons/`) | `Weapon`, `Projectile`, `WeaponArt`, `InfernalFx` |
| Menus (`scenes/menu/`) | title (`title.gd`, shaders in `shaders/title/`), demon select (`demon_select.gd` = camera, demons, UI, input; `RitualChamber` = the built set), `Warmup` |
| Dev | `Autopilot` (`scripts/autopilot.gd`, the `--autopilot` bot; dodges with `Danger`) |

## 5. Shared helpers (static classes in `scripts/`)

| Class | File | Use for |
|---|---|---|
| `Danger` | `scripts/danger.gd` | `Danger.threat_at(tree, pos, margin)`: is this spot about to be hit? Reads every telegraph (`danger_zones`, `boss_hazards`, `enemy_shots`). Used by the Autopilot; use it for ally / AI dodging. |
| `ScaleStack` | `scripts/scale_stack.gd` | Composable named scale factors on a Node3D (`ScaleStack.set_factor(node, &"girth", 1.12)`), so several systems never overwrite each other's `scale`. |
| `JsonIO` | `scripts/json_io.gd` | `read_dict(path, context, missing_ok, as_error)` for data/save JSON, `write_atomic(path, data, context)` for crash-safe saves (temp file + rename). Used by Maps, ObjectiveDirector, DemonSkins, CharacterRoster, DailyChallenge, RunLoadout, StoryState. |
| `Perf.enemies()` | `autoload/perf.gd` | The "enemies" group as one array cached per frame / physics step; iterate it (read-only) instead of `get_nodes_in_group(&"enemies")`. |
| `TextFormat` | `scripts/text_format.gd` | `roman(n)`, `clock(seconds)` for ranks, waves and timers. |
| `Targeting` | `scripts/targeting.gd` | `nearest_enemy(tree, from, range, exclude)`, `nearest_enemies(...)`, `flat_dir()`. XZ-plane, skips dying enemies, built on `Perf.enemies()`. Use it instead of writing your own nearest-enemy loop. |
| `Art` | `scripts/art.gd` | Material + primitive-mesh kit for procedural models (current look). |
| `ArtStyle` | `scripts/art_style.gd` | Art-direction helpers on top of `Art`: faction palettes, rim light. |
| `Toon` | `scripts/toon.gd` | Legacy primitive kit; `Art` wraps parts of it. Do not use in new code. |
| `Props` | `scripts/props.gd` | Blender-made world props (`Props.build(name, rng)`). |
| `PropBuilder` / `PropKit` | `scripts/terrain/` | Procedural prop meshes + collision (terrain role). |
| `GlbModel` | `scripts/glb_model.gd` | Wraps an imported `.glb` model with animation helpers. |
| `AngelDeathFX` | `scenes/enemies/models/angel_death_fx.gd` | One-shot holy FX: `light_flash`, `spawn_motes`, `spawn_feathers`, `spawn_debris`, `shockwave`, `poof` (EnemyModel forwards to it). |
| `Dissolve` | `scripts/dissolve.gd` | Burn-into-light death dissolve. |
| `DamageNumber` | `scripts/damage_number.gd` | `DamageNumber.spawn(amount, position)`. |
| `Graphics` | `scripts/graphics.gd` | Applies `Settings` to the viewport, lights and environment. |
| `Icons` | `scripts/icons.gd` | Painted item icons from `assets/icons/`. |
| `Rarity` | `scripts/progression/rarity.gd` | Rarity tiers for boons, relics, drops. |
| `UIPalette` | `ui/palette.gd` | Shared UI colours and fonts (theme in `ui/theme.tres`, built by `tools/build_theme.gd`). |

## 6. Physics layers

1 `world`, 2 `player`, 3 `enemies`, 4 `pickups` (named in `project.godot`). Enemies collide with
each other but not with the player; contact damage comes from the player's `Hurtbox` area.

## 7. Folders

| Path | Contents |
|---|---|
| `autoload/` | Autoload singletons only |
| `scenes/` | Scenes and their scripts, one folder per feature |
| `scripts/` | Scene-less code: static helpers, data classes, subsystems |
| `data/` | `.tres` and `.json` content |
| `shaders/` | Shared shaders and includes (`*.gdshaderinc`) |
| `ui/` | Theme, palette, reusable UI components |
| `assets/` | Generated assets (models, icons, textures). Regenerate them, don't hand-edit |
| `tools/` | Dev/build scripts, headless checks, Blender sources, perf and QA harnesses |
| `docs/` | This file and per-role team docs |

## 8. Dev workflow

- Godot 4.7.2: see `Play.bat` / `Open in Godot Editor.bat` for the executable path.
- Boot check: `godot --headless --path . --quit-after 300`.
- Warnings: `tools/check_warnings.sh` (lists editor-only GDScript warnings for every script).
- Whole suite: `tools/qa/run_all.sh` (every headless check + the boot -> hub -> each map -> hub flow test, summary table; see docs/team/qa.md).
- Script check: `godot --headless --path . --script res://tools/check_scripts.gd` (every `.gd`
  compiles; exit code 1 on failure).
- New `class_name`s are only known to other scripts after Godot rescans the project (opening the
  editor, or `godot --headless --path . --import`). Until then headless runs report
  "Could not find type". Run the import once after adding a class.
- Command-line dev args (after `--`): `--autopilot`, `--godmode`, `--demon=<id>`, `--map=<id>`,
  `--boss`, `--event=<id>`, `--save-profile=<name>`, `--unlock-all`, `--sfx-nocache`,
  `--shot=path.png --shot-time=seconds`. Debug builds: F1 level-up, F2 damage numbers, F4 win,
  F6 +25 Ichor.
- Contents at a glance (demons, maps, bosses, counts) and the human to-do list: `docs/STATUS.md`.
