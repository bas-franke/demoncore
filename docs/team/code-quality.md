# Code quality (role: code refactorer / code-quality keeper)

Owner of: this file, `docs/ARCHITECTURE.md`, and small behaviour-preserving cleanups across
the tree (comments, static types, dead code). I do not own any gameplay feature. If I touch your
file it is a surgical Edit; tell me (here) if something I changed gets in your way.

---

## CODE_STYLE (please follow this)

Short version: **typed GDScript, one class per file, doc comment at the top, signals in the past
tense, autoloads only for truly global state.** The existing code (`autoload/game.gd`,
`scenes/player/player.gd`, `scenes/weapons/weapon.gd`, `scripts/targeting.gd`) is the reference.

### 1. Naming

| Thing | Style | Example |
|---|---|---|
| Files, folders, scenes | `snake_case` | `hellfire_bolt.gd`, `hellfire_bolt.tscn` |
| `class_name`, inner classes | `PascalCase` | `class_name EnemySpawner` |
| Functions, variables | `snake_case` | `func take_damage()`, `var pickup_radius` |
| Private members | leading `_` | `var _cooldown_left`, `func _on_level_changed()` |
| Constants, enum values | `CONSTANT_CASE` | `const FACE_RANGE := 14.0` |
| Signals | `snake_case`, **past tense** | `leveled_up`, `enemy_died`, `boss_spawned` |
| Signal handlers | `_on_<source>_<signal>` | `_on_pickup_area_entered` |
| Groups, input actions, meta keys | `StringName` literal | `&"enemies"`, `&"move_left"` |

