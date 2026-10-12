# Story & dialogue (docs/team/story.md)

Status: round 6 complete. The lore bible is in `docs/lore.md`.

## Round 6 changes
- **Iscariel, the Turncoat** (demon id `iscariel`) gets the full treatment. His backstory: he
  kept the First Gate of the Silver City as Azrafel's brother-warden, opened it from the inside
  at the Fall, and invented the "thirty pieces of light" so Heaven would think he could be bought.
  - 6 quips, 2 death lines, run-start and return narration, boss-kill remarks (generic, plus
    Sariel, Azrafel, Baraqiel and Ozias)
  - intros against all 10 bosses
  - Sariel and Azrafel also get repeatable turncoat taunts and their own death lines for him
  - NPC reactions from all 8 hub NPCs
  - story beats with Vesper (he saw her fall), Kesh (opening a door you swore to keep), the Clerk
    (who paid the thirty pieces), Malphine and Pip
  - his own Archon and Throne lines in the ending, and Kesh's line in `ending_return`
  - Heaven's Gate and Gardens arrival lines, and a codex entry

## Round 5 changes
- **Nhazgul, the Plague Hive** (demon id `nhazgul`) now has everything the other demons have:
  - 6 mid-run quips, 2 death lines, Basecamp return narration
  - run-start lines (one first-run, one repeatable)
  - boss-kill remarks (generic, plus Sariel, Verdance and Aurum)
  - an intro exchange with all 10 bosses
  - a reaction line from all 8 hub NPCs (incl. Velka)
  - story beats with Grimmaul, Vesper, Pip and Kesh
  - Archon and Throne lines in the ending, a Pip line in `ending_return`
  - arrival lines for the Gardens and the Monastery, a codex entry, and an objective quip
- **16 map signature enemies:** taunts and death lines for each, plus a codex entry per enemy
  (category Heaven) that unlocks after a first run on that enemy's map (`map_runs.<map>`).
- `tools/story/story_check.gd` now knows the demon id `nhazgul`.

## Round 4 changes
- **Four more bosses** have intro, phase 1/2, rage and death lines, plus demon-specific and
  story-aware intros and codex entries:
  - `war_chariot`: Lord-Marshal Caddoc
  - `storm_archon`: Baraqiel
  - `gilded_seraph`: Aurum
  - `cantor`: Cantor Seraphiel
- **Enemy chatter for the 11 new enemies:** mounted knight, crossbow militia, flagellant,
  holy-water friar, mortal choir, Dominion, Virtue, Power, gryphon rider, Herald of the Last
  Trump, Paschal Lamb.
- **Celestial Leviathan:** a `celestial_whale` bark plays when it starts a pass. StoryHooks
  spots the whale by its script as it enters the tree.
- **New codex entries:** the Leviathan, the Paschal Lamb, Virtues and Powers.
- **Objective quips** for the objectives role's new objectives and events (escort_reliquary,
  defile_font, bishop_procession, bell_towers, carnage_totem, cursed_coffer,
  altar_of_temptation, crusade, holy_eclipse, angel_of_death).
- **Ending stage:** the kneeling Archons now kneel on gold-capped marble plinths beside the
  stairs instead of floating (`ARCHON_OFFSET`).
- **Keepsakes:** when an NPC's keepsake unlocks (affinity 3, `data/meta/keepsakes.json`), they
  hand it over with a thank-you scene (`keepsake_<speaker>`, sets `keepsake.<speaker>`). It plays
  right after the unlocking offering, or as their next story beat ("!"). It ends with a
  narration line naming the keepsake and saying it is chosen at the hellgate.
- **The Breach** (`the_breach`): first-visit, story-aware (Kesh's widening Breach, the hymn,
  the Empty Throne, the March, post-ending), Skarn-specific and repeatable arrival narration.
- **Malphine now accepts "tribute"** (G offerings), with 5 scenes and rewards, so her Ashen
  Signet keepsake can actually be earned.

## Round 3 changes
- **Ending trigger:** now the real finale. Passing the Seventh Gate on `heavens_gate` (maps /
  objectives roles, `SeventhGate` calls `RunState.end_run(true, &"seventh_gate")`) is the ending.
  The temporary 2-bosses rule is gone.
