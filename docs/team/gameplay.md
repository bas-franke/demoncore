# Core gameplay (docs/team/gameplay.md)

Status: round 3 landed and tested (`tools/gameplay_check.gd`, 55 checks passing): Danger queries,
aim lanes, frenzy, zealot friendly fire, taunt + hit source, feel pass (scaled hitstop, kill
confirm, heartbeat, last stand), Ascension mode, fresh-save and per-map balance.
Owns the moment-to-moment feel: dash + i-frames, hit feedback, damage numbers (behaviour), enemy
AI state machines, wave pacing and difficulty, run state (HP flow, Ichor) and the run-end flow.

## Owned files
- `autoload/run_state.gd` (autoload **`RunState`**): run lifecycle, signal hub, Ichor, difficulty.
- `scenes/player/player_dash.gd` (`PlayerDash`): dash, i-frames, dodge, post-hit mercy frames.
- `scenes/pickups/ichor_drop.gd/.tscn` (`IchorDrop`): run-currency pickup.
- `scenes/spawner/*` (`EnemySpawner`, `SpawnRule`): spawn rate, wave pacing, horde rings, elites, boss timer.
- `scenes/enemies/enemy.gd`, `enemy_data.gd`, `holy_orb.gd`, `holy_smoke.gd`, `holy_telegraph.gd`: enemy AI.
- `scripts/autopilot.gd` (`Autopilot`): the --autopilot bot (movement, dashing, level-up picks).
- `scripts/danger.gd` (`Danger`): "is this spot about to be hit?" over every telegraph convention.
- `scenes/player/last_stand.gd` (`LastStand`), `scenes/ui/ascension_score.gd` (`AscensionScore`, minimal; UI may replace).
- `scenes/world/game_feel.gd` (GameFeel): hit feedback director (shared with visuals for the post-fx).
- `tools/gameplay_check.gd`: headless core-loop test.
- Shared, edited surgically: `scenes/player/player.gd` (movement/health parts), `scenes/main.gd`,
  `scenes/ui/game_over.gd` + `pause_menu.gd` (button handlers only; UI role owns the look),
  `scripts/damage_number.gd` (added `prefix` param + `PLAYER_HIT` color), `project.godot`
  (`RunState` autoload, `dash` input action).

## RunState API
```gdscript
RunState.active                 # true between start_run() and end_run()
RunState.currency               # Ichor carried this run; currency_earned = total picked up
RunState.heat                   # extra difficulty tiers (set by Progression pacts before the run)
RunState.wave / wave_kind       # 1-based wave, &"build" / &"surge" / &"lull"
RunState.last_result            # result dict of the last ended run
RunState.start_run()            # main.gd calls this after Game.reset()
RunState.end_run(victory, cause)  # ends once; cause &"slain" / &"victory" / &"abandoned" / custom
RunState.run_won() -> bool      # run ended in victory (player can't be hurt anymore)
RunState.return_to_basecamp()   # ends (abandoned) if needed, goes to scenes/basecamp/basecamp.tscn
RunState.restart_run()          # ends (abandoned) if needed, Meta.start_run() or main.tscn
RunState.add_currency(n) / spend_currency(n) -> bool / drop_currency(pos, amount, pieces)
RunState.difficulty_tier()      # minutes survived + heat
RunState.enemy_hp_mult() / enemy_damage_mult() / enemy_speed_mult()
```
Result dict keys: `victory, cause, time, kills, elites, bosses, level, wave, currency,
currency_earned, damage_taken, dodges, character`.

### Signals
| signal | when |
|---|---|
| `run_started()` | after main.gd set up the player |
| `run_ended(result)` | exactly once per run (death, victory, abandon) |
| `enemy_killed(position, data, elite)` | every enemy death; bosses pass their own EnemyData and `elite = true` (`RunState.is_boss_data(data)` tells them apart) |
| `player_damaged(amount, hp, max_hp)` | after HP dropped (includes per-frame contact ticks) |
| `player_dodged(amount)` | a hit was negated by dash i-frames (perfect dodge) |
| `player_dashed(direction)` | dash started |
| `player_died()` | HP reached 0 (run_ended follows in the same frame) |
| `currency_changed(total, delta)` | Ichor gained/spent |
| `wave_started(index, kind)` | pacing phase changed (`build` / `surge` / `lull`) |
| `difficulty_changed(tier)` | every minute (and heat) |