- The script file name matches the `class_name` (`EnemySpawner` lives in `enemy_spawner.gd`).
- Give a `class_name` only to things other scripts reference by type. Never give one to an
  autoload script (it would clash with the autoload's global name).
- Booleans read as questions: `is_dead`, `is_dying`, `has_weapon()`.

### 2. Static typing

- Type everything you can. Inferred is fine when the type is obvious: `var speed := 6.0`.
- Use explicit types when inference fails or would be `Variant`, typically for values coming from
  `Dictionary`/`Array` lookups, `get()`, `get_node()`, or methods that exist only on a subclass:
  `var il: int = mesh.surface_get_array_index_len(s)` and `var d: float = dict["dist"]`.
- Always type function parameters and return values (`-> void` too).
- Use typed arrays (`Array[Enemy]`) and, for dictionaries, a comment with the key/value types
  (`var passive_levels := {}  # PassiveData -> int`) or `Dictionary[K, V]` in new code.
- Cast once with `as` and null-check instead of calling dynamic methods:
  `var e := body as Enemy` then `if e and not e.is_dying:`.
- Prefer `&"name"` (StringName) for groups, actions, signal names and `has_method()`.

### 3. File layout

Keep this order in every script (Godot's official order):

```gdscript
class_name Foo            # only if needed
extends Node3D
## One-line summary of what this class is for.
##
## Longer notes: how it is used, who calls it, gotchas.

signal something_happened(value: float)

enum State { IDLE, CHASING }
const MAX_THINGS := 8

@export var speed := 4.0          ## exports first, grouped with @export_group
var public_state := 0             ## then public vars
var _private_state := 0           ## then private vars
@onready var _mesh: MeshInstance3D = $Mesh

func _ready() -> void: ...        # built-in virtuals first (_init, _ready, _process, ...)
func public_api() -> void: ...    # then public methods
func _helper() -> void: ...       # then private helpers
```

- Every script starts with a `##` doc comment (class doc) saying what it is and how it plugs in.
- Document every `@export` and every public method that is not self-explanatory with `##`.
- Comment the *why* of non-obvious logic (magic numbers, ordering constraints, perf tricks), not
  the *what*.
- Group long scripts with section banners: `# ---------------------------------------------------------------- health`
- Soft limit: ~400 lines per script. Past that, split out a helper (a static-function class in
  `scripts/`, or a child-node component). Procedural model/audio builders may be longer but
  should still be split by section.
- Line length: aim for 100 columns, tabs for indentation, two blank lines between functions.
- UTF-8, LF line endings, final newline (`.editorconfig` / `.gitattributes` at the repo root).
  Godot reads CRLF fine, but mixed endings make search/replace tools miss matches.
- No dead code: delete commented-out blocks and unused variables/functions instead of leaving
  them. Git history (once we commit) remembers.
- Dev-only code (autopilot, debug keys) goes at the bottom under a `# ---- dev` banner.

### 4. Signals

- Declare signals at the top, with typed parameters.
- Name them for what *happened* (past tense): `died`, `leveled_up`, `damaged(amount)`. Not
  `die`, `on_death`, `do_level_up`.
- **Call down, signal up.** A parent calls methods on its children; a child emits signals and
  never reaches up to its parent with `get_parent()`.
- Connect in code (`player.died.connect(_on_player_died)`) rather than in the editor, so the
  wiring is visible in the script. Editor connections in `.tscn` are allowed for UI buttons.
- Cross-system gameplay events (things many unrelated systems react to: deaths, hits, boss
  phases) go through the **`Game` event bus** signals (`Game.enemy_died`, `Game.player_hit`, ...).
  Add a new one there with a comment naming its emitter, rather than making VFX/audio/UI hold
  references to enemies. Local events stay on the node that owns them.
- Do not emit another node's signals from outside it; call a method on it instead.

### 5. Autoloads vs. components vs. static helpers

Use an **autoload** (`autoload/*.gd`, registered in `project.godot`) only when it is:
- genuinely global and lives for the whole session (current run state, settings, audio), and
- needed from many unrelated places.

Current autoloads: `Game` (run state + event bus), `Sfx` (procedural audio), `Settings` (user
options). Adding one is a shared-file change: ask/announce it in your team doc first, and keep it
small. Do not put feature logic (a shop, a weapon, a boss) in an autoload; put its *persistent
data* there if it must survive scene changes, and keep the behaviour in the scene.

Use a **component** (a child node with its own script/scene) when the behaviour belongs to one
entity and could be reused by others: hurtboxes, health, a model builder, a telegraph. Components
get references through `@export` or `@onready`, and talk upward with signals.

Use a **static helper class** (`class_name Foo` with only `static func`, in `scripts/`) for stateless
utilities: `Targeting`, `Upgrades`, `Props`, `Toon`. No instance state, no autoload needed.

Use a **Resource** (`extends Resource`, `.tres` in `data/`) for authorable data: `EnemyData`,
`PassiveData`, `DemonData`, `SpawnRule`. Behaviour reads from data; data never holds node refs.

### 6. Misc rules

- Spawn runtime nodes with `Game.spawn(node, position)`, so they land under the run's world node
  and physics interpolation starts at the right place.
- Look nodes up with `@onready var x: Type = $Path` once, not `get_node()` every frame.
- Avoid `get_tree().get_nodes_in_group()` in per-frame code of many entities; use `Targeting`.
- Use `push_warning()` / `push_error()` for recoverable problems, never silent `return` on bad data.
- Validate with a headless run after every change (see "Validation" below) and fix your warnings.

---

## Validation

Godot console binary:
`C:\Users\buunn\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`

- Boot check: `<godot> --headless --path . --quit-after 300`
- Script check: `<godot> --headless --path . --script res://tools/check_scripts.gd` loads every
  `.gd` under `res://` (after autoloads are up) and lists parse/compile errors. Exit code 1 on failure.
- Warning check: `tools/check_warnings.sh` (Git Bash). Godot only shows GDScript warnings in the
  editor; this copies the project to a temp folder, promotes the default warnings to errors there
  and prints `message @ res://file.gd:line` for each. **Run it on your files before you finish**
  and fix what it reports (unused vars, shadowed names, int division, static-on-instance, ...).
  Add `untyped_declaration` as an argument to also list untyped variables.
- After adding a new `class_name`, run `<godot> --headless --path . --import` once, or other
  scripts fail with "Could not find type X" in headless runs.

---

## Shared helpers I own (use them instead of re-writing)

| API | File | Notes |
|---|---|---|
| `TextFormat.roman(n) -> String` | `scripts/text_format.gd` | Any n (0 -> "", 14 -> "XIV"). Replaces the 6 copies of a `ROMAN` table. |
| `TextFormat.clock(seconds) -> String` | `scripts/text_format.gd` | "mm:ss" run timer (HUD, game over, run summary). |
| `Pickup` (extends `Area3D`) | `scenes/pickups/pickup.gd` | Base for "fly to the demon when touched" pickups. Call `_home(delta)` from `_physics_process`, override `_collect(player)`. Tunables: `homing_accel`, `homing_start_speed`, `homing_height`. `attract(player)` / `is_attracted()` are provided. Also has `_ease_out_back(x)` for the spawn pop. `XPGem` and `BloodChalice` use it. |
| `tools/check_scripts.gd` | `tools/` | Headless compile check of every script (see Validation). |
| `tools/check_warnings.sh` | `tools/` | Lists GDScript warnings project-wide (see Validation). |
| `JsonIO.read_dict(path, context, missing_ok, as_error)` / `JsonIO.write_atomic(path, data, context)` | `scripts/json_io.gd` | Shared JSON loader + crash-safe save writer. Use instead of hand-rolled parse/check/warn code. |
| `Targeting.nearest_enemy(tree, from, range, exclude)` | `scripts/targeting.gd` | Now takes an optional `exclude` (Array or Dictionary). |

## Integration notes / open cleanup items for owners

These are things I noticed but did **not** change because the files are being actively edited.
Owners: please pick them up (or tell me here when the file is quiet and I will do it).

- **Warnings**: `tools/check_warnings.sh` went from 130 to a handful (round 4). Left: an
  unnecessary `await` in `tools/characters/characters_check.gd`, unused `_phase_errors` in
  `tools/qa/flow_smoke.gd` (QA's file), the `name` parameter of
  `Atmosphere.has_overlay_def()` and a mixed int/float ternary in `objective_director.gd:208`.
  All four files were being edited at the time.
- **Split requests (owners: please do these when you next touch the file; tell me here if you'd
  rather I do it once the file is idle).** None of the owner docs mention a planned split:
  - `autoload/progression.gd` (~1550 lines, progression): move the "run: start / during / end"
    sections into a `scripts/progression/progression_run.gd` helper, and the save/load into JsonIO.
  - `scenes/maps/game_map.gd` (~1300, maps): the geometry / blockers / markers "building helpers"
    sections are a natural `GameMapBuilder` static helper; the nav grid / flow field could be its own file.
  - `autoload/abilities.gd`: the abilities owner is already splitting it (ability_events,
    ability_modifiers, ability_synergies, ability_offers ... in `scripts/abilities/`).
  - `scripts/terrain/terrain_patch.gd` (~970) and `scripts/terrain/prop_kit.gd` (~940, terrain):
    the liquid / bridges / scatter sections, and the holy-realm vs Basecamp prop catalogs.
  - `autoload/music_manager.gd` (~830, music): fine for now.
  - `autoload/sfx.gd` (~1900, sfx): the core recipes ("combat", "ritual", "interface") could join
    the existing `scripts/audio/sfx_recipes*.gd` files.
- **Two save/meta systems**: settled. `Meta` owns Souls and shopkeeper upgrades, `Progression`
  owns Sin Shards / Hellstone / the upgrade tree / pacts and proxies Souls to Meta. Keep it that way.
- **Two event hubs**: keep `Game` for raw combat signals and `RunState` for gameplay-level ones
  (see ARCHITECTURE.md "Event layers"). Don't add the same event to both.
- **New `class_name` not found in headless runs**: after adding a class, run
  `<godot> --headless --path . --import` once (takes seconds) to refresh
  `.godot/global_script_class_cache.cfg`; otherwise other scripts fail with "Could not find type".

## Work log

- CODE_STYLE guide (above) and `docs/ARCHITECTURE.md`.
- `tools/check_scripts.gd`: headless compile check of every script, exit code 1 on failure.
- Warning sweep (warnings promoted to errors on a scratch copy of the project) and fixes:
  - `autoload/game.gd`: event-bus signals wrapped in `@warning_ignore_start("unused_signal")`.
  - `autoload/settings.gd`: `window_mode` / `graphics_preset` typed `int` (anonymous enum + clampi).
  - `scripts/graphics.gd`: explicit `DirectionalLight3D.ShadowMode` cast.
  - Intentional integer divisions annotated (`hud.gd`, `game_over.gd`, `foliage.gd`, `sfx.gd`).
  - Shadowed locals renamed (`foliage.gd` tint_r/g/b, `foliage_field.gd` noise_tex,
    `warmup.gd` file_name, `ground_marks.gd` wisp_cell).
  - Unused members removed: `JudgementPillar._done`, `Boss._flashed`, `foliage.gd _queue`.
  - `tools/_props_check.gd`: parse error fixed (untyped `surface_get_array_index_len`).
- `scripts/text_format.gd` (`TextFormat`), `Upgrades.roman()` now delegates to it.
- `scenes/pickups/pickup.gd` (`Pickup`): shared homing/collect base; `XPGem` and `BloodChalice`
  moved onto it (behaviour unchanged, verified with an autopilot run: XP is collected, levels rise).
- `scenes/enemies/enemy.gd`: calls `BloodChalice.try_drop` directly instead of the `FoodBowl` shim.
- `Weapon.cooldown_mult` (new, in `scenes/weapons/weapon.gd`) replaces the identical
  `get_cooldown()` overrides in hellfire_bolt, infernal_chain, ravagers_cleave, reapers_scythe and
  brimstone_sigil (`tick_mult`). Subclasses just set `cooldown_mult` in `_on_level_changed()`.
  Verified: max-level cooldowns unchanged (e.g. Hellfire Bolt 0.6 s, Brimstone 0.45 s).
  Public `Weapon` methods now have doc comments.
- `scenes/menu/title.gd`: the four inline shader strings moved to `shaders/title/{sky,beam,pool,mist}.gdshader`
  (preloaded constants; title renders identically). title.gd went from 759 to 608 lines.
- Deleted the dead `FoodBowl` shim (`scenes/pickups/food_bowl.gd`); class cache refreshed.
- `UIPalette.roman()` and the pause menu now use `TextFormat.roman()`.
- `scenes/main.gd`: stale dev-args comment (`--cat=luna`) corrected.
- Removed dead deprecated members: `EnemyModel.pop_words`, `.poof_color`, `.googly_eye()`,
  `.pop_word()` and `DemonModel.set_happy()` (no callers anywhere).
- `tools/check_warnings.sh`: project-wide GDScript warning report (see Validation).
- Repo root: `.gitattributes` (LF in git, binaries marked) and `.editorconfig` (tabs, LF, UTF-8).
  ~45 scripts currently have CRLF endings; git normalizes them on the first commit.
- `scenes/ui/hud.gd` and `scenes/spawner/enemy_spawner.gd` use `TextFormat.roman()` /
  `TextFormat.clock()` (removed two more roman tables and an mm:ss copy).
- `autoload/meta.gd`, `scenes/ui/game_over.gd` and `scenes/ui/pause_menu.gd` now use `TextFormat`
  too.

### Round 2
- `IchorDrop` moved onto `Pickup` (`_collect()` grants the Ichor; accel 50, start speed -3 kept).
  `shard_pickup` / `relic_pickup` had already been moved by progression. No attract copies remain.
- Atmosphere: the editor-only `global_shader_parameter_get_list()` call was already gone; boot log
  verified clean, note added to `docs/team/visuals.md`.
- Warning sweep of the new scripts (`check_warnings.sh`), fixed in files idle >= 10 min:
  shadowed/"declared below" locals in archangel, monk, villager, malphine, breachwarden,
  demon_skins, dialogue_portrait, prop_kit (`snapped` -> `is_snapped`), damage_number
  (`font_size` -> `px`); int-division annotations in run_state, glass_golem, siege_objective,
  objective, _gallery; enum typing in upgrades.gd; float/int ternary in prop_kit; Variant/null
  ternary in sfx_hooks; unused param in proc_model.
- ARCHITECTURE.md: added a per-feature class index (hub, bosses, enemies, objectives, abilities,
  dialogue, atmosphere, terrain, UI, characters) and kept the 13-autoload table current.
- **Split `scenes/menu/demon_select.gd`** (1056 -> 685 lines): the whole set (environment, moon,
  mist, chamber, ceiling, pillars, chains, altar, rubble, summoning circle, spotlight, braziers,
  candles, light flicker) is now `RitualChamber` in `scenes/menu/ritual_chamber.gd` (414 lines,
  API `build()`, `update_lights(t)`, `prop(path, pos, yaw, scale, parent)`, static
  `find_mesh(root, name)`). demon_select keeps the camera (`_build_camera()`), demons, UI and
  input; shared layout constants (`FRONT`, `ARC_CENTER`, `ARC_RADIUS`) alias RitualChamber's.
  Unused `WAX` constant dropped. Verified by screenshot: the screen renders identically.
- `basecamp.gd` run summary uses `TextFormat.clock()`: no mm:ss copies remain anywhere.


## Note from progression (round 3): save isolation — please use it in every test
`scripts/save_profile.gd` (`SaveProfile`) decides where Progression, Meta and Dialogue (story) save:
- default: `user://<file>` (the player's real saves);
- `-- --save-profile=<name>` (alias `--save-dir=<name>`) or env `DEMONCORE_SAVE_PROFILE=<name>`:
  `user://test/<name>/<file>`;
- **automatic "bot" profile** for headless runs and for `--autopilot` / `--shot=` runs
  (`user://test/bot/`), so bots and screenshots never touch the real saves; `--real-save` opts out.
- In a `--script` tool: call `preload("res://scripts/save_profile.gd").use("<name>")` in
  `_initialize()` (runs before the autoloads' `_ready`, so even their boot-time load uses the profile),
  then `SaveProfile.use_and_reload(self, "<name>")` for a wiped, fresh state. Backing up / restoring
  `user://meta_save.json` etc. is no longer needed (basecamp_smoke and flow_smoke can drop it; it is
  harmless meanwhile). Read saves through `Progression.save_path()` / `Meta.save_path()`, not literals.
- Story: `--save-profile` also moves `story.json`; `--story-save=` still overrides it.

### Round 3
- Warnings fixed: `Maps.color_of` now called via `const MapsScript := preload("res://autoload/maps.gd")`
  in map_loader (x12) and hub_shop_ui; progression int division moved into
  `_hellstone_for_heat()`, `sign` -> `sgn`; int division in sfx_recipes_world; unused `_scroll` in
  shop_panel; Variant/int ternary in story_state; `tr` / `basis` locals in game_map.
- **Split `autoload/sfx.gd`** (2222 -> 1904 lines): legacy GDScript music synthesis ->
  `scripts/audio/sfx_legacy_music.gd`. Bit-identical output (hash-checked); noted in sfx.md.
- **New `JsonIO`** (`scripts/json_io.gd`): Maps, ObjectiveDirector, DemonSkins, CharacterRoster,
  DailyChallenge and RunLoadout read through `JsonIO.read_dict`; StoryState saves through
  `JsonIO.write_atomic` (it was the only non-atomic save writer). Meta / Progression saves were
  already atomic; they can switch to `write_atomic` when their owners next touch them.
- **Enemy scans consolidated**: `Targeting.nearest_enemy()` gained `exclude`; infernal_chain's
  private `_nearest_unhit` copy removed. holy_font, pylon_enemy, objective_fx and world_barks
  iterate `Perf.enemies()` (cached) instead of `get_nodes_in_group(&"enemies")` every call.
- API docs added to affinity, codex, surface_probe, hub_pit, hub_boards, hub_life, dialogue_db,
  conversation_runner, map_interactable, damned_soul.
- `docs/CONTRIBUTING.md` written (run, test suite, --import gotcha, how to add a map / enemy /
  ability / weapon / dialogue / sound).
- **Split `enemy_model.gd`** (1056 -> 876 lines): the static FX helpers (light_flash, motes,
  feathers, debris, shockwave, poof + their pools) are now `AngelDeathFX`
  (`scenes/enemies/models/angel_death_fx.gd`). `EnemyModel.light_flash(...)` etc. still work
  through one-line forwarders, so no caller changed. Verified with an autopilot run + screenshot.
- `meta.gd`: `tr` -> `saved_trophies`, inner `maps` -> `maps_node` (shadowing warnings).

### Round 4 (final pass)
- Warnings 130 -> ~5: integer divisions annotated where they are intentional (31 files, mostly
  tools / terrain / objectives; hub_boards' mm:ss now uses `TextFormat.clock`). "Declared below"
  and shadowing locals were renamed in the boss / enemy models, hub_boards, hub_life, hub_shop_ui,
  atmo_scene, atmosphere_director, ability_caster, ability_hud, scorch_trail and glb_skin. Unused
  members (`mobile_reliquary`, `map_overview`, `kind_pride`, `toon`) and an unused local
  (`ability_combat`) were removed. Unused params became `_x` (targeting, toon, proc_boss, progression),
  enum casts were added (`atmo_hub_dressing`, `sfx_cache`), and the ternaries in `atmo_presets`
  became if/else. Abilities' externally emitted signals are now inside `@warning_ignore_start`.
- `docs/ARCHITECTURE.md` / `docs/CONTRIBUTING.md` updated (PhasedBoss / ArchonBoss / ProcBoss,
  RunEvents, RunScore, AtmoEvents, Danger, LastStand, ScaleStack, SkinBake / GlbSkin, SaveProfile,
  per-demon sound sets, the QA suite's checks, how to add a boss or a demon). New
  `docs/STATUS.md`: contents, how to play and test, and the "needs a human" list.
