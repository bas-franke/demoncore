# Visuals: lighting, atmosphere, weather (docs/team/visuals.md)

Status: round 2 landed. The `Atmosphere` autoload drives per-map lighting, sky, fog, colour grade
and weather from JSON presets, escalates the weather over a run (calm -> storm, surges, a holy
dawn at the final boss), lights bosses, dresses Basecamp Hell, adds quality-scaled screen-space
touches (corruption vignette, holy bloom on boss telegraphs, heat haze) and is benchmarked per tier.

## Owned files
| Path | What |
|---|---|
| `autoload/atmosphere_director.gd` | autoload `Atmosphere`: presets, blending, the public API |
| `data/atmosphere/presets.json` | every preset, weather variant, overlay and the scene -> preset table |
| `scenes/world/atmo/atmo_presets.gd` | `AtmoPresets`: JSON, inheritance, (weighted) overlay ops, blending |
| `scenes/world/atmo/atmo_stack.gd` | `AtmoStack`: overlays + overrides on top of the preset |
| `scenes/world/atmo/atmo_scene.gd` | `AtmoScene`: the current scene's driven nodes; applying a state; fallbacks |
| `scenes/world/atmo/atmo_apply.gd` | `AtmoApply`: state -> Environment / sky / sun / post pass / stock nodes |
| `scenes/world/atmo/atmo_events.gd` | `AtmoEvents` (child "Events"): boss lighting, gloom, clouds, flicker, haze, bloom |
| `scenes/world/atmo/atmo_run_weather.gd` | `AtmoRunWeather` (child "RunWeather"): escalation, surges, final dawn |
| `scenes/world/atmo/atmo_rig.gd` | `AtmoRig`: in-scene layers, moon, hellglow, gloom light, boss light |
| `scenes/world/atmo/atmo_layers.gd` | `AtmoLayers`: particle layers (ash, embers, feathers, snow, rain, splash, rays, wisps) |
| `scenes/world/atmo/atmo_lightning.gd` | `AtmoLightning`: bolts, flash lights, thunder, shake |
| `scenes/world/atmo/atmo_screen_fx.gd` | `AtmoScreenFX`: corruption vignette, holy bloom, flashes (CanvasLayer 0) |
| `scenes/world/atmo/atmo_heat.gd` | `AtmoHeat`: heat-haze burst pool + persistent sources |
| `scenes/world/atmo/atmo_hub_dressing.gd` | `AtmoHubDressing`: Basecamp lava bounce, warm pools, lava haze |
| `scenes/world/atmo/hellfire_light.gd` | `HellfireLight`: flickering OmniLight3D for anyone |
| `shaders/atmo/*.gdshader` | holy_ray, feather, snow, wisp, lightning_bolt, heat_haze, holy_bloom, corruption_vignette |
| `tools/atmo_test.tscn/.gd`, `tools/atmo_tour.gd`, `tools/atmo_bench.sh` | test arena, screenshot tour, benchmark |

Shared-file edits I made (surgical): `project.godot` (autoload `Atmosphere`, `[shader_globals]`
`atmo_cloud_*`), `shaders/cloud.gdshaderinc` (cloud shadows read those globals), `scenes/maps/map_loader.gd`
(removed the dead `Weather` configuration), `scenes/maps/features/lightning_storm.gd` (one guarded call to
`Atmosphere.strike_lightning`), `scenes/basecamp/hub_avatar.gd` (group `atmo_focus`),
`data/maps/outer_gardens.json` + `gilded_isles.json` (`atmosphere_preset`), notes in maps / sfx /
basecamp docs, the `World` row of `docs/ARCHITECTURE.md`. Removed (round 2): `scenes/world/weather.gd`
and `tools/weather_test.*` (nothing referenced them any more; their moods live on as presets).

## API
```gdscript
Atmosphere.apply_preset("cathedral_city")          # snap (map load); apply_preset(name, 8.0) blends
Atmosphere.push_overlay(&"shrine", "shrine", 2.0)   # named overlay ("_overlays" or the preset's own)
Atmosphere.push_overlay(&"rite", {"grade.saturation*": 0.5}, 1.0, 0.7)   # ad hoc, at 70 % weight
Atmosphere.pop_overlay(&"rite") / has_overlay(&"rite") / has_overlay_def("run_storm_local")
Atmosphere.set_weather("rain", 1.0, 5.0) / clear_weather("rain") / set_value("env.exposure", 1.2)
Atmosphere.get_value("weather.rain")                # current blended value of any key
Atmosphere.strike_lightning()                       # random; (pos, 0.0) = right there; (pos, 0.2, false) = no sound
Atmosphere.flash(Color(1, 0.9, 0.7), 0.4, 2.0)      # full-screen additive flash (honours reduce_flashes)
Atmosphere.heat_haze(pos, 3.0, 1.0)                 # heat shimmer burst (Medium+)
Atmosphere.add_gloom(0.2) / set_gloom(0.8) / get_gloom()   # corruption darkness (-1 = automatic)
Atmosphere.get_escalation()                         # run storm 0..1
Atmosphere.quality()                                # Atmosphere.Quality.LOW / MEDIUM / HIGH / ULTRA
```
Signals: `preset_changed(preset)`, `lightning_struck(position, far)`.
Groups: `atmo_focus` (weather follows this Node3D when there is no `Game.player`),
`hellfire_flicker` (any Light3D flickers with the preset), `heat_haze_source` (Node3D gets a
persistent shimmer; metas `heat_radius`, `heat_strength`).

