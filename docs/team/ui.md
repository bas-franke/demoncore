# UI designer (docs/team/ui.md)

Status: first pass landed and validated (headless boot + screenshots of every screen via the gallery).
The infernal theme, palette, reusable components, HUD widgets, shop panel, run ledger, keybinds,
main menu and damage-number styling are in. Ask here if you need a widget or a field.

## Owned files
| path | what |
|---|---|
| `ui/palette.gd` (`UIPalette`) | every UI colour + fonts + small helpers. **Use it instead of hard-coded colours.** |
| `ui/theme.tres` | the project theme (`gui/theme/custom`). Generated, do not hand-edit. |
| `tools/build_theme.gd` | theme generator: `<godot> --headless --path . --script res://tools/build_theme.gd` |
| `ui/keybinds.gd` (`Keybinds`) | rebindable actions, `user://keybinds.cfg`, key labels for hints |
| `ui/components/*` | reusable widgets (table below) |
| `scenes/ui/hud.gd`, `hud_widgets.gd` | HUD (life/XP/level/powers/timer/kills/toasts + widgets) |
| `scenes/ui/settings_menu.*`, `settings_controls.gd` | settings overlay: General (audio buses), Graphics, Controls |
| `scenes/ui/main_menu.gd` (`MainMenu`) | Descend / Settings / Quit column on the title screen |
| `scenes/ui/run_ledger.gd` (`RunLedger`) | souls banked + tallies + powers block on the end screen |
| `scenes/ui/level_up_menu.*`, `pause_menu.*`, `game_over.*` | look and layout (gameplay / progression own their handlers and fate bar) |
| `scripts/damage_number.gd` | styling (API kept: `DamageNumber.spawn(amount, at, color, prefix)`) |
| `tools/ui/ui_gallery.*` | visual test harness (see "Validation") |

Shared files I touched (surgical): `autoload/settings.gd` (`ambience_volume` + one deferred
`Keybinds.load_and_apply()` line), `scenes/menu/title.gd` (first key opens `MainMenu`; Descend runs the
old `_leave()`), `scenes/ui/boss_bar.gd` (sits above the ability dock via `hud.bottom_reserved()`).

## Palette (ui/palette.gd)
Obsidian panels (`OBSIDIAN`, `SCORCH`, `ASH`), ember-lit lines (`IRON`, `EMBER_DIM`, `EMBER`, `HELLFIRE`),
brimstone gold headings/numbers (`BRIMSTONE`), bone text (`BONE`, `BONE_BRIGHT`, `ASH_TEXT`, `SMOKE`).
Semantic: `BLOOD*` life, `WRATH` player resource, `SOUL` souls, `ASCEND` XP, `HOLY*` angels/holy,
`VENOM` healing, `DANGER`, `LOCKED`. Rarity: `UIPalette.rarity_color(&"epic")` (`RARITY_COLORS`, used by
`Rarity.color()`). Fonts: `serif()`, `serif_bold()`, `display_font()`, `blackletter()` (system fonts with
fallbacks, nothing downloaded). Helpers: `box(bg, border, w, radius, margin)`, `gradient(...)`,
`rule(width, color)`, `roman(n)`.

## Theme type variations (`theme_type_variation`)
- Labels: `InkLabel` body, `TitleLabel` big tracked display, `LoreLabel` slanted flavour, `HeaderLabel`
  section heading, `CaptionLabel` small muted caps, `ValueLabel` bold gold numbers, `CostLabel` soul-green
  prices, `DangerLabel` warnings.
- Buttons: `Button` (forged plate), `CardButton`, `AccentButton` (blood-red call to action), `GhostButton`
  (flat text), `TabButton` (toggle tab with ember underline), `SlotButton` (square slot). `OptionButton`,
  `PopupMenu`, `LineEdit`, sliders, toggles, scroll bars and tooltips are themed too.
- Panels: `PanelContainer` (default), `InfernalPanel` (heavy modal frame), `CardPanel`, `InsetPanel`
  (sunken well), `HeaderBand` (blood band), `HudPanel`, `Badge`, `Chip`, `LevelBadge`.
- Bars (ProgressBar): `HPBar`, `XPBar`, `ResourceBar`, `SoulBar`.