Game's low-level signals (`Game.enemy_hit`, `enemy_died`, `player_hit`, `boss_spawned`,
`boss_died`) still exist; RunState listens to them, so you need not edit emitters.

### Feel helpers
`RunState.shake(trauma)`, `RunState.kick_toward(world_pos, strength)`, `RunState.impact(0..1)`
(hitstop + shake). Lower level: `Game.hitstop(duration, scale)` and the `camera_rig` group
(`shake`, `kick`, `zoom_punch`, `set_zoom`, `set_focus_bias`; see scenes/camera/camera_rig.gd).
`scenes/world/game_feel.gd` (GameFeel) already reacts to big hits, elite kills, player hits and bosses.

### Ending a run from your system
- Objectives: `RunState.end_run(true, &"victory")` (or a custom cause). main.gd shows the end screen
  2 s later (golden "ASCENDANT" variant); the player becomes invulnerable at once.
- Meta (basecamp) pays Souls from `run_ended` (`result.currency` = Ichor carried). Don't bank Ichor elsewhere.

## Player: dash, i-frames, hits
- Input action `dash`: Space, Shift, pad A, pad right shoulder.
- Stats on `Player` (use `apply_stat`): `dash_speed` 21, `dash_time` 0.17, `dash_cooldown` 1.1
  (per charge), `dash_charges` 1, `hit_mercy_time` 0.45.
- `player.dash` (`PlayerDash`): `is_dashing()`, `is_invulnerable()`, `charges`, `max_charges()`,
  `recharge_ratio()` (0..1 for a HUD slot), `grant_iframes(seconds)` (abilities, revives),
  signals `charges_changed(charges, max)`, `dash_started(dir)`, `dash_ended`.
- While dashing the player's body collision layer is 0, so holy orbs/smoke pass through.
- `Player.take_damage(amount, source := Vector3.INF)` = a **discrete hit**: negated during dash
  (emits dodge + one short slow-mo), else knocks the demon away from `source` (falls back to the
  nearest enemy within 3 m; pass `player.global_position` for "no knockback"), grants mercy
  i-frames (body blinks) and shows a red damage number. Contact damage is continuous and uses an
  internal path (no mercy, no numbers).

## Enemy AI
`Enemy` state machine per behaviour (CHASE / SHOOT / CHARGE / HOP / SLAM) with states MOVE ->
WINDUP -> ATTACK -> RECOVER and ground telegraphs. Added:
- `setup(data, hp_scale, damage_scale, speed_scale)`; damage scale also applies to projectiles,
  stomps and slams.
- CHASE flanking: each chaser approaches at its own angle offset (+-0.7 rad, straightening
  within ~3 m), so crowds fan out and surround instead of trailing in a line.
- Hit stagger: effective knockback (`knockback * data.knockback_scale`) >= 2 freezes the enemy's
  own movement briefly; >= 5 cancels a non-elite's wind-up (telegraph vanishes, cooldown restarts).

## Wave pacing (EnemySpawner)
60 s waves: **build** 0-36 s (rate x0.75 -> x1.15), **surge** 36-50 s (x2.2, x1.54 in wave 1;
opens with a HUD toast from wave 2 on, a ring of 8 + 3/wave melee angels around the demon and an elite),
**lull** 50-60 s (x0.35). Boss timer unchanged (every 300 s, half spawn rate while alive, no
surge rings during a boss). All numbers are `@export`s on `Main/EnemySpawner`.
`spawn(data, angle := NAN) -> Enemy` spawns with current difficulty scaling.

## Ichor drops
Regular angel 12% for 1, elite 6 (3 drops), boss 40 (8 drops). Drops hop out of the corpse,
are magnetised by the PickupArea like soul shards, fade after 60 s, play `gold` and pop a
gold "+N". Tunables are `@export`s at the top of `run_state.gd`.

## Debug
F4 win the run, F6 +25 Ichor (debug builds). Test: `godot --headless --path . -s res://tools/gameplay_check.gd`.

## Audio hooks (added by sfx, see docs/team/sfx.md)
- `Game.enemy_struck(enemy, amount)`: new signal emitted in `Enemy.take_damage` right after
  `Game.enemy_hit`; Sfx picks the surface hit sound from `enemy.data` via `data/audio/enemy_audio.json`.
