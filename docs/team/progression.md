# Progression & upgrades (docs/team/progression.md)

Status: round 2 landed and tested (`tools/progression_check.gd`, `tools/progression_run_check.gd`,
`tools/progression_economy_sim.gd`). Owner of the *second layer* of meta progression and in-run loot quality.

## Split with Basecamp (`Meta`) and Gameplay (`RunState`) — settled, no duplication
- **`Meta`** (basecamp) owns **Souls**, the souls upgrade catalog (`data/meta/upgrades.json`), shops,
  shopkeepers, maps and scene flow, saved in `user://meta_save.json`. Progression never stores souls; it
  reads/spends/adds them through Meta (`Progression.get_currency(&"souls")` etc. proxy to Meta).
- **`RunState`** (gameplay) owns the in-run currency **Ichor** (this game's "gold"), the run lifecycle and
  `heat`. Progression sets `RunState.heat` from the chosen pacts at run start (x `HEAT_TO_RUNSTATE`).
- **`Progression`** (`autoload/progression.gd`, save `user://progression.json`, version 2, atomic) owns:
  Sin Shards + Hellstone, the upgrade tree (incl. school branches), unlocks (demons / weapons / abilities),
  pacts (heat), per-demon **mastery**, the **relic codex**, the **Hellstone respec**, currency **transmutes**,
  **map gates**, in-run relics, rarity, rerolls / banishes, starting boons / relics.
- Basecamp sells Progression wares: `occultist` -> shop `occult`, `blacksmith` -> `hellforge`,
  `soul_broker` -> `bindings` (`Basecamp.PROGRESSION_SHOPS`); its Covenant stall edits pacts. Item tabs come
  from `item_info().category` (school name, "Rites") else the currency name.

## Owned files
| File | What |
|---|---|
| `autoload/progression.gd` | `Progression` autoload (everything below) |
| `scripts/progression/rarity.gd` | `Rarity`: tiers, weighted `roll(luck, min, max)`, colours (from `UIPalette`), `BOON_POWER` |
| `scenes/progression/shard_pickup.gd`, `relic_pickup.gd`, `relic_hud.gd` | Loot pickups and the in-run strip |
| `data/progression/currencies.json` | Currency names / glyphs / colours |
| `data/progression/upgrades.json` | 40-node upgrade tree (format in its `_doc`) |
| `data/progression/unlocks.json` | Demon / weapon / ability unlocks (anything not listed is free) |
| `data/progression/pacts.json` | Heat pacts |
| `data/progression/relics.json` | 34 relics (14 stat relics, 10 school relics, 10 build-defining legendaries) |
| `data/progression/mastery.json` | Mastery XP curve, level rewards, signature boons, mastery skins |
| `tools/progression_check.gd`, `progression_run_check.gd`, `progression_economy_sim.gd` | Tests + economy simulator |

Small surgical edits in shared files (marked with comments):
- `scripts/upgrades/upgrades.gd`: `_roll_rarity()` on passive boons (meta `&"rarity"`), banish filter.
- `scenes/ui/level_up_menu.gd`: rarity on the card sigil; fate bar with Reroll [R] / Banish [B].
- `scenes/menu/demon_select.gd`: sealed demons; mastery line (`_mastery_text`).
- `scenes/ui/run_ledger.gd`: end-screen line with `Progression.rewards_text()`.
- `scenes/basecamp/basecamp.gd`: shop tab uses `item_info().category` when set.
- `autoload/meta.gd`: `map_requirement()` also asks `Progression.map_gate()`; `_ready` catches a Player that
  entered the tree before the autoload connected `node_added` (editor launch of `main.tscn`).
- `data/maps/{cathedral_city,frozen_monastery,sunlit_citadel,gilded_isles}.json`: `unlock` blocks (gates).
- `data/skins/skins.json`: 6 mastery skins appended (`mastery_<demon>`, `archfiend`).
- `project.godot`: autoload `Progression`.

## Upgrade tree (40 nodes)
- **Core** (10): luck, rerolls, banishes, starting boons, Shadowstep dash charges, Ichor gain, shard gain,
  starting relics, Archfiend might, Molten Heart.
- **School branches** (10 schools x 3 = 30), one per combat style in docs/team/abilities.md:
  1. `<School> Attunement` (Souls, 3 ranks): +6% `tag:<school>` ability damage per rank.
  2. School mechanic (Sin Shards, 2 ranks, needs Attunement II): burn power, knockback, bind duration,
     life-cost cut, curse power, shadow crit, DoT rate, +1 summon, +40 soul cap, +1 chain jump.
  3. Capstone (Sin Shards, needs rank 2): start every run with the school's starter ability
     (cinder spray, brimstone maul, hellhook, hemorrhage lance, hex of frailty, shadow daggers,
     blight spit, raise thralls, soul siphon, ball lightning).
  Hellfire / Brimstone / Chains at the blacksmith, Blood / Curses / Shadow / Plague at the occultist,
  Necromancy / Soul Harvest / Storm at the soul broker.
- Effect kinds: `{stat}` (Player.apply_stat or run stat), `{ability_mod: "<Abilities mod key>"}` (added to
  `Abilities.mods` once the Abilities run binds), `{grant_ability}`, `{on_hit}` / `{on_kill}` (Abilities effects).

## Relics (34)
Stat relics as before, plus 10 uncommon/rare **school relics** (`ability_mods` for one tag) and 10
**legendaries** that define builds via `ability_mods` + global `on_hit` / `on_kill` effects: Crown of the
Ninth Circle (burn on hit), Phylactery of the Lich (+2 summons), Stormcaller's Heart (arcing lightning),
Censer of Pestilence (plague spreads on kill), Chalice of Ichor (blood rites half cost + heal on kill),
Executioner's Hood (execute), Shackles of the Fallen (bind on hit), Mask of Malediction (curse on hit),
Lantern of the Ferryman (souls), Heart of the Falling Star (burning blasts on kill). Relics carry `tags`;
drops weight relics matching your build's tags (`Abilities.owned_tags()`) x3.

## Mastery (per demon)
- Every run adds XP to the demon you played: `10 + 8/min + 0.02/kill + 2/level + 25/boss + 60 on victory`,
  x(1 + 5%/heat). Level n -> n+1 costs `80 + 40 (n-1)` XP, max X (2160 XP, ~14-18 runs on one demon).
- Rewards: II +2 shards, **III signature boon I**, IV +3 shards, **V mastery skin**, VI +1 Hellstone,
  **VII signature boon II**, VIII +5 shards, **X "Archfiend Ascendant" skin** (any demon) + 2 Hellstone.
- Signature boons: Vharok *Ravager's Fury* (brute/knockback/HP), Lilaeth *Hymn of Cinders* (fire, burn on hit),
  Morvane *Hexbinder's Litany* (curses), Skarn *Warden's Shackles* (binds, chain jumps), Ysolde *Pale Harvest*
  (souls, shadow). Applied in `apply_to_player` for the chosen demon.
- Skins: unlock ids `mastery:<model id>:<level>` / `mastery:any:<level>` resolve through
  `Progression.is_unlocked()`, which `DemonSkins.is_unlocked()` already calls — no code on the skins side.

## Respec, transmutes, codex, map gates
- **Unbinding Rite** (`&"respec"`, sold in `hellforge`): refunds every upgrade rank in the currency paid;
  costs 1 / 2 / 3 Hellstone (rising per use, capped). Unlocks are kept. `respec_cost()`, `respec_refund()`, `respec()`.
- **Transmutes** (sold in `bindings`, repeatable): 450 Souls -> 1 Sin Shard, 12 Sin Shards -> 1 Hellstone.
  Late-game sink so surplus Souls still progress the shard/hellstone tail.
- **Relic codex** (for the UI): `codex_entries()` -> `[{id, name, icon, rarity, tier, color, description,
  tags, discovered, times_found}]`, `codex_progress()` -> `{found, total, by_tier}`, `signal codex_updated(id, n)`.
  First finds toast "New relic recorded in the Codex".
- **Map gates**: a map JSON's `unlock` block may add `progress {stat, min, hint}`, `cleared "<map id>"`
  (boss slain or win there), `mastery N` (any demon), `story "<Dialogue flag>"` + `story_hint`.
  `Progression.map_gate(id) -> reason`, `map_stats(id) -> {runs, victories, bosses, best_time}`. Meta enforces it.
  Current chain: Ruined Sanctum + Outer Gardens open; Cathedral City (2 runs, 60 Souls); Gilded Isles
  (3 relics found, 150 Souls); Frozen Monastery (a boss slain, 150 Souls); Sunlit Citadel (conquer the
  Monastery + mastery IV, 300 Souls).

## Economy (round 2 tuning)
Simulated with `tools/progression_economy_sim.gd` (8 careers per profile, real reward + shop code, greedy
buyer, progression-seeking map choice, heat taken once 35-60% of the catalog is owned). "Full" = every
Progression rank and unlock, every Meta rank and every map.

| Profile | runs to 50 % | 75 % | 100 % |
|---|---|---|---|
| novice (dies at 4-11 min, 45% boss kill) | 15 | 25 | 54 (52-63) |
| average (6-15 min, 70% boss kill) | 10 | 15 | **31 (30-33)** |
| expert (9-18 min, 90% boss kill, uses heat) | 7 | 9 | 20 (18-23) |

Catalog totals: 665 Sin Shards, 39 Hellstone, 6020 Souls (Progression) + 6620 Souls (Meta upgrades + maps).
Income per average mid-game run: ~250-900 Souls, 4-8 Sin Shards, 0-1 Hellstone (+2-5 late with heat).
Levers: costs in the JSONs (I scaled shards x2.1, hellstone x1.8, souls x1.5 from round 1), `RUN_SHARDS` (1 per
run, novice catch-up), `SHARDS_PER_MINUTE` 0.25, `SHARD_CHANCE_ELITE` 0.3, `BOSS_SHARDS` 3, `HEAT_*`,
`TRANSMUTES`. The shape: Souls gate the first ~15 runs, Sin Shards + Hellstone the tail; transmutes stop the
tail from stalling once the Souls catalogs are done.

## API
```gdscript
# currencies (souls proxy to Meta)
Progression.get_currency(&"sin_shards") -> int      Progression.add_currency(id, n)   Progression.spend(id, n)
Progression.get_currency_def(id) -> {name, icon, color}            signal currency_changed(id, total)
# shop
Progression.get_shop_items("occult") -> Array[StringName]   (includes &"respec" / transmute ids)
Progression.item_info(id) -> {name, icon, description, level, max_level, maxed, cost, currency, currency_name,
                              currency_icon, currency_color, effect, next_effect, reason, kind, category}
Progression.buy(id) -> bool   can_buy(id)   block_reason(id)   get_level(id)   meta_bonus(&"luck")
Progression.is_demon_unlocked(demon)  is_weapon_unlocked(scene)  is_ability_unlocked(id)  is_unlocked(id)  grant_unlock(id)
Progression.respec_cost() / respec_refund() / respec()      Progression.transmute(id)
signal upgrade_bought(id, level)   signal unlocked(id)   signal respecced(refund)
# pacts / heat
Progression.pact_defs  get_pact_rank(id)  set_pact_rank(id, rank)  get_heat()  pact_total(effect)  heat_rewards(heat)
# mastery
Progression.demon_id_of(demon_data) -> &"vharok"     mastery_level(id)   get_mastery_xp(id)
Progression.mastery_progress(id) -> {level, xp, into, need, maxed, signature_rank, next_reward}
Progression.signature_info(id) / signature_text(id) / signature_rank(id)   add_mastery_xp(id, xp)
signal mastery_changed(demon_id, level, xp)
# codex / maps
Progression.codex_entries()  codex_progress()  signal codex_updated(id, times)
Progression.map_gate(map_id) -> String   is_map_open(map_id)   map_stats(map_id)
# in-run
Progression.get_run_stat(&"luck")  get_luck()  apply_stat(stat, amount)  apply_effect(effect, rank)
Progression.rerolls_left / banishes_left / use_reroll() / use_banish(title) / is_banished(title)
Progression.roll_relic(min_tier)  grant_relic(id)  drop_relic(pos, min_tier)  drop_loot(pos, id, n)
signal relic_gained(relic)   signal run_loot_changed(id, amount)
# end of run
Progression.last_rewards -> {victory, heat, time, shards, hellstone, relics, souls_bonus, mastery: {...}}
Progression.rewards_text()   static compute_run_rewards(...)   mastery_xp_for(...)   signal rewards_banked(rewards)
Progression.get_flag(key, default) / set_flag(key, value) / stats
```

## Dev / test
- Args after `--`: `--unlock-all`, `--rich`, `--reset-progress`, `--heat=N`, `--relics=N`, `--loot-test`.
- `progression_check.gd` (data, buying, gating, rarity, mastery, respec, transmute, codex, map gates, save)
- `progression_run_check.gd` (real run: stats, Shadowstep full charges, school mods + capstone ability,
  boss loot, relic pickup, banking, mastery XP, codex)
- `progression_economy_sim.gd -- --careers=8 --csv=out.csv` (the table above). All three restore
  `user://progression.json` and `user://meta_save.json`; don't run them while playing (they share the saves).

## Round 3
- **Save isolation**: `scripts/save_profile.gd` (`SaveProfile`). Progression, Meta (marked edit) and Dialogue
  (marked edit) save to `SaveProfile.path(file)`: `user://<file>` normally, `user://test/<profile>/<file>` with
  `--save-profile=<name>` / `--save-dir=<name>` / env `DEMONCORE_SAVE_PROFILE`, and the automatic `bot`
  profile for headless, `--autopilot` and `--shot=` runs (`--real-save` opts out). All three of my tools switch
  profile in `_initialize()` (before any autoload loads) and verify the real saves are untouched.
  `Progression.save_path()`, `Meta.save_path()`. Details for other workers: docs/team/qa.md.
- **Weapon hits**: relic and signature `on_hit` / `on_kill` effects now also fire on weapon hits / kills
  (`_on_weapon_struck`, `_on_weapon_kill`, via `AbilityCombat.run_effect`, depth 1). Coordinated in abilities.md.
- **Codex milestones** (relics.json `codex_milestones`): 25 % (9 relics) +10 Sin Shards; 50 % +15 Sin Shards
  +1 Hellstone; 75 % +3 Hellstone and permanent +5 % luck; 100 % +5 Hellstone and a permanent starting relic.
  Paid once, automatically, with a HUD toast. `codex_milestones()` -> `[{percent, name, reached, claimed,
  reward_text, relics_needed}]`, `signal codex_milestone_reached(percent, info)`.
- Economy re-checked after the milestones and the Meta catalog growth (7820 Souls now): average 30 runs,
  expert 20, novice 55 to unlock everything.

## Known issues / next steps
- The sim's run model (minutes, kills, boss odds) is a guess; re-fit `SKILLS` to real playtest numbers.
- Weapon-hit effects use the struck amount as their damage base and 12 x might for weapon kills.
- Ideas: weekly "blessed" pact modifiers, per-school mastery, codex completion rewards.

## Note from gameplay (round 2)
- `RunState.enemy_killed` now carries the boss's EnemyData for boss kills (was null). I made a one-line
  edit in `autoload/progression.gd` `_on_enemy_killed`: it now also skips `RunState.is_boss_data(data)`,
  so bosses keep paying out only through your `_on_boss_died`.
- `RunState.heat` now weighs `heat_minutes` = 0.5 minutes per point (was 1). With your
  HEAT_TO_RUNSTATE 0.5, max pacts (18 heat) add ~4.5 min of generic scaling. Retune either side freely.
- Fixed your known issue "Dash charges bought mid-session...": PlayerDash now adds newly granted
  charges full (meta upgrades applied after Player._ready, or boons mid-run).

## Notes from the UI role (round 3)
- `scenes/progression/relic_hud.gd`: relic chips now paint their icon with `GlyphIcon` (one small
  edit in `_on_relic`); `CurrencyCounter` (your shard / hellstone counters) paints its glyph too.
- Relics also show in the pause menu ("RELICS (n)", `Progression.run_relics`), in a "Relics" tab
  of the Codex (`Progression.codex_entries()`, silhouettes until found, "Found N times"), and in the
  end screen's full ledger. Shared builders: `RelicView.row(relic)` / `RelicView.chip(relic, size)`.

- From basecamp (round 3): the hellgate loadout uses `Progression.is_weapon_unlocked` / `is_ability_unlocked`;
  keepsake and trial effects of type run_stat go through `Progression.apply_stat` (deferred after your Player
  setup). Daily trials add their heat on top of pacts via `RunState.heat`.

## Note from characters-new (round 4): a new demon, Nhazgul the Plague Hive
`data/demons/nhazgul.tres` (model `nhazgul.glb`): unlock `demon_nhazgul` in unlocks.json (Bindings,
24 Sin Shards, requires `demon_skarn`), mastery entry `nhazgul` (signature "Queen of the Swarm":
tag:plague damage, max HP, regen) and skin `mastery_nhazgul` in skins.json. Retune freely.

## Note from characters-new (round 5): Iscariel, the Turncoat
`data/demons/iscariel.tres` (model `iscariel.glb`): unlock `demon_iscariel` (Bindings, 5 Hellstone,
requires `demon_ysolde`), mastery entry `iscariel` (signature "Thirty Pieces of Light": tag:envy
damage, 8% curse on hit, move speed) and skin `mastery_iscariel`. +0.6 speed, +10% might, -8%
cooldown, starts with Brimstone Sigil. Retune freely.