- **The ending is staged in the world** (`scenes/dialogue/ending_stage.tscn`). The demon climbs
  the stairs past seven kneeling Archons to the empty Throne. Camera moves and Atmosphere cues
  follow the `stage_*` events in the conversation:
  - start: `heavens_gate` preset
  - sit: `blood_moon` preset, crimson flash, the halo turns red
  - break: the Throne flies apart, lightning, `sanctum_ash_storm` preset
- **Codex toast:** a "New codex entry" card slides in on every `codex_unlocked` (`CodexToast`).
- **New boss lines** (intro / phase / rage / death, plus per-demon intros):
  - Azrafel, the Gate Archon (`gate_archon`)
  - Ysmir, the Frost Abbot (`frost_abbot`)
  - Aurelion, the Dawn Wyrm (`dawn_wyrm`)
  - Mother Verdance (`verdant_matriarch`)
  - Each also has a codex entry.
- **New enemy chatter** for 15 new enemy types: gargoyle, cherubim, choir wraith, clockwork
  cherub, dryad, exorcist, frost hermit, wyrmling, martyr and shade, mobile reliquary, ophan,
  plague doctor, templar ballista, witch-hunter captain.
- **New map arrival lines** for `gilded_isles`, `storm_spire` and `heavens_gate`; the Heaven's
  Gate lines are story-aware.
- **Gift rewards** via Progression (`affinity_rewards` in `gifts.json`):
  - Affinity 2: 3 Sin Shards.
  - Affinity 3: a permanent per-run stat perk:
    - Grimmaul: +5% might
    - Vesper: +6% XP
    - Clerk: +0.25 regen
    - Ossek: +0.3 speed
    - Pip: +0.6 pickup radius
    - Kesh: +12 max HP
  - Affinity 4: 1 Hellstone.
  - Affinity 5: an unlock:
    - Grimmaul: Infernal Chain
    - Vesper: Wraith Host
    - Clerk: Harvest Moon
    - Ossek: Tempest Nova
    - Pip: frees Morvane
    - Kesh: Infernal Storm
    - If the unlock is already owned, the reward is 8 Sin Shards instead.
  - Each reward is announced as narration.
- **Per-demon voice:**
  - each demon has 6 mid-run quips and 2 death lines of its own
  - boss-kill remarks (`demon_boss_kill.<demon>[.<boss>]`, 4 s after a boss falls)
  - its own Basecamp return narration
  - a reaction line to each demon from all 7 NPCs
  - demon-specific lines in the ending (Archons, the Throne) and demon-specific boss intros

## What exists
- **`Dialogue` autoload** (`autoload/dialogue.gd`): data-driven conversations, a modal typewriter
  box with portraits and choices, non-blocking barks and narration, and story memory (flags,
  counters, seen conversations) saved to `user://story.json` across runs.
- **About 410 conversations** in `data/dialogue/*.json`:
  - prologue, plus run-start, run-end and Basecamp-return narration
  - arrival lines for all five maps
  - demon quips and objective quips
  - boss lines for Sariel and Ozias the Grand Inquisitor (intro, phase, rage, death), plus
    fallbacks for other bosses
  - story beats and chatter for Grimmaul, Vesper, the Clerk, Ossek, Pip, Kesh and Malphine
  - offering scenes for each giftable NPC
  - the ending and the epilogue
  - floating chatter for every enemy type
- **Ending**: the Seventh Gate victory, then the `ending` conversation in Basecamp (choice: sit
  on or break the empty chair). After it comes act 4 ("the Reconquest"): epilogue lines per NPC,
  new narration, and the Sinbound Crown shrine by the bonfire. See "Ending" below.
- **Offerings / affinity**: in Basecamp, walk up to an NPC and press **G** (gamepad Y) to offer
  souls: one offering per NPC per visit, costing 20/40/70/110/160. Affinity goes 0..5 and each level
  plays its own scene. Affinity also unlocks extra chatter and codex entries.
- **Codex**: 29 entries in `data/dialogue/codex.json`, unlocked by story conditions. The UI
  role's CodexScreen (`C` in Basecamp) shows them.
