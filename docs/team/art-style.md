# Art style (docs/team/art-style.md)

Owner: art style director. Status: round 3 done (shopkeeper rim, holy_glow halos, telegraph
bloom cap, VFX palette pass on the round-2 schools and new enemies, Blight detail setting, outline
corner fix, ability icons). See the work log at the bottom.

## 1. Style guide

**One sentence:** a muted, physically lit dark-fantasy world where the only saturated things are
the two powers at war: *hellfire that glows from inside dark matter* (the player) and
*sterile holy light that glows on polished surfaces* (heaven). Wherever the demon walks, the
world is burned toward the hellfire palette.

The baseline renderer is the existing `Art` kit (`scripts/art.gd`, `shaders/lit*.gdshader`): PBR,
procedural grime, no cel bands, **no ink outlines on ordinary content** (the legacy `Toon` /
`outline.gdshader` are intentionally disabled). Everything below builds on that, it does not
replace it.

### Palette (use the constants, not ad-hoc colors)
| Group | Constants (`ArtStyle.*` / `Art.*`) | Rule |
|---|---|---|
| Neutral world | `Art.OBSIDIAN ASH STONE BONE LEATHER CLOTH_DARK MOSS` | 70% of the screen. Desaturated, value range 0.05-0.45. Never fully black or white. |
| Hell (player) | `HELL_OBSIDIAN HELL_CHAR HELL_BLOOD HELL_CRIMSON` surfaces, `HELL_EMBER HELL_FIRE HELL_CORE HELL_SOUL` light | Dark, matte, rough bodies; the light comes **from inside** (cracks, eyes, runes, veins, rim). Hue 0-30 deg. |
| Heaven (enemies) | `HEAVEN_MARBLE HEAVEN_BONE HEAVEN_GOLD HEAVEN_STEEL` surfaces, `HEAVEN_LIGHT HEAVEN_WHITE HEAVEN_SKY` light | Bright, clean, polished (low grime, gold metallic 1.0 / rough 0.3). The light sits **on the surface** (halos, rims, gilding). Hue 40-55 deg plus cold `HEAVEN_SKY` accents. |
| Corruption | `BLIGHT_CHAR BLIGHT_ASH BLIGHT_BLOOD BLIGHT_EMBER` | Only via the corruption shaders: char + ash crust, dried-blood patches, thin ember fissures. |

- Emission: hell glows hot (`energy` 2-4, orange -> white-gold core), holy glows pale (`energy`
  1.5-3, white -> gold). Values > 1 bloom, so keep big emissive areas small; one bright focal point
  per object.
- Never give an angel red/orange emission or the demon gold/white emission (except a holy weapon
  the demon stole, which should look "wrong": gold body, ember cracks).

### Shape language
- **Demon side: jagged, asymmetric, heavy.** Horns, spikes, broken silhouettes, forward-leaning
  mass, triangles pointing down/forward. Cracks instead of seams.
- **Heaven side: circles, verticals, symmetry.** Halos, rings, columns, wings in fans, perfectly
  regular patterns (the holy-glow shimmer scrolls in straight bands, never flickers). Triangles
  point up.
- **Corruption: organic and creeping.** Noise-frayed edges, crack networks, nothing straight.
- Read from a steep top-down camera at ~26 m: silhouettes and the top surface matter most; keep
  details >= 0.15 m; tall thin things need a glow or rim to read.

### Material rules
1. Opaque bodies use `Art.mat()` / `Art.textured_mat()` (flashable lit) for anything that can be
   hit, `Art.mat(..., flashable = false)` (lit_static) for scenery. Never StandardMaterial3D for
   opaque content: it skips grime, cloud shadows, hit flash, dissolve, rim and corruption.
2. Glows: hell side -> `ArtStyle.hellfire()` (molten crust) or `Art.emissive()` (lit + glowing);
   holy side -> `ArtStyle.holy_glow()` (radiant light body). `Art.glow()` is fine for tiny bits.
