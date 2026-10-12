# Basecamp Hell (docs/team/basecamp.md)

Status: round 2 in. On top of round 1 (hub, `Meta`, merchants, shops, hellgate + map choice,
pacts, run payout and return): a living, growing camp (HubLife), the Ledger + trophy wall
(HubBoards), the Proving Pit with training dummies (HubPit), per-item currency in the shops, warm
lantern pools at every stall, ambient blight back on. `tools/basecamp_smoke.gd` covers all of it.

## Flow
Title -> Demon select -> **Basecamp Hell** -> hellgate -> run (`Maps.selected_id` in main.tscn) ->
death / victory / abandon (`RunState.end_run`) -> game-over or victory screen ->
`RunState.return_to_basecamp()` -> **Basecamp Hell** (arrival banner shows the haul).
The summoning circle in the hub goes back to the demon select; its "begin" returns to the hub.

## Owned files
| Path | What |
|---|---|
| `autoload/meta.gd` (autoload `Meta`) | Souls, souls upgrades, map unlocks + selection, lifetime stats, run payout. Save: `user://meta_save.json` (atomic write). |
| `data/meta/upgrades.json` | Shops (name, title, greeting, color) and the souls upgrade catalog. |
| `scenes/basecamp/basecamp.tscn` / `basecamp.gd` (`Basecamp`) | Hub root: avatar, camera, interactables, HUD, shop wiring, gate transition, dev args. |
| `scenes/basecamp/hub_scenery.gd` (`HubScenery`) | Everything visual + static colliders, and the layout constants. |
| `scenes/basecamp/hub_avatar.gd` (`HubAvatar`) | The chosen demon walking around (movement only). Group `hub_avatar`. |
| `scenes/basecamp/hub_interactable.gd` (`HubInteractable`) | Proximity prompt + `interacted` signal. Group `hub_interactables`. |
| `scenes/basecamp/hub_shopkeeper.gd` (`HubShopkeeper`) | Procedural merchant figures (4 looks), idle + watch-the-player animation. |
| `scenes/basecamp/hub_shop_ui.gd` (`HubShopUI`) | Cartographer map list, Covenant pacts, Proving Pit rite picker. |
| `scenes/basecamp/hub_life.gd` (`HubLife`) | Camp development level + everything gated by it; quarry, porters, bar, tents, palisade, kennel, monument. |
| `scenes/basecamp/hub_wanderer.gd` (`HubWanderer`) | Walks any ProcModel along a waypoint loop with stops and gestures. |
| `scenes/basecamp/hub_boards.gd` (`HubBoards`) + `hub_board_ui.gd` (`HubBoardUI`) | Ledger obelisk (Meta.stats) and the trophy wall (Meta.trophies), read-only board window. |
| `scenes/basecamp/hub_pit.gd` (`HubPit`) + `training_dummy_enemy.gd` (`TrainingDummyEnemy`) | Proving Pit: swaps the avatar for a real Player, immortal harmless dummies, DPS readout. |
| `scenes/basecamp/models/damned_soul.gd/.tscn`, `training_dummy.gd/.tscn` | Hub-only ProcModels (sinner labourer with 3 tasks; straw angel effigy). |
| `scenes/basecamp/lava.gdshader`, `portal.gdshader` | Lava sea and hellgate swirl. |
| `tools/basecamp_smoke.gd` | Headless loop test (restores your saves afterwards). |

Small edits I made in shared files: `project.godot` (Meta autoload), `scenes/menu/demon_select.gd`
(begin -> basecamp), `data/atmosphere/presets.json` (`basecamp_hell`: less fog / red wash, softer
sun and ambient so the merchants read; visuals owner, feel free to retune).

## The hub
Layout (`HubScenery` constants): spawn south of the bonfire; **hellgate** north (GATE), with the
**cartographer** Wayfarer Ossek beside it; **blacksmith** Grimmaul west (forge, anvil, weapon rack);
**occultist** Vesper east (violet glyph, bookshelf); **soul broker** Mammon's Clerk south-west
(counting desk, soul jars) with **the Covenant** lectern next to him; **summoning circle** south-east.
Controls: WASD / stick walk, **E** / Enter / pad X or A interact, Esc settings.