## Reusable components (ui/components/)
| class | what | key API |
|---|---|---|
| `InfernalBar` (Control) | life / wrath / shield / boss meter: dark well, lingering loss trail, glossy fill, ticks, text | `set_values(v, max)`, `fill_color`, `trail_color`, `text_mode` (`TEXT_VALUE_MAX`...), `segment_value`, `low_warning`, `snap()`; signals `emptied`, `filled` |
| `CooldownSlot` (Control) | square ability slot: radial sweep + seconds, key hint, charges, ready flash | `setup(id, title, tex, glyph, tint, key)`, `set_cooldown(remaining, total)`, `set_charges(n)`, `set_disabled(b)`, `trigger()`; signal `ready_again` |
| `CurrencyCounter` (HBox) | glyph + rolling number, pop on gain, shake on deny | `setup(glyph, color, tooltip)`, `set_amount(n, snap)`, `deny()`, `icon_texture` |
| `Minimap` (Control) | round radar oriented to the camera | `world_radius`; reads groups `enemies`, `boss`, `pickups`, `objectives` (their `color`), `minimap_marker` (metas `minimap_color`, `minimap_size`, `minimap_pin`, `minimap_label`) |
| `ChoiceRow` (PanelContainer) | list row for choices (maps, pacts, rites): medallion, title, tags, note, actions, rank stepper; state edge + shape | `setup({glyph, color, title, subtitle, description, tags, state, note})`, `add_action(text, cb, variation, disabled)`, `add_stepper(rank, max, on_change)`, `first_button()` |
| `ListPanel` (CanvasLayer) | modal list window for ChoiceRows with wallet + summary gauge | `open({title, subtitle, wallet, gauge, rows, footer, pause})`, `refresh()`, `close()`; signal `closed` |
| `GlyphIcon` (Control) | glyph painted in code (flame, drop, chain, lock, bolt, skull, heart, swords, crown, shield, pentagram, lantern, sigil, hourglass, dash, eye, candle); other glyphs drawn as plain serif text. No emoji font needed | `glyph`, `color`; `GlyphIcon.icon_id(g)`, `GlyphIcon.plain(g)` (text-safe stand-in for Labels) |
| `LoadoutPanel` (CanvasLayer) | pre-run Weapon / Ability / Keepsake picker | `open({title, subtitle, current, weapons, abilities, keepsakes})`, signals `confirmed(choice)`, `closed` |
| `RelicView` (static) | relic chip / row builders | `RelicView.chip(relic, side)`, `RelicView.row(relic, show_count)` |
| `ShopPanel` (CanvasLayer, `ui/components/shop_panel.tscn`) | full shopkeeper screen | see below |

### Shop panel
```gdscript
var shop: ShopPanel = preload("res://ui/components/shop_panel.tscn").instantiate()
add_child(shop)
shop.open({
	"title": "Mother Marrow", "subtitle": "Flesh is only a first draft.",
	"currency_glyph": "◈", "currency_name": "Souls", "currency_color": UIPalette.SOUL,
	"currency": func() -> int: return Meta.souls,            # or an int
	"items": func() -> Array: return my_items(),               # or an Array
	"buy": func(id: String) -> bool: return Meta.buy(StringName(id)),
	"pause": false,
})
shop.closed.connect(...)   # also: purchased(id), purchase_failed(id, reason), purchase_requested(id)
```
Item dictionaries: `id`, `name` (required); `description`, `glyph`, `icon` (Texture2D or path),
`color`, `cost` (<0 hides), `level`, `max_level` (0 = one-off), `rarity`, `category` (2+ categories ->
tabs, Q/E cycle), `locked` + `locked_reason`, `owned`, `effect_now` / `effect_next`, `flavor`, per-item currency (`currency_glyph`, `currency_color`,
`currency_name`, `currency_amount` or `affordable`). Config `"wallets"` adds extra header counters.
Grid columns and the detail pane (right, or below on narrow windows) adapt to the window. First
press selects a card, pressing the selected card (or PURCHASE) buys. Esc / pause closes.
Used by Basecamp Hell for every merchant (`scenes/basecamp/basecamp.gd`, `_open_shop_panel`).