3. Characters get the faction rim (`ArtStyle.apply_faction`). Outlines only for gameplay emphasis:
   elites (gold), interactables / shopkeepers (pulsing ember), the selected target (red).
4. Death: angels burn away into gold light (`Dissolve` with `Art.HOLY`, the default), demons into
   embers and ash (`DemonModel` already does this, or `ArtStyle.dissolve(x, Faction.DEMON)`).
5. Hit flash is white (`Art.flash` / `model.set_flash`), short (0.1-0.25 s), on the whole model.
6. All ground-like shaders include the corruption library (section 3). New terrain / floor shaders
   must too.

## 2. Files I own
- `shaders/style/corruption.gdshaderinc`: corruption library (global uniforms, blight / wither /
  char functions).
- `shaders/style/hellfire.gdshader`, `shaders/style/holy_glow.gdshader`,
  `shaders/style/outline.gdshader` + `shaders/style/outline_mask.gdshader`.
- `assets/materials/*.tres`: ready-made presets (see below).
- `scripts/art_style.gd` (`ArtStyle`): palette, faction rim, outlines, material factories,
  hit-flash / dissolve helpers.
- `autoload/corruption.gd` (autoload `Corruption`).
- Tools: `tools/style_test.*` (look-dev scene), `tools/style_shader_check.gd` (shader compile),
  `tools/style_audit.*` (off-pipeline material audit), `tools/style_perf.*` (blight GPU cost),
  `tools/icons/build_ability_icons.py` + `tools/icons/icon_sheet.gd`.
- `assets/icons/abilities/*.svg` (ability icons).

Surgical edits I made in shared files (please keep them when refactoring):
- `project.godot`: autoload `Corruption`, `[shader_globals]` `corruption_map / _params / _origin /
  _ambient / _quality`.
- `shaders/lit_common.gdshaderinc`: `instance uniform vec4 rim_color` (FLASHABLE, default off) and
  the `CORRUPTIBLE` define block; `shaders/lit_static.gdshader` defines `CORRUPTIBLE`.
- `scenes/world/ground.gdshader`, `shaders/terrain/terrain.gdshader`: include + 3-4 lines of blight.
- `shaders/foliage.gdshader`: per-plant wither (shrinks up to 35%, darkens / reddens).
- `scenes/enemies/enemy.gd`, `scenes/player/player.gd`, `scenes/ui/bestiary.gd` (seen entries),
  `scenes/characters/allies/demon_kit.gd` (`_ready`): one `ArtStyle.apply_faction(...)` line each.
- `scripts/toon.gd`: `Toon.material()` returns an `Art.mat()` (muted color) and `static_variant()`
  maps Art lit -> lit_static, so any legacy Toon content is on the Art pipeline.
- `scenes/basecamp/hub_interactable.gd`: `highlight` export + ember outline while focused;
  `hub_life.gd` points the bar at its succubus; `basecamp.gd` `BLIGHT := 0.6`.
- Palette fixes in other roles' content (round 2, see work log).

## 3. Corruption spread (autoload `Corruption`)
The demon blights the ground it walks on: a live aura around the player plus a trail that holds
for `hold_time` (14 s) then fades out by `lifetime` (32 s). Angel deaths leave a small blight spot.
The trail is a 256x256 RGF texture of "last blighted at" timestamps in world space (0.375 m per
texel, toroidal with a per-texel tile id, so it never ghosts). Cost: one ~250-texel stamp and one
texture upload every 0.1 s.

