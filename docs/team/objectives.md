# Objectives & Bosses (docs/team/objectives.md)

Role: in-map objectives, boss spawns, multi-phase bosses, objective tracker + markers.
Status: round 2 landed and self-tested (17 objective types + the Seventh Gate finale, 5 shared variants,
per-map preferences, 3 mid-run events, 3 own bosses incl. Azrafel's own fight, run-end scoring).

## Owned files
| Path | What |
|---|---|
| `data/objectives/objectives.json` | Every objective definition + director settings (data-driven, edit freely) |
| `data/bosses/bosses.json` | Boss roster (id -> EnemyData + scene + herald line) |
| `data/bosses/gate_archon.tres` | Azrafel, Archon of the Seventh Gate (finale boss, `ArchonBoss`) |
| `data/objectives/events.json` | Mid-run events (timings, per-map weights, event fields) |
| `data/bosses/grand_inquisitor.tres` | Grand Inquisitor EnemyData (Sariel's `sariel.tres` predates me; I maintain it now) |
| `scenes/objectives/objective_director.gd/.tscn` | `ObjectiveDirector`: spawns objectives, grants rewards, summons bosses (instanced in `scenes/main.tscn`) |
| `scenes/objectives/objective.gd` | `Objective` base class (life cycle, beacon, minimap marker) |
| `scenes/objectives/objective_fx.gd` | `ObjectiveFX` static helpers (beacon, ground zone, enemy spawn, corruption burst) |
| `scenes/objectives/objective_tracker.gd` | `ObjectiveTracker` UI: top-right list + on-screen / screen-edge markers |
| `scenes/objectives/types/*_objective.gd` | One script per objective type |
| `scenes/objectives/damned_soul.gd` | `DamnedSoul` ally wisp (freed souls) |
| `scenes/objectives/saint/*` | `SaintEnemy` (fleeing saint) + scene |
| `scenes/objectives/pylon/*` | `PylonEnemy` + `PylonModel` (Sanctified Pylons) |
| `scenes/objectives/objective_selftest.gd` | Dev self-test (see Validation) |
| `scenes/objectives/run_events.gd` | `RunEvents`: schedules the mid-run events (child of the director) |
| `scenes/objectives/run_score.gd` | `RunScore`: run-end score, grade, bonus (child of the director) |
| `scenes/objectives/profane_ground.gd` | `ProfaneGround`: lasting hell terrain (regen for the demon, burns angels) |
| `scenes/objectives/reaper/*` | `ReaperEnemy` + `ReaperModel` (the Pale Reaper event) |
| `scenes/bosses/phased_boss.gd` | `PhasedBoss`: shared multi-phase boss skeleton (extend it for new bosses) |
| `scenes/bosses/archon/*` | `ArchonBoss` (Azrafel) |
| `scenes/bosses/**` | Sariel (`Boss`, pre-existing) and the Grand Inquisitor (`scenes/bosses/inquisitor/*`) |

Small edits in shared files: `autoload/game.gd` (4 signals), `scenes/main.tscn` (ObjectiveDirector
node), `scenes/ui/boss_bar.gd` (duck-typed `is_enraged` + phase notches), `scenes/bosses/boss.gd`
(phase hooks), `scenes/spawner/enemy_spawner.gd` (`spawn_boss()` accepts any Enemy-based boss
scene, returns `Enemy`), `scenes/ui/run_ledger.gd` (grade line), `autoload/run_state.gd` (typed-array
fix in `_on_boss_spawned`), `data/dialogue/ending.json` untouched.

## Objective types (data/objectives/objectives.json -> `type`)
All are optional. Each sits DORMANT with a light-beam beacon until the demon engages it; untouched
ones fade after `dormant_life` s (the tracker warns for the last 30 s).

| type | id | What the demon does |
|---|---|---|
| `shrine` | desecrate_shrine | Stand in the shrine's circle for `channel_time` s (drains outside); guard waves from the rim. Statue sinks, flame turns to hellfire. |
| `relic` | corrupt_relic | Break `seals` seals by standing near a floating reliquary; it fights back with Judgement Pillars on/ahead of the demon; a guardian per seal. |
| `champion` | slay_champion | A crowned, scaled-up angel (base from `bases`) wakes at `wake_radius`, with one affix: radiant (pillars), zealous (fast), bulwark (tanky), choir_led (summons wisps), martyr (death ring of orbs). |
| `siege` | holy_siege | Step on the hellgate, then hold its circle for `duration` s against growing one-sided waves; leaving > `grace` s fails. Finale scorches every angel inside. |
| `souls` | free_damned | Break `cages` gilded cages (stand beside 1.2 s) within `time_limit`; each freed soul becomes a `DamnedSoul` ally for `ally_duration` s and pays `per_soul` rewards at once. |
| `saint` | hunt_saint | A saint flees (sprints when close, dawdles when far, bends around walls), leaving pillars in its wake; kill it within `time_limit` s or it ascends. |
| `ritual` | blood_sacrifice | Step into your ritual circle, then slay `kills` angels inside it within `time_limit` s; the circle lures angels in. Finale scorches the circle. |
| `pylons` | topple_pylons | Three marble Sanctified Pylons (`PylonEnemy`, targetable like angels) heal nearby angels with telegraphed pulses (and burn the demon inside). Break them all. |
| `gate` | storm_seventh_gate | **Finale** (see below): break 7 seals in the arena before the Gate under waves and pillars, then the doors open and the Warden (`gate_archon`) steps through. Slay it to win the run (`seventh_gate`). |
| `escort` | escort_reliquary | A cart with a stolen reliquary rolls only while the demon walks beside it, to a sigil ~30 m away; angels gnaw the cart (it has HP) and ambush ahead of it. |
| `font` | defile_font | Channel at a baptismal font while rings of purity roll out (step out or dash through); done = the area becomes **ProfaneGround** hell terrain for the rest of the run (Corruption.stamp; regen for the demon, angels burn). |
| `procession` | bishop_procession | A bishop walks a winding road to a cathedral sigil with escorts; it panics and flees when the demon closes in or strikes. Kill it before it arrives (or within the flight timer). |
| `towers` | bell_towers | King of the hill: corrupt three bell towers (4 s each); a held tower stays yours 10 s, then the angels reclaim it. Hold all three at once. Raiders hit the best-held tower. |
| `slaughter` | carnage_totem | Touch the totem: 40 kills anywhere in 30 s; it calls fodder around the demon. Spoils come to the demon. |
| `chest` | cursed_coffer | Break the lock; three ambush waves (the last led by a crowned warden) drop in. Clear them and the coffer opens. |
| `temptation` | altar_of_temptation | A deal floats over a black altar (curse for the run + a big reward, 4 deals in params). Kneel 2.5 s to accept. Never gets variants, max 2 per run. |
| `challenge` | bell_of_challenge | Ring the Bell of Challenge (stand under it 2 s) to call a boss early; slay it for a big reward. Only offered while no boss is up, max 2 per run. |

### Variants (shared `variants` list in objectives.json + a definition's own `variants`)
Each new objective has a `settings.variant_chance` (0.3, +0.03 per minute, max 0.8) to roll a variant:
**Gilded** (x1.8 rewards, more/tougher angels), **Hasty** (tighter timers, x1.35), **Warded** (a
crowned guardian answers when engaged, x1.5), **Bloodsoaked** (heal + chalices), **Martyrs'**
(drains faster, defenders more often; shrine/relic/font/towers only). The variant name prefixes the
title ("Gilded Desecrate the Shrine") and can recolour it. Fields: `id, name, weight, color,
min_time, types, params` (override), `param_mult` (scales numeric params the type has),
`reward_mult` (scales numeric rewards; x1.75+ bumps relic rarity), `rewards` (extra),
`guardian` / `guardian_hp`. Definitions with `"no_variants": true` (temptation, finale, events)
never roll one.

### Per-map preferences (objectives.json `map_preferences`)
`{map id: {"types": {type: mult}, "weights": {id: mult}}}` multiplies pick weights: processions
and bell towers in Cathedral City, fonts in the Outer Gardens, sieges in the Sunlit Citadel,
chests and escorts on the Gilded Isles, carnage and rituals in the Ashen Wastes, and so on. A map
definition's own `objectives.weights` (absolute) still wins.

### Definition fields
`id`, `type`, `title`, `description`, `glyph` (tracker/marker symbol), `color` (hex), `weight`
(pick weight), `min_time` (run seconds before it can appear), optional `dormant_life`,
optional `maps` (only on these map ids), optional `requires_no_boss`, optional `max_per_run`, `anchors` (GameMap objective anchor kinds to place on, tried
in order; `"*"` = any anchor; falls back to a random walkable spot), `params` (per type, documented
at the top of each type script), `rewards`.

### Rewards (any combination)
| key | effect |
|---|---|
| `xp_levels` | XP worth that many level-ups from the current progress (shard ring, or a Reliquary of Sin when big) |
| `souls` | meta Souls -> `Progression.add_currency(&"souls")` (falls back to `Meta.add_souls`) |
| `ichor` | run currency drops -> `RunState.drop_currency` |
| `sin_shards`, `hellstone` | meta loot pickups -> `Progression.drop_loot` |
| `relic` | a relic pickup of at least that rarity ("uncommon", "rare", ...) -> `Progression.drop_relic` |
| `heal`, `chalice` | heal now / Blood Chalice pickups |
| `boon` | `{stat, amount, label}`: permanent-for-the-run `Player.apply_stat` |
| `per_soul` | (souls type) a reward dict paid per freed soul |

### Settings (top of the JSON; per-map overrides)
`first_delay`, `initial_count`, `max_active`, `spawn_interval`, `min_distance`, `max_distance`,
`min_separation`, `dormant_life`, `boss_after_completions` (e.g. `[3, 7, 12]`: a boss arrives when
the run's completed-objective count hits each value), `boss_rotation` (roster ids),
`abandon_distance` (dormant objectives this far behind the demon fade early), `victory_bosses`
(**Final Judgement**: the run is won - `RunState.end_run(true, &"victory")` - when this many bosses
have been slain; 0 = endless; default 3, override per map).
Per map: `"map_settings": {"<map id>": {...}}` in objectives.json, **or** in the map definition
(data/maps/*.json) an `"objectives"` block: `{"settings": {...}, "include": [ids], "exclude": [ids],
"weights": {id: weight}}`. The map's `"boss"` (if it is a roster id) goes first in the rotation.

## Mid-run events (data/objectives/events.json, `RunEvents`)
First at ~140 s, then every 110-170 s (never while a boss is up, one at a time, weighted per map).
Each is an objective placed on the demon and engaged at once (tracker row, rewards, run score); they
do not count toward the boss thresholds.

| id | kind | What happens |
|---|---|---|
| crusade | crusade | Waves march in from one swinging front for 50 s; on wave 2 a crowned **Captain** (archon, x18 HP, banner) takes the field. Kill it for the rewards; outlast it and the crusade withdraws. |
| holy_eclipse | eclipse | 45 s black sun (screen shade + corona): every angel is empowered (x1.45 HP, x1.3 damage), but every kill drops an extra soul shard and banks Souls paid at the end. |
| angel_of_death | reaper | **The Pale Reaper** (`ReaperEnemy`, wandering mini-boss in group `champions`, not `boss`) hunts the demon for 90 s: Reap (wide arc), Harvest (pillar ring) every third reap. Kill it for a rare relic; else it departs. |

## Run-end scoring (`RunScore`)
On `RunState.run_ended` (not on abandon): score = objectives x100 (+50 per variant, +80 per event)
+ bosses x250 + minutes x25 + kills/4 - failures x30 + victory 600 (+400 Seventh Gate). Grades
S 2600 / A 1700 / B 1000 / C 450 / D. Bonus Souls S 120, A 70, B 35, C 15 (+ Sin Shards S 3, A 1),
paid through Progression. Written into the run result as `result["objectives"]` = `{score, grade,
completed, failed, variants, events, bosses, curses, titles, bonus_souls, bonus_shards}` and into
`Meta.pending_summary.objectives` (its `souls` includes the bonus). The end screen's RunLedger shows
a "GRADE A · score 1840 · 7 objectives" line (small edit in `scenes/ui/run_ledger.gd`).
Live: `director.score.report()`.

## Run victory (every objectives-side win calls `RunState.end_run(true, cause)`)
All wins go through `ObjectiveDirector.win_run(cause, delay)` (4-4.5 s pause, then
`RunState.end_run(true, cause)`; skipped if the demon died meanwhile).
- **Final Judgement** (`&"victory"`): `settings.victory_bosses` bosses slain in one run (default 3).
  Disabled on finale runs and on maps with their own Seventh Gate (the Gate is the win there).
- **Storm the Seventh Gate** (`&"seventh_gate"`, the story ending): definition `"finale": true`.
  Offered once per run, at `min_time` (150 s), never expiring, when `finale_available()`:
  the map is in `settings.finale_maps` (`sunlit_citadel`) and the Dialogue flag `settings.finale_flag`
  (`known.march`) is set, or the map definition has `"finale": true` (no flag needed).
- **Map-authored Seventh Gate** (heavens_gate map, `scenes/maps/features/seventh_gate.gd`, maps
  role): the director finds it (group `map_interactables`, signals `seals_changed`/`opened`), turns
  off its own finale and Final Judgement there, and when the Gate's last ward breaks it **always**
  summons the Warden, Azrafel (`gate_archon`), raising the Gate's `bosses_required` past the current
  count so the doors open on Azrafel's death (settings `warden_always: false` restores the old
  only-if-short rule).
  The Gate itself ends the run with `seventh_gate`.
- Story: the old 2-boss fallback rule is gone (ending_rule is now cause-based); new boss id for
  story pools: `gate_archon` (Azrafel, Archon of the Seventh Gate; Sariel's AI with the Archon model).

## Map integration (for the maps role)
- Place anchors with `GameMap.objective(kind, pos)`. Kinds I look for: `shrine`, `altar`, `relic`,
  `arena`, `landmark`, `ritual`, `graveyard`, `prison`, `chapel` (any kind works with `"*"`).
  Each anchor hosts at most one objective per run. Without anchors (open sanctum) objectives land
  20-34 m from the demon on walkable ground (`Maps.random_point`).
- Objective enemies and boss relocations are clamped with `Maps.clamp_to_bounds`.
- Set `"boss": "grand_inquisitor"` (or `"sariel"`) in a map definition to pick the map's first boss.

## Bosses
Roster: `data/bosses/bosses.json`. Bosses arrive (a) on the EnemySpawner timer (every `boss_time`
s; the director swaps `EnemySpawner.boss/boss_scene` to the next roster entry after each arrival)
and (b) when completed objectives hit `boss_after_completions`. One boss at a time; extra summons
queue. A herald banner precedes each by 3 s.

### Azrafel, Archon of the Seventh Gate (`ArchonBoss` extends `PhasedBoss`, three phases)
| Phase | HP | Attacks |
|---|---|---|
| I The Warden | 100-70% | Cleave (wide arc ahead), Lance Dash (a warning lane, then it charges down it), Sevenfold Brand (7 pillars marching at the demon) |
| II The Seventh Light | 70-35% | + Wheel of Light (6 lanes from its body, twice, offset), Triple Dash (re-aims), two Sentinels join |
| III Wrath of the Throne | < 35% | + Dawn Wings (huge arcs left, right, ahead), Halo Rings (orb rings), Bell of Dawn (3 expanding rings) |

New bosses: extend `PhasedBoss` (set `phase_lines`, `phase_names`, `cooldowns` in `_init()`,
override `_start_attack` / `_release_attack` / `_action_process` / `_on_phase_begin`).

### Ozias, the Grand Inquisitor (`InquisitorBoss`, three phases)
| Phase | HP | Attacks (all telegraphed on the ground) |
|---|---|---|
| I Interrogation | 100-66% | Chains of Penance (3 fanned lanes), Brand (pillars chasing the demon), Censure (a cross of lanes on the demon) |
| II Trial by Fire | 66-33% | + Sanctified Pyre (disc around itself), Censer Sweep (200-degree arc), 5 lanes, Censer Clerics join |
| III Auto-da-fe | < 33% | + Bell of Judgement (3 expanding rings), Rain of Judgement, double cross, pyre on the demon, faster tells |
Phase changes: untouchable rise for 2.4 s, a short ring of fire, minions; damage cannot skip a phase
(the hit is clamped at the line, re-entrant hits cannot double-advance, and `die()` before the last
phase becomes a phase change instead, so even external hp / max_hp changes cannot skip one).
**Bell of Judgement vs. the dash:** dashing through a ring's front shatters the whole ring (no
damage) and the blow rebounds on the boss that rang it (2% of its max HP; `BellRing.SHATTER_RECOIL`).
Rings cast by objectives (`boss_recoil = false`, e.g. the font) shatter without the recoil.
Hazard classes (reusable, all in group `boss_hazards`, `dissipate()` on boss death):
`InquisitorLane.cast(from, dir, length, width, tell, dmg)`, `PyreBurst.cast(center, r, tell, dmg,
dir, half_angle)`, `BellRing.cast(center, max_r, speed, width, dmg, delay)`, plus Sariel's
`JudgementPillar.cast(at, r, tell, dmg)` and `SarielOrb.fire(at, vel, dmg, life)`.

### Boss UI hooks (any boss script)
- group `boss`, extends `Enemy` (`hp`, `max_hp`, `data.display_name`, `is_dying`)
- `is_enraged: bool`, `phase_index: int`, `phase_count: int`, `phase_thresholds() -> Array[float]`
  (HP ratios; the boss bar draws notches there), Inquisitor also `phase_name()`
- `Game.boss_spawned(boss)`, `Game.boss_phase_changed(boss, phase)`, `Game.boss_died(position)`

## Signals / API for other systems
- `Game.objective_started(id)`, `Game.objective_completed(id, rewards)`, `Game.objective_failed(id)`
- `var d := get_tree().get_first_node_in_group(&"objective_director") as ObjectiveDirector`
  - signals `objective_added/activated/completed/failed/removed(objective)`, `boss_summoned(boss)`,
    `souls_earned_changed(total)`
  - `d.objectives` (live `Objective`s), `d.open_objectives()`, `d.completed_count`, `d.souls_earned`
  - `d.spawn_objective(id := "", near := Vector3.INF)`, `d.summon_boss(id := "")`,
    `d.make_boss(id, hp_scale) -> Enemy` (unspawned), `d.win_run(cause, delay)`, `d.finale_available()`,
    `d.grant(rewards: Dictionary, at)`, `d.add_souls(n)`, `ObjectiveDirector.xp_for_levels(levels)`
- `Objective`: `title`, `description`, `glyph`, `color`, `state` (DORMANT/ACTIVE/COMPLETED/FAILED/EXPIRED),
  `progress` (0..1), `status_text`, `marker_position()`, `time_to_expire()`; group `objectives`.
- Tracker: `ObjectiveTracker` (child of the director): `list_top`, `list_right`, `show_list`,
  `show_markers` (UI may reposition it). Objectives also appear on the HUD minimap (group
  `minimap_marker`, metas `minimap_color/size/pin/label`).
- Allies: `DamnedSoul` nodes are in group `allies`.

## Validation
- After adding a `class_name`: `<godot> --headless --path . --import` (refreshes the class cache).
- `--objectives-selftest=<mode>`: `bosses`, `new` (round-2 types), `events`, `id:<objective id>`, or
  nothing for everything. The test zeroes the demon's XP gain (no level-up pause) and runs without
  `--autopilot`. Dev args also: `--event=<id>` (3 s), `--no-events`.
- `<godot> --headless --path . res://scenes/main.tscn -- --godmode --autopilot --objectives-selftest`
  runs every objective and boss in turn and prints `OBJTEST ...` lines, ending with
  `OBJTEST DONE fails=0`.
- Dev args: `--objective=<id>` (spawns it beside the demon at 2 s), `--summon=<boss_id>` (4 s),
  `--no-objectives`. Debug key **F8**: spawn the next objective beside the demon.

## Work log
- Round 2: Azrafel's own fight (`ArchonBoss`, `PhasedBoss` base); 7 new objective types (escort,
  font + ProfaneGround, procession, towers, slaughter, chest, temptation); shared variants and
  per-map preferences; mid-run events (crusade, eclipse, Pale Reaper); dash-through shatters Bell
  rings; run-end score / grade / soul bonus on the end screen; Azrafel always guards the map's
  Seventh Gate; fixed RunState._on_boss_spawned typed-array error (boss HP scaling never applied).
- Pass 3: Seventh Gate finale objective + Gate Archon boss, map-gate integration (warden summon),
  `win_run()` for every objectives-side victory, roster banners (`rage_text`/`felled_text`),
  `make_boss()`, boss bar holy style on.
- Pass 2: ritual / pylons / challenge objectives, Final Judgement victory (3 bosses), dormant
  objectives left far behind fade early, tracker markers avoid the HUD and the list.
- Pass 1: director, 6 objective types, tracker/markers/minimap, rewards wired to Progression /
  RunState / Meta, Grand Inquisitor (3 phases, 7 attacks, 3 new hazard types), boss rotation +
  objective-triggered bosses, boss bar phase notches, Sariel phase hooks.

## Responses
- UI: agreed, `holy_style = true` is now set on Main/BossBar. Tracker glyphs still use text (they
  render fine with the serif fallback in our screenshots); GlyphIcon is a good fallback if not.
- Story: finale built (above). Pools for the new boss: `boss_intro.gate_archon`,
  `boss_rage.gate_archon`, `boss_death.gate_archon`.

## Request from the UI role (docs/team/ui.md)
- Boss bar holy styling: `scenes/ui/boss_bar.gd` now has `@export var holy_style := false`. When on,
  the angel's fill is radiant gold (white-hot when enraged) and the lingering "damage dealt"
  segment is blood red, so the boss reads as "the other side" next to the demon's crimson life bar.
  It is **off** until you agree: set `holy_style = true` on the BossBar node in `scenes/main.tscn`
  (or tell me in docs/team/ui.md and I flip it). Nothing else changes.
- Objective glyphs: `GlyphIcon` (ui/components/glyph_icon.gd) paints ☠ ♛ ⛨ ⛧ etc. in code; your
  tracker can use it instead of text glyphs if the OS font renders them as colour emoji.

## Request from the story role (docs/team/story.md): the Seventh Gate ending
- The game has no story victory yet, so the story role owns a **fallback win condition**
  (`StoryHooks._watch_ending_rule`, data: `ending_rule` in `data/dialogue/ending.json`): on map
  `sunlit_citadel`, once the story flag `known.march` is set (around run 12+), felling **2 bosses in
  one run** calls `RunState.end_run(true, &"seventh_gate")`.
- If you build a proper finale (e.g. a "Storm the Seventh Gate" objective or an Archon boss), end
  the run with `RunState.end_run(true, &"seventh_gate")` and it counts as the ending. Make it
  available only when `Dialogue.has_flag("known.march")`. Then set `"boss_kills": 99` in
  `ending_rule`, or ask me to, so the fallback steps aside.
- Story lines exist for any boss: pools `boss_intro.<id>`, `boss_rage.<id>`, `boss_death.<id>`,
  `boss_phase.<id>.<phase>` (Ozias has phase 1 and 2 lines). New bosses: tell me their ids.

## characters-polish hooks in boss files (marked `# characters-polish`)
- `scenes/bosses/sariel_model.gd`: `motion = CharacterMotion.attach(_glb, self, null, _tree)` in
  `build()` (procedural physics on Sariel's 6 wings, veil and robe strips, torso lean, hit flinch,
  driven after your AnimationTree's manual `advance()`), and `motion.weight` follows kneel /
  dissolve in `animate()` so the death sequence owns the body.
- `scenes/bosses/inquisitor/inquisitor_model.gd`: `wrap_pose_pivot = true` in `build()`: after
  build the model's children move under `EnemyModel.pose_pivot` (node refs unchanged) for the hit
  flinch (scaled down by boss size, rate-limited). Remove the line if it fights your pose code.
- Any boss model extending `EnemyModel` gets the flinch from `Enemy.take_damage` -> `jiggle_eyes`.
- (round 3) Glyphs: your tracker rows now use `GlyphIcon` for the objective glyph, and on-screen
  markers pass the glyph through `GlyphIcon.plain()` (text-safe stand-in). Two small edits in
  objective_tracker.gd (`_make_row`, `_glyph`); revert freely if you prefer your own drawing.

## Note from maps (round 2)
The finale you asked for exists as a map set piece: `heavens_gate` + `SeventhGate` (scenes/maps/features)
calls `RunState.end_run(true, &"seventh_gate")`. That map sets `"objectives": {"settings":
{"victory_bosses": 4}}`, so Final Judgement stays a fallback there. Maps now also have interactables
(group `map_interactables`, signal `activated`): holy fonts, summoning bells and breakable statues
(`MapStatue`, an Enemy in group `enemies`). Skip them in kill-count objectives if needed (`e is MapStatue`).

## Note from characters-new: three more bosses (ProcBoss)
`frost_abbot` (frozen_monastery), `verdant_matriarch` (outer_gardens) and `dawn_wyrm`
(sunlit_citadel) are in `data/bosses/bosses.json` and set as those maps' `"boss"`. They run on
`ProcBoss` (scenes/characters/bosses/proc_boss.gd, extends Enemy): 3 phases each, built only from
your hazards (InquisitorLane, PyreBurst, BellRing) and Sariel's (JudgementPillar, SarielOrb), same
hooks as yours (`phase_index`, `phase_count`, `phase_thresholds()`, `phase_name()`, `is_enraged`,
Game.boss_spawned / boss_phase_changed / boss_died, `setup(data, hp_scale)`). `--summon=<id>` works.
Tested by `scenes/characters/_roster_check.gd` (summon, every phase, death). Feel free to retune
their `cfg` (patterns, minions, cooldowns) in the subclass scripts.

## Note from maps (round 3): interactable objectives + statues
- New type `interactables` (`scenes/objectives/types/interactables_objective.gd`, written by maps):
  use `count` of the map's own features of kind `feature` ("font" = corrupt a HolyFont, "bell" =
  strike a SummoningBell). It stands over the nearest unused one, engages on the first use, optional
  `time_limit`, expires at once if the map lacks enough features. Two entries are in objectives.json:
  `profane_fonts` (2 fonts, 90 s, maps with 2+ fonts) and `toll_the_bell` (1 bell). Retune or
  rename freely. Test: `tools/maps/feature_check.tscn` (FEATURECHECK lines).
- Breakable statues (`MapStatue`, group `map_features`) no longer emit `Game.enemy_died` or count in
  `Game.kills`. `ObjectiveFX.spawn_enemy`'s cap and the spawner cap subtract them (marked `# [maps]`).

## QA notes (from docs/team/qa.md)
- QA renamed `InquisitorBoss._aim` to `_sweep_aim` (`# QA:`): gameplay added `Enemy._aim` and the Inquisitor stopped compiling ("member already exists in parent class").

## Note from characters-new (round 3)
- Four more ProcBoss bosses in bosses.json: `war_chariot` (ashen_wastes' `"boss"`), `storm_archon`
  (storm_spire), `gilded_seraph` (gilded_isles), `cantor` (ruined_sanctum: added after Sariel via
  the map's `"objectives": {"settings": {"boss_rotation": [...]}}` block). Tested through all phases.
- **Hazard tints (marked edits in your files):** `HolyFX.hazard_tint` (static, default Art.HOLY) +
  `HolyFX.white_of(c)`; InquisitorLane, PyreBurst, BellRing, JudgementPillar and SarielOrb copy it
  into their new `tint` member when created and use it wherever they used Art.HOLY / HOLY_WHITE
  (only in instance code; default look unchanged). ProcBoss sets it around everything it casts from
  its `cfg.hazard_tint`. To tint your own casts: `HolyFX.hazard_tint = c; X.cast(...);
  HolyFX.hazard_tint = Art.HOLY`.
- **Sanctified elites** (`Sanctified.apply(enemy, affix)`, scenes/characters/elites/sanctified.gd):
  a gold aura + crown overlay for any Enemy, x3 HP, x1.3 damage and one affix. The affix ids and
  names are yours: radiant, zealous, bulwark, choir_led, martyr (+ `hallowed`, heals nearby angels);
  `Sanctified.AFFIX_NAMES` mirrors your AFFIX_NAMES and `Sanctified.title_for(name, affix)` builds
  "Radiant X, the Dawnbringer". The champion could call `Sanctified.apply(_champion, _affix)` for
  the aura (it skips enemies in group `champions` automatically otherwise). Rolled per spawn by
  `RosterDirector` (main.gd, one line), from 90 s, 1.5% + 0.6%/min (max 6%, max 4 alive).
  Dev: `-- --sanctify-all`.
- Map event: `CelestialWhale.spawn_pass()` - a whale of light drifts over the demon shedding
  telegraphed pillars; RosterDirector runs it every 170 s on open-sky maps (`-- --whale=<s>`).

## QA notes (from docs/team/qa.md)
- QA added your self-test to `tools/qa/run_all.sh` as `objectives_selftest` (`main.tscn -- --godmode --objectives-selftest`, run with `--fixed-fps 60 --disable-vsync`: ~135 s instead of >10 min in real time; skipped by `--quick`). It passed at 00:40 (17 completed, 0 fails). Tell me in qa.md if the flags change.
- QA fixed `scenes/objectives/types/eclipse_objective.gd` `_empower()` (`# QA:`): the deferred call got enemies freed in the meantime, and the typed `n: Node` parameter made the engine reject it (31 "Cannot convert argument 1 from Object to Object" errors per self-test). Now untyped + `is_instance_valid` first.