- `Enemy._set_state` plays `Sfx.play_enemy_voice(data, pos)` when entering WINDUP (per-enemy cry).
- New enemies: add their id to `data/audio/enemy_audio.json` (material + voice), or they fall back to
  keyword matching, then flesh.

## Round 2

### Support behaviours (EnemyData.Behavior, appended so old .tres numbers hold)
| behaviour | enemy (data/enemies) | what it does | tunables (EnemyData) |
|---|---|---|---|
| `HEAL` (5) | censer_nun | hangs back ~7 m; when an ally within `heal_radius` is under 90% HP it stops and channels a green circle (`windup_time`), then heals every non-boss ally inside by `heal_fraction` of max HP (green "+N") | heal_radius, heal_fraction, attack_cooldown |
| `SHIELD` (6) | paladin | slams like SLAM; every 0.25 s wards up to `ward_max` nearest allies within `ward_radius` (blue ring on the ground, halo over warded heads): they take `1 - ward_reduction` damage | ward_radius, ward_reduction, ward_max |
| `KITE` (7) | inquisitor | SHOOT that flees at an angle when the demon is inside 75% of `preferred_distance`, and keeps backing off while winding up / firing | preferred_distance, attack_cooldown |
| `EXPLODE` (8) | zealot | sprints (x1.25), lights a fuse inside `preferred_distance` (orange circle, quickening blink, creeps on), detonates for `explode_damage` in `explode_radius`. Killing it first defuses it; a detonation gives no XP / kill credit | explode_radius, explode_damage, windup_time |
| `SUMMON` (9) | throne | hangs back ~9 m; every `attack_cooldown` (while < `summon_max` minions live) channels and calls `summon_count` minions (`summon`, default cherub) around itself, scaled like their caller | summon, summon_count, summon_max |
`Enemy.apply_ward(seconds, reduction)` is public (abilities could use it for curses in reverse).
HolyTelegraph warnings now join group `danger_zones` while shown and expose `contains(point, margin)`
and `danger_center()` (the autopilot dodges them; AI or abilities may use them too).
docs/team/characters-new.md did not exist when this landed; the behaviour assignment above was made
in the .tres files directly. Characters-new: retune freely, the numbers are data.

### Bosses
- Boss HP scales with difficulty at spawn (any spawner: timer, objectives, F3): x`RunState.boss_hp_mult()`
  = 1 + 0.12 per (minute + heat), on top of the spawner's per-arrival step. Marked with meta `run_scaled`.
- `enemy_killed` for a boss carries the boss's EnemyData (matched from Game.boss_spawned tracking).
- Victory is wired by objectives: `ObjectiveDirector` calls `RunState.end_run(true, &"victory")` 4.5 s
  after the `victory_bosses`-th (default 3) boss falls (data/objectives/objectives.json settings).

### Autopilot (`--autopilot`, scripts/autopilot.gd)
Steering: pickups (chalices first when hurt) > open objectives (every other 20 s) > idle wander,
pushed away from nearby enemies, out of `danger_zones` telegraphs and boss hazards. Dashes when
standing in a telegraph, when 4+ enemies are within 2.2 m, or (sometimes) at low HP with contact.
Level-up picks prefer new abilities > ability ranks > new weapons > ability boons (abilities cast
themselves, so this is how bot runs exercise them). Typical bot run: 5 abilities, ~1000+ casts,
~130 dashes by minute 6.

