# Music (docs/team/music.md)

Status: round 4 is done and verified headless. That covers `MUSIC CHECK OK`, a real run to game over, the staged ending with both choices, and every map and all ten bosses in a live run. The music source is 24.90 MB, against a strict 25,000,000-byte budget.

## What it does
- **MusicManager** autoload: adaptive, layered music.
  - Each track is a set of sample-locked, seamlessly looping stems played as one `AudioStreamSynchronized`.
  - A 4-bar stem loops exactly twice per 8-bar stem.
  - Stems fade in and out individually.
  - Track switches wait for the playing track's next bar line (beat line for a boss arrival), then crossfade between two decks.
  - Stingers start on the next beat.
- **Intensity** (runs only): `CALM` (base stem), then `COMBAT` (adds the combat stem), then `FRENZY` (adds the frenzy stem).
  - It follows nearby enemies, kill rate, recent hits and low HP.
  - A wave surge (`RunState.wave_started`) bumps it to FRENZY for 14 s.
  - `Game.objective_started` bumps it to COMBAT for 25 s.
- **Bosses**: each of the six bosses has its own theme, picked from music.json `boss_tracks` by the boss's EnemyData file name.
  - Extra layers follow `phase_index` (`phase2`/`phase3`), `is_enraged` (`enrage`), or intensity (`host` on the Archon).
  - `Game.boss_died` plays the `victory` stinger, then the map theme returns.
- **Run end**: when the game-over screen calls `Sfx.play_music(&"run_end")`, a won run gets the looping `run_won` theme and a lost run gets the `defeat` dirge. On death the music first drains away.
- **Story**:
  - The staged ending (`scenes/dialogue/ending_stage.tscn`) plays `ending_climb`.
  - `stage_archons` adds the `archons` layer and `stage_throne` adds the `throne` layer.
  - `stage_sit` and `stage_break` cut to the `ending_sit` and `ending_break` resolutions.
  - Once `Dialogue.has_flag("story.ended")` is set, the hub plays `basecamp_ended`.
- **Stingers** (music.json `stingers`: cooldown, priority, duck, all beat-quantized):
  - objective complete
  - hub purchase
  - boss defeated

  The relic and level-up events are still hooked but **off by default**, since SFX covers them. To turn them back on, render them with `python tools/music/gen_music.py sting_relics sting_level_up` and add entries to `stingers`.
- **Pause muffle**: while the tree is paused, the Music bus low-pass sweeps down and the music dips 5 dB. Stingers play on the `MusicStingers` bus, which isn't muffled.
- **Ducking**: `MusicManager.duck(db, s)` glides the dip in and out. Sfx uses it under big sounds.

