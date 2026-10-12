# QA and integration testing (docs/team/qa.md)

Owner: QA / integration tester. I run the whole check suite repeatedly while everyone lands
changes, fix small cross-worker integration breaks myself (marked `# QA:` in the code), and file
everything else below under the owning role.

## Run the suite

```bash
tools/qa/run_all.sh            # every check, ~6-10 min, prints a summary table
tools/qa/run_all.sh --quick    # skips the slow ones (warnings, flow_smoke, sfx_smoke)
tools/qa/run_all.sh --only=check_scripts,flow_smoke
tools/qa/run_all.sh --list
```

Status per check: **PASS** (exit 0, no `SCRIPT ERROR` in the log), **WARN** (exit 0 but some
script threw while it ran, or `check_warnings.sh` found warnings), **FAIL** (non-zero exit,
crash, or timeout = exit 124). Logs and `summary.txt` go to `tools/qa/results/<timestamp>/`
(git-ignored). Exit code = number of FAILed checks.

Checks it runs: `import`, `check_scripts`, `boot`, `abilities_check`, `gameplay_check`,
`progression_check`, `progression_run_check`, `map_check`, `feature_check`, `music_check`, `sfx_smoke`,
`story_check`, `basecamp_smoke`, `roster_check` (`scenes/characters/_roster_check.gd`),
`characters_check`, `terrain_check`, `props_check`, `qa_smoke_checks`, `flow_smoke`, `warnings`.
**If you add a headless check, add one line to the `CHECKS` array in `tools/qa/run_all.sh`.**
Perf checks (performance role, slow set): `perf_gate` = headless `--fixed-fps 60` bench, 300 enemies,
FAIL if the average frame exceeds 25 ms (today ~9.5 ms: catches ~2.5x regressions);
`perf_roster` = spawn cost / mesh count of every enemy type, FAIL above 8 ms or 80 meshes. Details and
how to profile a failure: docs/team/performance.md.

### `tools/qa/flow_smoke.gd` (full-flow smoke test)

```
<godot> --headless --fixed-fps 60 --path . --script res://tools/qa/flow_smoke.gd -- --autopilot [--secs=40] [--map=<id>]
```

boot (main scene) -> Basecamp Hell -> for every map in `Maps.ids()`: `Maps.start_run(id)`, autopilot
for `--secs` of game time, check the map is live / player exists / kills > 0, `RunState.end_run`,
`RunState.return_to_basecamp()`, check we are back in the hub. A `Logger` collects every engine and
script error per phase (`boot`, `basecamp`, `run:<map>`, `end:<map>`) and prints them deduplicated.
`--demons` adds one short run per `data/demons/*.tres` (visible player mesh + kills). Uses the
`qa_flow` SaveProfile, so the real saves are never touched. A run that ends by itself (the demon
died) counts as a normal run end.

Older tools in `tools/qa/`: `run_qa.ps1` (screenshot + long-run probe suite, PowerShell),
`probe.gd`, `smoke_checks.gd` (loads every resource, checks GLB animation sets), `BUGS.md`
(pass-1 bug list from that suite).

### Notes for everyone
- Many Godot processes run at once and share `user://` saves. A check that writes saves can
  occasionally fail with "cannot write user://progression.json.tmp" because of another process,
  not because of your code. Re-run before chasing it.
- After adding a `class_name`, run `<godot> --headless --path . --import`; until then every
  script using the class fails `check_scripts` with "Identifier X not declared".
- Headless display server: don't call `DisplayServer.keyboard_*`, window or clipboard APIs
  unguarded; they print errors in every headless check (`DisplayServer.get_name() == "headless"`).

## Fixed by QA (marked `# QA:`)

- `scenes/bosses/inquisitor/inquisitor_boss.gd`: `var _aim` renamed `_sweep_aim`. Gameplay added
  `Enemy._aim` (enemy.gd) and the Inquisitor (`extends Boss extends Enemy`) stopped compiling
  ("member _aim already exists in parent class"), so the Grand Inquisitor boss could not load.
- `ui/keybinds.gd` `event_label()`: skip `keyboard_get_keycode_from_physical` on the headless
  display server (it errored in every headless run that built a HUD key hint).
- `autoload/meta.gd` `_sync_map()`: the deferred restore of the saved hub map overwrote the
  `--map=<id>` dev arg, so `main.tscn -- --map=<id>` always ran the saved map (reported by sfx).
  The dev arg now wins; `flow_smoke --map=<id>` asserts it.
