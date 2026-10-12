# Sound effects (docs/team/sfx.md)

Status: round 5 landed (79 enemies/bosses in the registry; signature-enemy mechanic sounds;
Nhazgul's swarm identity). Round 4 landed (abilities round 2 wired: evolutions, Sin / Illusion / Machinery / Whip
tags, summons, Devour, Stolen Radiance, mines, Gilded; hub footsteps; 23 new enemies and bosses).
Round 3 landed (startup cache, surface footsteps, elite voices, music ducking, UI bus,
Sin / gadget school sounds, evolutions, synergy sting, relics by rarity).
Every sound is synthesized procedurally (22.05 kHz 16-bit `AudioStreamWAV`s, mostly mono, a few
stereo beds; 151 streams). The **first launch** renders them on a worker thread (~20 s, gameplay
sounds first, long beds last) and saves them to `user://sfx_cache/streams.bin` (zstd, ~12 MB);
**later launches load that file in ~0.15 s**. Nothing is added to the repo.

## Startup cache (scripts/audio/sfx_cache.gd)
- Key = MD5 of every recipe source in `Sfx.CACHE_SOURCES` + `Sfx.RECIPE_VERSION` + cache format +
  engine version. Editing any recipe script re-renders automatically on the next launch. In an
  export without .gd sources, bump `Sfx.RECIPE_VERSION` when recipes change.
- Plain Variants only (`get_var(false)`), validated on load; written to a temp file then renamed.
- `-- --sfx-nocache` forces a fresh render (and rewrites the cache). `Sfx.loaded_from_cache` tells
  which path ran. There was no docs/team/performance.md to coordinate with; perf: the cache
  removes the 20 s worker-thread load from every launch after the first, main thread untouched.

## Owned files
- `autoload/sfx.gd`: the `Sfx` autoload (pools, voice limiting, buses, listener, core recipes,
  ambience beds). Music now lives in `MusicManager` (music role); `Sfx.play_music/stop_music`
  forward to it and the legacy music synthesis in sfx.gd is skipped when it is registered.
