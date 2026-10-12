# Abilities and synergies (docs/team/abilities.md)

Status: round 3 is in. 68 abilities in 18 schools, 10 status effects, 35 synergies, 37 boons
(3 duo legendaries), 18 evolutions (every school has one), and per-demon favoured schools, all JSON.
Abilities cast on their own, show in the HUD ability dock (keys 1-4 unleash them early), and are
offered on the level-up screen. Weapon hits apply statuses from the (exact) weapon's tags; mirror
decoys taunt angels.

## Owned files
| File | What |
|---|---|
| `autoload/abilities.gd` (autoload `Abilities`) | facade (< 400 lines): registry, run lifecycle, ownership (grant / boons / evolve), affinity, modifier + helper forwarders, damage report |
| `scripts/abilities/ability_data.gd` (`AbilityData`) | loads data/abilities/*.json into the autoload |
| `scripts/abilities/ability_resources.gd` (`AbilityResources`, `Abilities.res`) | Souls, Wrath, Greed, Girth, empower, corpses, resource passives |
| `scripts/abilities/ability_synergies.gd` (`AbilitySynergies`, `Abilities.syn`) | active synergies, data hooks, hit amps / statuses / effects |
| `scripts/abilities/ability_modifiers.gd` (`AbilityModifiers`) | damage / cooldown / count / crit / amp maths |
| `scripts/abilities/ability_events.gd` (`AbilityEvents`) | status deaths, minion expiry, blood spent, blinks, weapon hits, decoys, risen thralls |
| `scripts/abilities/ability_dev.gd` (`AbilityDev`) | dev args, bench setup, report printing |
| `scripts/scale_stack.gd` (`ScaleStack`) | shared composable Node3D scale (named factors); Girth uses it |
| `scripts/abilities/ability_def.gd` (`AbilityDef`) | one parsed ability + level scaling (`stats_at(level)`) |
| `scripts/abilities/ability_caster.gd` (`AbilityCaster`) | runtime instance per owned ability: stats, cooldown, costs, damage scaling, unleash; delegates behaviour to its kind |
| `scripts/abilities/kinds/ability_kind.gd` (`AbilityKind`) | base class of a kind (`cast`, `tick`, `rebuild`, `cleanup`, `can_unleash` + helpers) |
| `scripts/abilities/kinds/ability_kinds.gd` (`AbilityKinds`) | registry kind id -> script |
| `scripts/abilities/kinds/kind_*.gd` | one file per kind: bolt, nova, aura, zone, chain, strike, summon, orbit, cone, line, hook, blink, hex, buff, corpse, harvest, retaliate, reflect, mimic, pride, devour, construct (turret / mine / decoy), whip |
| `scripts/abilities/ability_offers.gd` (`AbilityOffers`) | level-up cards (new abilities, rank-ups, boons, duo legendaries, evolutions) + evolution queries and `evolve` |
| `scripts/abilities/ability_combat.gd` (`AbilityCombat`) | static damage pipeline: `hit()`, trigger effects, `explode()`, `chain()`, `spread()`, area queries |
| `scripts/abilities/status_host.gd` (`StatusHost`) | statuses on one enemy (child node "StatusHost"): DoT ticks, slows, binds, doom, death reports |
| `scripts/abilities/ability_bolt.gd` (`AbilityBolt`) | projectile (Area3D, mask = enemies), styles orb / dagger / spear / soul / coin / holy / shard |
| `scripts/abilities/ability_zone.gd` (`AbilityZone`) | lingering ground effect (pillar / cloud / pool) |
| `scripts/abilities/ability_minion.gd` (`AbilityMinion`) | summons: procedural thrall / wraith / shade / locust, or the demonic ally models (imp, hellhound, succubus, hell_brute via `CharacterRoster.make_ally`, driven with autoplay off; casters strike from range) |
| `scripts/abilities/ability_construct.gd` (`AbilityConstruct`) | turrets (bolts or flame cone), mines, mirror decoys (group `ability_constructs`) |
| `scripts/abilities/ability_fx.gd` (`AbilityFx`) | one-shot visuals: ring, disc, pillar, lightning, fan, beam, telegraph, sigil, tether |
| `scripts/abilities/ability_hud.gd` | pushes abilities into the HUD dock (and removes evolved ones); right edge: Souls / Wrath / Greed / Girth counters + synergy list |
| `data/abilities/abilities.json` | abilities, statuses, weapon tags, weapon statuses, `max_abilities` |
| `data/abilities/synergies.json` | synergies |
| `data/abilities/boons.json` | level-up boons |
| `data/abilities/evolutions.json` | evolutions |
| `tools/abilities_check.gd` | data validator |
| `tools/ability_bench.sh` | per-school balance bench |

Shared files I touched (surgical): `project.godot` (autoload line), `scripts/upgrades/upgrades.gd`
(two hook lines: `Abilities.extend_pool(player, pool)` and `Abilities.ensure_choice(...)`),
`scenes/enemies/enemy.gd` (round 2: `move_factor` / `set_move_factor()`, applied in
`velocity = move * move_factor + _knockback`), `scenes/bosses/boss.gd` (same factor on its velocity).

## How it plugs in
- A run starts when a `Player` enters the tree (any map scene; fallback poll of group `player`).
  Abilities adds a `Player/Abilities` Node3D holding one `AbilityCaster` per owned ability, and an
  `AbilityHud` CanvasLayer next to the player. The run ends when the player is freed.
- Casters cast automatically when their cooldown is up and their kind finds something to do (they
  retry every 0.15 s otherwise). Abilities are separate from weapons (cap `max_abilities` = 5).
- All ability damage goes through `AbilityCombat.hit(enemy, amount, source)` which calls
  `Enemy.take_damage`, so HP, flashes, damage numbers, `Game.enemy_hit` / `enemy_died` all work.
- Weapon hits: `Game.enemy_struck` from a weapon (not an ability) applies `weapon_status` for the
  weapon's tags (fire -> Burn 50%, storm -> Shock 40%, chain -> Bound 6%, shadow -> Curse 25%,
  soul -> Soul-mark 15%, necro -> Plague 25%, brute -> Chill 30%) plus synergy hit statuses. The
  weapon is exact when the hit came through gameplay's `Enemy.hit(e, dmg, kb, source)`
  (`Enemy.last_hit_source`; a projectile source may name its weapon in a `weapon` property or
  meta); otherwise a random owned weapon is used.
- Decoys (Mirror Image, Hall of Doubles, Smoke and Mirrors) call `Enemy.set_taunt_target(decoy,
  0.7)` on every non-boss angel within 6 m every 0.4 s, so the crowd chases the decoy; they shatter
  when 4+ angels reach them.
- Demon affinity (`demon_affinity` in abilities.json): Vharok -> Brimstone, Lilaeth -> Hellfire,
  Morvane -> Curses, Skarn -> Chains, Ysolde -> Soul Harvest (the same themes as Progression's
  mastery signature boons). The favoured school's abilities are offered 3x as often, deal +10%
  damage, and their cards say so. `Abilities.affinity` (current), `affinity_for(demon_id)`,
  `Abilities.demon_id(player)` for menus (e.g. the demon select can show "Favoured: Brimstone").
- Slows / Bound: StatusHost calls `Enemy.set_move_factor(&"abilities", f)`; the factor multiplies
  all self-propelled movement including charges and leaps, so Bound chargers can't dash, and it
  composes with any other speed change. Bosses are never fully Bound (slowed instead).
- Unleash: pressing an ability's dock key (input actions `ability_1`..`ability_4`, rebindable; we
  listen to `hud.widgets.ability_key_pressed(id)`) casts it early once half its cooldown has passed,
  for +50% damage, then restarts the full cooldown. Auras and orbits can't be unleashed.
- `Abilities.grant()` / `take_boon()` called before the run's player is bound are queued.
- Level-up (AbilityOffers): up to 2 new abilities (weighted toward your tags and synergy
  completions; "Completes: X" on the card), up to 2 rank-ups, up to 2 boons, and every ready
  evolution (always gets a card). Under 2 abilities one card is always a new ability.
- Meta unlocks: abilities listed in `data/progression/unlocks.json` (kind `ability`) are offered
  only once `Progression.is_ability_unlocked(id)`. Extra gate: `Abilities.unlock_filter`.

## Run resources
- **Souls** (Soul Harvest): +1 per kill (cap 200 + boons). `soul_scale` / `per_souls` params.
- **Wrath** (Wrath): +1 stack per 4 damage taken, and +0.4 per angel within 2.5 m each 0.5 s
  (max 3) while you carry a wrath ability; cap 40; drains 4/s after 3 s of peace. `wrath_scale`
  param (damage per stack), Retribution vents it, Berserker's Howl converts it to Might.
- **Greed** (Greed): Ichor carried (`RunState.currency`, cap 250; Soul Market adds half your
  Souls). `greed_scale` param; `ichor_cost` param spends Ichor per cast. Gilded foes drop Ichor.
- **Girth** (Gluttony): +1 per angel devoured (cap 40): +2 max HP each, and `Player/Body` grows
  through `ScaleStack` factor `&"girth"` (composes with other scale owners).

## Evolutions (data/abilities/evolutions.json)
Base ability at max rank + its boon taken -> an "Evolve" card (always offered) replaces it with
the evolved form. One per school (18):
| School | Base + boon | Evolution |
|---|---|---|
| Hellfire | Inferno Nova + Kindling | Heart of Gehenna |
| Blood Magic | Hemorrhage Lance + Open Veins | Exsanguinator |
| Necromancy | Raise Thralls + Grave Lord | Legion of the Damned |
| Plague | Pestilent Cloud + Virulence | The Great Pestilence |
| Storm | Infernal Storm + Overcharge | Storm of the Pit |
| Shadow | Shadow Daggers + Night Blade | A Thousand Cuts |
| Brimstone | Brimstone Maul + Tectonic Fury | Worldbreaker |
| Chains | Hellhook + Iron Grip | Abyssal Anchors |
| Curses | Hex of Frailty + Deep Hex | Anathema |
| Soul Harvest | Soul Siphon + Soul Glutton | Reaper's Toll |
| Wrath | Wrathful Cleave + Endless Grudge | Wrath Incarnate |
| Greed | Coin Barrage + Gilded Purse | Midas Storm |
| Envy | Covetous Gaze + Green-Eyed | Usurper's Gaze |
| Pride | Hubris + Vanity | Sovereign Hubris |
| Gluttony | Devour + Bottomless Hunger | Insatiable Maw |
| Illusion | Mirror Image + Mirrored Self | Hall of Doubles |
| Infernal Machinery | Brimstone Turret + Legion of Sin | Infernal Battery |
| Hellfire Whip | Hellfire Lash + Cat o' Nine Tails | Scourge of Gehenna |
Rank-up cards for the last rank say what the ability evolves into. `Abilities.evolve(id)`, signal
`ability_evolved(from, to)`.

## Duo legendary boons
Boons with `"requires_all": [tag, tag]` (both schools owned) and `"legendary": true` (max 1, shown
with the Legendary rarity frame): Hellstorm Covenant (fire + storm), Gilded Gullet (greed +
gluttony), Crimson Eclipse (blood + shadow).

## Data format
Ability (abilities.json `abilities[]`, also the `ability` of an evolution):
```
{"id", "name", "school", "tags": [...], "icon": glyph, "color": "#rrggbb", "desc", "kind",
 "cooldown": s, "damage": base, "hp_cost": fraction of max HP (blood magic, never below 25% HP),
 "params": {kind-specific: count, radius, range, speed, pierce, spread, size, homing, explode,
            duration, tick, jumps, jump_range, delay, lifetime, hit_rate, arc, length, width,
            knockback, crit, crit_mult, style, prefer, max, rate, reach, flamer, scatter,
            threshold, retaliate_mult, power, charge_rate, max_charge, hurt_loss, heal, tip_mult,
            soul_scale, per_souls, wrath_scale, greed_scale, ichor_cost, might_per_wrath, ...},
 "status": [{"id": "burn", "stacks": 2}],  "on_hit": [effects], "on_kill": [effects],
 "after": [effects run at the impact point],
 "levels": [{"text": "+2 cinders", "count": 2}, ...]}   // rank II, III, ...
```
Each kind documents its params at the top of `kinds/kind_<kind>.gd`. Summon `style` may name an
ally from `data/allies/allies.json`. Level keys: `damage` / `cooldown` are fractions,
`status_stacks` adds to every applied status, anything else adds to `params`.

Effects (`{"do": ..., "chance"?, "if_status"?, "if_tag"?}`): `status {id, stacks}`,
`explode {radius, damage (fraction of the hit, or flat with "flat": true, x might), status?, color?}`,
`chain {jumps, range, damage}`, `heal {amount}`, `soul {stacks}`, `zone {radius, duration, damage,
status?}`, `spread {status, count, range, stacks}`, `empower {might, duration}`, `ichor {amount}`,
`wrath {stacks}`, `raise`, `decoy`.

Statuses: burn / plague / bleed (DoT, batched every 0.5 s), curse (+8% damage taken per stack),
chill (slow), root (Bound), shock (+10% storm damage taken per stack), doom (erupts after 3 s for
40 + damage taken while marked), soul_mark (extra soul on death), gilded (+15% damage taken, drops
Ichor on death). Plague spreads on death.

Synergy (synergies.json): `{"id", "name", "requires": {"fire": 1, "plague": 1}, "desc", "color",
"icon", "params"}` plus optional data hooks (each gated by `tags_any`, empty = every ability hit):
`hit_status {tags_any, status}`, `hit_amp {tags_any, amount, vs_status?, vs_elite?}`,
`on_hit {tags_any, effects}`, `on_kill {tags_any, effects}`. Older synergies are bespoke code keyed
by id (grep the id). Tags count over owned abilities plus owned weapons (`weapon_tags`).

Boon (boons.json): `{"id", "name", "desc", "icon", "color", "max", "requires_tag": [any of],
"requires_all": [every one of]?, "legendary": bool?,
"mods": {...}, "on_hit": [effects], "on_kill": [effects]}`. Mod keys: `damage`, `cooldown`, `area`,
`count`, `duration`, `crit`, `crit_mult`, `hp_cost_cut`, `summon_count`, `corpse_life`, `dot_rate`,
`jumps`, `execute`, `knockback`, `root_amp`, `soul_cap`, `soul_bonus`, `wrath_gain`, `wrath_cap`,
and prefixed `tag:<tag>` (damage), `tagcd:<tag>`, `tagcrit:<tag>`, `power:<status>`,
`max:<status>`, `dur:<status>`, `spread:plague`.

## Content
Round 1 schools: Hellfire (+ Imp Rabble), Blood Magic, Necromancy (+ Call the Pack), Plague, Storm,
Shadow, Brimstone (+ Pit Brute), Chains, Curses, Soul Harvest.
Round 2 schools: Wrath (Wrathful Cleave, Retribution, Berserker's Howl, Seething Aura), Greed (Coin
Barrage, Midas Touch, Avarice, Tithe of Coins), Envy (Stolen Radiance: reflects holy projectiles;
Covetous Gaze: copies the nearest angel's attack; Jealous Hex), Pride (Hubris: charges while
unhurt, one colossal blade; Pride's Fall; Crown of Contempt), Gluttony (Devour, Maw of Hell,
Bilious Belch), Illusion (Mirror Image decoys, Hall of Mirrors, Doppelganger succubus), Infernal
Machinery (Brimstone Turret, Hellmine Field, Infernal Engine flame turret), Hellfire Whip (Hellfire
Lash, Chain Dance, Barbed Flurry).

Synergies (35): round 1's 17, plus Blood Fury, Unstoppable, Soul Market, Coin-Op Hell, Stolen
Thunder, Covetous Curse, Regicide, Sunfall, Rotten Feast, Bone Banquet, Smoke and Mirrors, False
Idols, Hellforge, Tripwire, Lash of Gehenna, Chain Dancer, Flagellant, The Seven Deadly (all five
sins at once: +30% damage).

## API for other systems
```gdscript
Abilities.grant(&"inferno_nova")       # give, or rank up if owned
Abilities.take_boon(&"kindling")
Abilities.evolve(&"heart_of_gehenna")
Abilities.has_ability(id) / get_caster(id) / ability_count() / casters (id -> AbilityCaster)
Abilities.has_synergy(&"firestorm") / active_synergies (id -> definition)
Abilities.souls / wrath / greed() / girth / ichor() / damage_taken
Abilities.add_souls(n) / add_wrath(n) / add_girth(n) / empower(might, seconds)
Abilities.owned_tags() -> {tag: count}
Abilities.defs (id -> AbilityDef), statuses, synergy_defs, boon_defs, evolutions
Abilities.damage_report() -> {id: [casts, effective damage]}
AbilityCombat.hit(enemy, amount, {"tags": PackedStringArray(["fire"]), "status": [...]})
AbilityCombat.apply_status(enemy, &"curse", 2)      # e.g. a relic that curses on hit
StatusHost.of(enemy).has(&"burn")                   # null if the enemy never had a status
enemy.set_move_factor(&"my_system", 0.5)            # composable slow (1 removes it)
```
Signals: `ability_added(id)`, `ability_leveled(id, level)`, `ability_cast(id)`,
`ability_evolved(from_id, to_id)`, `boon_taken(id, stacks)`, `synergy_activated(id)`,
`souls_changed(souls)`, `damage_dealt(amount, tags)`.

## Dev / validation / balance
- `<godot> --headless --path . --script res://tools/abilities_check.gd` validates the JSON.
- Run args (after `--`): `--abilities=id,id` or `all`, `--boons=id,id`, `--souls=N`,
  `--ability-rank=N`, `--evolve=evo_id`, `--ability-report` (casts and effective damage per ability
  every 5 s), `--ability-bench` (unarmed, no level-ups, 100k HP: the demon stands and takes hits).
- `tools/ability_bench.sh <godot> [secs] [rank]` runs every school alone with `--ability-bench`
  and prints effective damage (no overkill) and kills per school.

- Round 2 balance pass (rank III, 60 s, effective damage per ability): first pass ranged 210
  (Soul Harvest) to 1980 (Pride, Pride's Fall alone 3780). After tuning (Pride's Fall 90 -> 55
  damage / 10 s cooldown / smaller blast, Hubris and Crown trimmed, Brand of Thunder 16 -> 11,
  Brimstone and whips trimmed, auras widened, Soul / Plague / Gluttony / Greed / Machinery buffed),
  schools sit at roughly 240-830 per ability with 61-88 kills (Pride 33 kills by design: few,
  huge hits for elites). Run-to-run noise is about +-30%. The bench is biased against close-range
  kinds (auras, orbits, novas): angels rarely reach a demon that stands still, so judge those in play.

- Round 3 real-play check (new autopilot moves, dashes and picks; `--fixed-fps 30`, rank III, 150 s):
  a close-range kit (Inferno Nova, Pyre Circle, Brimstone Maul, Umbral Step, Wrathful Cleave) first
  did about half the damage and kills of a ranged kit (12.3k / 406 vs 26.6k / 726). After buffing
  the close-range kinds (Pyre Circle 2 -> 4 dmg and 3.0 m, Inferno Nova 18 / 4.0 m, Umbral Step
  28 dmg / 2.5 s / 4 m trigger, wider Maul / Cleave / auras / Crimson Tide) and trimming the top
  ranged picks (Hemorrhage Lance 22, Bone Spear 17, Brand of Thunder 10), the two kits match:
  12.3k / 379 kills vs 10.7k / 375.
- Round 3 re-bench after the final trims (60 s, rank III, effective damage per ability):
  Hellfire 265, Blood 425, Necromancy 426, Plague 342, Storm 398, Shadow 476, Brimstone 700,
  Chains 406, Curses 520, Soul Harvest 367, Wrath 522, Greed 337, Envy 605, Pride 706 (36 kills,
  by design), Gluttony 365, Illusion 588, Machinery 341, Whip 822; kills 69-94 elsewhere. The
  bench still under-rates auras / novas (the demon stands still), which the real-play check covers.

## Known issues / next
- Weapons that don't yet call `Enemy.hit(..., source)` still fall back to a random owned weapon.
- Summons use AbilityMinion (driving the ally models itself) rather than characters-new's
  `AllyMinion`, because AbilityMinion carries the ability's source (id for the damage report,
  statuses, summon amps); switching needs AllyMinion to accept a full hit source.

## Audio notes (from the sfx role, see docs/team/sfx.md)
- Sounds hook in automatically: `Abilities.ability_cast(id)` layers the element cast sound of the
  ability's first element tag, and `Abilities.damage_dealt(amount, tags)` plays the element hit at
  the struck enemy's position (via `Game.enemy_struck`). Nothing to call.
- Avoid `&"soul"` for ability sounds: it is the XP-gem pickup and every play climbs its pitch
  ladder. sfx changed `_cast_harvest` in `ability_caster.gd` to `&"harvest"` (the summon cast was
  already `&"necro_cast"`).

## Notes from the UI role (docs/team/ui.md)
- Input actions `ability_1`..`ability_4` now exist in project.godot (keys 1-4; pad X / Y / LB for
  1-3) and are rebindable in Settings > Controls. The HUD dock gives each ability slot added
  without an action the next free `ability_N` (stable per id across your rank-up re-adds) and shows
  its key. `hud.action_for(id)` returns it.
- When the player presses one, the HUD pulses the slot and emits
  `hud.widgets.ability_key_pressed(id)`. Abilities still auto-cast; if you want a manual cast /
  overcharge, connect to that signal (nothing else is needed from the UI side).
- Synergies: the UI shows a banner on `Abilities.synergy_activated` and lists
  `Abilities.active_synergies` in the pause menu. Your right-edge list stays as is.

## Audio for round 2 (from the sfx role)
- Round 2 schools need no audio work: tags `wrath`, `greed`, `envy`, `pride`, `gluttony`,
  `decoy`, `turret`, `mine`, `whip` have their own cast / hit sounds; `synergy_activated` plays a sting
  and an `ability_evolved(id)` (or `evolved`) signal plays the evolution sound.

## Notes from art-style (round 3)
- Icons: `Icons.for_ability(id)` -> `res://assets/icons/abilities/<id>.svg` (generator:
  `python tools/icons/build_ability_icons.py`; add a motif for new ids in its `BY_ID`, otherwise the
  kind's fallback is used). `ability_hud.gd` dock + chips use them (marked edits).
- Palette pass on the round-2 schools (docs/team/art-style.md section 7): Envy neon green -> jade,
  Illusion ice-blue -> lilac, Pride near-white gold -> rose-gilt (Greed keeps coin gold), plus the
  matching boons / synergies and the illusion decoy colour in `abilities.gd`; boon `cruel_edge`
  white -> bone. Orbit default core, Pride's pillar, Retribution's inner ring and the whip tip burst
  no longer use pure white (school colour lerped toward white instead; pure white reads holy).
  Mirror orbiters are smoked black glass instead of cold silver-blue.
- (round 3) `AbilityCombat.hit` now always calls `Abilities.report_damage` (it was gated on
  `reporting`), `_report` is cleared in your run reset, and `Abilities.damage_report()` exposes it.
  The end screen's full ledger shows damage per ability from it. Casts are still only counted with
  `--ability-report`.


## Note from progression (round 3): relic / signature effects on weapon hits
Your `_on_enemy_struck` applies weapon-tag statuses; `Abilities.global_on_hit/on_kill` still fire on
ability hits only. Progression now replays **its own** trigger effects (relic and signature `on_hit` /
`on_kill`, which it also appends to your global lists) for weapon hits: it listens to `Game.enemy_struck`
and `Game.enemy_died` and runs them through `AbilityCombat.run_effect()` when `AbilityCombat.in_hit == 0`,
with src `{"tags": ["weapon"], "depth": 1}` (so their damage can't re-trigger). Your boons' on_hit lists are
untouched. If you later run `global_on_hit` for weapon hits yourself, tell me and I'll drop my replay to
avoid double triggers (`Progression._on_weapon_struck` / `_on_weapon_kill`).

## Note from characters-new: demonic ally minions (AllyMinion)
Ready-made summon bodies with a brain: `AllyMinion.spawn(&"imp" | &"succubus" | &"hellhound" |
&"hell_brute", at, {"damage", "lifetime", "hit_rate", "speed", "range", "scale", "tags": [...]})`
(scenes/characters/allies/ally_minion.gd). It heels near the demon, hunts the nearest angel, and its
hits go through `AbilityCombat.hit(enemy, amount, {"tags": PackedStringArray(tags)})`, so statuses,
crits and synergies apply. Signals `struck(enemy, amount)`, `expired`; `dismiss()`; groups `allies`,
`ally_minions`. Base stats in `data/allies/allies.json`. A `summon` ability kind could spawn these
instead of AbilityMinion's built-in bodies; tell me in docs/team/characters-new.md if you need a hook
(e.g. on_hit callbacks or a summon cap group).

- From basecamp (round 3): the hellgate loadout grants one unlocked starting ability via `Abilities.grant`
  before the run (queued), and the daily trial may grant a seeded one ("Borrowed Rite"). The Proving Pit
  hides the AbilityHud while training.

## Note from gameplay (round 3): taunt, exact weapon source, contact damage
- **Taunt**: `enemy.set_taunt_target(node, seconds)` (Enemy): for `seconds` the enemy walks to and aims
  shots / charges / slams at `node` instead of the demon (call again to refresh; `clear_taunt()`,
  `is_taunted()`). Contact and area damage still only hurt the demon, so a decoy needs no hurtbox.
  It is dropped automatically when the node leaves the tree. Your decoys can now draw aggro:
  `for e in Targeting.nearest_enemies(tree, decoy_pos, 40, radius): e.set_taunt_target(decoy, 1.0)`
  every ~0.5 s.
- **Exact weapon source**: weapons now hit through `Enemy.hit(e, dmg, knockback, source)`, which sets
  `e.last_hit_source` (the Weapon node) for the duration of `take_damage()`, i.e. while
  `Game.enemy_struck` fires. I made a 3-line marked edit (`# [gameplay]`) in `_on_enemy_struck`:
  it uses `e.last_hit_source as Weapon` and only falls back to the random pick when null. Your
  ability hits can pass a source too (`Enemy.hit(e, dmg, kb, caster)`), and AbilityCombat could set
  it for minions. `Projectile.source` / `ScytheProjectile.source` carry the firing weapon.
- **Contact damage (your bench note: "unarmed demon took ~2 HP in 60 s")**: not reproducible now.
  Checks: 30 wisps around a still, unarmed demon: 192 HP in 10 s; `--ability-bench --abilities=inferno_nova`
  for 60 s: 443 HP taken (757 contact ticks). Perf's Crowd keeps enemies on layer 3, which the
  Hurtbox masks, and maps steering doesn't stop them. Likely causes on your side: early in a bench
  run few enemies exist (7 at 10 s, spawn rate starts low), knockback-heavy schools keep them out of
  reach, or the level-up screen paused the tree. `tools/gameplay_check.gd` now asserts contact damage.
- **Bug for you**: `Abilities._end_run()` calls `res.reset(player)` with a freed player when a run is
  restarted ("Rise Again" / RunState.restart_run): `Invalid type in function 'reset' ... (previously
  freed)` at abilities.gd:157. Guard with `player if is_instance_valid(player) else null`.

## QA notes (from docs/team/qa.md)
- QA fixed `Abilities._end_run()` (`# QA:`): it passed the freed `player` to `res.reset(Player)`, which errored and aborted `_end_run`, so `casters` kept freed casters across hub -> run -> hub (15k+ errors in `ability_hud.gd:80` / `owned_tags()` per flow_smoke run). Typed loops like `for c: AbilityCaster in casters.values()` error on freed entries; keep the dict clean or loop over Variants.

## Note from characters-new (round 5): demon affinities
Added `demon_affinity` entries: `nhazgul` -> Plague (round 4) and `iscariel` -> Envy (round 5; a
fallen angel who covets and steals Heaven's light - Stolen Radiance is his signature fit). Their
mastery signatures use `tag:plague` / `tag:envy`.