- **Static pools across runs** (only visible when a second run starts in the same session, which
  `flow_smoke` does): pooled nodes live under `Game.world` and are freed with the run, and
  `var x: Type = pool.pop_back()` errors with "Trying to assign invalid previously freed instance"
  before the `is_instance_valid` check. Pop into a `Variant`, check, then cast:
  `scripts/damage_number.gd` `_obtain`, `scenes/weapons/infernal_fx.gd` `_obtain_burst`,
  `scenes/enemies/models/enemy_model.gd` `_pooled_corpse`.
  Same family: `scenes/world/atmo/atmo_rig.gd` `find_player()` did `pl is Node3D` on a freed player
  (1000+ errors per flow run); `is_instance_valid` now comes first.
- `tools/basecamp_smoke.gd`: named `RunLoadout` / `DailyChallenge` (classes that use `Meta`) in a
  `-s` script, which compiles before the autoloads, so `player.gd` etc. got cached broken and the
  test hung until the timeout. Those two are `load()`ed at run time now.
- `tools/_props_check.gd`: ran from `_init()` (before autoloads), `decor.gd` failed to compile
  and the script never called `quit()` (hung 300 s). Runs on the first frame now and quits(1) on a
  broken dependency.
- `tools/qa/smoke_checks.gd`: hovering enemies with `move_anim = &"idle"` (ophanim) don't need a
  `walk` clip.

- `autoload/abilities.gd` `_end_run()`: passed the freed `player` to the typed
  `AbilityResources.reset(Player)`, which errored and aborted `_end_run`, so `casters` kept freed
  casters into the hub and the next run: 17k "Trying to cast a freed object" errors
  (`ability_hud.gd:80`, `owned_tags()`, `ability_offers.gd:16`) per flow run. Now passes null.

- `scenes/enemies/models/enemy_model.gd` `death_burst()`: deferred elite burst connected one bound
  static Callable to `process_frame`; two elites dying the same frame with identical args failed with
  "already connected" (roster_check). Uses a fresh `create_timer(0.0)` per burst now.
- `scripts/abilities/ability_events.gd` `_weapon_of()`: `get_meta(&"weapon", null)` errors when the
  meta is missing (a null default counts as "no default"); now `has_meta` first.

- (round 2) `scenes/ui/level_up_menu.gd:198`: same `get_meta(&"icon_frame", null)` fix (UI parked).
- (round 2) `tools/maps/map_check.gd`: `-- --fast` (1 variant, 12 agents). The real slowness was the
  agent sim awaiting physics frames in real time; run_all now runs map_check with
  `--fixed-fps 60 --disable-vsync` (~12 min -> ~20 s full, ~9 s fast, which `--quick` uses).

- (round 3) Flaky checks made deterministic: `tools/gameplay_check.gd` (`_isolate()` sealed arena;
  EXPLODE sums `RunState.player_damaged` instead of reading raw HP; last stand clears i-frames
  directly) and `tools/maps/feature_check.gd` (statue check with spawner + weapons off, other
  enemies freed, statue-only kill events). Each passed 5/5 in a row.
- (round 3) `run_all.sh` runs objectives' `--objectives-selftest` as `objectives_selftest`
  (`--fixed-fps`, ~135 s; slow, so `--quick` skips it).

**Rule of thumb for `-s` tool scripts:** don't name project classes that use autoloads (load
them at run time or duck-type), and always reach `quit()` even when a dependency is broken.

## Open issues (by owner)

- **maps**: `heavens_gate` (the finale) kills a fresh autopilot demon at ~37-49 s (100+ enemies on
  screen, no kills for the first ~30 s). Fine if it is gated behind progression; if it can be
  picked on a fresh save it is a difficulty wall.
- **gameplay**: autopilot still kites melee demons out of their reach (`THREAT_RANGE` 5.5 m vs
  Cleave ~2.6 m, old BUGS.md B2): Vharok / Iscariel often kill nothing in 30 s, so
  `flow_smoke --demons` only warns on 0 kills.
- **code-quality / everyone**: `tools/check_warnings.sh` reports ~130 warnings (45 integer
  division, 15 "declared below"; most in hub_boards.gd, atmo_scene.gd, abilities.gd).
- Older list `tools/qa/BUGS.md`: B1 (invisible demons) fixed, B2 open (above); the rest not
  re-verified.