## Round 3 additions
- **Hellgate loadout** (`ui/components/loadout_panel.gd`, `LoadoutPanel`): Weapon / Ability / Keepsake
  columns of cards built from `RunLoadout.weapons() / abilities() / keepsakes()`, preselects
  `Meta.loadout`, locked entries say why, summary line, DESCEND (D / pad Start) emits
  `confirmed(choice)` -> `Meta.start_run_with_loadout(choice)`. Usage in docs/team/basecamp.md.
- **Full ledger** (`scenes/ui/run_breakdown.gd`, `RunBreakdown`), opened from "◆ FULL LEDGER" on the
  end screen: damage by source (each ability via `Abilities.damage_report()`, afflictions, synergies &
  effects, weapons = the rest of `RunTally.total_damage`), heaviest blow, kills by angel type
  (`RunTally.kills_by_type`, elites marked), relics carried. `ui/run_tally.gd` (`RunTally`, added by
  the HUD) keeps total damage / kills per type in static vars until the next run. Abilities now
  always tallies damage per id (one-line change in `ability_combat.gd`, reset per run).
- **Relics:** pause menu "RELICS (n)" chips; Codex "Relics" tab (`Progression.codex_entries()`,
  silhouettes until found, times found); shared builders `RelicView.row(relic)` / `RelicView.chip(relic, size)`.
- **Map overview** (`scenes/ui/map_overview.gd`, `MapOverview`, added by the HUD): action
  `map_overview` (Tab / M / pad Back, rebindable). Pauses; shows bounds (GameMap circle / rect /
  polygon, 70 m around you on endless maps), landmarks (`Maps.landmarks()`), objectives (glyph,
  colour, title), boss, allies, angels, the demon; side list of objectives with distance + status.
- **Glyphs elsewhere:** objective tracker rows (`GlyphIcon`) and markers (`GlyphIcon.plain`),
  Progression's relic HUD chips, every `CurrencyCounter` glyph.
- **Controller / keyboard navigation:** `ui/nav.gd` (`UINav.page_dir(event)` = Q/E, PgUp/PgDn,
  pad LB/RB; `UINav.recover_focus(event, fallback)` refocuses after a mouse click left nothing
  focused). Used by settings, shop, codex, list panel, loadout, pause, level-up, end screen, main
  menu; the bestiary scrolls with up/down/LB/RB. Every focusable control has the theme's hellfire
  focus outline. Pads: A accept, B back (Godot ui_* defaults), LB/RB tabs, Start descends (loadout),
  Back opens the map.
- **Title + credits:** the title menu is a single row (Descend / Settings / Credits / Quit) under the
  tagline with a controls hint in the letterbox; `scenes/ui/credits_screen.gd` (`CreditsScreen`)
  auto-scrolls every role (manual scroll with up/down / wheel).

## Round 2 additions
- **Codex** (`scenes/ui/codex_screen.gd`, `CodexScreen`): category tabs (Q/E), entry list (◆ = unread),
  page text, marks entries read; footer opens the Bestiary. Reads `Dialogue.codex_entries()` /
  `codex_mark_read()`. Opened from the pause menu ("Codex  ◆N" when unread) and the hub (`C` key,
  hook in `scenes/basecamp/basecamp.gd`). `CodexScreen.new_count()` for badges.
- **Synergies:** `hud.synergy_banner(name, desc, color)` (Abilities calls it on `synergy_activated`,
  falls back to `toast`); the pause menu lists `Abilities.active_synergies` under the attributes.
- **Ability keys:** input actions `ability_1`..`ability_4` (keys 1-4; pad X / Y / LB for 1-3),
  rebindable. Dock slots without an action get the next free one (stable per id); key shown on the
  slot; pressing it pulses the slot and emits `hud.widgets.ability_key_pressed(id)`; `hud.action_for(id)`.
- **Objectives:** the objectives role owns the list + edge markers + minimap pins; the HUD keeps their
  list (`list_top`) just under the currency counters. Minimap draws `minimap_marker` nodes (theirs).
- **Painted glyphs:** HUD power chips, level-up cards, shop cards, pause powers, run ledger and
  cooldown slots draw glyph fallbacks with `GlyphIcon` (no colour emoji).
- **Boss bar:** `holy_style` export (gold fill, blood-red damage segment), off until the objectives
  role agrees (request in docs/team/objectives.md).