- **Enemy chatter** (`WorldBarks`): floating taunts and death screams over the battlefield.
  There are lines for paladins, knights, inquisitors, zealots, monks, nuns, villagers, seraphs,
  cherubs, archangels, valkyries and statues, with faction fallbacks for the rest.
- **Basecamp NPCs** (all automatic):
  - Pip by the fire.
  - Kesh the Breachwarden at the hellgate.
  - Duchess Malphine, after the Empty Throne reveal.
  - The Crown, after the ending.
  - These NPCs use characters-new models through `StoryNpc`.
  - A "!" floats over NPCs with a new story beat, and an offering hint shows when one is focused.
  - Merchants tell their story beat before the shop opens, and the shop subtitle shows their
    chatter.

## Files I own
- `autoload/dialogue.gd` (autoload `Dialogue`: API, picking, variables; registered in project.godot)
- `scripts/dialogue/`:
  - `dialogue_db.gd`: JSON loading
  - `story_state.gd`: variables, conditions, save
  - `conversation_runner.gd`: steps through a conversation
  - `story_hooks.gd`: every automatic trigger and the ending rule
  - `world_barks.gd`: enemy chatter
  - `affinity.gd`, `codex.gd`
- `scenes/dialogue/`:
  - `dialogue_box.gd`, `dialogue_portrait.gd`, `dialogue_subtitles.gd`
  - `story_marker.gd`: "!" marker plus offering hint and G key
  - `story_npc.gd`: a talkable roster NPC
  - `crown_shrine.gd`
  - `ending_stage.gd` / `.tscn`: the staged ending
  - `codex_toast.gd`
- `data/dialogue/*.json`, `docs/lore.md`, this file
- `tools/story/`:
  - `story_check.gd`: data lint plus a 30-run simulation covering gifts and the ending
  - `dialogue_preview.tscn`: plays one conversation and auto-advances it
  - `camp_probe.tscn`: walks the hub avatar to an NPC, for screenshots

Shared-file edits:
- `project.godot`: the Dialogue autoload line.
- `scenes/basecamp/basecamp.gd`: `_open_shop_panel` uses `Dialogue.chatter(shop_id)` for the
  greeting.
- Notes appended to `docs/team/objectives.md` (the ending) and `docs/team/ui.md` (codex,
  affinity, codex toast).

## API
```gdscript
Dialogue.start("vesper_intro")          # modal conversation by id (pauses the game) -> bool
Dialogue.start_for("vesper")            # best conversation for a speaker / shop id / pool -> id or ""
await Dialogue.conversation_finished    # (id: String)
Dialogue.has_new("occultist")           # unseen story beat waiting (for a "!" marker)
Dialogue.bark("boss_intro.sariel")      # non-blocking subtitles from a pool or an id -> id or ""
Dialogue.chatter("blacksmith")          # one line of repeatable chatter as a String ("" if none)
Dialogue.say("pip", "text")  /  Dialogue.narrate("text")
Dialogue.speaker_for_shop("soul_broker")  # -> "clerk"
Dialogue.get_var(k) / set_var(k, v) / add_var(k, n) / has_flag(k) / set_flag(k)
Dialogue.is_active()   Dialogue.reset_story()   Dialogue.demon_id()
Dialogue.codex_entries()                # [{id, category, title, text, unlocked, is_new}]
Dialogue.codex_mark_read(id) / codex_new_count()
Dialogue.affinity(who) / gift_cost(who) / can_gift(who) / give_gift(who)
Dialogue.hooks.map_id()                 # id of the current run's map ("" if unknown)
StoryMarker.attach(node3d, "pip", 2.5)  # "!" + offering hint over any NPC of your own
```
Signals:
- `conversation_started(id)`, `conversation_finished(id)`
- `event_triggered(event_name, conv_id)`, from a line with `"event": "open_shop"`
- `gift_given(speaker, level)`
- `codex_unlocked(id)`, fired at run start and on Basecamp arrival

Shop ids map to speakers: blacksmith/forge -> grimmaul, occultist/oracle -> vesper,
soul_broker/covenant -> clerk, cartographer -> ossek. Other speakers: pip, kesh, malphine,
sariel, grand_inquisitor (shown as "Ozias").