## Tracks (all procedural; `tools/music/gen_music.py`)
| Track id | Used for | Character | Stems (bars) |
|---|---|---|---|
| `basecamp` | Basecamp Hell hub | C minor/Phrygian organ with tremolo, pedal drone, monk hum, reed solo, bells, heartbeat | main 8 |
| `basecamp_ended` | hub after the ending | the hub theme crowned: C with major cadences, a crown motif, bells, no heartbeat | main 8 |
| `title` | title, demon select | a music-box hymn in D major that sours into D minor | main 8 |
| `battle_sanctum` | Ruined Sanctum | cello lament, E minor | calm 8 / combat 4 / frenzy 4 |
| `battle_city` | Cathedral City | Gregorian chant in D Phrygian with a tritone shadow | 8 / 4 / 4 |
| `battle_monastery` | Frozen Monastery | oktavist choir and ice bells, B minor | 8 / 4 / 4 |
| `battle_gardens` | Outer Gardens | ironic F-major harp and soprano choir | 8 / 4 / 4 |
| `battle_citadel` | Sunlit Citadel | crusader brass, A minor | 8 / 4 / 4 |
| `battle_isles` | Gilded Isles | a 3/4 waltz in D Lydian: harp, sopranos, wind chimes | 16 / 4 / 4 |
| `battle_spire` | Storm Spire | C# minor at 132 BPM: storm wind, thunder, 16th strings | 8 / 4 / 4 |
| `battle_gate` | Heaven's Gate | G-minor organ and choir chorale, processional, tritone fanfare | 8 / 4 / 4 |
| `battle_breach` | The Breach (via `map_tracks`; its JSON says `battle_wastes`) | **layered variant**: battle_gate's holy chorale, march and fanfare stems, overrun by a "hell" layer: Basecamp Hell's heartbeat, its b2 tremolo organ and its reed motif, transposed to G, over lava | gate 8/4/4 + hell 2 (11.025 kHz) |
| `battle_wastes` | Ashen Wastes | A Phrygian: ash wind, a detuned dulcimer, frame drums, distorted bass | 8 / 4 / 4 |
| `boss_sariel` | Sariel | E Phrygian-dominant war mass | main 8 / enrage 4 |
| `boss_inquisitor` | Ozias, Grand Inquisitor | Dies Irae chant, hammers, fire bed | main 8 / phase2 4 / phase3 4 |
| `boss_archon` | Azrafel, Gate Archon (finale) | the grandest: C minor with a Neapolitan Db, full organ plenum, SATB choir, brass anthem, taiko, the Gate's bells | main 8 / host 4 (frenzy) / enrage 4 |
| `boss_abbot` | Ysmir, Frost Abbot | B Phrygian: oktavist chant stabs, ice bells, 3-3-2 drums | main 8 / phase2 4 |
| `boss_wyrm` | Aurelion, Dawn Wyrm | D-major heroic brass curdled by Lydian-dominant, sunrise harp, roars | main 8 / phase2 4 |
| `boss_verdance` | Mother Verdance | an F-minor 3/4 lullaby: harp, log drums, sagging alto choir | main 16 / phase2 4 |
| `boss_chariot` | Lord-Marshal Caddoc (`war_chariot`) | A harmonic minor at 140 BPM: galloping war drums, military snare, a crusader horn march, fire bed | main 8 / phase2 4 |
| `boss_tempest` | Baraqiel, Archon of the Tempest (`storm_archon`) | **layered variant**: battle_spire's stems plus a "tempest" layer: 3-3-2 choir hits, rising b2 brass, lightning cracks | spire 8/4/4 + tempest 4 (phase2) |
| `boss_aurum` | Aurum, the Gilded Seraph (`gilded_seraph`) | **layered variant**: battle_isles' waltz plus a gilded-cage ostinato (music box and bells circling D Lydian's G#, warped organ) and a pompous soured fanfare | isles 16/4/4 + cage 4 + phase2 4 |
| `boss_cantor` | Cantor Seraphiel, the Broken Choir (`cantor`) | E minor at 100 BPM: a detuned choir sliced into stutters, reversals, dropouts and octave jumps; a broken-clock tick, hammers | main 4 / phase2 4 |
| `ending_climb` | the staged ending | an organ pedal climbing one step per bar, heartbeat, drone | main 8 / archons 2 / throne 2 |
| `ending_sit` | the "Sit" resolution | dark coronation: organ plenum on Dm, crown bell, choir, low b2 rumble | stinger 20 s |
| `ending_break` | the "Break" resolution | cataclysm: shattering bells, choirs screaming down an octave, thunder, rubble, one last bell | stinger 17 s |
| `run_won` | ASCENDANT screen (loops) | E-Mixolydian processional: organ, choir, bells | main 4 |
| `defeat` | game over (loops) | D-minor funeral dirge | main 4 |
| `victory` | boss killed | boom, then an E-major organ plenum, choir, bells | stinger |
| `sting_objective`, `sting_purchase` | objective done, hub purchase | short cadences | stinger |