- **Accessibility** (Settings > Access, `scenes/ui/settings_access.gd`): text speed
  (`Settings.text_speed`, DialogueBox reads it; Slow / Normal / Fast / Instant), reduce flashes
  (`Settings.reduce_flashes`: hit flash in game_feel x0.25, lightning screen flash x0.2, UI pulses /
  glows calmed; read `UIPalette.calm()` in your own effects), screen shake, interface scale.
  Rarity is never colour-only: `UIPalette.rarity_mark(r)` pips (◆ .. ◆◆◆◆◆) + the tier name on
  level-up cards and shop cards. Choice rows mark state by shape too.

## HUD API (group `hud`: `get_tree().get_first_node_in_group(&"hud")`)
- `toast(text, color)`: centred serif banner (stacked, max 3).
- `set_resource(value, max, color = UIPalette.WRATH, label = "")`, `hide_resource()`: bar under the XP bar.
- `add_ability_slot(id, title, icon = null, glyph = "✦", tint = UIPalette.EMBER, action = &"") -> CooldownSlot`,
  `set_ability_cooldown(id, remaining, total)`, `remove_ability_slot(id)`: bottom-centre dock. The key hint
  comes from the InputMap action (`Keybinds.label`), refreshed after a rebind.
- `bottom_reserved() -> float`: pixels the dock takes (the boss bar sits above it).
- `widgets` (`HudWidgets`): `resource_bar`, `ability_dock`, `minimap`, `ichor_counter`, `soul_counter`.
- Automatic, no calls needed:
  - Dash slot from `Player.dash` (`PlayerDash`: charges, recharge).
  - Ichor (`RunState.currency_changed`) and run souls (`Meta.run_souls`, shown once > 0), top-right.
  - Low-life red vignette below 30 % life.
  - Pull protocols on `Game.player` (duck-typed, optional): `resource` / `max_resource`
    [+ `resource_color`, `resource_name`] and `get_hud_abilities() -> Array[Dictionary]`
    (`{id, title, glyph, icon, color, action, remaining, total, charges, disabled}`).
    **Abilities role:** either implement `get_hud_abilities()` on the player/caster side or call
    `add_ability_slot` + `set_ability_cooldown`; no separate ability HUD needed. Add your input actions
    (`ability_1`..`ability_4`) to the InputMap and they appear in Settings > Controls automatically.
- Layout: top-left level/life/XP/resource + powers; top-centre timer; top-right kills, currencies, then
  the objectives list (objectives role, `list_top` 104); bottom-centre ability dock; bottom-right minimap.

## Damage numbers
`DamageNumber.spawn(amount, at, color = WHITE, prefix = "")` (unchanged) and
`DamageNumber.spawn_kind(amount, at, kind)` with kinds `&"normal"`, `&"crit"` (orange, larger, pop, "!"),
`&"player"`, `&"heal"`, `&"holy"`, `&"burn"` (small, DoT ticks), `&"currency"`. At most 70 alive at once
(crits / big hits always show). Toggle: `Settings.damage_numbers` / debug F2.

## Settings
General: Music / Sound / Ambience sliders (`Settings.music_volume`, `sfx_volume`, `ambience_volume`,
applied live by Sfx), screen shake, damage numbers, fullscreen. Graphics: preset + options (unchanged).
Controls: one row per `Keybinds.ACTIONS` entry present in the InputMap; click, press a key or mouse
button; Esc cancels; per-row Reset and "Restore all defaults". Only keyboard/mouse bindings are
rebound (gamepad stays as authored). Saved to `user://keybinds.cfg`, applied at boot.
To add a rebindable action: append `[&"my_action", "Label"]` to `Keybinds.ACTIONS`.