## Automatic behaviour
- **Maps**: `Maps.map_loaded` applies the def's `atmosphere_preset`, else a preset named like the id.
  **Scenes**: `presets.json` `"_scenes"` (Basecamp -> `basecamp_hell`) or a root meta `atmosphere_preset`.
- **Run progression** (`AtmoRunWeather`, from `RunState`): `run_calm` at the start fading out by ~40 %
  escalation; `run_storm` + the preset's `run_storm_local` weighted by escalation =
  `difficulty_tier() / 12` (sun sinks and reddens, clouds close in, gusts, lightning; rain in the city
  and gardens, a blizzard in the monastery, an ash storm in the wastes); `surge` / `lull` overlays on
  `wave_started` (a far rumble opens surges once the sky has turned); `final_dawn` when the last boss
  needed for victory (ObjectiveDirector `victory_bosses`) spawns: a low, backlit holy dawn with long
  shadows and gold rays, kept for the victory; `run_lost` drains the colour on death.
- **Boss** (`AtmoEvents`): `boss` overlay + heralding strike + judgement spotlight; `is_enraged` ->
  `boss_enraged` (crimson, more lightning); boss death -> flash, overlays clear after 2.5 s.
- **Holy bloom**: visible `BossTelegraph` / `HolyTelegraph` nodes owned by a boss or boss hazard drive a
  radial chromatic split + golden glow centred on the strongest (it grows with the telegraph's `fill`).
- **Heat haze**: abilities with a fire / hellfire / brimstone / blood tag (`Abilities.ability_cast`)
  shimmer around the demon; nodes in `heat_haze_source` shimmer persistently.
- **Gloom**: preset `fx.gloom` x blight under the player (`Corruption.amount_at`) + kill pulses ->
  a negative light pool, a dark FogVolume (High+ with volumetrics) and the corruption vignette
  (dark tendrils creeping in from the screen edges).
- **Basecamp** (`AtmoHubDressing`): lava-bounce uplights on the merchants, warm pools at the stalls
  and gate, heat haze over the lava and the bonfire, heavier ash fall (layout read from HubScenery).
- **Quality**: `Settings.graphics_changed` -> particle counts (`particle_density` x tier), haze and
  bloom off on Low, wisps/splash need Medium, lightning/boss-light shadows need High, volumetric fog
  per `Settings.volumetrics`, glow/SSAO per Settings. `Settings.reduce_flashes` cuts flashes to 20 %.
- Thunder: `thunder` (near, + `impact` when very close) / `thunder_far`, on a pausable timer on
  purpose (the flash freezes with the game too). `WeatherAudio` (sfx role) follows `weather.rain` /
  `weather.gust` through `get_value`.

## Presets
Maps: `ruined_sanctum` (= `sanctum_dusk`, cycles ash storm / holy rain), `cathedral_city`,
`outer_gardens` (cycles `outer_gardens_rain`), `frozen_monastery` (alias `frozen_reliquary`),
`sunlit_citadel` (high noon), `heavens_gate`, `gilded_isles` (cycles `gilded_isles_rain`),
`ashen_wastes`, `storm_spire`; hub `basecamp_hell`; spare `blood_moon`.
Overlays: `boss`, `boss_enraged`, `shrine`, `run_calm`, `run_storm`, `surge`, `lull`, `final_dawn`,
`run_lost`; per-preset `run_storm_local` in cathedral_city, outer_gardens, frozen_monastery,
heavens_gate (and sunlit_citadel), gilded_isles, ashen_wastes, sanctum_dusk.

Sections and keys (every key can be blended, overridden, or used in an overlay):
- `env`: tonemap (agx/aces/filmic/reinhard/linear), exposure, white, background, ambient,
  ambient_energy, ambient_sky, glow (bool), glow_intensity/strength/bloom/threshold, ssao (bool),
  ssao_intensity/radius, fog (bool), fog_color/energy/density/scatter/height/height_density,
  volfog (bool), volfog_density/albedo/emission/emission_energy/anisotropy, adjust (bool),
  brightness/contrast/saturation
- `sky`: top, horizon, ground_bottom, ground_horizon, energy
- `sun` / `moon`: color, energy, pitch, yaw (degrees); sun.fog_energy
- `grade`: shadow_tint, highlight_tint, saturation, contrast, lift, vignette, vignette_color, grain
- `weather`: ash, embers, feathers, snow, rain, rays, wisps (0..1), lightning (strikes/min),
  wind [x, z], gust, clouds, cloud_cover, cloud_speed, wet, *_color, lightning_color
- `scene`: ash, embers, beams, beam_color, mist (main.tscn's stock Atmosphere node), map_particles
- `fx`: hellglow_color/energy/range, flicker, gloom, gloom_color, gloom_radius
- `cycle` [{preset, time}], `extends`, `overlays` {name: ops}

Overlay operators: `"key*": 0.7` multiply, `"key+": 0.1` add, `"key~": [target, 0.5]` mix toward;
a weight w applies them partially (`*` by lerp(1, v, w), `+` by v * w, `~` by amount * w).

## Round 3
- `the_breach` (terrain map) retuned: split sky (heaven blue overhead, crimson horizon), gold heaven
  sun from high above vs a low red hell light from the opposite side (the moon slot, which also fills
  the cliff faces the sun leaves dark), ash and feathers falling together, embers rising.
- Terrain cliffs under low sun: `gilded_isles` sun raised to -54 deg plus a cool fill light from the
  opposite side; `the_breach` sun at -56 deg with the hell fill. (Run escalation still lowers the sun.)
- Enemy shadows off on Low / Medium (`AtmoEvents`, group `enemies`, live with settings changes).
- Per-boss overlays layered on `boss` as `boss_tint`: `boss_<EnemyData file id>` from presets.json
  (`boss_war_chariot` ember fire, `boss_storm_archon` violet tempest, `boss_gilded_seraph` gold,
  `boss_cantor` lilac hush, `boss_grand_inquisitor` pyre); any other ProcBoss gets a light tint from
  its `cfg.hazard_tint`.

## Performance (tools/atmo_bench.sh, details in docs/team/performance.md)
In the fixed test arena (720p, RTX 4070 Ti) a preset costs ~0.05 ms GPU on Low and ~0.2-0.6 ms on
High/Ultra; volumetric fog (frozen_monastery, basecamp_hell) and particle layers are the largest
items, and both scale with the settings. Haze and bloom read the screen only while active, never on Low.

## Testing
```
godot --path . res://tools/atmo_test.tscn -- --atmo=storm_spire
godot --path . res://tools/atmo_test.tscn -- --atmo-tour=C:/tmp/shots [--atmo-tour-boss] [--atmo-tour-run] [--atmo-tour-quality=0]
tools/atmo_bench.sh C:/tmp/bench.txt
godot --path . res://scenes/main.tscn -- --map=cathedral_city --boss --godmode --autopilot
godot --path . res://scenes/basecamp/basecamp.tscn -- --hub-at=occultist
```
Debug builds: F7 = next preset, Shift+F7 = close lightning strike (F8 is the objectives worker's).
`--verbose` logs preset applies, run escalation, waves and holy-bloom triggers.

## Known issues / next steps
- New `class_name`s from any worker need a `--headless --import` before `Play.bat` sees them; the
  Atmosphere scripts look other autoloads up by path so a broken script elsewhere can't break lighting.
- Heaven maps are bright by design; their ground textures are pale, so contrast comes from the grade.
- Ideas: rain puddle reflections per biome, a petals layer for the gardens (the map brings its own),
  boss-specific overlays (`overlays.boss` per preset) for the Inquisitor's fire phases.

## Note from code-quality
- `RenderingServer.global_shader_parameter_get_list()` / `global_shader_parameter_get()` are
  editor-only. Use `ProjectSettings.has_setting("shader_globals/<name>")` (visuals: done).

- From basecamp (round 3): with the stall lanterns carrying the hub, I lowered `basecamp_hell`
  ambient_energy 0.55 -> 0.45 and sun energy 1.0 -> 0.85. After the ending, Basecamp pushes overlay
  `reconquest` (sun toward gold, +exposure, -fog). Retune either freely.

## QA notes (from docs/team/qa.md)
- QA fixed `scenes/world/atmo/atmo_rig.gd` `find_player()`: `pl is Node3D` ran on a freed player after a run ended (1000+ script errors per hub->run->hub cycle); `is_instance_valid` now comes first (`# QA:`).

## From terrain (round 2)
- Added preset **`the_breach`** to `data/atmosphere/presets.json` (before `_overlays`): extends
  `gilded_isles`, `"cycle": []` (no holy-rain cycle), crimson horizon, lava-lit ground bottom,
  embers + feathers, a little gloom. It's a first pass for the new map `the_breach` (a heaven island
  over a lava sea, heavy corruption). Please retune or rebuild it as you like.