### Automatic hooks (`StoryHooks`, nothing to call)
- `RunState.run_started`:
  - counts runs, per demon and per map
  - promotes `beat.*` to `known.*` and sets `story.act`
  - after 1.4 s, plays map arrival narration (pool `map_arrival.<map id>`), or `run_start` if
    nothing there is eligible
- `RunState.run_ended(result)`: sets `last.*` vars, counts deaths and victories, detects the
  ending, and plays run-end narration over the game-over screen.
- Bosses:
  - `Game.boss_spawned`: intro line (2.8 s after the spawn).
  - `Game.boss_phase_changed`: pool `boss_phase.<id>.<phase>`.
  - Rage line when `is_enraged` turns true; death line when `is_dying` turns true.
  - `Game.boss_died`: boss kill counters.
  - Boss id = the file name of its EnemyData `.tres` (`sariel`, `grand_inquisitor`,
    `gate_archon`, `frost_abbot`, `dawn_wyrm`, `verdant_matriarch`).
  - 4 s after a boss falls, the demon remarks on it (`demon_boss_kill...`).
- Run start: affinity stat perks are applied to the demon (`Affinity.apply_run_perks`).
- `Game.objective_completed(id)`: a demon quip (`objective_done.<id>`), at most one every 40 s.
- Entering the Basecamp scene: NPCs and markers, then the prologue (first visit), the ending
  conversation (after the ending run), or the return narration.
- Mid-run quips (pool `run_mid`) at 95 s, 215 s and 420 s, if no boss is up.
- `WorldBarks`:
  - `enemy_taunt.<enemy id | faction>`: every ~7..13 s, from an enemy within 17 m of the demon.
  - `enemy_death.<...>`: for 7% of nearby deaths.

### Ending
- **Rule** (`ending_rule` in `data/dialogue/ending.json`): a victory with cause `seventh_gate`
  while `story.ended` is unset. The cause comes from passing the Seventh Gate on
  `heavens_gate`, which the Gate itself only allows once `known.march` is set (around run 12+).
- **The ending itself:**
  - The run-end line plays: "Beyond the Gate there are stairs...".
  - On the next Basecamp arrival, `ending_stage.tscn` loads and plays `ending` unpaused, so the
    staging keeps moving.
  - Then it fades back to Basecamp, which plays `ending_return` (NPC reactions).
  - Afterwards: `story.ended`, `known.ending`, `story.act = 4`, `ending.choice` ("sit" / "break").
  - Stage events, for anyone extending it: `stage_climb`, `stage_archons`, `stage_throne`,
    `stage_sit`, `stage_break`, `stage_after`.
- **Post-ending Basecamp:**
  - the Sinbound Crown shrine by the fire
  - an epilogue line from every NPC
  - Reconquest run-start and return narration
  - The basecamp role already themes the hub on `Dialogue.has_flag("story.ended")`.
- **Dev:** `godot --path . res://scenes/dialogue/ending_stage.tscn -- --story
  --story-save=user://story_dev.json --demon=vharok --auto-advance=1.6 --pick=0|1`

### Test mode
- With `--autopilot`, `--shot=...` or in headless runs, Dialogue does nothing automatically and
  never saves, so bots and screenshots are never paused by a conversation.
- Pass `--story` to turn it back on (e.g. `-- --story --shot=x.png`).
- Add `--story-save=user://story_dev.json` to play against a separate save file instead of the
  real one.

## Story variables (read them anywhere with `Dialogue.get_var`)
- **Runs and totals:** `runs`, `deaths`, `victories`, `endings`, `kills_total`, `best_time`,
  `basecamp_visits`, `gifts_given`.
- **Per id:** `boss_kills`, `boss_kills.<id>`, `boss_seen.<id>`, `runs_as.<demon>`,
  `map_runs.<map>`.
- **Current run:** `run.boss_kills`, `run.map`.
- **Last run:** `last.result` ("death" / "victory" / "abandon"), `last.died`, `last.victory`,
  `last.ending`, `last.time`, `last.kills`, `last.boss_kills`, `last.level`, `last.demon`,
  `last.map`.