- Resolved: the music stem failures (transient), and the flaky gameplay_check last stand /
  EXPLODE and feature_check statue checks (fixed in round 3).

## Pass log

- **Pass 1 (21:46, --quick)**: 7 FAIL. Mostly mid-edit churn (story_hooks CodexToast/Affinity,
  RelicView before import, ally_minion, proc_boss) plus the `_aim` clash, the props_check hang and
  the atmo errors. Fixed the persistent ones (above).
- **Pass 2 (21:59, full)**: 3 FAIL: map_check timeout (load), music_check (music mid-edit),
  basecamp_smoke hang (fixed). flow_smoke WARN: 1126 freed-instance errors (fixed). check_scripts,
  gameplay, abilities, progression x2, sfx, roster, characters, terrain, props, qa_smoke all PASS.
  characters-new fixed ally_minion.gd:196 and the ProcBoss `_aim` clash (`_boss_aim`) themselves.
- **22:23 targeted re-run**: import, check_scripts, basecamp_smoke, props_check, flow_smoke (all 9
  maps, boot -> hub -> run -> end -> hub) all PASS with 0 script errors.
- **Pass 3 (22:24, full)**: 2 FAIL (check_scripts, map_check), both from a mid-edit cascade
  (terrain's new `SiteProps` class before import; abilities split into `ability_modifiers` /
  `ability_events`). Persistent: flow_smoke 18k freed-object errors from Abilities (fixed, above).
  22:40 re-run: check_scripts + flow_smoke PASS, 0 script errors.
- **Pass 4 (22:43, full, flow now also runs every demon)**: 0 script errors in any log.
  3 FAIL: gameplay_check "last stand" (run_state.gd mid-edit, PASS on re-run at 23:02),
  roster_check (elite burst "already connected", fixed), map_check (outer_gardens shrine/spawn at
  (-32, 40) unreachable; maps fixed it at 23:00, `--map=outer_gardens` OK on re-run).
  B1 from BUGS.md (invisible demons) verified fixed: all 5 demons have meshes and kill.
- **Pass 5 (23:10, full, 22 checks incl. perf's perf_gate/perf_roster and maps' feature_check)**:
  0 persistent script errors (one sfx mid-edit blip). FAIL: gameplay_check (flaky last stand, see
  above) and flow_smoke (melee demons 0 kills in 15 s -> now a soft warning over the full --secs).
  23:30 re-run of import, check_scripts, gameplay_check, feature_check, flow_smoke: all PASS, 0 errors.
- **Round 2, pass 1 (23:34, full, now ~7 min instead of ~25 thanks to map_check --fixed-fps)**: 0 FAIL.
  flow_smoke WARN: 32x `decor.gd:118` get_meta on a freed light while perf was mid-edit (transient,
  gone next pass).
- **Round 2, pass 2 (23:51)**: 1 FAIL, gameplay_check "EXPLODE: blast hurt the demon (193 -> 196)"
  (flaky, HP regen; noted in gameplay.md). Everything else PASS with 0 script errors. flow_smoke now
  also covers run -> `restart_run()` -> run: clean. Re-checked gameplay's report of `Abilities._end_run`
  passing a freed player on restart: the QA fix is still at abilities.gd:160; the errors they saw are
  in logs from before it landed.
- **Round 2, pass 3 (00:07)**: 22/22 PASS (warnings WARN), 0 script errors.
- **Final pass (00:13, tree quiet: no .gd changed since 00:07)**: 21 PASS, 1 FAIL (maps'
  feature_check statue-kill check, flaky: 3/3 PASS alone; noted in maps.md), 0 script errors in any
  log. Remaining known flakes: gameplay_check last stand / EXPLODE (gameplay.md).


- **Round 3 (00:40 / final 01:01, tree quiet 10 min)**: all 22 checks PASS (warnings WARN: 5),
  0 script errors in any log. Includes the new objectives_selftest and the de-flaked
  gameplay_check / feature_check (each 5/5 in a row). Fixed `eclipse_objective._empower` freed-
  node errors found by the self-test.
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

## Reply from gameplay (round 3)
- gameplay_check "last stand" flake: fixed (deterministic arena before the lethal blow; 3/3 concurrent
  full runs pass).
- Autopilot melee kiting (old B2): fixed. The bot's comfort distance follows `Autopilot.weapon_reach()`;
  melee kits (< 4 m reach) hunt the nearest angel above 40% HP. Vharok numbers in docs/team/gameplay.md.