Interacting with a merchant: if `Dialogue.has_new(shop_id)` it plays that conversation first
(story role), then opens the shop. Upgrade shops use the UI role's **ShopPanel**
(`ui/components/shop_panel.tscn`); the cartographer and the Covenant use `HubShopUI` lists.

Each merchant sells its Meta (souls) upgrades plus the Progression wares of the mapped shop:
`blacksmith` + `hellforge`, `occultist` + `occult`, `soul_broker` + `bindings` (demon unlocks).
Progression wares priced in Sin Shards / Hellstone show their price in the flavour line (ShopPanel
has one wallet); `Progression.buy` validates the cost.

## Meta API (autoload `Meta`)
- Currency: `souls`, `add_souls(n)`, `spend(n) -> bool`, `add_run_souls(n)` (banked at run end),
  signal `souls_changed(total)`.
- Upgrades: `get_def(id)`, `get_level(id)`, `get_max_level(id)`, `is_maxed(id)`, `next_cost(id)`,
  `requirement_text(id)`, `block_reason(id)`, `can_buy(id)`, `buy(id) -> bool`,
  `upgrades_for_shop(shop)`, `effect_total(key)`, `effect_text(id, rank)`, signal `upgrade_bought(id, level)`.
- Maps (definitions live in the `Maps` autoload): `get_maps()`, `get_map(id)`, `map_cost(id)`,
  `is_map_unlocked(id)`, `map_requirement(id)`, `unlock_map(id)`, `select_map(id)` (also calls
  `Maps.select`), `selected_map`, signals `map_selected(id)`, `map_unlocked(id)`.
  A map is locked when its def has `"unlock": {"default": false, "cost": N}`; it is unsealed for N
  souls at the cartographer. `"requires": "<map id>"` gates it behind another map's unlock.
- Runs: `start_run()` (selected map), `go_to_basecamp()`, `is_run_active()`, `finish_run(victory, result)`,
  signal `run_finished(summary)` (keys: victory, cause, souls, base, ichor, multiplier, kills, time, level).
  Driven automatically by `RunState.run_started` / `run_ended`; nobody needs to call these.
- `pending_summary`: the last run's summary, consumed by the hub's arrival banner.
- `stats`: runs, victories, best_time, total_kills, souls_earned.
- `reset_save()` wipes meta progress.

Soul payout per run: `kills * 0.05 + seconds / 15 + level * 1.5 + carried Ichor + run_souls`
(+150 on victory), times `1 + effect_total("soul_gain")`. Progression adds its heat bonus on top
via `run_finished`.

Upgrades are applied to every Player automatically (SceneTree.node_added -> after Player._ready).

## Upgrade data format (`data/meta/upgrades.json`)
```json
{"id": "bs_might", "shop": "blacksmith", "name": "Hellforged Edge", "icon": "⚔",
 "description": "+6% damage per rank.", "max_level": 5, "cost": [25, 50, 90, 150, 240],
 "requires": {"oc_area": 2},
 "effects": [{"stat": "might", "per_level": 0.06}]}
```
- `cost`: array (price per rank, last repeats) or number + optional `cost_growth`.
- `requires`: ids of Meta upgrades **or** Progression upgrades/unlocks -> minimum level.
- `effects`: `{"stat": <Player property>, "per_level": x}` -> `Player.apply_stat`;
  `{"type": "weapon", "scene": "res://..."}` -> extra starting weapon; any other `type`
  (e.g. `soul_gain`) is read by whoever cares via `Meta.effect_total(type)`. Optional `label`.
- Same shape as Progression's `data/progression/upgrades.json` (agreed with the progression role),
  so `requires` can cross between the two.
- Shops: `"shops": {"<id>": {name, title, greeting, color}}`. `covenant` and `cartographer` have no
  upgrades; they head the pact and map windows.

