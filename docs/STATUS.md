# DemonCore (SINBOUND): status

A 3D Vampire-Survivors-style roguelite in Godot 4.7.2. You play a demon cast out of Heaven's
war; the enemies are angels, saints, knights and other righteous forces. Every run starts and
ends in **Basecamp Hell**, a hub where you spend what you bring back. Everything (code, models,
sounds, music, data) is authored as text or generated from text. There are no downloaded assets.

How it fits together: [ARCHITECTURE.md](ARCHITECTURE.md). How to build, test and add content:
[CONTRIBUTING.md](CONTRIBUTING.md). Per-system detail: `docs/team/*.md`.

---

## What's in the game

| | |
|---|---|
| **Playable demons (7)** | Vharok the Horned Ravager, Lilaeth the Fallen Seraph, Morvane the Hexbinder, Skarn the Chain Warden, Ysolde the Pale Reaper, Nhazgul the Plague Hive, Iscariel the Turncoat. Each has its own look, perks, starting weapon, palette-swap skins (14 in the wardrobe), mastery track, sound set and story lines. |
| **Maps (10)** | The Ruined Sanctum (endless), The Outer Gardens, Cathedral City, The Gilded Isles, The Frozen Monastery, The Ashen Wastes, The Breach, The Sunlit Citadel, The Storm Spire, Heaven's Gate (the finale). Each has its own layout, hazards / interactables, atmosphere preset, music theme and boss. |
| **Bosses (10)** | Sariel, Herald of the Last Dawn; Ozias, the Grand Inquisitor; Mother Verdance; Ysmir, the Frost Abbot; Aurelion, the Dawn Wyrm; Lord-Marshal Caddoc (war chariot); Baraqiel, Archon of the Tempest; Aurum, the Gilded Seraph; Cantor Seraphiel; and the finale, Azrafel, Archon of the Seventh Gate. |
| **Enemy types** | 70 (`data/enemies/`): cherubs and choirs, knights, priests, inquisitors, villagers, beasts (griffons, pegasi, unicorns, the Lion), golems, statues, siege engines, and map-signature enemies. Behaviours: chase, shoot, charge, hop, slam, heal, shield, kite, explode, summon. |
| **Weapons (6)** | Ravager's Cleave, Hellfire Bolt, Infernal Chain, Reaper's Scythe, Wailing Souls, Brimstone Sigil. Each has 7 levels. |
| **Abilities** | 68 rites across the sin schools (Hellfire, Blood Magic, Plague, Necromancy, Shadow, Storm, Chains, Curses, Illusion, Soul Harvest, Infernal Machinery, the seven sins…), 35 synergies, 37 level-up boons, evolutions. |
| **Objectives & events** | 19 objective types per map (desecrate shrines, hunt the fleeing saint, free the damned, topple pylons, escort, rituals, gates…), 3 mid-run events (Crusade, Holy Eclipse, the Pale Reaper), a run score and a Daily Trial. |
| **Progression** | Souls (Meta: 13 shopkeeper upgrades in 6 shops); Sin Shards and Hellstone (Progression: 40 upgrades, unlocks, 6 pacts = heat); 34 relics with rarities; demon mastery; camp levels that change the hub. |
| **Basecamp Hell** | Shopkeepers (Mother Marrow, Hask Cinderjaw, Vesper, Grisk), Kesh at the hellgate (pre-run loadout: weapon, starting rite, keepsake), Pip, Malphine, Velka's Bloodwine Bar, the Ledger and trophy wall, the Board of Trials, the Proving Pit (training dummies), the wardrobe, the codex, a quick menu (Tab). |
| **Story** | About 900 conversations and barks (`data/dialogue/`), NPC affinity and offerings, 59 codex entries, enemy chatter, boss taunts, an ending in the hub. |
| **Presentation** | Procedural / Blender-script models, per-map atmosphere and weather, corruption trail, procedurally synthesized sound effects (per-surface footsteps, per-demon sound sets), adaptive stem music with a theme per map, full settings (graphics presets, keybinds, controller navigation, accessibility). |

## How to play

1. Run `Play.bat` (or open the project in Godot 4.7.2 and press F5).
2. Pick a demon, walk around Basecamp Hell (WASD, **E** to interact, **Tab** quick menu), then
   use the hellgate to choose a loadout and a map.
3. In a run you move; weapons and rites fire on their own. **Space** dashes. Pick a boon on every
   level-up, chase objectives on the minimap, survive the waves and fell the map's boss.
4. Win or die, you return to the hub with Souls, Shards and Hellstone to spend.

Pads work (A accept, B back, LB/RB tabs, Start pause). Debug builds: F1 level-up, F2 damage
numbers, F4 win the run, F6 +25 Ichor, F8 spawn the next objective.

## How to test

```bash
tools/qa/run_all.sh            # the integration suite (~6-10 min), summary table + logs
tools/qa/run_all.sh --quick    # skip the slow checks
godot --path . res://scenes/main.tscn -- --map=storm_spire --autopilot --godmode   # watch the bot play
```

Test runs use a separate save profile (`user://test/<profile>/`), so they never touch real saves.
The QA owner's notes and open issues: `docs/team/qa.md`.

---

## Needs a human

Things the automated checks and the autopilot bot cannot judge. Collected from every
`docs/team/*.md`; the owning doc has the details.

**Playtesting and balance**
- Run length and difficulty were tuned with the autopilot bot. It dodges well but picks level-ups
  at random and kites melee demons badly. A human pass is needed on: first-run length (target 3-5
  min), per-map difficulty (maps.md has the bot numbers), boss fights, and the Heaven's Gate
  finale. On a fresh save the bot dies there in under a minute. (gameplay, maps, qa)
- The progression economy sim's player model is a guess. Re-fit it to real playtest numbers
  (progression.md).
- Melee demons (Vharok, Iscariel) under the bot often score no kills. Check they feel right in human
  hands (qa.md, B2).
- Do the abilities feel distinct? Their synergies and evolutions were only checked by data tests.

**Listening**
- No music was checked by ear, only with spectra and loudness meters. Listen through every map
  theme, the boss layers and the ending (music.md). The music budget is nearly full.
- Sound effects need a listening pass: the per-demon sets (Nhazgul's swarm, Iscariel's cracked
  choir), footsteps per surface, statue grinding when many are alive, and thunder timing (sfx.md).

**Looking**
- Readability: are telegraphs visible in big waves? Are small enemies readable, and do big
  ones (ballista, reliquary, gargoyle) hide the player? (characters-new.md, characters-polish.md)
- Heaven maps are bright by design and hell arenas read dark. Check contrast on a real monitor
  (visuals.md, terrain.md).
- Basecamp merchants are primitive-built figures, and the focus outline fills some of their parts
  (basecamp.md, characters-polish.md). Portraits are placeholder medallions (story.md).

**Controls and platforms**
- Controller play end to end: the hub, the quick menu, loadout, shops, codex, level-up, pause and
  rebinding (ui.md). Pads were only tested with simulated input.
- Window modes, resolutions and the graphics presets on low-end hardware (perf budgets are in
  performance.md).
- An export build: include `*.json` in the export filter (story.md) and check the first-launch
  sound-cache build time.

**Decisions**
- Whether Heaven's Gate should be locked until the story allows it (qa.md).
- Summons use their own controller instead of the ally one (abilities.md). Decide whether to merge
  them.