### Balance (autopilot, ruined_sanctum, --fixed-fps 30)
Before: 243 / 369 / 378 / 639 s (the 639 s run won after 3 bosses). Enemy HP was linear
(+0.35/min); runs that fell behind early (few abilities) drowned at minute 3-4.
Now: enemy HP = 1 + 0.25 m + 0.025 m^2 (gentler early, steeper after ~6 min, when abilities and
synergies snowball), damage +0.09/min, speed +0.02/min (cap 1.3). Heat counts 0.5 min per point
(`RunState.heat_minutes`; Progression already passes 0.5 x its heat, so max pacts = +4.5 min
of scaling on top of the pacts' own effects).

| setting (bot now picks abilities + dashes; save had 2 dash charges) | survival (s) |
|---|---|
| linear 0.35/min, dmg 0.08 | 243, 369, 378, 639 (won) |
| 0.25 m + 0.02 m^2, dmg 0.08 | 302, 720+, 720+, 720+ (too easy late) |
| 0.25 m + 0.035 m^2, dmg 0.10 | 128, 283, 288, 365 (too hard) |
| **0.25 m + 0.025 m^2, dmg 0.09 (shipped)** | 207, 257, 287, 345, 528, 720+ (median ~5 min) |
| shipped + `--heat=12` | 138, 241, 272 |
Most bot deaths fall at 4-6 min (surges + first boss), where a human using the dash should do
better; strong runs reach the 3-boss victory. Next lever if runs feel short: map `spawner` blocks
(base_rate / rate_growth / ring sizes in data/maps/*.json), not the HP curve.
Measure: `scratchpad`-style script = load main.tscn with Game.autopilot, loop until
`RunState.active` is false, print `Game.elapsed`.

## Hooks added by characters-polish (one line each, marked `# characters-polish`)
- `scenes/player/player.gd` `take_damage()`: `model.hit_source = source` right before
  `_receive_damage()`, so `DemonModel.play_hurt()` flinches away from the real source (falls back
  to the nearest enemy for contact damage; trusted for 150 ms only).
- `scenes/enemies/enemy.gd` `take_damage()`: `model.jiggle_eyes(1.0, -knockback)`, so angels
  flinch away from the blow (zero knockback = away from the player).
Please keep both lines if you restructure these functions.

## Note from maps (round 2)
- `RunState._minutes()` now adds `map_difficulty_minutes()` (marked `# [maps]`): the live map's
  `"difficulty_minutes"` from data/maps/*.json (0 for the sanctum and gardens, up to 4 on Heaven's Gate).
  So HP / damage / speed scaling and `difficulty_tier()` start higher on harder maps. 0 outside a run.
- `scenes/enemies/enemy.gd`: `dir` (the move direction) is bent around walls by `Maps.steer()`, while
  the new `_aim` (straight at the player) drives facing, `_fire()`, charge / hop / slam lanes. There is
  also an un-stick nudge (`_stuck_t` / `_unstick_t`, `Maps.unstick()`), which only fires next to walls.
- `MapStatue` (scenes/maps/features) extends Enemy: a stationary breakable statue in group `enemies`.

## QA notes (from docs/team/qa.md)
- `Enemy._aim` (new) clashed with `_aim` in InquisitorBoss and ProcBoss (both fixed by renaming in the subclasses). When adding members to `Enemy`/`Boss`, grep the subclasses (`scenes/bosses`, `scenes/characters`) first. QA also fixed the static pools in `infernal_fx.gd` / `enemy_model.gd` / `damage_number.gd` that errored on freed nodes from the previous run (`# QA:`).

## Note from the objectives role (round 2)
- Fixed `RunState._on_boss_spawned`: `_bosses = _bosses.filter(...)` assigned an untyped Array to
  `Array[Node3D]` (and typed the lambda parameter, which errors on freed bosses), so the function
  errored before scaling any boss's HP. Now `_bosses.assign(_bosses.filter(func(b: Variant) ...))`.

## Note from characters-new (round 4): Enemy.heal + Game.enemy_healed
Marked block in `enemy.gd` (after `apply_ward`): `heal(amount, source := &"", show_number := true) ->
float` (clamped, refused while dying, green "+N", signal `healed(amount, source)`) and a new
`Game.enemy_healed(enemy, amount)` signal in game.gd. My support / miracle enemies use it (Virtue,
Paschal Lamb, Carrion Angel, Sanctified "hallowed"). Your `_cast_heal` could call it too so every
heal is tallied the same way. My speed buffs now use your `set_move_factor()` (sources
`flagellant_rage`, `hymn_blessing`, `sanctified`, `mimic`), and the Golden Legionary uses
`apply_ward()` for its frontal shield.

## Round 3

### Telegraph conventions + Danger
`Danger.threat_at(tree, pos, margin) -> Vector3` (push-away dir, ZERO = safe) / `is_threatened()`
reads: HolyTelegraph (group `danger_zones`), boss hazards (group `boss_hazards`, duck-typed lanes /
sectors / discs / bell rings / orbs), enemy projectiles (group `enemy_shots`, added by `Enemy._fire`),
and any node implementing `danger_contains(p, margin)`. The Autopilot steers and dashes with it.
Full conventions for enemy authors: docs/team/characters-new.md "Note from gameplay (round 3)".

### New EnemyData flags
`aim_line` (SHOOT/KITE lane telegraph, aim locks at 70%), `enrage_hp` / `enrage_speed_mult`
(one-time frenzy), `explode_ally_mult` (EXPLODE blasts hurt other angels, x2.5 of explode_damage
scaled with enemy HP growth; kills count for the demon, the bomber's own death does not).

### Enemy hooks (abilities, allies)
- `enemy.set_taunt_target(node, seconds)`, `clear_taunt()`, `is_taunted()`: move / aim at a decoy.
- `Enemy.hit(e, amount, knockback, source)`: `e.last_hit_source` = source during `take_damage()`
  (so `Game.enemy_struck` listeners know the weapon). All weapons now hit through it.
- Contact damage verified after perf's Crowd change (regression check in gameplay_check).

### Feel
- Enemy big hits: hitstop / shake / kick scale with how far above the running average a hit is
  (0.025-0.075 s). Player hits were already scaled by the HP fraction.
- Elite kills: gold "SLAIN" word (`DamageNumber.spawn_text`), hellfire ring, toll; plus the old
  hitstop / kick / zoom.
- Low HP: GameFeel's heartbeat now also plays `Sfx &"heartbeat"` per beat (sfx role adds the sound).
- **Last stand**: `Player.last_stands` (default 1, a stat). A lethal blow leaves 1 HP, 1.5 s of
  i-frames, a 6.5 m hellfire burst (max(80 x might, 60% of each angel's max HP), bosses 80 x might),
  heavy hitstop, "LAST STAND" text, `RunState.last_stand` signal. Counted in `RunState.last_stands_used`.

### Ascension (endless after a win)
On the victory screen "Ascend" -> `RunState.ascend()`: the run resumes, enemy HP x1.45^min,
damage x1.15^min, spawn rate x1.12^min (minutes since ascending); score = 20/s + kill points
(10 x 1.3^min, elites x5). Death ends it with `RunState.ascension_ended(result)` (NOT run_ended: the
run was banked at the victory). Result adds `ascension, ascension_time, ascension_score,
ascension_best, ascension_new_best`; best per map in SaveProfile `ascension.json`.
API: `can_ascend()`, `ascend()`, `ascending`, `ascension_score`, `ascension_minutes()`,
`spawn_rate_mult()`, `best_ascension_score()`, signals `ascension_started`, `ascension_ended`,
`score_changed`. UI coordination in docs/team/ui.md.

### Fresh-save balance (SaveProfile per career, wiped first; bot = --autopilot brain)
Target: a new player's first 3 runs last 3-5 min. The bot dodges and dashes better than a new
human, so bot runs of ~4-8 min map to that.
| globals | run 1 | run 2 | run 3 |
|---|---|---|---|
| base_rate 0.8, growth 0.025, HP 0.25 m | 345, 526, 720+ | 320, 720+, 720+ | 411 |
| **shipped: base_rate 0.9, growth 0.028, HP 0.28 m (+0.025 m^2)** | 227, 360, 470, 517 | 168, 358, 720+, 720+ | - |
Heat is 0 on a fresh save; heat weighting unchanged (0.5 min per point).

## Note from characters-new (round 5, marked edits in enemy.gd)
- `_cast_heal` now heals through `Enemy.heal(amount, &"heal_circle")` (same clamp, the same green
  "+N", plus `healed` / `Game.enemy_healed`); motes only when something was healed.
- `die()` emits a new `died(enemy)` signal and calls `model.on_host_died(enemy)` right after
  `_hide_telegraph()`, before `model.death_burst()`, so model-side death mechanics (martyr burst,
  revenant rise, Paschal Lamb heal, ice shards) can't be skipped by any death FX. Sanctified elites
  pay out on `died` too. Covered by `_roster_check.gd`.
- (QA, open) `tools/gameplay_check.gd` "last stand: lethal blow left 1 HP" is flaky: failed in 2 of 6 full-suite runs (22:43, 23:11), passed 4/4 when run alone. Likely the live boss / spawner hits the demon first (using up the last stand) or the blow lands while mercy i-frames are still up after the 90-frame wait. Suggest stopping the spawner + freeing the boss and asserting `last_stands_used == 0` / not invulnerable right before the blow.
- (QA, open) Autopilot still kites melee kits out of their own reach (`scripts/autopilot.gd` pushes away from every enemy inside `THREAT_RANGE` 5.5 m; Ravager's Cleave reaches ~2.6 m). In `flow_smoke --demons` Vharok and the new Iscariel often kill nothing in 15-30 s, so autopilot runs under-test melee demons (old tools/qa/BUGS.md B2). Suggest scaling the push radius to the shortest weapon reach unless hurt.

### Per-map pressure (bot profile with mid-career meta, 2 runs each, cap 720 s)
Knob ownership agreed in docs/team/maps.md ("Difficulty knobs: who owns what"): gameplay owns the
global curve + spawner defaults and tunes the ruined_sanctum baseline; maps owns every per-map offset.
I measured and posted; I did not edit map JSONs.
| map (difficulty) | survival s | read |
|---|---|---|
| ruined_sanctum (1) | 294, 412 | baseline |
| outer_gardens (1) | 313, 720+ | fine (easiest) |
| cathedral_city (2) | 155, 698 | wide; early villager swarms + ballistas |
| gilded_isles (2) | 164, 218 | **harder than its rating** (no difficulty_minutes but heavy pool) |
| ashen_wastes (3) | 93, 183 | **too hard for a 3**: dies before the 2nd surge |
| frozen_monastery (3) | 267, 643 | fine |
| sunlit_citadel (4) | 539, 720+ | **easier than its rating** |
| storm_spire (5) | 157, 309 | ok for a 5 |
| heavens_gate (5) | 106, 122 | finale; QA's note stands (gate it behind progression) |
Suggestions sent to maps: ashen_wastes `difficulty_minutes` 1.5 -> 0.75 or `base_rate` 1.0 -> 0.85;
gilded_isles set `difficulty_minutes` 0 and trim its early pool weights; sunlit_citadel +0.5
`difficulty_minutes`. (These runs used the round-2 kiting autopilot; melee kits now close in.)

### QA fixes (round 3)
- gameplay_check "last stand" flake: the check now builds a deterministic arena (spawner off,
  enemies and hazards cleared, fresh charge, i-frames waited out). 3/3 concurrent full runs pass.
- Autopilot melee: `Autopilot.weapon_reach(player)` (duck-typed weapon ranges x area). Below 4 m the
  kit counts as melee: the bot hunts the nearest angel while above 40% HP and keeps only
  ~0.55 x reach of comfort distance (ranged kits keep 5.5 m). Vharok (Cleave) bot runs now: 295 s /
  1568 kills, 354 s / 1567 kills, 720+ s / 9774 kills.
- (QA, 23:55) Re: `Abilities._end_run()` with a freed player on restart: re-checked. The QA fix is still in `autoload/abilities.gd:160` (`res.reset(player if is_instance_valid(player) else null)`), the only `res.reset` call site; the abilities split did not move it. `flow_smoke` now also does run -> `restart_run()` -> run and logs 0 errors. The AbilityResources errors in old logs (results/20261011_2224*, 2236*) predate the fix (22:40); if you still see it, send me the log.
- (QA, open) Another flaky check in `gameplay_check`: "EXPLODE: blast hurt the demon (193 -> 196)" failed in the 23:51 suite run: HP regen / a heal between the before and after reads outweighs the blast. Compare against damage taken (`RunState.damage_taken` or the `player_damaged` signal) instead of raw HP.
- (QA, round 3, done) Made the flaky checks deterministic in `tools/gameplay_check.gd` (`# QA:`): new `_isolate(p, spawner)` (spawner off; enemies, enemy_shots, boss_hazards, danger_zones, pickups, gems freed; regen 0; i-frames cleared via `_clear_iframes`). EXPLODE now runs in that sealed arena and sums `RunState.player_damaged` amounts instead of comparing raw HP. Last stand uses `_isolate` + `_clear_iframes` instead of waiting out timers. 5/5 consecutive runs PASS.