```gdscript
Corruption.stamp(pos, 3.0)        # blight a disc (radius m); strength < 1 fades sooner
Corruption.amount_at(pos)         # 0..1 trail strength on the CPU (gameplay: bonuses on blight?)
Corruption.ambient = 0.6          # scene-wide blight (Basecamp Hell); resets to 0 on scene change
Corruption.focus = node           # follow something other than Game.player (hub avatar)
Corruption.enabled = false        # e.g. a sanctuary that resists corruption
Corruption.quality = 1            # 0 off, 1 crust only, 2 full; follows the graphics preset
Corruption.clear()
# tunables: trail_radius, aura_radius, hold_time, lifetime, kill_stamp_radius, kill_stamp_strength
# dev args: --blight=<0..1> (force ambient in every scene), --blight-quality=<0|1|2>
```
In a shader:
```glsl
#include "res://shaders/style/corruption.gdshaderinc"
float c = corruption_at(world_pos);                    // 0..1, noise-frayed edge
corruption_blight(c, world_pos, col, rough, emit);     // ground / floors: char, ash, ember fissures
corruption_wither(c, col);                             // foliage, cloth, living things
corruption_char(c, world_pos, wn, col, rough, emit);   // props (wn = world normal); floors -> blight
```
Already wired: `ground.gdshader` (run maps), `terrain/terrain.gdshader` (TerrainPatch, also
tarnishes gold accents), `foliage.gdshader`, every `lit_static` material (all `Art` scenery).

Settings > Graphics > "Blight detail" (Off / Low / Full, `Settings.blight_quality`, part of the
presets) drives `Corruption.quality`.