## Screens
- Title: first key shows `MainMenu` (Descend / Settings / Quit). Descend = the old fade into demon select.
- Level-up: rarity-tinted card frames + glow (Progression's `rarity` meta), number keys 1-3 pick,
  the offer scales down to fit small windows / large UI scale.
- Pause: subtitle shows map, time and Ichor; scales to fit.
- End screen (game_over): stats row + `RunLedger` (souls banked from `Meta.pending_summary` counting up,
  breakdown, elites / bosses / dodges / wounds, the demon's powers and boons). "UNMADE" in blood red,
  "ASCENDANT" in bone gold.

## Validation
- `<godot> --headless --path . --import` after adding any `class_name` (refreshes the class cache).
- `<godot> --headless --path . --script res://tools/check_scripts.gd`
- Screenshots: `<godot> --path . res://tools/ui/ui_gallery.tscn -- --view=<v> --shot=<png> --shot-time=<s>`
  with views `components`, `shop`, `run_end`, `victory`, `levelup`, `pause`, `title`, `settings`,
  `graphics`, `controls`, `access`, `list`, `codex`, `glyphs`, `synergy`, `loadout`, `credits`,
  `mapview`, `ledger`.

## Known issues / next steps
- Basecamp uses `ShopPanel` for the upgrade shops. **Done (basecamp request):** per-item currency —
  item keys `currency_glyph`, `currency_color`, `currency_name` + `currency_amount` (int held) or
  `affordable` (bool); extra header wallets via config `"wallets": [{glyph, color, name, amount}]`
  (`amount` int or Callable, refreshed after each purchase). The flavour-line workaround can go.
- UI glyphs are painted by `GlyphIcon`. Other roles' own text labels (objective tracker, AbilityHud
  synergy list, relic UI) still print data glyphs as text; they can switch to `GlyphIcon` or
  `GlyphIcon.plain(g)`.
- Boss bar keeps its own soulslike styling (boss role); it only moves above the ability dock.

## Note from the story role: codex data (docs/team/story.md)
- `Dialogue.codex_entries() -> Array[Dictionary]` `{id, category, title, text, unlocked, is_new}`
  in display order. Locked entries come back with title "???" and empty text. Categories:
  The War, The Pit, Factions, Heaven, Truths, Cast. Data: `data/dialogue/codex.json`.
- `Dialogue.codex_mark_read(id)`, `Dialogue.codex_new_count()`, and the signal
  `Dialogue.codex_unlocked(id)`, which fires at run start and on Basecamp arrival for each entry
  that became readable. Use it for a "New codex entry" toast if you like.
- Affinity, for any hub UI: `Dialogue.affinity(who)` (0..5), `gift_cost(who)`, `can_gift(who)`,
  `give_gift(who)`, and the signal `gift_given(speaker, level)`. `who` is a speaker or shop id.
  Basecamp NPCs already show `♥♥♡♡♡ [G] Offer gift ✧ 40` when focused (scenes/dialogue/story_marker.gd).

## Note from gameplay (headless error in ui/keybinds.gd) - RESOLVED (headless guard landed at keybinds.gd:110)
Headless runs (tools/gameplay_check.gd, autopilot bot runs) log
`ERROR: Not supported by this display server.` from `keyboard_get_keycode_from_physical`
in `ui/keybinds.gd:111` (`event_label`, called by `hud_widgets.gd` `add_ability_slot` / `_update_dash`).
Suggest guarding with `if DisplayServer.get_name() == "headless": return OS.get_keycode_string(physical)`
(or caching the label). Harmless in the real game, but it pollutes every automated log.

## Note from art-style (round 3)
- Settings > Graphics has a new **"Blight detail"** row (Off / Low / Full) = `Settings.blight_quality`
  (int 0..2, saved with the graphics keys, part of the presets: Low preset = 1, others = 2). The
  `Corruption` autoload applies it on `graphics_changed`. Edits: one row in `GFX_ROWS`
  (`settings_menu.gd`), the property + preset values + `GRAPHICS_KEYS` entry in `autoload/settings.gd`.
- Ability icons: `res://assets/icons/abilities/<id>.svg` (73, generated by
  `tools/icons/build_ability_icons.py`), loaded with `Icons.for_ability(id)`; `Icons.for_option()`
  now resolves ability / evolution options too, so level-up cards show them, and the ability HUD
  dock + chips use them. They are textures, so your GlyphIcon emoji replacement still covers every
  place that only has a glyph (boons, synergies, relics); no overlap. Style: dark vignette disc like
  the painted weapon icons, emblem in the ability colour with an ink outline.

## Note from the story role (round 3): codex toast
- The "new codex entry" notice is the story role's `CodexToast` (`scenes/dialogue/codex_toast.gd`).
  It is a child of the Dialogue autoload, on CanvasLayer 88, and slides a small card in at the left
  edge (36% down) on `Dialogue.codex_unlocked`. It never pauses or takes input, and a burst of more
  than 3 unlocks becomes a single card. You don't need to add a HUD toast for it. If you'd like it
  moved or restyled, say so here and I'll change it, or edit `_card()` directly.
- Bosses with story lines now: sariel, grand_inquisitor, gate_archon (Azrafel), frost_abbot,
  dawn_wyrm, verdant_matriarch.


## Note from progression (round 2): relic codex + mastery data APIs
- Relic codex: `Progression.codex_entries()` -> `[{id, name, icon, rarity (id), tier, color, description, tags,
  discovered, times_found}]` (all relics, data order; your Codex "Relics" tab already reads these keys),
  `Progression.codex_progress()` -> `{found, total, by_tier: {rarity: [found, total]}}` for a completion
  header, `signal codex_updated(relic_id, times_found)`. First finds toast via the HUD.
- Mastery for a demon panel / end screen: `Progression.mastery_progress(Progression.demon_id_of(demon))` ->
  `{level, xp, into, need, maxed, signature_rank, next_reward}`, `Progression.signature_text(id)`,
  `Progression.last_rewards.mastery` -> `{name, xp, level_before, level_after, rewards: [text]}`.
- New shop "action" rows from Progression (kind `"action"`, max_level 0, repeatable): `respec`
  (Unbinding Rite) and `transmute_shards` / `transmute_hellstone`; `item_info().category` = tab name.


## Note from progression (round 3): codex milestones
`Progression.codex_milestones()` -> `[{percent, name, reached, claimed, reward_text, relics_needed}]` (25/50/75/100 %)
for a completion bar in the Codex Relics tab; `signal codex_milestone_reached(percent, info)`. Rewards pay
automatically (HUD toast); the UI only needs to display them.

## Note from maps (round 3)
- Minimap: map interactables (holy fonts, summoning bells, the Seventh Gate; group
  `map_interactables`) and landmarks (group `map_landmark`) now join `minimap_marker` with
  `minimap_color` / `minimap_size` / `minimap_pin = false`. Interactables dim when spent (fonts turn red).
- Map overview: small marked `# [maps]` block in `scenes/ui/map_overview.gd` draws interactables (ring
  in their tint, name, dimmed when spent) and breakable statues (group `map_features`, marble squares),
  and leaves statues out of the angel specks.

## QA notes (from docs/team/qa.md)
- QA guarded `ui/keybinds.gd` `event_label()` against the headless display server (`keyboard_get_keycode_from_physical` errored in every headless check) (`# QA:`).
- `scenes/ui/level_up_menu.gd:198`: `get_meta(&"icon_frame", null)` errors when the meta is missing (a null default counts as no default). Use `has_meta()` first. (Fixed by QA, `# QA:`.)

## Note from the objectives role (round 2)
- `scenes/ui/run_ledger.gd`: one small block after the Progression line shows the objectives grade
  ("GRADE A · score 1840 · 7 objectives · 2 events survived (+70 souls)") from `result["objectives"]`
  (RunScore, docs/team/objectives.md). Restyle freely; the keys are stable. `Meta.pending_summary.souls`
  already includes the grade bonus.
- The Holy Eclipse event draws a CanvasLayer (layer 1) shade + black sun at 33% / 12% of the screen.

## Note from gameplay (round 3): Ascension mode + last stand + kill confirm
- **Ascension** (endless after a victory): the end screen (`game_over.gd`, marked `# [gameplay]`)
  gets an "Ascend" AccentButton (created in code, first in the button row, focused) when
  `RunState.can_ascend()`. Pressing it hides the screen and calls `RunState.ascend()` (unpauses).
  When the ascension ends (death) the same screen opens with title "ASCENSION ENDS" and two extra
  stats ("Ascension score", "Best"/"New best!"). Please restyle freely.
- Live score: `RunState.ascending`, `ascension_score`, `ascension_minutes()`, signal
  `score_changed(score)`, `best_ascension_score()`. I added a minimal readout
  `scenes/ui/ascension_score.gd` (top-centre label, added by RunState.ascend()); put any node in group
  `"ascension_hud"` (e.g. your HUD) and mine is not added. RunState also toasts each new ascension minute.
- `DamageNumber.spawn_text(text, at, color, px)` (added): words instead of numbers. Used for the gold
  "SLAIN" elite kill confirm (GameFeel) and "LAST STAND".
- `RunState.last_stand` signal: a HUD flash / vignette would sell it (the demon survives at 1 HP).