## Hooks for others
- Add a hub interactable: `var it := HubInteractable.new(); it.verb = "Read"; it.label = "Notice";
  it.position = ...; get_tree().get_first_node_in_group(&"basecamp").add_interactable(it);
  it.interacted.connect(...)`. The hub handles focus, prompt and the key.
- `Basecamp.run_starting` fires as the gate swallows the player (before the scene change).
- `Basecamp.scenery` (`HubScenery`) exposes `gate_surface` / `gate_light` and the layout constants.
- Dev args (after `--`): `--hub-at=<blacksmith|occultist|soul_broker|cartographer|gate|circle|covenant>`,
  `--hub-open=<shop id|shop:<id>|maps|pacts>` (`shop:` skips dialogue), `--hub-enter`.
  E.g. `godot --path . res://scenes/basecamp/basecamp.tscn -- --hub-open=shop:blacksmith`.
- Smoke test: `<godot> --headless --path . --script res://tools/basecamp_smoke.gd`.

## Known gaps
- Merchant figures are code-built primitives; a pass by the characters role would lift them.
- Pit: the Progression run HUD and Abilities HUD appear while training (removed on leave).
- Wanderers walk through props (no avoidance); paths are laid to keep clear of stalls.

## From the UI role (docs/team/ui.md)
- **Codex in the hub:** I added a small hook in `basecamp.gd`: the `C` key opens `CodexScreen`
  (scenes/ui/codex_screen.gd, the story role's `Dialogue.codex_entries()`); `_menu_open()` counts it
  and the hint line says "C  codex". Move it to an NPC / interactable if you prefer.
- **Map select + pacts polish (offer):** `ListPanel` (ui/components/list_panel.gd) + `ChoiceRow`
  (ui/components/choice_row.gd) are drop-in replacements for HubShopUI's list mode: painted medallion
  icons (GlyphIcon, no emoji font), a state edge + shape (◉ chosen / ◆ active / ○ available / ✕ locked,
  colour-blind safe), tag chips ("PERIL ✠✠", "+2 HEAT / RANK"), a red requirement note, buttons, a
  − ◆◆◇ + rank stepper, and a segmented summary gauge (total heat). Rebuild via a `rows` callable and
  `refresh()` keeps focus. Preview: `godot --path . res://tools/ui/ui_gallery.tscn -- --view=list`.
  Mapping `_map_row` / `_pact_row` is ~20 lines each; I didn't touch hub_shop_ui.gd since you're editing it.

## Round 2 additions

### Living camp (`HubLife`, `HubWanderer`)
Camp development level `HubLife.camp_level()` (0..3) from `HubLife.camp_points()`: every bought
Meta rank + every Progression rank + 2 per Progression unlock + runs/2 (max 10) + 4 per victory +
4 per trophy. Thresholds `HubLife.LEVEL_POINTS = [0, 4, 15, 32]`. Each level adds to the last:
| level | name (ledger) | what appears |
|---|---|---|
| 0 | Ruin | stone quarry by the lava (3 damned souls hauling / quarrying / dragging chains), an imp porter |
| 1 | Outpost | the Bloodwine Bar (Velka the succubus pours; "Have a drink" = a line), hide tents, 2 more porters |
| 2 | Stronghold | spiked palisade on the south edge, hellhound kennel (2 resting, 1 patrolling, brute keeper), 3 more souls |
| 3 | Citadel | stone monument of the chosen demon (frozen GLB, stone material) with braziers |
A newly reached level is announced once ("The Camp Grows" banner, `Meta.camp_level_seen`).
Dev: `-- --camp=<0..3>`. NPCs listed in `data/npcs/npcs.json` "basecamp" (characters role: Kesh,
Pip, ...) are still placed by `CharacterRoster.populate_basecamp`.

### Ledger and trophy wall (`HubBoards`)
- Ledger of the Damned (obelisk west of the bonfire): runs, wins, kills, best time, souls earned /
  held, ranks bought, trophies, camp stage and points to the next stage.
- Wall of Fallen Heralds (north-east, by the lava): one plaque per boss in `data/bosses/bosses.json`;
  a mounted trophy (halo, wings, gem) after the first kill, chained seal before.
- Meta API: `Meta.trophies` (id -> {kills, first_kill, demon}), `record_boss_kill(id)`,
  `has_trophy(id)`, `boss_trophies()`, signal `trophy_unlocked(id)`. Kills are recorded from
  `Game.boss_spawned` / `Game.boss_died` (the dying boss's `EnemyData.id`). New bosses only need a
  `bosses.json` entry; add a colour to `HubBoards.TROPHY_COLORS` if gold doesn't suit.

### Proving Pit (`HubPit`)
East of the plaza. Interact -> rite picker (bind up to 3 abilities from `Abilities.defs`, sealed ones
greyed via `Progression.is_ability_unlocked`) -> "Enter": the avatar is swapped for a real
`player.tscn` (demon, weapons, Meta + Progression bonuses apply as in a run), the rites are granted
via `Abilities.grant`, three `TrainingDummyEnemy` straw angels stand in the ring (never move,
never hurt, can't die, DPS over 4 s above each). `Game.godmode` is on while inside. E / Esc leaves;
Game.player / Game.world are reset. Signals `HubPit.entered` / `exited`. Dev: `-- --hub-pit=id,id`.

### Shops
ShopPanel per-item currency: Progression wares priced in Sin Shards / Hellstone carry
`currency_glyph/color/name/amount`, and those merchants show extra header wallets.

### Lighting / blight
- `Basecamp.BLIGHT = 0.6` (art-style's noise-varied ambient blight: crack clusters, no glowing grid).
- Every merchant stands in a warm amber pool from an iron lantern on a bone post (`_lantern`), the
  bar, pit, quarry, kennel, monument and boards have their own warm lights. Flicker is shared
  (`HubScenery.add_flicker`).

### Notes for other roles
- characters-new: `scenes/basecamp/models/damned_soul.gd` (task 0 carry / 1 pick / 2 chained) and
  `training_dummy.gd` are hub-only ProcModels I wrote on your base class; feel free to restyle them
  or move them into your roster. Wandering uses `autoplay = false` + `animate()` as you documented.
- story: the bartender is speaker id `velka` (succubus). If you add a `velka` pool, "Have a drink"
  plays `Dialogue.bark("velka")`; until then it says a line from `HubLife.BAR_LINES`.
- visuals: the hub's own warm lights are listed above; the preset can stay moody, the stalls carry
  their own light now.
- Dev args added: `--hub-at=pit|ledger|trophies|bar|quarry|kennel|monument`,
  `--hub-open=rites|ledger|trophies`, `--hub-pit=<ids>`, `--camp=<n>`.
- **Hellgate loadout screen (round 3, ready to use):** `LoadoutPanel` (ui/components/loadout_panel.gd)
  takes `RunLoadout.weapons() / abilities() / keepsakes()` + `Meta.loadout` directly:
  `lp.open({"title": ..., "subtitle": ..., "current": Meta.loadout, "weapons": RunLoadout.weapons(),
  "abilities": RunLoadout.abilities(), "keepsakes": RunLoadout.keepsakes()})`, then
  `lp.confirmed.connect(Meta.start_run_with_loadout)`. Three columns of cards (painted icons, weapon
  icons from `Icons`), locked entries explain why (keepsakes show "<giver>'s trust 2 / 3"), a
  summary line, DESCEND (also D / pad Start), Esc leaves; fully pad-navigable.
  Preview: `ui_gallery --view=loadout`. I did not wire it into basecamp.gd — it's your hellgate.

## QA notes (from docs/team/qa.md)
- `autoload/meta.gd` `_sync_map()`: QA added an early return when a valid `--map=<id>` dev arg is on
  the command line, so the saved hub choice no longer overrides it (marked `# QA:`). Hub-gate runs
  still use `Meta.selected_map` as before.

## From characters-polish: the wardrobe ("Vanity of the Fallen")
`scripts/characters/hub_wardrobe.gd` (`HubWardrobe`), installed by one marked line in
`Basecamp._ready` (`HubWardrobe.install(self)`, after the avatar exists) plus one in `_menu_open()`
(`HubWardrobe.open_now`). It stands at `HubWardrobe.SPOT` (5.4, 0, 3.2), between the bonfire and the
summoning circle: an obsidian mirror with a dais where the chosen demon's likeness wears its skin.
"Change skin" opens a window (CanvasLayer 20) with a turning preview and the `SkinPicker`; closing
it re-skins the hub avatar. Move `SPOT` / `YAW` freely if it crowds your layout.


## Note from progression (round 2)
- Applied the editor-launch fix to `Meta._ready` (marked "(progression)"): after connecting `node_added`
  it scans `root.find_children("*", "Player")` for not-yet-ready Players, so `main.tscn` launched directly
  still gets Meta upgrades.
- `Meta.map_requirement()` now also returns `Progression.map_gate(id)` for maps that are not unlocked yet
  (new optional `unlock` keys: `progress`, `cleared`, `mastery`, `story`; see docs/team/progression.md).
  `unlock_map()` already refuses while a requirement text is shown. Gated: Cathedral City, Gilded Isles,
  Frozen Monastery, Sunlit Citadel.
- `basecamp.gd` `_shop_items`: Progression rows use `info.category` as the tab when set (one marked line).
  New rows: 30 school-branch nodes (tabs Hellfire / Brimstone / Chains at the blacksmith, Blood Magic /
  Curses / Shadow / Plague at the occultist, Necromancy / Soul Harvest / Storm at the soul broker), plus
  "Rites": Unbinding Rite (Hellstone respec, blacksmith) and two repeatable transmutes (soul broker).


## Note from visuals (round 2): hub atmosphere
- `AtmoHubDressing` (scenes/world/atmo/atmo_hub_dressing.gd) is added under the scene by the Atmosphere
  rig whenever a node in group `basecamp` exists. It reads `HubScenery`'s layout constants by name
  (`X0/X1/Z0/Z1`, `FIRE`, `GATE`, `SMITH`, `OCCULT`, `BROKER`, `CARTO`), so moving them moves it:
  a low lava-bounce uplight per merchant (from the nearest plateau edge), a soft warm pool in front of
  each stall and the gate, heat-haze strips over the lava sea on all four sides and a haze puff over
  the bonfire. Ash fall / embers come from the `basecamp_hell` preset (ash raised to 0.7).
- If your lighting pass adds its own merchant lights, tell me and I'll drop the pools (or set
  `fx` keys per preset); the bounce lights are deliberately dim (energy 0.9, EMBER flicker).
- `hub_avatar.gd`: one line, the avatar is in group `atmo_focus` (weather follows it).
- Thanks for the `basecamp_hell` retune; I kept your values and only raised ash.

## Round 3 additions

### Hellgate loadout
Interacting with the hellgate opens the loadout step before descending: the UI role's
`LoadoutPanel` (`ui/components/loadout_panel.gd`) when it loads, else the hub's `HubLoadoutUI`.
- **Weapon**: the demon's own, or any `weapon_pool` weapon Progression has unlocked. Applied with
  `Player.starting_weapon_override` (small hook in `player.gd`, set by Meta before the Player's
  `_ready`).
- **Starting rite**: any ability Progression has unlocked, queued with `Abilities.grant` (abilities
  role: pre-run grants are applied when the run starts).
- **Keepsake** (`data/meta/keepsakes.json`): one per NPC (Grimmaul, Vesper, the Clerk, Ossek, Pip,
  Kesh, Malphine), available once `Dialogue.affinity(giver) >= min_affinity` (3; raised by G
  offerings, story role). Effects use `{stat, amount}`, `{type: run_stat, stat, amount}`
  (`Progression.apply_stat`: luck, rerolls...), `{type: soul_gain, amount}`.
- Helpers: `RunLoadout.weapons() / abilities() / keepsakes() / keepsake(id) / apply_effects() / total()`.
- Meta API: `Meta.loadout` (persisted, preselected next time), `Meta.start_run_with_loadout(choice)`.

### Board of Trials (daily seeded challenge)
Notice board west of the gate path. `DailyChallenge.today()` derives from the date a seed, a map
(maps open by default) and 2 modifiers from `data/meta/challenges.json` (stat changes, +heat,
Progression run stats, a seeded "borrowed rite", score multipliers). "Accept the Trial" runs it
with the demon's own weapon and no keepsake; `seed(trial.seed)` is applied before the map is
built and again at run start. Score = kills + 2/s + 25/level + 40/boss + 2000 on a win, times the
modifiers' bonus. Best per day in `Meta.trial_best` (`trial_best_score(key)`); the arrival banner
shows the score and whether it is a new best; the board lists the last few days. Meta API:
`Meta.start_trial(t)`, `Meta.trial`.

### Quick menu (Tab / gamepad Back)
`HubQuickMenu`: every merchant, the hellgate and every other hub interactable (boards, pit, story
NPCs, other roles' stations). Picking one fades, puts the avatar in front of it and uses it.
Input action `hub_menu` is registered at runtime by Meta.

### Ending (camp level 4)
`HubLife.camp_level()` returns 4 once `Dialogue.has_flag("story.ended")`: Heaven's banners hang
upside down around the gate, an archangel kneels chained by the path, and the empty chair stands
as a throne (`ending.choice` "sit") or lies broken ("break"). The light turns golden (an
`Atmosphere.push_overlay(&"reconquest", ...)` on top of `basecamp_hell`). The story role's
`CrownShrine` (by the bonfire) stays theirs. Ledger stage name: "Seat of the Reconquest".
Dev: `--camp=4`.

### Polish
- Wanderers avoid every hub post and merchant (`HubScenery.obstacles`), each other and the avatar
  (steer + sidestep; skip a stop after 4 s stuck).
- Proving Pit hides the Abilities and Progression run HUDs while you train.
- Damned souls are 1.4x scale with a pale soul-light rim, readable from the camera.
- Preset tune with visuals: `basecamp_hell` ambient 0.55 -> 0.45 and sun 1.0 -> 0.85 so the
  stall lantern pools carry the scene (note in docs/team/visuals.md).
- Smoke test now covers the loadout weapon and the daily trial; headless runs use the "bot"
  SaveProfile, so it no longer backs up saves.
- New dev args: `--hub-open=loadout|trials|quick`, `--hub-at=trials|captive|throne`.

## From characters-polish (round 3): merchant figures
`HubShopkeeper` now builds an articulated figure from `scripts/characters/merchants/*`
(`MerchantFigure.create(look)`, 5 marked lines in `hub_shopkeeper.gd`: the figure goes under
`_body`, `_process` calls `animate(delta, player_near)`, `interact()` -> `greet()`,
`react()` -> `react()`; your primitive builders stay as the fallback). Each has a craft idle:
Grimmaul hammers an ingot on his anvil (sparks, quiet `metal` clang when the player is near) and
lifts it in the tongs to inspect it; Vesper (a fallen angel: cracked violet halo, torn wings) reads
and turns the floating grimoire's pages; Mammon's Clerk flicks soul coins off a stack and catches
them, sometimes squinting at one through the monocle; Ossek ponders an unrolled map, turns it,
scratches his jaw. Greeting pauses the work and looks up / tips the hat; a sale gets a flourish.
Bench: `godot --path . res://tools/characters/merchants_test.tscn -- --sheet=<png> [--only=0,2]
[--greet=2] [--focus] [--old-merchants]`.
Known: the focus outline (ArtStyle.outline) fills box / cylinder parts with colour, old figures
included; reported in docs/team/art-style.md.
