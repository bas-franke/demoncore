# New character models (docs/team/characters-new.md)

Status: round 5 landed (playable demon Iscariel, heal circle on Enemy.heal, unskippable death mechanics). Round 4 landed (16 map-signature enemies, ragdoll_limbs, Enemy.heal API, playable demon Nhazgul; see "Round 4 additions"). Round 3 landed (see "Round 3 additions"; 47 roster enemies, 7 ProcBoss bosses, Sanctified elites, the Celestial Leviathan, kneeling archangels, hazard tints). Round 2: 36 holy enemy data entries (35 model types, incl. the Grand Inquisitor
variant and the spawned-only Martyr's Shade), 3 bespoke map bosses (ProcBoss), 4 demonic ally
models with an ally controller (AllyMinion), Basecamp NPC models (Pip, Kesh, Malphine) plus hub set
pieces (bar, kennel, laborers) and a talkable-NPC wrapper (HubNpc). All code-built from `Art`
primitives with procedural animation. Tests: `_roster_check.gd` and `_script_check.gd` (below).

## Owned files
- `scenes/characters/proc_model.gd` (**`ProcModel`**, extends `EnemyModel`): base for every
  procedural character: rig helpers, walk cycle, state weights, foot planting, solid wings, mesh
  merging, procedural corpse.
- `scenes/characters/character_roster.gd` (**`CharacterRoster`**): registry (metadata, tags, spawn
  rules, ally / NPC factories, NPC collision, Basecamp placement).
- `scenes/characters/enemies/*.gd|tscn`: enemy models. `holy_horse.gd` (`HolyHorse`) = shared horse.
- `scenes/characters/allies/*`: demonic models (`demon_kit.gd` = `DemonKit` base) and
  `ally_minion.gd` (**`AllyMinion`**, the ally controller).
- `scenes/characters/npcs/*`: Basecamp NPCs and set pieces, `hub_npc.gd` (**`HubNpc`**).
- `scenes/characters/bosses/*`: **`ProcBoss`** (boss fight runner), **`BossModel`** (boss model
  base), Frost Abbot, Verdant Matriarch, Dawn Wyrm (script + body scene + model scene each).
- `scenes/characters/projectiles/`: `HolyBolt` (crossbow bolt), `ExorcismBolt` (drains Ichor + souls).
- Dev: `scenes/characters/_gallery.gd|tscn`, `_roster_check.gd`, `_script_check.gd`.
- Data: `data/enemies/<id>.tres` (ids below), `data/bosses/{frost_abbot,verdant_matriarch,dawn_wyrm}.tres`,
  `data/allies/allies.json`, `data/npcs/npcs.json`.
- Round 3 files: `scenes/characters/elites/sanctified.gd`, `scenes/characters/events/{roster_director,celestial_whale}.gd`, `scenes/characters/enemies/hymn_blessing.gd`, `scenes/characters/projectiles/{holy_water_flask,holy_puddle}.gd`, bosses `war_chariot`, `storm_archon`, `gilded_seraph`, `cantor` (+ models), `data/bosses/<those>.tres`.
- Round 3 shared edits (marked): `scenes/main.gd` (adds RosterDirector), `scenes/bosses/holy_fx.gd` + the five hazard scripts (tint), `scenes/dialogue/ending_stage.gd` (kneeling), `data/maps/*.json` (pools, bosses, ruined_sanctum boss_rotation).
- Shared files edited surgically: `data/maps/*.json` (appended `enemy_pool` entries; `"boss"` of
  frozen_monastery / outer_gardens / sunlit_citadel set to my bosses), `data/bosses/bosses.json`
  (3 roster entries), `scenes/basecamp/basecamp.gd` (one line: `CharacterRoster.populate_basecamp`),
  `scenes/basecamp/hub_life.gd` (one line: Velka uses the succubus barkeep pose).

## Enemy roster
Ids are stable (`res://data/enemies/<id>.tres`). Behaviour = `EnemyData.Behavior`; the gameplay role
retuned some to its newer behaviours (marked "gameplay"); the .tres files are the truth.

| id | name | behaviour | notes |
|---|---|---|---|
| `cherub` | Cherub | CHASE | swarm, flies, tiny |
| `seraph` | Seraph | SHOOT (holy orb) | six wings, face wings part on wind-up |
| `throne` | Throne | SUMMON (gameplay) | eyed fire-wheel that rolls |
| `archangel` | Archangel | SLAM | **elite** (xp 32), flaming greatsword, 4 wings |
| `paladin` | Paladin | SHIELD (gameplay) | tower shield + warhammer |
| `holy_knight` | Knight of the Dawn | CHASE | cosmetic sword cut in reach |
| `inquisitor` | Inquisitor | KITE (HolyBolt) | crossbow, lantern |
| `grand_inquisitor` | The Grand Inquisitor | SHOOT (HolyBolt) | **elite**, `inquisitor.gd` with `grand = true` |
| `monk` | Warrior Monk | CHARGE | staff levelled like a lance |
| `censer_nun` | Sister of the Thurible | HEAL (gameplay) | swinging censer |
| `zealot` | Crusader Zealot | EXPLODE (gameplay) | flail; wind-up = holy fire swelling in the chest |
| `villager_torch` / `villager_pitchfork` | Villagers | CHASE | `villager.gd` exports `tool`, `variant` |
| `holy_lion` | Lion of Judah | HOP | pounce arc from `state_progress` |
| `griffon` | Griffon | CHARGE | flies low, stoops talons-first |
| `unicorn` | Unicorn | CHARGE | rears on wind-up, horn kindles |
| `pegasus` | Pegasus | CHASE | flies |
| `saint_statue` | Animated Saint | SLAM | slow, sinks into rubble |
| `glass_golem` | Stained-Glass Golem | CHASE | tanky, shatters |
| `valkyrie` | Valkyrie | HOP | leaping spear dive |
| `light_elemental` | Light Elemental | SHOOT (holy orb) | rings close in on wind-up |
| **round 2** | | | |
| `ophan` | Lesser Ophan | CHASE | the Ophanim swarm: tiny eyed wheels |
| `cherubim` | Cherubim | CHARGE | four-faced (man / lion / ox / eagle) ox-bodied beast, 4 wings |
| `martyr` | Martyr | CHASE | **on death**: a telegraphed fire ring (PyreBurst) and it rises as a Martyr's Shade |
| `martyr_shade` | Martyr's Shade | CHASE | fast ghost; spawned only (weight 0, not in pools) |
| `plague_doctor` | Plague Doctor of the Order | KITE (HolySmoke) | beak mask, censer cane |
| `choir_wraith` | Choir Wraith | SHOOT (holy orb) | ghost choir boy, sings the shot |
| `bell_gargoyle` | Bell-Tower Gargoyle | HOP | stone gargoyle, its bell tolls on landing |
| `templar_ballista` | Templar Ballista | SHOOT (HolyBolt) | siege engine, long range, wheels roll with speed |
| `mobile_reliquary` | Mobile Reliquary | SHIELD | gilded shrine on a bier with two bearers, wards allies |
| `witch_hunter_captain` | Witch-Hunter Captain | CHARGE | rapier lunge, pistol |
| `light_wyrm` | Dawn Wyrmling | SHOOT (holy orb) | small light dragon, breath |
| `frost_hermit` | Frost-Blessed Hermit | KITE (holy orb) | monastery hermit, ice crook |
| `clockwork_cherub` | Gilded Clockwork Cherub | EXPLODE | the key spins up, belly glows (the fuse) |
| `dryad_priestess` | Dryad Priestess | HEAL | nature saint of the gardens |
| `exorcist` | Exorcist | SHOOT (ExorcismBolt) | **drains** 3 Ichor + 6 reaped souls per hit |

Map pools (appended in `data/maps/*.json`, retune freely): cathedral_city = villagers, zealot,
knight, inquisitor, nun, golem, saint, martyr, plague doctor, gargoyle, exorcist, witch-hunter
captain, ballista, grand inquisitor (late, rare); frozen_monastery = monk, knight, nun, valkyrie,
saint, frost hermit, choir wraith, martyr, exorcist, gargoyle; outer_gardens = cherub, pegasus,
lion, unicorn, griffon, light elemental, ophan, dryad, wyrmling, cherubim; ruined_sanctum = cherub,
knight, zealot, paladin, golem, seraph, throne, ophan, choir wraith, martyr, reliquary, ballista,
archangel (rare); sunlit_citadel = cherub, seraph, paladin, light elemental, throne, valkyrie,
clockwork cherub, ophan, wyrmling, reliquary, cherubim, archangel (rare).

## Bosses (ProcBoss)
| id | map (`"boss"`) | phases | attacks |
|---|---|---|---|
| `frost_abbot` Ysmir, the Frost Abbot | frozen_monastery | Vigil / Hailstorm / White Silence | ice lances, hunting icicles, abbey bells, frost nova, hail, crossing lances, frost orbs; monks / hermits / wraiths join |
| `verdant_matriarch` Mother Verdance | outer_gardens | Blossom / Overgrowth / Wildwood | erupting thorns, crossing roots, pollen orbs, bloom disc, seed rain, branch sweep; dryads / unicorns / lions join |
| `dawn_wyrm` Aurelion, the Dawn Wyrm | sunlit_citadel | First Light / High Noon / Eclipse | breath fans and arcs, sun-orb bursts, diving charges, falling stars, wingbeat rings; wyrmlings / clockwork cherubs / a seraph join |

Registered in `data/bosses/bosses.json` (ObjectiveDirector rotation, the map's own boss first).
`ProcBoss` (extends Enemy) is generic: a subclass merges its `cfg` in `_configure()`: `title,
felled, phase_lines, phase_names, patterns` (per phase; kinds `lanes cross chase rain pyre sweep
bells orbs charge summon`), `minions` (per phase, enemy ids), `cooldown, tell_mult, speed_mult,
keep_distance, attack_range, damage, intro_color`. Every attack uses the shared, telegraphed boss
hazards (InquisitorLane, PyreBurst, BellRing, JudgementPillar, SarielOrb). Same UI / story hooks
as the other bosses (`phase_index`, `phase_count`, `phase_thresholds()`, `phase_name()`,
`is_enraged`, Game.boss_* signals). Boss models extend `BossModel` and read `attack_kind`,
`boss_phase`, `rise_w`, `kneel_w` and `act([kinds])` for their poses.
Dev: `-- --summon=frost_abbot` (objectives arg) or the roster check.

## Round 5 additions
- **Iscariel, the Turncoat** (second new playable demon): `data/demons/iscariel.tres`, model
  `assets/models/demons/iscariel.glb` built from `tools/blender/models/demons/iscariel.py`, which
  `_iscariel_from_lilaeth.py` generates from lilaeth.py (same rig and animation set). Re-theme:
  ash-grey skin with holy-gold veins turning to hellfire, blackened armour and burnt-gold filigree, a
  charcoal robe over a molten-gold lining, a blackened halo broken in four places, and mismatched
  wings (right pale ash-white with gold-ember tips, left burned to a smaller charred ruin). Stats
  +0.6 speed, +10% might, -8% cooldown; starts with Brimstone Sigil; Envy affinity; unlock
  `demon_iscariel` (Bindings, 5 Hellstone, after Ysolde); mastery "Thirty Pieces of Light" + skin
  `mastery_iscariel`; in the demon select list; walk clip 7.05; death style feathers.
- **Heal circle on Enemy.heal**: gameplay's `_cast_heal` (marked edit) now uses `Enemy.heal`.
- **Unskippable death mechanics**: `Enemy.die()` emits `died(enemy)` and calls
  `model.on_host_died(enemy)` (new ProcModel hook) before `death_burst`. The martyr's burst + shade,
  the revenant's rise, the Paschal Lamb's heal and the ice-bound penitent's shards moved there;
  Sanctified pays out on `died`. `_roster_check.gd` now tests the lamb heal and that the revenant
  rises exactly once.
- Notes left for story, characters-polish, sfx, progression, abilities and gameplay.

## Round 4 additions

### Map signature enemies (16; each appears only in its map's pool)
Roster entries carry tag `signature`, weight 0 (never in generic spawn_rules) and `"map"`.
| map | id | behaviour | identity / mechanic |
|---|---|---|---|
| frozen_monastery | `icebound_penitent` | CHASE | entombed in ice; on death a ring of frost shards (short orbs) bursts out |
| frozen_monastery | `bell_ringer_monk` | SHOOT (bell_toll) | each toll is an expanding ring (BellRing, frost tint) |
| cathedral_city | `watch_pikeman` | SLAM | a pike thrust: small struck circle far ahead (slam_reach 2.6) |
| cathedral_city | `rooftop_archer` | KITE (HolyBolt) | carries his own roof chunk and shoots from its ridge; long range |
| outer_gardens | `thorn_guardian` | SLAM | topiary knight; erupts a thorn ring all round itself (slam_reach 0) |
| outer_gardens | `hummingbird_cherub` | CHASE | darting cherub-hummingbirds; each brings 3 companions |
| sunlit_citadel | `sun_priest` | KITE (mirror_beam) | throws a long telegraphed beam lane (dawn tint) |
| sunlit_citadel | `golden_legionary` | CHASE | shield wall: wards itself (Enemy.apply_ward, 65%) while you are in front - flank it |
| ashen_wastes | `crusader_revenant` | CHASE | rises once from its ashes 1.6 s after death (60% HP) |
| ashen_wastes | `carrion_angel` | HOP | feeds: heals 20% (Enemy.heal) whenever anything dies within 7 m |
| storm_spire | `rod_acolyte` | KITE (lightning_call) | calls a telegraphed lightning pillar onto you |
| storm_spire | `cloud_djinn` | CHASE | every ~6.5 s bursts into storm and re-forms behind you |
| gilded_isles | `mimic_reliquary` | CHASE | sits still as a treasure chest (move factor 0) until you come within 5 m |
| gilded_isles | `gilded_harpy` | HOP | a dive that lands next to you steals 2 Ichor |
| heavens_gate | `gate_warden` | SHIELD | Kesh's holy mirror: wards the Host, key-halberd slam |
| heavens_gate | `honour_guard` | CHARGE | always a pair; sabres crossed in salute, then a dash |
Spells-as-projectiles: `SpellCast` (scenes/characters/projectiles/spell_casts.gd): `bell_toll`,
`mirror_beam`, `lightning_call` scenes cast a shared hazard where Enemy._fire() spawns them.
`ProcModel.spawn_companions(count, tag)` spawns flock / pair companions once.

### Ragdoll limbs (for characters-polish DeathFx)
`ragdoll_limbs() -> Array` on beasts, riders, siege and the new signature enemies: holy_horse
(unicorn, pegasus), mounted_knight, holy_lion, griffon, gryphon_rider, cherubim, bell_gargoyle,
paschal_lamb, light_wyrm, hellhound, templar_ballista, mobile_reliquary, crossbow_militia and most of
the round-4 enemies. Helper: `ProcModel.limbs_with(extra)` = walk legs + arms + extra pivots.

### Heal API (with gameplay)
`Enemy.heal(amount, source := &"", show_number := true) -> float` (marked block in enemy.gd):
clamped, refused while dying, green "+N", signal `healed(amount, source)` and
`Game.enemy_healed(enemy, amount)` (new signal in game.gd). Virtue's miracle, the Paschal Lamb,
Sanctified "hallowed" and the Carrion Angel now heal through it. Speed buffs (flagellant rage,
hymn blessing, sanctified zealous / bulwark, the mimic's sleep) go through
`Enemy.set_move_factor(source, f)` instead of writing `speed`. The Power still dismisses allies via
their own API (AllyMinion.dismiss / AbilityMinion.expire / DamnedSoul).

### New playable demon: Nhazgul, the Plague Hive
- Blender model `assets/models/demons/nhazgul.glb` built by the regular pipeline from
  `tools/blender/models/demons/nhazgul.py` (generated from vharok.py by `_nhazgul_from_vharok.py`:
  same rig + animation set, plague palette, hive combs on the back and shoulders, belly sac,
  pustules, chitin antennae and mandibles). Rebuild: `blender -b --factory-startup --python
  tools/blender/build.py -- demons/nhazgul`, then `godot --headless --path . --import`.
- `data/demons/nhazgul.tres`: BRUTE build, +30 max HP, +0.5 regen, +10% area, starts with Wailing
  Souls. In the demon select list (`demon_select.tscn`), unlocked at the Bindings shop for 24 Sin
  Shards after Skarn (`demon_nhazgul` in unlocks.json), Plague affinity (abilities.json), mastery
  signature "Queen of the Swarm" + skin `mastery_nhazgul` (mastery.json / skins.json), walk clip
  speed 5.44 (demon_model.gd), death style ash (demon_death.gd). All marked as small data edits.

## Round 3 additions

### Enemies (11 more; all fight in `_roster_check`)
| id | name | behaviour | mechanic |
|---|---|---|---|
| `mounted_knight` | Mounted Knight | CHARGE | very fast, long lance pass (HolyHorse body + rider) |
| `crossbow_militia` | Crossbow Militia | SHOOT (HolyBolt) | a 3-man squad in one enemy; volleys 3 bolts in a fan (flankers fired from the model) |
| `flagellant` | Fanatical Flagellant | CHASE | grows stronger as it bleeds: up to +100% speed, +80% damage near death |
| `holy_water_friar` | Holy-Water Friar | SHOOT (HolyWaterFlask) | lobbed flasks shatter into scalding HolyPuddles (4.5 s, ticks every 0.6 s) |
| `mortal_choir` | Mortal Choir | HEAL | 3 singers; each completed hymn blesses angels in 7 m: +35% speed, +25% damage, 5 s (HymnBlessing) |
| `dominion` | Dominion | SHIELD | wards; four floating tower shields orbit and lock into a wall on its ward |
| `virtue` | Virtue | HEAL | miracle: restores nearby angels to their health 3 s ago |
| `power` | Power | CHASE | hunts the demon's allies (group `allies`): chain-lashes and dismisses one every 2.6 s |
| `gryphon_rider` | Gryphon Rider | HOP | climbs, then dives lance-first onto the circle |
| `herald_trumpeter` | Herald of the Last Trump | SUMMON | blows the trumpet: cherubs answer |
| `paschal_lamb` | Paschal Lamb | CHASE | harmless; killing it heals every angel within 6 m by 40% |
Model-side mechanics use `ProcModel.host()` (the owning Enemy) and `enemies_near(at, r)`;
`_on_state_enter()` catches the end of a wind-up (WINDUP -> ATTACKING / RECOVER).

### Bosses (4 more ProcBoss)
| id | map | phases |
|---|---|---|
| `war_chariot` Lord-Marshal Caddoc, the Burning Crusade | ashen_wastes (`"boss"`) | The Muster / The Advance / The Pyre |
| `storm_archon` Baraqiel, Archon of the Tempest | storm_spire | Gathering / The Squall / Eye of the Storm |
| `gilded_seraph` Aurum, the Gilded Seraph | gilded_isles | The Counting / The Tithe / Avarice |
| `cantor` Cantor Seraphiel, the Broken Choir | ruined_sanctum (after Sariel in its boss_rotation) | Introit / Requiem / Dies Irae |
Every map now has a bespoke boss. Notes left in objectives.md, story.md and music.md.

### Hazard tints
`cfg.hazard_tint` per ProcBoss (frost blue, pollen green, dawn amber, ember, storm violet, gold,
choir lilac). Mechanism: `HolyFX.hazard_tint` (static) is copied into the new `tint` member of
InquisitorLane / PyreBurst / BellRing / JudgementPillar / SarielOrb when they are created (marked
edits in the objectives role's files; default Art.HOLY keeps the original look). ProcBoss scopes it
around its frame; Sanctified and the whale use it too.

### Sanctified elites
`Sanctified.apply(enemy, affix := "")` (scenes/characters/elites/sanctified.gd): gold aura, crown,
light, x3 HP, x1.3 damage, one affix (radiant, zealous, bulwark, choir_led, martyr - the champion
affix ids - plus hallowed), +4 Ichor on death. `Sanctified.of(e)`, `is_sanctified(e)`,
`title_for(name, affix)`, group `sanctified`. Rolled on spawn by `RosterDirector`
(scenes/characters/events/roster_director.gd, added in main.gd): from 90 s, 1.5% + 0.6%/min, max 6%,
max 4 alive; never bosses / elites / champions / spawned-only minions. Map override:
`"characters": {"sanctified_max": 2, "whale": false, ...}` in a map JSON. Dev `-- --sanctify-all`.

### The Celestial Leviathan (map event)
`CelestialWhale.spawn_pass()` (scenes/characters/events/celestial_whale.gd): a translucent whale of
light drifts over the demon for ~30 s (it steers sideways to stay over the fight), dropping
telegraphed pillars of light biased toward the demon; can't be fought. RosterDirector starts one at
100 s and every 170 s on open-sky maps (`whale_maps`: heaven realm, sky_islands, storm, eden,
citadel). Dev `-- --whale=<seconds>`. Signal `passed`.

### Kneeling archangel
`archangel.gd` `@export var kneeling` (knee down, sword planted point-first, head bowed, wings
folded, halo dimmed; blends in, or starts knelt when set before add_child). The story ending's
seven Archons use it (`ending_stage.gd`, one marked edit).

## CharacterRoster API
```gdscript
CharacterRoster.ENEMIES                 # id -> {faction, tier 1..4, tags, start, weight}
CharacterRoster.enemy_ids() / enemies_with([&"mortal", &"ranged"], &"order") / enemy_data(&"paladin")
CharacterRoster.spawn_rules([&"heaven"], time_scale, weight_scale, include_elites)  # Array[SpawnRule]
CharacterRoster.allies() / make_ally(&"hellhound")     # allies.json / a fresh ProcModel
CharacterRoster.npcs() / spawn_npc(parent, &"pip", pos, yaw, extra := {})  # adds model (+ collision)
CharacterRoster.add_collision(parent, pos, radius, height)   # StaticBody3D cylinder, layer 1
CharacterRoster.populate_basecamp(hub)  # npcs.json "basecamp" list (talkers become HubNpc)
```
Factions: `angel`, `order`, `mortal`, `beast`, `construct`, `elemental`. Tags: realm (`heaven`,
`mortal`), role (`swarm`, `ranged`, `charger`, `leaper`, `slam`, `armored`, `melee`, `flying`,
`elite`, `support`, `siege`, `bomber`, `drain`, `spawned`), theme (`urban`, `snow`).

## Allies: AllyMinion (summons)
```gdscript
var hound := AllyMinion.spawn(&"hellhound", at)                       # stats from allies.json
AllyMinion.spawn(&"imp", at, {"damage": 6, "lifetime": 12, "tags": ["fire"], "scale": 1.2})
hound.struck.connect(func(enemy, amount): pass)    # also: signal expired, dismiss()
```
It heels near the demon, hunts the nearest angel within `aggro_range` (12 m, biased toward the
demon); melee roles strike every `hit_rate` s, the caster (succubus) throws hellfire from range. No
physics body (glides over the crowd), enemies ignore it, it teleports back beyond 18 m. Damage goes
through `AbilityCombat.hit` (statuses, crits, synergies; `tags` from opts) when the abilities
framework is loaded, else `Enemy.take_damage`. Groups `allies` + `ally_minions`. Options: damage,
speed, hit_rate, range, aggro, lifetime (0 = until dismiss()), scale, role, tags.
Models: `imp` (swarm; `outfit` 0 / 1 porter / 2 courier = Pip), `succubus` (caster; `barkeep`),
`hellhound` (hunter; `resting`), `hell_brute` (tank).

## Basecamp NPCs and set pieces
- Story NPCs (placed and made talkable by the story role's `StoryNpc`; collision from npcs.json):
  `pip`, `breachwarden` (Kesh; gesture 1 slams the halberd), `malphine`.
- Placed by me (npcs.json "basecamp"): a hell brute guarding the gate, an imp porter by the forge.
- Ready-made set pieces in npcs.json, not placed by default because the basecamp role's HubLife
  already builds a bar, kennel and quarry from my models (add them to the "basecamp" list to place
  them): `sable` (The Infernal Bar: counter, bottle shelf, keg, stools, Sable the barkeep; solid),
  `kennel` (iron pen, rib doghouse, trough, three hellhounds: two asleep, one pacing; solid; "Pet
  the hounds" wakes them), `damned_hauler` / `damned_carrier` (patrolling laborers; `patrol`
  offset), `damned_miner` (talkable "A Damned Soul" at his rock).
- `HubNpc.create(id)` wraps any npcs.json entry in a HubInteractable: verb / label / height from
  the entry; talking calls `model.talk()`, then plays an unseen story beat from the Dialogue pool
  `speaker`, else a bark from it, else one of the entry's `lines` (`narrate` for narration).
- Collision: `"collision": radius` in an npcs.json entry; spawn_npc adds a StaticBody3D (layer 1).

## Driving a model yourself
Inside an `Enemy`, models are driven by `animate(delta, move_ratio, state)` with `ground_speed`,
`state_progress`, `state_duration`, `body_scale` set first. Elsewhere set `autoplay = false` before
adding it and do the same, or leave autoplay on (idle + gestures). `play_attack()`, `play_land()`,
`jiggle_eyes()`, `talk()`, `gesture(id, length)` work on every model. Weights: `move_w`,
`windup_w`, `strike_w`, `recover_w`, `attack_kick`, `land_kick`, `gesture_w`.

## Writing a new procedural model
```gdscript
extends ProcModel   # DemonKit for demons, BossModel for bosses
func build() -> void:
    var torso := biped(0.5, 0.05, leg_mat, boot_mat)       # hips (body), planted walking legs, torso
    var a := arm(torso, Vector3(0.2, 0.36, 0), 0.4, 0.04, sleeve, hand, 0.0, 0.0)  # [shoulder, hand]
    solid_wing_pair(torso, Vector3(0, 0.34, 0.1), 0.8)     # cheap solid wings for big fliers
    _blade = keep(Art.part(...))                             # meshes you scale / glow at runtime
    finish()                                                 # merge static meshes (do this last)
func pose(delta: float) -> void:
    biped_bob(0.5)
    a_shoulder.rotation = mixv(rest, deg(190, 0, 10), windup_w)   # +X swings an arm forward/up
```
Rules: `build()` deterministic (merged meshes are cached per script + pivot path; `bake_variant()`
when exports change the geometry); register every moving pivot (`animated()`, `add_leg()`,
`add_arm()`, `limb_pivot()`, base `wing_pair` / `solid_wing_pair` / `eye` / `halo`); wrap meshes
changed at runtime in `keep()`. Feet: legs made by `leg()` / `beast_leg()` (or
`add_leg(..., length)`) are shortened along their axis when the hips sink below their reach, so
soles stay on the floor in crouches (`plant_feet = false` to opt out). Death: `death_style` =
`topple` / `sink` / `shrink` / `none` (see also the polish role's faction deaths below).
GDScript warnings such as Variant inference are errors in this project: type such variables.

Cost: ~6-17 mesh instances / 12-40 draw surfaces per model (`_gallery.tscn -- --stats`).

## Dev tools
- Gallery: `godot --path . res://scenes/characters/_gallery.tscn -- --shot=<abs png> --shot-time=2
  [--only=id,id] [--dir=enemies|allies|npcs|bosses] [--state=0..3] [--cols=N] [--close] [--side] [--stats]`.
- Smoke test: `godot --headless --path . -s res://scenes/characters/_roster_check.gd`: every roster
  enemy fights in a real run, ally minions must land hits, corpses clean up, each ProcBoss is pushed
  through all phases and killed, every ally / NPC model spawns. Exit 1 on failure.
- Compile check: `godot --headless --path . -s res://scenes/characters/_script_check.gd`.

## Known issues / next steps
- Boss hazards use the shared holy colours (the frost / pollen / dawn tints are on the models only).
- Allies are invulnerable and enemies never target them (by design for summons).
- The ballista, reliquary and gargoyle are large; the polish role's readability table may need them.

- From basecamp (round 2): the hub now walks your imp / hellhound / succubus / hell_brute models with
  `HubWanderer` (autoplay = false + animate) and adds two hub-only ProcModels of mine,
  `scenes/basecamp/models/damned_soul.gd` (task 0 carry / 1 pick / 2 chained) and `training_dummy.gd`.
  Feel free to restyle them; tell me in docs/team/basecamp.md if you want them in the roster instead.

## Audio (added by sfx, see docs/team/sfx.md)
- Every enemy needs no audio work: `data/audio/enemy_audio.json` lists material (hit/death sound) and
  wind-up voice per id; ids missing there are guessed from `CharacterRoster.ENEMIES` (faction +
  tags: construct -> stone + grind, elemental -> holy + hum, armored -> metal, beast -> roar /
  screech, mortal -> villager shout, angel -> angel cry). Add an entry to the JSON to override.

## characters-polish hooks (please keep; ping docs/team/characters-polish.md if they get in the way)
- `proc_model.gd` `_ready()`: `wrap_pose_pivot = true` (one marked line). After `build()` the
  EnemyModel base moves every child of the model under `pose_pivot` (local transforms and node refs
  unchanged; runs after `finish()`, so merged-mesh cache paths are unaffected). That pivot carries
  the hit flinch (away from the blow), the wind-up crouch / strike stretch and the white wind-up
  telegraph glow for all procedural enemies. Don't write `pose_pivot` yourself.
- `scripts/characters/enemy_polish.gd` (`EnemyPolish`): per-model readability scale on the pivot
  (collision untouched): ophan 1.9, clockwork_cherub 1.45, choir_wraith / martyr_shade 1.25, cherub /
  bell_gargoyle 1.15, the hooded casters ~1.1. Edit the table there rather than the models.
- Faction deaths (`scripts/characters/death_fx.gd`, `DeathFx`): EnemyModel.death_burst tries a
  faction death before your `spawn_corpse()`: angels / elementals SHATTER into light, mortals /
  orders / beasts RAGDOLL-topple away from the killing blow (your `_legs` / `_arms` flop), constructs
  CRUMBLE (parts drop, bounce, dust). Per-frame / concurrent caps fall back to your corpse. Faction
  comes from `CharacterRoster.ENEMIES`; overrides in `EnemyPolish.DEATH_STYLE`.

## Request from characters-polish (round 3): ragdoll limbs
Ragdoll deaths (DeathFx) now flop your walk `_legs` / `_arms` fully and every other `_animated`
pivot gently. For models whose real limbs are custom pivots (beasts' `beast_leg`s, the cherubim's
four legs, the ballista's arms, tails, wings), please expose them so they flop properly:
```gdscript
## Pivots that go limp when this model ragdolls (DeathFx). Return [] to keep it rigid.
func ragdoll_limbs() -> Array:
    return [_tail0, _tail1, _leg_fl, _leg_fr, ...]
```
When the method exists DeathFx uses only that list (full flop). No other change needed.

## Note from gameplay (round 3): conventions for enemies (please follow for round 3)
1. **Use the shared state machine.** Pick an `EnemyData.Behavior` (CHASE / SHOOT / CHARGE / HOP /
   SLAM / HEAL / SHIELD / KITE / EXPLODE / SUMMON) and drive the model from `animate(state)`. Extra
   per-type flavour goes in data flags, not new AI loops. Flags available now:
   - `aim_line` (SHOOT / KITE): paints the shot lane during the wind-up, aim locks at 70%
     (set on `templar_ballista`; good for snipers, ballistas, mounted lances).
   - `enrage_hp` + `enrage_speed_mult` (any): one-time frenzy below that HP fraction (faster, attacks
     40% sooner, red flare). Made for the **flagellant**.
   - `explode_ally_mult` (EXPLODE): blast damage to other angels (default 2.5x; luring is a tactic).
   - `summon` / `summon_count` / `summon_max` (SUMMON), `heal_*` (HEAL), `ward_*` (SHIELD).
2. **Telegraph everything that hurts**, via one of: `HolyTelegraph` (what the state machine uses; it
   joins group `danger_zones`), the boss hazard classes (`PyreBurst`, `InquisitorLane`,
   `JudgementPillar`, `BellRing`, `SarielOrb`, group `boss_hazards`), or your own node in either group
   implementing `danger_contains(p, margin) -> bool` (+ optional `danger_center()`).
   `scripts/danger.gd` (`Danger.threat_at(tree, pos, margin)`) reads all of these; the Autopilot,
   and later allies / AI, dodge with it. Projectiles fired through `Enemy._fire` join `enemy_shots`.
3. **Spawned enemies** (shades, minions): `e.setup(data, RunState.enemy_hp_mult(),
   RunState.enemy_damage_mult(), RunState.enemy_speed_mult())`. I changed `martyr.gd` `_rise_shade`
   to this (one marked `# [gameplay]` line; it used its own 0.35/min curve).
4. **Round 3 suggestions** (data only, no new AI needed): mounted knight = CHARGE with high
   `charge_speed` / `charge_time` (the lane telegraph is automatic); flagellant = CHASE with
   `enrage_hp = 0.5`; Dominion = SUMMON (commands lesser angels; `summon` = cherub or ophan) or
   SHIELD; Virtue = HEAL. Tell me in docs/team/gameplay.md if a design needs a new behaviour.

### Round-2 enemies I retuned (data/enemies/*.tres; retune freely)
`bell_gargoyle` attack_cooldown 1.4 -> 2.6 (it stomped every 2 s); `templar_ballista` aim_line = true
(16-damage bolts at 17 m/s were undodgeable without a tell); `mobile_reliquary` ward_reduction
0.5 -> 0.4 (it wards up to 8, more than the paladin); `witch_hunter_captain` windup 0.55 -> 0.65.
Checked, unchanged: martyr burst (PyreBurst = a boss hazard, so Danger sees it), exorcist drain,
gargoyle leap (HOP circle), reliquary ward (SHIELD), clockwork cherub (EXPLODE, now also hurts angels).

## Note from performance (round 2): skin-baked horde types
`ProcModel.finish()` now ends with an optional **SkinBake** step (`scripts/perf/skin_bake.gd`,
marked `# perf round 2` in `proc_model.gd`): every static mesh is folded into 1-2 *skinned*
meshes with one rigid bone per registered pivot (`animated()`, legs, arms, wings, eyes, halos), and
`animate()` copies the posed pivots into the skeleton. Cherub 13 -> 2 render instances, ophan 18 -> 3,
villager 8 -> 2; 300-enemy render CPU about -30%. Opt-in list: `ProcModel.SKIN_BAKE_TYPES`
(cherub, ophan, holy_knight, zealot, martyr, light_elemental, monk, censer_nun, villager, flagellant,
holy_water_friar); set `skin_bake = true/false` in `build()` before `finish()` to override.
Rules that matter more for baked types: register every pivot your `pose()` moves (an unregistered one
won't move its parts), and `keep()` every mesh you hide, scale on its own or recolour at runtime.
Visual check: `godot --path . res://tools/perf/skin_compare.tscn` (back row merged, front row baked).
Bones update at the 30 Hz physics tick, not interpolated per frame.