- **Story progress:** `story.act` (1..4), `story.ended`, `ending.choice`.
- **Beat flags** `beat.*` / `known.*`: hollow_hymn, lattice_question, lattice_answer, dawn_fuel,
  empty_throne, march, ending, brittle_steel, herald_doubt, crossed_name.
- **Choices:** `path.*` (path.defy_court, path.throne, path.vengeance).
- **Affinity:** `affinity.<speaker>` (0..5), `bond.<speaker>` (affinity 5).
- **Codex:** `codex.read.<id>`, `codex.known.<id>`.

## Data format (`data/dialogue/*.json`)
```json
{
  "speakers": {"vesper": {"name": "Vesper Ashtongue", "title": "...", "color": "#b03bff",
                          "glyph": "V", "portrait": "res://optional.png", "shops": ["occultist"]}},
  "conversations": [
    {"id": "vesper_hymn", "pool": "vesper", "once": true, "priority": 80,
     "requires": {"min": {"runs": 4}}, "set": {"beat.hollow_hymn": true},
     "lines": [
       {"who": "vesper", "text": "Listen when you go up, {demon}."},
       {"choices": [{"text": "Why?", "goto": "why"}, {"text": "No.", "end": true}]},
       {"label": "why", "text": "...", "requires": {...}, "set": {...}, "add": {...}, "event": "x"},
       {"goto": "why"}, {"end": true}
     ]}
  ],
  "codex": [{"id": "...", "category": "...", "title": "...", "text": "...", "requires": {...}}],
  "ending_rule": {"map": "sunlit_citadel", "boss_kills": 2, "requires": {...}}
}
```
- **Picking** (`start_for`, or `bark` on a pool):
  - The eligible unseen `once` conversation with the highest priority wins, but only one per
    pool per Basecamp visit.
  - Otherwise a random repeatable from the highest eligible priority, never the same one twice
    in a row.
- **`requires`:**
  - `min` / `max` / `eq` on vars (numbers compare by value)
  - `flags` / `not_flags`, `seen` / `not_seen`
  - `demon` / `not_demon` (an id or a list)
  - `any` (a list of blocks), `chance`
- **`who`:** a speaker id, `player` (the current demon), or `narrator`. A line without `who`
  uses the conversation's `who`, else its pool if that is a speaker, else the narrator.
- **Text:** BBCode allowed; `{demon}`, `{demon_title}` and `{any.var}` are substituted.
- **Other top-level keys** (`codex`, `ending_rule`, ...) land in `DialogueDB.extra`.
- **Validate after editing:** `godot --headless --path . --script res://tools/story/story_check.gd`

## Known issues / next steps
- No real portraits yet: procedural medallions with glyphs. Drop a texture path into a
  speaker's `portrait` and it is used automatically.
- The kneeling Archons in the ending are tilted archangel models; they have no real kneel pose.
- Offerings cost souls only; there are no gift items.
- Text speed follows `Settings.text_speed` (the UI role wired this into the dialogue box).
- Exports must include `*.json` in the export filter.

- From basecamp (round 2): the Bloodwine Bar bartender (succubus) is speaker id `velka`. A `velka`
  pool would be played by "Have a drink" via `Dialogue.bark("velka")`; until then the hub uses its own
  lines (`HubLife.BAR_LINES`) through `Dialogue.say("velka", ...)`.
  **Story, round 3: done.** Speaker `velka` and pool `velka` are in `data/dialogue/velka.json`:
  your bar lines, plus story-aware and per-demon ones.

## Request from maps (round 2): the Seventh Gate is built
Map `heavens_gate` (order 8; unlocked after `storm_spire`, needs `known.march`) ends the run with
`RunState.end_run(true, &"seventh_gate")` when the demon breaks the 3 Gate Wards, fells 1 boss
and walks through the opened Gate (`scenes/maps/features/seventh_gate.gd`). The doors refuse a demon
without `known.march`. Please move `ending_rule.map` in data/dialogue/ending.json to `heavens_gate`, or set
its `boss_kills` to 99, so the sunlit_citadel fallback steps aside. Hint toasts at the Gate are in that
script if you want to reword them.
**Story, round 3: done.** The ending now triggers only on cause `seventh_gate`; the fallback is gone.