- `scripts/audio/sfx_recipes.gd`: element / hit / dash / shop / portal / hub sounds and their
  voice, gap, alias and variant tables (merged into Sfx's at `_ready`).
- `scripts/audio/sfx_recipes_world.gd`: material hits/deaths, enemy voices, objective sounds,
  boss stinger, thunder/rain/gusts, dialogue blips, stereo beds (+ `_pack_stereo`).
- `scripts/audio/sfx_registry.gd` + `data/audio/enemy_audio.json`: enemy id -> material + wind-up
  voice, speaker id -> dialogue blip. Exposed as `Sfx.registry`.
- `scripts/audio/sfx_hooks.gd`: node `Sfx/SfxHooks`, wires gameplay signals to sounds.
- `scripts/audio/weather_audio.gd`: node `Sfx/SfxHooks/WeatherAudio`, rain + gust beds following
  the Atmosphere director's `weather.rain` / `weather.gust`.
- `scripts/audio/sfx_recipes_sins.gd`: Sin schools, gadgets, evolve, synergy, relic tiers,
  snow / wood / water / ash footsteps.
- `scripts/audio/sfx_cache.gd`: the user:// stream cache.
- `scripts/audio/surface_probe.gd`: what the ground sounds like at a position (footsteps).
- `tools/export_sfx.gd`: writes every sound to `assets/audio/sfx/*.wav` (folder has a `.gdignore`,
  the game never imports them; they are only for listening) and prints a peak/RMS sanity report.
- `tools/sfx_smoke.gd`: API checks + a real autopilot run, prints how often each sound fired.

## API (stable)
```gdscript
Sfx.play(&"hit_flesh")                         # 2D one-shot, default pitch jitter 0.08
Sfx.play(&"smite", 0.15, -6.0)                 # pitch jitter, volume_db
Sfx.play_at(&"angel_shatter", pos)             # pooled AudioStreamPlayer3D, -> bool
Sfx.play_at(&"coin", pos, 0.06, -8.0)
Sfx.play_element(&"plague", &"hit", pos)       # &"<element>_<kind>", pos = null for 2D, -> bool
Sfx.play_element(&"fire", &"cast", null, -3.0, 0.1)   # (element, kind, position, volume_db, jitter)
var hum := Sfx.play_loop(&"amb_portal", portal_node, -6.0)   # looping emitter child, -> Node
Sfx.play_loop(&"amb_hellfire", some_plain_node, -10.0, Sfx.AMB_BUS)  # plain Node parent = 2D
Sfx.wire_button(button)                        # hover (mouse + focus) + click sounds, idempotent
Sfx.play_material_hit(&"stone", pos, db)       # flesh / stone / glass / metal / holy, -> bool
Sfx.play_material_death(&"metal", pos, db)
Sfx.play_enemy_voice(enemy_data, pos)          # wind-up cry from the registry (none = silent)
Sfx.play_blip("grimmaul")                      # one dialogue syllable in that speaker's voice
Sfx.registry.material_of(enemy_data) / voice_of(enemy_data) / blip_of("pip")
Sfx.play_enemy_voice(data, pos, -6.0, true)    # elite: +4 dB, pitched down, shared 2.5 s gap
Sfx.play_element(&"greed", &"hit", pos)        # Sin / gadget schools work like elements
Sfx.play_relic(tier)                           # 0 common .. 4 legendary (Rarity enum)
Sfx.get_stream(&"amb_wind") / Sfx.has_sound(&"dash") / Sfx.get_play_counts()
```
- Every play: pitch jitter (argument) plus a random 0..-1.5 dB volume cut (`VOL_JITTER_DB`).
- Voice limiting: per-sound max voices (stealing the oldest, across 2D + 3D pools) and a per-sound
  minimum gap, so 200 simultaneous hits never machine-gun. Pools: 22 x 2D, 20 x 3D.
- Unknown names are ignored silently; sounds still rendering are skipped (first ~1 s of launch).
- `play_loop` waits for the stream to finish rendering, starts at a random offset, stops when the
  returned node (or its parent) is freed. Parent `Node3D` -> 3D emitter (`unit_size` arg sets reach).
- During a run Sfx keeps an `AudioListener3D` above the player along the camera axis.

## Sound list
| Group | Names |
|---|---|
| Elements | `fire_cast/_hit`, `blood_cast/_hit`, `shadow_cast/_hit`, `plague_cast/_hit`, `lightning_cast/_hit`, `necro_cast/_hit` (element aliases: hellfire, poison, rot, shock, storm, dark, void, bone, death, ...) |
| Hits | `hit_flesh` (3 variants), `hit`, `impact`, `holy_hit` |
| Enemy deaths | `angel_shatter` (glass crack), `holy_chime` (soul escaping), `angel_death` (shatter + choir sigh) |
| Player | `dash`, `hurt`, `faint`, `level_up`, `ability_ready`, `cast` |
| Weapons | `fire_bolt`, `cleave`, `chain`, `scythe`, `brimstone`, `beam`, `smite`, `wingbeat` |
| Pickups | `soul` (XP, climbing pitch combo), `coin` (Ichor), `gold`, `chalice` (heal), `pickup_item` |
| Shop / hub | `shop_buy`, `shop_deny`, `unlock`, `portal_open`, `portal_enter` |
| Bosses | `boss_intro`, `boss_roar`, `boss_charge`, `boss_death`, `choir`, `toll`, `triumph`, `unmade` |
| UI | `ui_click`, `ui_hover`, `ui_back`, `select`, `toast` |
| Footsteps | `step_stone`, `step_grass` (3 variants each) |
| Material hits | `hit_flesh`, `hit_stone`, `hit_glass`, `hit_metal`, `hit_holy` (3 variants each) |
| Material deaths | `death_flesh`, `crumble` (stone), `angel_shatter` (glass), `armor_clatter` (metal), `light_burst` (holy) |
| Enemy voices | `voice_villager`, `voice_zealot`, `voice_roar` (lion), `voice_screech` (griffon), `voice_whinny` (pegasus/unicorn/lancer), `voice_grind` (statues/golem), `voice_hum` (light beings), `voice_angel`, `voice_knight`, `voice_cherub` |
| Objectives | `desecrate` (shrine done), `amb_ritual` (shrine channel loop), `seal_break`, `relic_corrupt`, `harvest` (souls pulled in), `stinger_boss` |
| Weather | `thunder` (stereo, near), `thunder_far` (stereo), `amb_rain` (stereo loop 8 s), `amb_gust_wide` (stereo loop 20 s) |
| Dialogue | `blip_low`, `blip_mid`, `blip_high`, `blip_holy`, `blip_whisper` (pitched per speaker) |
| Sin schools | `wrath_cast/_hit`, `greed_cast/_hit`, `envy_cast/_hit`, `pride_cast/_hit`, `gluttony_cast/_hit` (aliases rage, avarice, gold, jealousy, vanity, hunger, devour) |
| Gadgets | `decoy_cast/_hit` (puff + giggle / pop), `turret_cast/_hit` (deploy / shot), `mine_cast/_hit` (arm / blast), `whip_cast/_hit` (crack / lash) (aliases clone, lure, sentry, trap, lash) |
| Summons / specials | `summon_hellhound`, `summon_imps`, `summon_brute`, `summon_succubus` (kind_summon by style), `devour`, `reflect` (Stolen Radiance), `gilded_drop` (Gilded foe spills Ichor) |
| Signature enemies | `bell_ring` (bell-ringer toll, spell_casts.gd), `mirror_beam` (sun priest), `mimic_snap` (mimic wakes), `ichor_steal` (harpy), `revenant_rise`, `frost_shatter` (ice-bound penitent), `djinn_blink` (cloud djinn) |
| Player state | `heartbeat` (0.45 s lub-dub, game_feel.gd once per beat at low HP; dry, never ducks), `last_stand` (hellfire burst + defiant roar; ducks the music), `slain` (short dark iron bell for game_feel's elite "SLAIN" confirm, replacing the 3.4 s holy `toll`) |
| Demon identity | `dash_swarm`, `hurt_swarm`, `death_swarm` (Nhazgul), `dash_turncoat`, `hurt_turncoat`, `death_turncoat` (Iscariel: cracked choir + hellfire), via `Sfx.DEMON_SOUNDS`; `amb_fly_buzz` (Nhazgul's movement loop, `Sfx.DEMON_LOOPS`) |
| Progression | `evolve` (ability evolution), `synergy` (synergy sting), `relic_common`, `relic_uncommon`, `relic_rare`, `relic_epic`, `relic_legendary` |
| Footsteps | `step_stone`, `step_grass`, `step_snow`, `step_wood`, `step_water`, `step_ash` (3 variants each) |
| Loops | `amb_portal` (6 s), `amb_hellfire` (8 s), `amb_hellfire_wide` (stereo 8 s), `amb_hell_choir` (16 s), `amb_ritual`, `amb_rain`, `amb_gust_wide`, `amb_fire`, `amb_wind`, `amb_choir`, `amb_storm`, one-shot `bell_distant` |

## Hooks already wired (scripts/audio/sfx_hooks.gd and small edits)
- `Game.enemy_struck(enemy, amount)` (new signal, emitted by `Enemy.take_damage` right after
  `enemy_hit`) -> positional material hit (louder with damage). `Game.enemy_died` -> positional
  material death, 12% chance of a faint `holy_chime`. `RunState.enemy_killed` elite -> `holy_chime`.
- `Enemy._set_state(WINDUP)` -> `Sfx.play_enemy_voice(data, pos, -6.0, is_elite())`; elites are
  louder, deeper and rarer (one elite cry per 2.5 s at most).
- `Abilities.synergy_activated` -> `synergy`; `Abilities.ability_evolved(from, to)` -> `evolve`.
  Ability tags pick the school's cast and hit sounds like the elements: wrath, greed, envy, pride,
  gluttony, whip, `illusion` -> decoy, `machine` -> turret, `trap` -> mine. Specific tags win over
  generic ones (`SINS.TAG_PRIORITY`: trap/mine 0, whip 1, others 5, then tag order), so
  Hellmine Field (machine + trap) is a mine.
- Ability kinds (small edits in scripts/abilities): summons play `SINS.SUMMON_SOUNDS[style]`
  (hellhound / imp / hell_brute / succubus; undead keep necro_cast), Devour `devour`, Stolen
  Radiance `reflect`, constructs `mine_cast` / `decoy_cast` / `turret_cast`, turret shots
  `turret_hit` (flame turrets `fire_cast`), mine / decoy bursts `mine_hit` / `decoy_hit`
  (positional), Gilded deaths `gilded_drop` (abilities.gd).
- Hub footsteps (hub_avatar.gd) go through SurfaceProbe too (flagstone fallback). The smallest
  `sfx_surface` zone containing the point wins.
- Relic pickups (`relic_pickup.gd`) -> `Sfx.play_relic(tier)`.
- Run footsteps (ambience.gd) ask `SurfaceProbe.surface_at()`: `sfx_surface` zones, then the
  TerrainPatch (bridge -> wood, river / pool -> water, paved path -> stone, theme ground: hell ->
  ash, heaven -> grass), then the map's `"footsteps"` key or `"biome"` (snow -> snow, eden ->
  grass, city / citadel -> stone), then the sanctum decor biome. Maps: add a Node3D to group
  `&"sfx_surface"` with metas `surface` + `radius` (or `size`) for local patches.

## Demon sound identity
`Sfx.DEMON_SOUNDS` maps a DemonData `model_id` to replacements for the generic player sounds
(`hurt`, `faint`, `dash`). SfxHooks calls `Sfx.set_demon(model_id)` when a run's Player appears;
`play()` / `play_at()` then swap the names, so player.gd / player_dash.gd stay untouched.
Nhazgul: swarm buzz + chitin. Iscariel: a choir chord with one voice a semitone sour, over
hellfire. Add a row for any future demon with its own sounds.
`Sfx.DEMON_LOOPS` (model_id -> loop) adds a `SfxMoveLoop` node (scripts/audio/move_loop.gd) under
the Player: the loop idles at -26 dB and swells to -9 dB (pitch +12%) with the player's speed,
silent once `is_dead`. Nhazgul carries `amb_fly_buzz`.

## Music ducking and buses
- Big sounds duck the music through `MusicManager.duck(db, seconds)` (added to music_manager.gd,
  glides at 24 dB/s): `stinger_boss`, `boss_intro`, `boss_roar`, `boss_death`, `unmade`,
  `level_up`, `desecrate`, `relic_corrupt`, `portal_enter`, `evolve`, `synergy`, `relic_epic`,
  `relic_legendary`, `triumph`, `thunder` (table `Sfx.DUCK`).
- `ui_*`, `select`, `toast`, shop sounds and dialogue blips play on the dry `UI` bus (`Sfx.UI_SOUNDS`);
  its volume follows `Settings.ui_volume` if it exists, else `sfx_volume`.
- `Game.boss_spawned` -> `stinger_boss`; the champion objective intro also plays it.
- `Game.boss_died` -> `holy_chime` (MusicManager plays the victory stinger); `Game.boss_phase_changed` (phase > 0) and `Boss._enrage`
  -> `boss_roar`.
- `RunState.player_dashed` -> `dash` (PlayerDash's own wingbeat lowered to sit under it);
  `PlayerDash.charges_changed` (charge regained) -> `ability_ready`; `RunState.player_dodged` -> `holy_hit` ting.
- `RunState.wave_started(&"surge")` -> distant `toll`.
- Portals: any Node3D named `*Portal*` or in group `&"portal"` gets an `amb_portal` hum; the
  Basecamp gate surface plays it explicitly; entering the gate plays `portal_enter`.
- Basecamp scenes (`res://scenes/basecamp/*` root) get `amb_hellfire_wide` + `amb_hell_choir` beds on the
  Ambience bus, unless the scene has a node in group `&"ambience"` (add one to opt out).
- Weapons: hellfire bolt hits `fire_hit`, infernal chain `lightning_hit`, wailing souls `necro_hit`
  (no longer `soul`, which drove the XP pickup pitch ladder). Ichor pickups `coin`.
- Hub: `hub_scenery.gd` fire bed uses `Sfx.play_loop(&"amb_fire")` (waits for synthesis); upgrades
  go through the UI role's ShopPanel (`shop_buy` / `shop_deny`); `hub_shop_ui.gd` map unlocks play
  `unlock` / `shop_deny`.
- Objectives: shrine channel drone `amb_ritual` (swells with progress while the demon is inside),
  `desecrate` on completion; relic seals `seal_break`, corruption `relic_corrupt`; souls objective
  `harvest`.
- Weather: `atmo_lightning.gd` plays `thunder` (it always asked for it; the sound now exists);
  legacy `weather.gd` plays `thunder` / `thunder_far` instead of `toll`; WeatherAudio fades the
  rain and gust beds.
- Dialogue: `dialogue_box.gd` typing blips use `Sfx.play_blip(speaker id)`.

## Materials and voices (data/audio/enemy_audio.json)
All 52 enemies and bosses in data/enemies + data/bosses are listed (round 4 added the round-2/3
characters and the new bosses). Unlisted ids: CharacterRoster faction/tags guess (constructs ->
stone, gilded heaven constructs -> metal, armored / siege -> metal, elemental and spawned flying
shades -> holy, beasts roar / screech, mortals shout, order grunts, angels cry), then name
keywords override the material (glass, statue, ...). Verified: with the JSON entries removed the
guesses match the hand-picked materials for every construct, golem and statue.
Characters-new / gameplay: when you add an enemy, add its id under `"enemies"` with a `material`
(flesh, stone, glass, metal, holy) and a `voice` (any `voice_*` sound, or ""). Unlisted ids fall
back to keyword matching on id + display name (statue -> stone, golem -> glass, knight -> metal,
wisp / light -> holy, ...), then flesh. You can also set a `hit_material` / `voice` property or
meta on the EnemyData itself; that wins over the JSON. New dialogue speakers: add
`"id": [blip, pitch]` under `"speakers"` (unknown speakers get a stable pitch from their id).

## For the abilities worker (wired, nothing to do)
- `Abilities.ability_cast(id)` -> SfxHooks reads `Abilities.defs[id].tags` and layers the first
  element tag's `<element>_cast` (-9 dB) under your own `_sfx()` sound.
- `Abilities.damage_dealt(amount, tags)` -> `<element>_hit` at the struck enemy's position (from
  the `Game.enemy_struck` of the same frame; 2D fallback), rate-limited; tags containing `"dot"`
  are skipped. Tag -> element: fire, blood, shadow (+curse), plague, storm ->
  lightning, necro (+soul). If you add an optional `element_hit(element, position)` signal it is
  picked up too and played positionally.
- `&"soul"` is the XP-gem pickup (its pitch climbs per play); ability_caster now uses `necro_cast`
  (summon) and `harvest` (gem harvest).
- Direct use: `Sfx.play_element(element, &"cast" | &"hit", position_or_null, volume_db)`.

## Bus layout (shared with music)
`Master` (hard limiter, ceiling -0.8 dB) <- `SFX` (small room reverb, wet 0.1), `Music` (low-pass
for the pause muffle), `UI` (dry), `Ambience` (long dark reverb, wet 0.3). Sfx creates them at runtime if they are missing
(no `default_bus_layout.tres` yet). Bus volumes follow `Settings.sfx_volume` / `music_volume`
(Ambience follows `Settings.ambience_volume` if that property exists, else sfx_volume).
MusicManager owns the `Music` bus effects (pause low-pass, stinger ducking). If you want ducking (music dips under boss_roar / level_up), add a sidechain
compressor on `Music` keyed from `SFX`, or ask me for a `Sfx.loud_sound_played` signal.

## Validation
- `godot --headless --path . --script res://tools/export_sfx.gd` (report + wav export; `-- --check` for report only)
- `godot --headless --path . --script res://tools/sfx_smoke.gd -- --autopilot --secs=60`

## Known issues / next
- Most one-shots are mono (3D panning gives placement); stereo is used for beds and thunder.
- atmo_lightning.gd schedules thunder with a pausable timer, so it waits while the tree is paused
  (level-up menu); that is the visuals role's call. (Visuals: kept on purpose, the flash and bolt
  freeze with the game too, so sight and sound stay in step. Far strikes now play `thunder_far`,
  near ones `thunder` (+ `impact` when very close). Legacy `weather.gd` has been removed.)
- `voice_grind` is frequent when many statues are alive (limited to 1 voice / 0.7 s).
- reliquary.gd and dialogue affinity.gd still play `&"soul"` once in a while, nudging the pickup
  pitch ladder; harmless, could move to `harvest`.
- The autopilot run does not cast abilities yet, so ability -> element sounds are covered only by
  the signal check in `tools/sfx_smoke.gd`, not by an actual run.

## Coordination note from music (round 2)
- `Settings.ui_volume` now exists (saved in `[audio]`), and the settings menu has an "Interface"
  slider for it, so your `UI_SOUNDS` -> `UI` bus routing is player-controllable.
- `default_bus_layout.tres` exists (Master/Music/SFX/UI/Ambience). MusicManager adds a runtime
  width reverb on `Music` and a `MusicStingers` bus. Your `MusicManager.duck()` calls are kept.
- Music stingers now fire on level-up, relic found (per rarity), objective complete and hub
  purchases, under your sounds. Tune or blank them in `data/music/music.json` -> `stingers`.

## Note from code-quality (split)
- The legacy GDScript music synthesis (menu choir / battle drums, the `MENU_*` / `WAR_*` data and
  `_render_menu`, `_render_battle`, `_mix`, `_distant`, `_tpl_string/_pluck/_drone/_wind/_taiko`)
  moved from `autoload/sfx.gd` to `scripts/audio/sfx_legacy_music.gd` (sfx.gd: 2222 -> 1904 lines).
  `Sfx._render_track()` is now a thin wrapper: it still returns null when MusicManager is
  registered, otherwise `LEGACY_MUSIC.new(self).render_track(track)`. The output is bit-identical
  (same sample hashes with a fixed seed). The new file is in `CACHE_SOURCES`, so the first launch
  re-renders the stream cache once. Since MusicManager always exists, the music / sfx owners
  could delete the legacy file entirely.
- (music round 3) The relic and level-up music stingers are now **off by default**: those moments
  are yours alone. Music stingers remain for objective complete, hub purchase and boss defeated,
  and now start on the music's next beat.

## Requests from gameplay (round 3)
- `&"heartbeat"`: a low lub-dub one-shot (~0.45 s). GameFeel plays it on every beat while the demon
  is near death (66-118 bpm), volume -16..-3 dB by how close to death. Unknown names are ignored, so
  it is silent until the sound exists.
- `&"last_stand"`: the "survive a lethal blow at 1 HP" moment (once per run): a deep hellfire roar /
  bell crack, ~1 s. Played with `brimstone` by `scenes/player/last_stand.gd`; also
  `RunState.last_stand` (signal) if you prefer hooking it.
- New signals you may want: `RunState.ascension_started`, `ascension_ended(result)`,
  `score_changed(score)` (Ascension mode), `RunState.last_stand`.
- Elite kill confirm (GameFeel) plays a positional `toll` at -8 dB; swap it for a better sting if you have one.

## Note from characters-new (round 5)
- New demon `iscariel` (fallen-angel turncoat; feathered wings, one burned; a broken halo) and
  `nhazgul` (round 4; plague hive, a cloud of flies). Per-demon voice / footstep / death sounds
  would help them read: Iscariel could carry a cracked choir note in his attacks, Nhazgul a buzz.
- New enemy hooks you may want sounds on: `Enemy.healed(amount, source)` / `Game.enemy_healed`
  (sources heal_circle, virtue_miracle, paschal_lamb, carrion_feast, sanctified_hallowed),
  `Enemy.died` (before the death FX), the Celestial Leviathan pass (CelestialWhale.passed), the
  mimic waking (mimic_reliquary), the cloud djinn's blink, the revenant rising.