**Footprint rules** (to stay under the 25 MB budget):
- 16 kHz, 16-bit, everything mono. A light, wide reverb that MusicManager adds to the Music bus at runtime supplies the width.
- The dark single-stem tracks (`basecamp`, `basecamp_ended`, `defeat`, `title`, `run_won`, `victory`, `ending_sit`, `ending_break`) are written at 11.025 kHz using a circular FFT resample, so they stay seamless. A stem can also take its own `out_rate`, as long as its loop is a whole number of samples at that rate (e.g. Breach's "hell" layer).
- **Layered variants**: `Track.reuse(base, stem names)` puts another track's already rendered stems into a new track by file reference (same tempo, meter and length), so a variant only pays for its new layers. MusicManager shares the loaded streams.
- Combat and frenzy stems are 4 bars on the tonic pedal, so they fit every chord of the calm layer.

music_check fails if the total (each file counted once) reaches 25,000,000 bytes.

## Owned files
- `autoload/music_manager.gd`
- `tools/music/gen_music.py`: synth and composer. Rerun it with `python tools/music/gen_music.py [track ...]` (numpy only, about 2 minutes for everything). The optional `sting_relics` and `sting_level_up` render only when you name them.
- `tools/music/music_check.gd`: run `godot --headless --path . -s res://tools/music/music_check.gd [-- --run]`; it should print `MUSIC CHECK OK`.
- `assets/audio/music/*.wav` + `manifest.json`: these are generated.
- `data/music/music.json`: aliases, boss and map tracks, story keys, quantize, stingers, intensity.
- `default_bus_layout.tres` (shared with SFX)
- Small marked edits in shared files:
  - `autoload/sfx.gd`: music forwarding.
  - `scenes/ui/game_over.gd`: `run_end`.
  - `autoload/settings.gd`: `ui_volume`.
  - `scenes/ui/settings_menu.gd`: the Interface slider.

## API
```gdscript
MusicManager.play(&"basecamp")                 # id or alias; next bar line, then crossfade
MusicManager.play(&"boss", 1.0, &"beat")       # fade, quantize &"bar" / &"beat" / &"none"
MusicManager.stop(2.0)
MusicManager.has_track(&"battle_city")         # aliases count; unknown battle_* -> default map theme
MusicManager.stinger(&"objective_complete")    # named event (cooldown, priority, next beat)
MusicManager.play_stinger(&"victory", -12.0)   # raw one-shot track, immediate
MusicManager.play_run_end(victory)             # run_won theme or the defeat dirge (also play(&"run_end"))
MusicManager.duck(-6.0, 2.0)
MusicManager.set_intensity_override(MusicManager.FRENZY)   # -1 = automatic
MusicManager.bump(MusicManager.COMBAT, 12.0)
MusicManager.intensity / MusicManager.current_track
signal track_changed(track)   signal intensity_changed(level)   signal stinger_played(event)
```
Aliases:
- `menu` / `title`: the basecamp theme (or `basecamp_ended`) in the hub, `ending_climb` in the ending stage, otherwise the title theme
- `backyard` / `battle` / `map`: the current map's theme
- `hub`: basecamp
- `boss`: boss_sariel
- `game_over`: defeat
- `run_end`: run_won or defeat, depending on how the run ended

Hooks for other roles:
- **Maps**: set `"music"` in the map JSON. To give a map its own theme without touching its JSON, use music.json `map_tracks` (map id -> track). **gilded_isles currently has `"music": "battle_gardens"`; music.json maps it to its own `battle_isles`.** The maps worker can set `"music": "battle_isles"` directly.
- **Bosses**: map the boss id to a track in `boss_tracks`, or set a `music_track` property or meta on the boss node. Expose `phase_index` / `is_enraged` to drive the extra layers.
- **Story**: the stage event names and track ids live in music.json `story`. The hub variant follows `story.ended_flag`.
- **Events**: `MusicManager.bump(level, s)`, or add a `stingers` entry and call `MusicManager.stinger(&"event")`.
- Dev: `godot --path . -- --music-log` prints track, intensity and stinger events.

## Buses
`Master` (HardLimiter) receives these buses:
- `Music`: low-pass for the pause muffle, plus a runtime width reverb.
- `MusicStingers`: runtime; mirrors the Music volume.
- `SFX`
- `UI`: Settings.ui_volume, "Interface" slider.
- `Ambience`

## Known issues / next steps
- None of it was checked by ear, only with spectra and loudness. At 16 kHz there is nothing above 8 kHz, which suits these dark mixes but dulls cymbals and hats a little. Retune in gen_music.py.
- **The budget is full: about 0.1 MB is left.** New themes should be layered variants with small layers: 2–4 bars, and 11.025 kHz where the material allows it. Otherwise, free space first, e.g. by moving more dark stems to 11.025 kHz or shortening calm stems.
- The ending resolutions start immediately on the stage event, not on a beat, to stay in sync with the staging flash.

## Note from characters-new (round 3): boss_tracks for the new bosses
(Done in music round 4: war_chariot -> boss_chariot, storm_archon -> boss_tempest,
gilded_seraph -> boss_aurum, cantor -> boss_cantor. The CelestialWhale event is not hooked.)
Please map these boss ids (EnemyData file names) in music.json `boss_tracks`; all expose
`phase_index` (3 phases) and `is_enraged` (last phase): `war_chariot` (ashen_wastes, a crusader
warlord on a burning war-chariot: drums, horns), `storm_archon` (storm_spire, a storm-archon
conducting lightning: choir + thunder), `gilded_seraph` (gilded_isles, a treasure-hoarding gilded
seraph: bells, harp), `cantor` (ruined_sanctum variant, a broken choirmaster: organ, choir). Until
then they use the default `boss_track`. Also new: a map event `CelestialWhale` (a whale of light
passing overhead for ~30 s on open-sky maps) if you want a `MusicManager.bump` or a stinger there
(signal `passed` when it leaves; it plays `choir` on arrival).
