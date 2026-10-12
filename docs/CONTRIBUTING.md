# Contributing to DemonCore

A short practical guide for humans. For the big picture read [ARCHITECTURE.md](ARCHITECTURE.md);
for conventions read the CODE_STYLE section of [team/code-quality.md](team/code-quality.md); each
system's API is in its `docs/team/<role>.md`.

## 1. Run the game

- Godot **4.7.2** (the path is in `Play.bat` / `Open in Godot Editor.bat`).
- Double-click `Play.bat`, or open the editor with `Open in Godot Editor.bat` and press F5.
- Flow: demon select (the entry scene) → Basecamp Hell (shops, boards, training pit, bar,
  hellgate with the loadout window) → a run on one of 10 maps → back to the hub.
  What's in the game: [STATUS.md](STATUS.md).
- Dev command-line args (after `--`): `--autopilot` (bot plays), `--godmode`, `--demon=<id>`,
  `--map=<id>`, `--boss`, `--event=<id>` (mid-run event at 3 s), `--shot=out.png --shot-time=30`
  (screenshot then quit), `--unlock-all`, `--rich`, `--save-profile=<name>`, `--sfx-nocache`. Debug builds: F1 level-up, F2 damage numbers, F4 win the run,
  F6 +25 Ichor.

  ```
  godot --path . res://scenes/main.tscn -- --map=cathedral_city --autopilot --godmode --shot=x.png --shot-time=20
  ```

## 2. Test before you hand anything in

| Command (Git Bash, repo root) | What it does |
|---|---|
| `tools/qa/run_all.sh` | **The integration suite** (owner: QA, see `docs/team/qa.md`). Imports, compiles, boots, runs every system check, a flow smoke over every map. `--quick` skips the slow ones, `--list` lists checks, `--only=a,b` runs some. Logs go to `tools/qa/results/<timestamp>/`. |
| `godot --headless --path . --script res://tools/check_scripts.gd` | Every `.gd` compiles (exit code 1 if not). Fast. |
| `tools/check_warnings.sh` | GDScript warnings the editor would show (unused vars, shadowing, integer division...). Fix the ones in your files. |
| `godot --headless --path . --quit-after 300` | Boots the main scene. |

The suite's checks: `import`, `check_scripts`, `boot`, `abilities_check`, `gameplay_check`,
`progression_check`, `progression_run_check`, `map_check`, `feature_check`, `objectives_selftest`, `music_check`,
`sfx_smoke`, `story_check`, `basecamp_smoke`, `roster_check`, `characters_check`, `terrain_check`,
`props_check`, `qa_smoke_checks`, `flow_smoke` (boot → hub → every map → hub), `warnings`, plus
the perf gates `perf_gate` / `perf_roster` in the slow set. PASS = exit 0 and no `SCRIPT ERROR`,
WARN = something threw, FAIL = non-zero exit / crash / timeout. **Adding a headless check? Add
one line to the `CHECKS` array in `tools/qa/run_all.sh`.**

### Saves in tests
Tests, sims, `--autopilot` and `--shot` runs never touch your real saves: every save path goes
through `SaveProfile.path()` and those runs use `user://test/<profile>/` (`bot` by default; pick
one with `--save-profile=<name>` or `DEMONCORE_SAVE_PROFILE`). New save files must use
`SaveProfile.path("<file>")` too, and write with `JsonIO.write_atomic()`.

### The `--import` gotcha
A new `class_name` is invisible to other scripts until Godot rescans the project. Headless runs
then fail with **"Could not find type X"** / **"Identifier X not declared"**. After adding or
renaming a class, run once:

```
godot --headless --path . --import
```

(opening the editor does the same). `run_all.sh` does it as its first step.

## 3. Common tasks

### Add a map
Full guide: `docs/team/maps.md` ("Making a new map").
1. `scenes/maps/<id>/<id>.gd` with `extends GameMap`: set the bounds in `_init()`, build the
   layout in `_build_layout()` with the GameMap helpers (`box`, `wall`, `prop`, `light`,
   `set_player_spawn`, `objective`, `enemy_spawn`, ...). Use `rng` for every random choice.
2. A tiny `.tscn` whose root has that script, plus `data/maps/<id>.json` (name, bounds, enemy pool,
   atmosphere preset, music, unlock).