## Note from progression (round 3)
`Dialogue` now defaults `save_path` to `SaveProfile.path("story.json")` (one marked line before the
`--story-save=` loop), so `--save-profile=<name>` and the automatic "bot" profile isolate the story save
too. `--story-save=` keeps working and wins when given. See docs/team/qa.md.

- From basecamp (round 3): keepsakes (data/meta/keepsakes.json) unlock at `Dialogue.affinity(giver) >= 3`
  for grimmaul, vesper, clerk, ossek, pip, kesh, malphine. A thank-you line when one becomes available
  would be welcome (pool "<speaker>" with requires min affinity.<speaker> 3). The camp reaches level 4 after
  `story.ended` (captive archangel, inverted banners, throne or broken chair from `ending.choice`).

## Note from the objectives role (round 2)
- Azrafel (`gate_archon`) now has his own three-phase fight (`ArchonBoss`): phases 1 "The Seventh
  Light" and 2 "Wrath of the Throne" fire `Game.boss_phase_changed` -> pools `boss_phase.gate_archon.1/2`.
  On heavens_gate he **always** steps through when the last Gate Ward breaks; the Gate opens on his death.
- New objective ids for `objective_done.<id>` quips: escort_reliquary, defile_font, bishop_procession,
  bell_towers, carnage_totem, cursed_coffer, altar_of_temptation. Mid-run events (also emit
  `Game.objective_started/completed/failed` with their id): crusade, holy_eclipse, angel_of_death
  (the Pale Reaper, not in group `boss`). `RunState.last_result.objectives.grade` (S..D) is available
  for run-end lines.

## Note from characters-new (round 3): new bosses + the kneeling Archons
- Four more ProcBoss bosses (boss id = EnemyData file name, so pools are `boss_intro.<id>`,
  `boss_rage.<id>`, `boss_death.<id>`, `boss_phase.<id>.1/2`):
  `war_chariot` Lord-Marshal Caddoc, the Burning Crusade (ashen_wastes), `storm_archon` Baraqiel,
  Archon of the Tempest (storm_spire), `gilded_seraph` Aurum, the Gilded Seraph (gilded_isles),
  `cantor` Cantor Seraphiel, the Broken Choir (ruined_sanctum, after Sariel in the rotation).
  Phase names: Caddoc "The Muster / The Advance / The Pyre", Baraqiel "Gathering / The Squall /
  Eye of the Storm", Aurum "The Counting / The Tithe / Avarice", Seraphiel "Introit / Requiem /
  Dies Irae". Until you add pools they fall back to the generic boss lines.
  **Story, round 4: done** (pools plus codex entries; the Archons are on plinths now).
- `archangel.gd` now has `@export var kneeling` (knee down, sword planted, head bowed, wings folded,
  starts knelt when set before add_child). `ending_stage.gd _build_archons()` uses it (one marked
  edit replacing the tilt): `m.set(&"kneeling", true)` before `holder.add_child(m)`.
- New enemies with codex-worthy mechanics: `exorcist` (drains Ichor + reaped souls), `martyr`
  (rises as a Martyr's Shade), `virtue` (undoes the last 3 s of damage to nearby angels),
  `paschal_lamb` (killing it heals the Host), `power` (hunts the demon's allies). And the Celestial
  Leviathan map event (a whale of light over open-sky maps).

## Note from characters-new (round 4)
- New playable demon `nhazgul` (Nhazgul, the Plague Hive: a rotten sinner the flies made a home
  of; brute build, Plague affinity). Demon-specific lines (`"demon": "nhazgul"`) for run start,
  merchants and boss intros would make him feel at home.
- Map signature enemies worth a codex line: see the table in docs/team/characters-new.md.

## Note from characters-new (round 5): Iscariel, the Turncoat
New playable demon `iscariel` ("He held the Gate for Heaven, then opened it for Hell. Both sides
remember. Only one forgives."): a fallen angel with a blackened, broken halo, one pale wing and one
burned to a charred stump, holy-gold veins turning to hellfire. Envy affinity. Demon-specific lines
(`"demon": "iscariel"`) would land well with Azrafel / Sariel / the Gate Warden (he knew them) and
with Kesh (he opened a gate once). Same request for `nhazgul` from round 4.