Look of the blight: charred crust and ash with dried-blood patches; ember fissures whose density
follows a broad (~8 m) noise field (denser in the player's fresh trail than in ambient blight);
patches of cooled glossy obsidian with a faint deep-red glint in the seams; a smouldering rim on
the advancing front. Ambient blight is modulated by a ~15 m noise field (thin spots where the
original floor shows). Props: char creeps up walls with a ragged edge; their upward faces near the
ground (flagstones, plinths, steps) are treated as floor; ember glow only at the foot of walls and
only in the player's own blight (an ambient-blighted scene would otherwise get a glowing grid).

### Performance (round 2, `tools/style_perf.tscn`)
RTX 4070 Ti, 1280x720, Forward+, no enemies, median GPU frame time over 3 rounds:

| map | case | q2 full | q1 crust | q0 off |
|---|---|---|---|---|
| sunlit_citadel (heaven) | whole screen blighted (ambient 1) | 2.16 ms | 2.08 ms | 1.77 ms |
| sunlit_citadel | player trail only (normal run) | 2.19 ms | 2.05 ms | 1.96 ms |
| cathedral_city (many props) | ambient 1 | 1.83 ms | 1.92 ms | 1.60 ms |
| cathedral_city | trail only | 1.65 ms | 1.46 ms | 1.44 ms |

So ~0.2 ms (trail) to ~0.4 ms (worst case) on this GPU at 720p, roughly 10-20% of a light scene's
GPU time; expect a few ms at 1080p on low-end GPUs (noise between rounds is ~0.1-0.3 ms). Toggle:
`Corruption.quality` (global `corruption_quality` uniform, no shader recompiles). It follows
`Settings.graphics_preset`: **Low -> 1** (crust only: no Voronoi crack network, no prop char),
everything else -> 2. There is no docs/team/performance.md yet; the perf report lives in
`tools/perf/REPORT.md`.

## 4. Materials and shaders
| Preset (`assets/materials/`) | Shader | Use |
|---|---|---|
| `hellfire_rock.tres` | hellfire | rock with faint lava veins (Basecamp rocks, sigil stones) |
| `hellfire_lava.tres` | hellfire | mostly molten, hotter at the bottom (pools, brazier bowls) |
| `hellfire_brand.tres` | hellfire | small fast cracks, very hot rim (weapons, brands, horns) |
| `holy_halo.tres` | holy_glow | bright halo / ring, shimmer bands |
| `holy_aura.tres` | holy_glow | soft fresnel shell, soft depth contact (shields, auras) |
| `outline_elite.tres` / `outline_interact.tres` | outline_mask + outline | put on `material_overlay` |
| `lit_demon_hide.tres` / `lit_heaven_gold.tres` | lit (flashable) | demon skin, angel gilding |
| `lit_heaven_marble.tres` | lit_static | holy architecture (chars in the blight) |

Code factories (cached; never modify the returned material, it is shared):
```gdscript
ArtStyle.hellfire(molten = 0.35, energy = 3.0, crack_scale = 2.2, heat_gradient = 0.0)
ArtStyle.holy_glow(core = HEAVEN_WHITE, edge = HEAVEN_LIGHT, energy = 2.2, rim_weight = 0.65)
ArtStyle.outline_overlay(color, width_px = 2.5, pulse = 0.0, energy = 1.6)  # mask + hull chain
ArtStyle.outline_material(...)                    # hull pass alone (has interior lines)
```
`holy_glow` has `instance uniform float fade` (per-object fade without copying the material).

**Outlines without interior lines:** `outline_mask.gdshader` draws the body into the stencil
buffer (ref 64, no color) and its `next_pass`, the inverted hull, only draws where the stencil is
not 64. Both run in the transparent pass (mask `render_priority` 0, hull 1), i.e. after all opaque
geometry. Don't use stencil ref 64 for anything else.

**Corner gaps (round 3):** the hull direction comes from the instance uniform `outline_mode`, set
by `ArtStyle.outline()` per mesh: Box / Prism / Cylinder primitives (centred on their origin) push
each vertex away from the projected centre on both screen axes (shared corners get the same offset,
no gaps); rigid `ArrayMesh`es (GLB parts, ProcModel merged meshes) get a cached twin with averaged
normals in CUSTOM0 (swapped onto that MeshInstance only); skinned / blend-shape meshes keep NORMAL.

## 5. Character hooks
```gdscript
ArtStyle.apply_faction(model, ArtStyle.Faction.HOLY, elite)  # rim; elites also get a gold outline
ArtStyle.set_rim(model, Color(r, g, b, strength))           # Color(0,0,0,0) = off
ArtStyle.outline(node, ArtStyle.INTERACT, 3.0, 0.6)         # pulsing ember: shopkeepers, portals
ArtStyle.clear_outline(node)
ArtStyle.hit_flash(node, 0.15)                              # for things without their own flash timer
ArtStyle.dissolve(node, ArtStyle.Faction.DEMON, 0.9)        # burn away (frees the node)
```
These touch only meshes using the flashable lit shader (Art / GLB / ProcModel models) and work per
instance (instance uniforms, `material_overlay`), so shared cached materials are never changed.
Call `apply_faction` again after rebuilding a model. Basecamp: `HubInteractable.highlight`
(default: the interactable's own meshes) gets the pulsing ember outline while focused.

## 6. Look-dev / validation
- `godot --path . res://tools/style_test.tscn -- [--map=<id>] [--autopilot] --shot=out.png
  --shot-time=6 [--ambient=1]`: every preset next to the player (dialogue pause skipped).
- `godot --path . --script res://tools/style_shader_check.gd` (windowed) compiles the style shaders
  and everything that includes the corruption library.
- `godot --headless --path . res://tools/style_audit.tscn -- --map=<id> [--audit-all]` (or
  `--scene=res://scenes/basecamp/basecamp.tscn`): lists meshes off the Art pipeline (opaque lit
  StandardMaterial3D, Toon shaders, no material). Round 2: zero offenders on all five maps and the
  hub; glows (unshaded / additive StandardMaterial3D) are intentional and only counted.
- `godot --path . res://tools/style_perf.tscn -- --map=<id>` (windowed): blight GPU cost per quality.

## 7. Palette rules for new content (round-2 findings)
- Heaven never uses red / orange (hue < 35 deg) in emission or as a main albedo. Holy fire is
  gold-white (`Color(1.0, 0.8, 0.45)`), not orange. Small mortal details (a villager's torch) are ok.
- Heaven's colored glass: sky blue, gold, pale violet, azure, ivory.
- Infernal accents besides ember / blood: **soul rose** (`#c86a78`..`#ff4058`, necromancy and
  souls), **void violet** (shadow, curses), **bile** (desaturated olive-yellow, plague only). No pale
  ice-blue or white (that reads holy) and no neon green on the demon side.
- Large additive glow spheres: prefer `ArtStyle.holy_glow()` shells (soft fresnel edge) over flat
  `Art.glow()` discs.

- Heaven's cloth accents are royal navy / blue-violet (`Color(0.14, 0.16, 0.36)`), gold or ivory,
  never crimson. The Outer Gardens (Eden) may use pale sage / olive foliage greens on its own
  enemies and boss; their glow stays gold-white.
- Wind-up / hit flash on white or gold bodies is capped in the shader; big holy glow spheres stay
  at energy <= 2 so the silhouette survives the bloom.
- School colours, round 2 schools: Wrath red, Greed coin gold, **Envy jade** (`#58c070`),
  **Pride rose-gilt** (`#f2b89a`), Gluttony brown-orange, **Illusion lilac** (`#c8a8e8`),
  Infernal Machinery orange, Hellfire Whip orange-red. Cores lerp the school colour toward white,
  never pure white.

## 7b. Ability icons
`res://assets/icons/abilities/<id>.svg` (73: every ability + evolution), written by
`python tools/icons/build_ability_icons.py` from the abilities JSON: dark vignette disc (matches the
painted weapon / passive PNGs), soft glow in the ability colour, emblem from a motif library
(flame, nova, skull, ghost, eye, crown, maw, gear, lash, ...) with a light-to-dark gradient of the
colour and an ink outline. `Icons.for_ability(id)`; `Icons.for_option()` resolves ability options;
the HUD dock and ability chips use them. New ability: add a motif in `BY_ID` (else the kind's
fallback), re-run, then `godot --headless --path . --import`. Contact sheet:
`godot --headless --path . --script res://tools/icons/icon_sheet.gd -- --out=<abs png>`.

## 8. Notes for other roles
- **characters-polish**: rim light is `rim_color` (lit_common) / `ArtStyle.set_rim`; skins already
  recolor it. Swapping `EnemyModel.halo()` to `ArtStyle.holy_glow()` would give halos the shimmer.
- **characters-new**: `DemonKit` models now get the ember rim automatically. I changed a few colors
  in your enemies (see work log); tell me here if any of it breaks a design intent.
- **terrain / maps**: new floor shaders: include the corruption library (section 3).
- **basecamp**: `BLIGHT := 0.6` now (try others with `-- --blight=x`); interactables outline
  themselves when focused; set `highlight` on standalone ones placed next to a model. Shopkeepers
  wear the demon rim (`hub_shopkeeper.gd`).
- **ui**: "Blight detail" row in Settings > Graphics (`Settings.blight_quality`), ability icons
  (section 7b); notes in docs/team/ui.md.
- **abilities**: I moved three necromancy colors and two boons off mint / ice-blue (section 7).
- **visuals**: "corruption gloom" can read `Corruption.amount_at(player_pos)` or the globals.
- **performance**: blight cost and toggle in section 3.

## Work log
- Round 1: style guide, corruption autoload + library, hellfire / holy glow / outline shaders,
  presets, ArtStyle helper, rim light in lit_common, blight on ground / terrain / foliage / static
  props, faction rim on player and angels, elite outline.
- Round 2:
  - Pipeline migration: audit tool; runtime audit of all maps + hub found no opaque
    StandardMaterial3D / Toon meshes left. Legacy `Toon.material()` now returns Art materials;
    bestiary fallback + shadow blob moved to Art; bestiary previews get the holy rim.
  - Blight: crack density field, cooled-obsidian patches, ambient noise modulation, no ember grid
    on floor tiles / ambient scenes (the "bright smear" Basecamp saw), prop tops treated as floor.
    Basecamp re-enabled at 0.6.
  - Outlines: stencil mask pass, no interior lines; elite outline 2.2 px; .tres presets updated.
  - Perf: measured (section 3), `corruption_quality` global + `Corruption.quality` tied to the
    Low preset, dev args.
  - Consistency pass: seraph / throne / archangel flame -> holy gold-white; glass golem panes ->
    heaven glass palette; grand inquisitor coat crimson -> ivory; holy knight red cross -> gold;
    light elemental + seraph glow spheres -> holy_glow shells; succubus charm magenta -> soul rose;
    necromancy colors (raise_thralls, wraith_host, corpse_explosion, thrall minion, boons
    grave_lord / corpse_harvest) off mint / ice-blue; ember rim on all DemonKit allies / NPCs;
    ember outline on focused Basecamp interactables.
- Round 3:
  - Demon rim on Basecamp shopkeepers; `EnemyModel.halo()` -> `ArtStyle.holy_glow` rings (Art.part
    turns off shadows for holy_glow meshes).
  - Telegraph / hit-flash emission capped on bright albedo (lit_common); seraph, zealot and light
    elemental wind-up glows toned down (notes in docs/team/characters-polish.md).
  - VFX palette pass: round-2 school colours (Envy, Illusion, Pride + boons / synergies), no pure
    white cores in orbit / pride / retaliate / whip FX, smoked mirror glass; new enemies: choir
    wraith, mobile reliquary, templar ballista, witch hunter captain lost their crimson cloth.
  - "Blight detail" setting (Off / Low / Full).
  - Outline corner gaps fixed (`outline_mode`: radial for primitives, CUSTOM0 smoothed normals for
    rigid ArrayMeshes).
  - 73 ability icons as SVG + generator + contact-sheet tool, wired into Icons, level-up cards and
    the ability HUD.

## Bug report from characters-polish (round 3): focus outline fills Box / Cylinder parts
`ArtStyle.outline()` (HubInteractable focus) paints every BoxMesh / CylinderMesh / PrismMesh part of
a basecamp merchant solid outline-colour (the whole part, not just a rim); SphereMesh parts outline
correctly. It happens with the hub's ORIGINAL primitive merchants too (robe cones, aprons), and with
my new merchant figures. Converting those parts to ArrayMesh twins (smoothed-normal mode 2) did not
help, so it looks like the mask / hull pass order or depth for those parts. Repro:
`godot --path . res://tools/characters/merchants_test.tscn -- --focus --only=0,2 --sheet=<png>`
(`--old-merchants` shows the original figures).

**Fixed (round 4).** Cause: instance uniforms are packed per GeometryInstance by *index*, shared by
all materials on it. `outline_mode` (outline.gdshader) defaulted to slot 0, which is lit_common's
`flash`, so `ArtStyle.outline()` setting `outline_mode` 1 (primitives) or 2 (ArrayMesh twins) turned
on the white hit flash over the whole part. Now `instance uniform float outline_mode :
instance_index(8)`; lit_common documents that it owns slots 0..3. Rule for everyone: any overlay /
next_pass shader with instance uniforms must pick `instance_index(4+)`. Verified with
`merchants_test -- --focus` (old and new merchants: silhouette rims only) and the style test
(elite angel gold rim, outlined box with closed corners).
- Round 4: fixed the focus outline filling box / cylinder parts (instance-uniform slot collision
  between `outline_mode` and `flash`, see the bug report section).

## From terrain (round 2): corruption on the terrain shader
`shaders/terrain/terrain.gdshader` now multiplies `corruption_at()` by a uniform
`corruption_strength` (per theme: `TerrainTheme.corruption_strength`; heaven 0.8, others 1.0).
On the bright heaven ground the char crust read almost black and hard-edged in big trail patches.
0.8 softens the edge and lowers the coverage a little without changing your library. The Breach
also sets `Corruption.ambient = 0.45` through its map JSON (`"terrain": {"corruption": 0.45}`).
Please check the look (`main.tscn -- --map=gilded_isles` / `--map=the_breach`) and adjust these
two numbers if you want them stronger or weaker. Both live in my data files, so edit them directly.