3. Validate: `godot --headless --path . res://tools/maps/map_check.tscn -- --map=<id>`.
4. Optional: ask music for a theme (`docs/team/music.md`) and story for arrival lines.

### Add an enemy
1. `data/enemies/<id>.tres`: an `EnemyData` (stats, behaviour, model scene, size, XP).
2. A model: a procedural `ProcModel` subclass in `scenes/characters/enemies/` (see
   `docs/team/characters-new.md`), or a Blender model wrapped by `EnemyModel`.
3. Register it in `CharacterRoster.ENEMIES` (faction, tier, tags, spawn window) and/or add it to a
   map's `enemy_pool` in `data/maps/<id>.json`. It appears in the bestiary automatically.
4. Optional: material / voice in `data/audio/enemy_audio.json` (sfx), chatter in
   `data/dialogue/enemies.json` (story). Check with `scenes/characters/_roster_check.gd`.

### Add a boss
Extend `PhasedBoss` (`scenes/bosses/phased_boss.gd`): it runs intro, phase transitions at HP
thresholds, enrage and death; you fill in the phase table and attacks (see `ArchonBoss`, or the
code-built `ProcBoss` bosses in `scenes/characters/bosses/`). Register it in
`data/bosses/bosses.json` + a `data/bosses/<id>.tres`, set `"boss"` in a map's JSON, and telegraph
every hit with a node in group `boss_hazards` / `danger_zones` so `Danger` (and the bot) can see it.
Owners: `docs/team/objectives.md`, `docs/team/characters-new.md`.

### Add a playable demon
`data/demons/<id>.tres` (`DemonData`: look, lore, perks, starting weapon, stat tweaks), its model
(Blender script in `tools/blender/models/demons/`, see `docs/team/characters-polish.md`), then add it
to `demons` in `scenes/menu/demon_select.tscn`. Give it its own sounds with a row in
`Sfx.DEMON_SOUNDS` (+ `Sfx.DEMON_LOOPS` for a movement loop) and story lines in
`data/dialogue/` (`{demon}` variants).

### Add an ability (rite / boon / synergy)
Data only, in `data/abilities/`: `abilities.json` (`abilities[]`, see the data format in
`docs/team/abilities.md`), `synergies.json`, `boons.json`. New behaviour kinds go in
`scripts/abilities/` (`AbilityCaster` dispatches by kind). Check with
`godot --headless --path . --script res://tools/abilities_check.gd`.

### Add a weapon
A scene whose root script `extends Weapon`: override `attack()` (return true when it fired) and
`_on_level_changed()` (set per-level stats and `cooldown_mult`), fill `level_descriptions`, then add
the scene to `Player.weapon_pool`.

### Add dialogue
Conversations are JSON in `data/dialogue/*.json` (every file there is loaded). Each conversation has
an `id`, `lines` (with `who`, `text`, optional conditions, `set` / `add` effects, choices) and may
belong to a pool (random barks / NPC chatter). Start one with `Dialogue.start("<id>")`. Format and
speakers: `docs/team/story.md`. Preview: `tools/story/dialogue_preview.tscn`.

### Add a sound
Recipes are synthesized in code: add a recipe to one of `scripts/audio/sfx_recipes*.gd` and play it
with `Sfx.play(&"name")` / `Sfx.play_at(&"name", pos)`. Bump `Sfx.RECIPE_VERSION` if the startup
cache doesn't pick the change up. See `docs/team/sfx.md`.

## 4. House rules
- Everything is text: `.gd`, `.tscn`, `.tres`, `.gdshader`, JSON. No downloaded assets.
- Typed GDScript, a `##` class doc at the top of every script, signals named in the past tense.
- Reuse the shared helpers instead of writing your own: `Targeting` (nearest enemies),
  `Perf.enemies()` (cached enemy list), `JsonIO` (read JSON / save atomically), `TextFormat`
  (Roman numerals, mm:ss), `Pickup` (fly-to-player pickups), `Game.spawn()`.
- Cross-system events go through the `Game` (raw combat) and `RunState` (gameplay) signals.
- Keep `docs/team/<role>.md` current with your files, APIs and hooks.
