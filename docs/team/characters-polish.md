# Character polish (docs/team/characters-polish.md)

Status: round 3 landed (basecamp merchant figures, Blender angels shatter at the end of their death
clips, per-demon player deaths + the ASCENDANT victory pose, siege-model readability, ragdoll limb
hook for characters-new). Round 2 landed (exact flinch sources, all five demons' silhouettes, bosses' motion layer,
procedural enemies' flinch / telegraph / readability scale, faction death variety, basecamp
wardrobe) on top of round 1 (procedural motion, enemy flinch / telegraph, skins + picker). Scope: improve EXISTING character models (player demons first, then the existing
angels). No new enemy types (that is characters-new).

## Owned files
- `scripts/characters/character_motion.gd` (`CharacterMotion`): procedural secondary motion layer.
- `scripts/characters/demon_skins.gd` (`DemonSkins`): skin catalog, unlocks, selection, recoloring.
- `scripts/characters/skin_picker.gd` (`SkinPicker`): drop-in skin chooser UI row.
- `data/skins/skins.json`: skin definitions (format in its `_doc`).
- `shaders/characters/presence_ring.gdshader`: the player's ground brand.
- `scripts/characters/death_fx.gd` (`DeathFx`): faction death animations (shatter / ragdoll / crumble).
- `scripts/characters/enemy_polish.gd` (`EnemyPolish`): per-model readability scale + death style.
- `scripts/characters/hub_wardrobe.gd` (`HubWardrobe`): basecamp wardrobe (mirror, likeness, picker).
- `scripts/characters/merchants/*` (`MerchantFigure` + one script per merchant): basecamp merchants.
- `scripts/characters/demon_death.gd` (`DemonDeath`): per-demon death styles.
- `tools/characters/*`: test bench (`motion_test.tscn`), headless check (`characters_check.tscn`),
  game-camera lineup of every enemy (`lineup.tscn`, `--bosses`, `--spacing=`), death bench
  (`death_test.tscn`, `--models` for bare models), merchants bench (`merchants_test.tscn`),
  `dump_materials.gd`.
- `scenes/demons/demon_model.gd`: the player demon model (main editor).
- `tools/blender/models/demons/*.py`: demon mesh/animation sources.

Shared files touched surgically:
- `scenes/enemies/models/enemy_model.gd`: `pose_pivot`, `hit_from()`, wind-up telegraph glow,
  anticipation squash (see below). characters-new: please keep `pose_pivot` between `rig` and `glb`.
- `scenes/menu/demon_select.gd`: 3 small hooks for the SkinPicker (+ the hint text).
- Round 2 one-liners, all marked `# characters-polish` and listed in the owners' docs:
  `scenes/player/player.gd` + `scenes/enemies/enemy.gd` (hit source, docs/team/gameplay.md),
  `scenes/characters/proc_model.gd` (`wrap_pose_pivot`, docs/team/characters-new.md),
  `scenes/bosses/sariel_model.gd` + `inquisitor/inquisitor_model.gd` (docs/team/objectives.md),
  `scenes/basecamp/basecamp.gd` (wardrobe install + `_menu_open`, docs/team/basecamp.md),
  `scenes/basecamp/models/training_dummy.gd` (`jiggle_eyes` signature follows the base).

## CharacterMotion (procedural layer on Blender node rigs)
Adds what baked clips can't know: lean into acceleration / speed and bank into turns (on the
`spine` joint, so the feet stay planted), spring wing physics (sweep back on surges, outer wing
flares on turns, tips whip), pendulum dangles for every cape / robe / chain / hair / tabard chain
(inertia + air drag, each link lagging the one above), directional hit flinch, attack flare and
squash & stretch. It hooks `AnimationMixer.mixer_applied` and pre-multiplies a rotation onto each
joint after the clip pose is written (no accumulation; the next clip frame overwrites it).

```gdscript
var motion := CharacterMotion.attach(glb_model, facing_node, squash_pivot)  # null if no anims
motion.hit(from_dir_world, 1.0)   # flinch away from where the blow came from
motion.kick(0.8)                  # attack flourish (wings flare, small stretch)
motion.squash(-1.5)               # squash (-) / stretch (+) impulse on squash_pivot
motion.weight = 0.0               # fade out (death clips own the body)
motion.lean_accel / wing_accel / dangle_accel / ... # tuning vars, per character
```
Joints are found by name: `wing*` chains, FAMILIES prefixes (robe, cape, chain, hair, ...), the
lean joint (`spine`, else chest/body/core/hips). Motion is measured on physics ticks (physics
interpolation would otherwise read 0 / huge velocities per rendered frame).
Cost: player-only by design (~20-100 joints). Enemies use the cheap pose layer below instead.

DemonModel uses it automatically: `play_hurt(from_dir := ZERO)` (zero = toward the nearest
enemy), `play_attack()`, `play_cheer()`, `play_faint()` drive it.

## EnemyModel pose layer (all Blender angels, cheap)
- `pose_pivot` (between `rig` and `glb`, owned by the base): flinch + squash only.
- `hit_from(from_dir_world, strength)`: tips the body away from a blow. `jiggle_eyes()` (called by
  `Enemy.take_damage`) already calls it with the direction from the player.
- Wind-up telegraph: the body kindles white over the last ~45 % of WINDUP, flickering faster as
  the strike nears (`telegraph_glow`, default 0.3, 0 = off), plus a crouch that releases into a
  stretch on `play_attack()` (`anticipation_squash`, default 0.05). Landing squash from `land_kick`.
- Fast path: nothing runs while an angel just walks (perf: hundreds of enemies).

## Skins (DemonSkins + SkinPicker)
Skins are palette swaps of the Blender demons, defined in `data/skins/skins.json`: per-material-
category albedo tints (skin / trim / horn / metal / cloth, from the Blender material names) or flat
replacements (gold plate), plus one glow color for eyes / embers / runes, the demon's light,
embers, ash, presence ring and its faction rim light. Skins: True Form, Ashen Penitent (finish a
run), Soulfire (slay a boss), Bloodsworn (win a run), Voidborn (finish at Heat 3+), Gilded Heretic
(find 10 relics), plus progression's per-demon mastery skins and Archfiend Ascendant (unlock ids
`mastery:<demon>:<level>`, answered by `Progression.is_unlocked`).

```gdscript
DemonSkins.list_for(&"vharok")            # Array[Dictionary] that fit this demon
DemonSkins.is_unlocked(skin) / DemonSkins.unlock_hint(skin)
DemonSkins.selected_id(&"vharok")         # what it wears (locked / unknown -> &"default")
DemonSkins.select(&"vharok", &"soulfire") # saves (Progression flag "skin:<model id>")
DemonSkins.demon_id_of(demon_data)        # model id key
demon_model.set_skin(&"soulfire")         # preview (rebuild + roar), doesn't save
var picker := SkinPicker.new(); panel.add_child(picker); picker.show_for(demon_model)
```
`DemonModel.build(data, skin := &"")` wears the saved choice by default, so the run, menus and the
basecamp all show it with no extra code. Unlocks read `Progression.stats` (runs, victories,
bosses_slain, relics_found, highest_heat) or `Progression.is_unlocked(id)` for shop-bought skins
(`"unlock": {"unlock": "<id>"}` in skins.json). Dev args `--all-skins` / `--unlock-all` unlock all
for the session. The demon select screen has the picker (W / S, or the arrows next to SKIN); the
basecamp `HubAvatar` wears the saved skin automatically.

For progression / basecamp: if you want skins sold in a shop (Mother Marrow fits), add an unlock
entry with `"kind": "skin"` in `data/progression/unlocks.json` and point the skin's `unlock` at its
id; nothing else is needed on my side. A wardrobe in the basecamp only needs a DemonModel + a
SkinPicker.

## Player presence
`DemonModel.show_presence(on)`: a faint ring of turning rune dashes + an ember pool on the ground
under the demon, in the skin's glow color; pulses on hits, fades on death. On automatically when
the DemonModel sits under a node in group `player` (the run), off in menus / basecamp.

## Models (Blender, rebuilt + rebaked)
Goal: every demon reads from the high game camera by its silhouette and a glow accent.
- Vharok: wings 1.32x (`WING_SCALE` in vharok.py).
- Skarn: two furnace smokestacks on the back with glowing mouths (venting embers: DemonModel
  attaches a small ember plume to every `fx_embers*` joint), wider + thicker horns, glowing seams on
  the pauldrons.
- Morvane: antler crown at full size (was 0.78x) with hexfire points on the top tines; the grimoire
  light (the "purple floor glow": an OmniLight at hip height pooling on the floor) is now 0.6 energy,
  2 m range and lifted above the book.
- Ysolde: horns swept ~25 % wider and thicker, soul-fire burning at the tips.
- Lilaeth: feather ember edges 1.3 -> 3.2 emission so the wing outline traces from above.

## Exact hit directions
- Player: `Player.take_damage(amount, source)` sets `DemonModel.hit_source` (trusted 150 ms);
  `play_hurt()` flinches away from it, else from the nearest enemy (contact damage).
- Enemies: `Enemy.take_damage(amount, knockback)` passes `-knockback` to
  `EnemyModel.jiggle_eyes(strength, from_dir)` (zero = away from the player); `last_hit_from` keeps
  it for the death (ragdolls fall away from the killing blow).

## Bosses
- Sariel: `CharacterMotion.attach(_glb, self, null, _tree)` (motion layer on an AnimationTree that
  is advanced by hand: physics delta is used then): 6 wings x feathers, veil, robe strips, torso
  lean, flinch, attack flare; `weight` follows kneel / dissolve.
- Grand Inquisitor (code-built): wrapped in `pose_pivot` for the flinch.
- The Gate Archon (Blender archon at boss size) already has the motion layer (big angels >= 1.5).
- `CharacterMotion.attach(model, frame, pivot := null, mixer := null)`: pass any AnimationMixer.

## Procedural enemies (characters-new's 30+ ProcModels)
- All are wrapped in `EnemyModel.pose_pivot` after build (one line in ProcModel): directional hit
  flinch, wind-up crouch -> strike stretch, white wind-up telegraph, landing squash.
- `EnemyPolish.VISUAL_SCALE`: readability scale on the pivot (collision untouched) for models that
  vanished at the game camera: ophan 1.9, clockwork_cherub 1.45, choir_wraith / martyr_shade 1.25,
  cherub / bell_gargoyle 1.15, the hooded casters 1.08-1.1. Judge with `lineup.tscn`.

## Death variety (DeathFx)
`EnemyModel.death_burst` tries `DeathFx.try_play(model, death_variant, last_hit_from, elite)` before
the model's own corpse. `death_variant` comes from `EnemyPolish` (CharacterRoster faction):
- angels / elementals SHATTER: a white-hot crack, the parts burst outward spinning, shrink and wink
  out in motes (0.8 s);
- mortals / orders / beasts RAGDOLL: cool from the hit flash, topple away from the killing blow with
  a bounce and a sideways twist, legs / arms flop loose, dust on impact, lie still, sink + burn (1.8 s);
- constructs CRUMBLE: parts drop under gravity, bounce once, dust bursts, the rubble sinks (1.25 s).
Caps: 6 new per frame, 24 alive; past them the model's default corpse plays. Blender angels keep
their death clips. Overrides: `EnemyPolish.DEATH_STYLE` (martyr_shade, light_wyrm shatter).
Bench: `godot --path . res://tools/characters/death_test.tscn -- --sheet=<png> [--only=ids]`.

## Basecamp wardrobe
`HubWardrobe` ("Vanity of the Fallen", next to the summoning circle): obsidian mirror + dais with the
chosen demon's likeness in its saved skin. "Change skin" opens a window with a turning preview and
the SkinPicker (A / D, W / S, arrows; E / Esc / Done close); closing re-skins the hub avatar and the
likeness. `HubWardrobe.open_now` blocks the hub's other input. Dev: `-- --hub-wardrobe`.

## Checks
`godot --headless --path . res://tools/characters/characters_check.tscn`: skins load / gate /
recolor, the motion layer attaches and reacts, the enemy flinch and telegraph work (exit code =
failures; never writes the save).
Cost (microbench): motion layer ~35 us/frame for Vharok (19 joints), ~0.3 ms for Ysolde (120).

## Test bench
`godot --path . res://tools/characters/motion_test.tscn -- --demon=vharok --sheet=out.png`
(or `--enemy=archon`, `--skin=soulfire --all-skins`, `--view=game|side|front`, `--at=t,t,...`,
`--debug` prints the spring values). Scripted course: idle, sprint, dead stop, hit from the front,
hard circle, attack, hit from behind, death (angels: wind-up telegraph + strike instead).

## Round 3
### Basecamp merchants (`MerchantFigure`)
Code-built articulated figures replacing the hub's primitives (HubShopkeeper hook, see
docs/team/basecamp.md): shoulder / elbow / hand pivots, head, torso, props, each with a craft idle
and greet / sale reactions. Grimmaul: hunched forge-brute, ember seams and ember beard, ram horns,
apron, bracers, hammer + tongs + anvil; three blows with sparks, then inspects the ingot. Vesper:
fallen angel in violet-black robes, void hood, cracked violet halo, torn drooping wings; reads and
turns the floating grimoire's pages, wisps orbiting. Mammon's Clerk: pot-bellied, waistcoat and
tailcoat, gold top hat with soul gem, monocle, gilt horns; flicks and catches soul coins, inspects
every fourth through the monocle. Ossek: lanky wanderer, greatcoat, wide hat pierced by horns,
satchel of scrolls, staff with a hanging soul lantern; ponders, turns and traces his map.
`MerchantFigure.create(look)`, `animate(delta, near)`, `greet()`, `react()`; rig helpers `arm()`,
`set_arm()`, `horn()`, `sparks()` for further hub characters.

### Blender angels shatter
`EnemyModel.spawn_corpse` (pooled "death" clip copies) ends with `_finish_corpse`: a snapshot of the
corpse's meshes (shared mesh / material resources) shatters into light via
`DeathFx.shatter_snapshot(source, color, scale, big)` and the corpse returns to its pool at once.
Past the DeathFx caps it shrinks / sinks as before.

### Player deaths and victory
- `DemonDeath` (driven by DemonModel's dissolve after the demon's own Blender "death" clip):
  Vharok burns to ASH where he kneels; Lilaeth's parts rise and spin away as burning FEATHERS
  (ember feathers burst); Morvane spirals into the grimoire's light with a HEX ring on the ground;
  Skarn's furnace bursts and his iron body CRUMBLES (parts drop, tumble, bounce, settle dark);
  Ysolde UNRAVELS: the robes sink empty into the ground while her souls fly free.
  `DemonDeath.STYLE_BY_DEMON` maps model ids; revive / rebuild restores every part.
- `DemonModel.play_victory()`: the "cheer" roar held at its peak (arms flung wide), light and
  presence brand blazing, ember bursts every ~1 s; PROCESS_MODE_ALWAYS so it keeps going behind
  the ASCENDANT screen. The player's demon calls it itself on `RunState.run_ended` with
  `victory = true` (no edits elsewhere). Bench: `motion_test.tscn -- --victory`.

### Readability (lineup)
Siege pieces read as small carts beside knights from the game camera: `templar_ballista` 1.3,
`mobile_reliquary` 1.2, `bell_gargoyle` 1.25 (visual only). The new bosses (ProcBoss models and
Sariel / Gate Archon) all read large and distinct; they get the pose pivot (flinch, telegraph) via
ProcModel; their deaths stay with ProcBoss (`corpse_on_death = false`).

### Ragdoll limbs
DeathFx flops `_legs` / `_arms` fully and every other `_animated` pivot gently; a model can return
its real limbs from `ragdoll_limbs() -> Array` (asked of characters-new in their doc).

## Round 4
- Nhazgul, the Plague Hive (Vharok's rig and clips): `DemonModel.MOTION_PROFILES[&"nhazgul"]` gives
  him an insectile feel on the shared motion layer: random sharp twitches of spine / wings / gear
  (`CharacterMotion.twitch`, `twitch_interval`), a fast wing buzz added after the springs
  (`buzz_amp`, `buzz_hz`), stiffer, twitchier springs, insect head ticks instead of slow glances
  ("tics"), and a sickly yellow-green presence brand ("presence"; skins still recolour it).
  Death `&"swarm"` (DemonDeath): the body shudders, each part pops outward and is gone in a buzzing
  cloud of flies with glowing larvae (plus the `plague` sound). Skins: his chitin is "horn", hive
  wax "trim" for every palette; progression's `mastery_nhazgul` works as is.
  Any demon can get a profile: CharacterMotion property names (suffix `*` multiplies).
- Demon select: a "Favoured school: X (+10% damage, offered 3x as often)" line from
  `Abilities.affinity_for(demon id)` under the starting weapon (3 marked lines).
- Map-signature enemies (16): readability scales (hummingbird cherub 2.2, bell-ringer monk, rod
  acolyte, crusader revenant 1.15, sun priest 1.1), death overrides (revenant / icebound penitent /
  thorn guardian crumble), ragdolls flop their `ragdoll_limbs()`; telegraph + flinch via the pivot.

## Round 5
- Iscariel, the Turncoat (Lilaeth's rig): death `&"turncoat"` (DemonDeath): the charred wing
  crumbles first (pieces drop and tumble, a puff of soot), the body burns away top-down, and the
  pale wing burns last, lifting and curling, in a burst of white-gold feathers. The charred chain is
  found from its "Burnt" feather material (it is the `_R` chain, his right as he faces you).
- Asymmetric wings: CharacterMotion `wing_odd_side` (+1 right / -1 left), `wing_odd_k`,
  `wing_odd_amp`, `wing_odd_twitch`; Iscariel's charred wing is 2.4x stiffer, moves at 45 % and
  twitches on its own. Presence brand: pale holy gold (1.0, 0.8, 0.42).
- Foot slide: `tools/characters/measure_stride.gd` measures a walk clip's planted-foot speed; Lilaeth's
  and Iscariel's clip covers 7.2 m/s (authored WALK_SPEED; the table said 7.05), now corrected.
- Skin coverage: every Iscariel material falls in a category (feathers / silk / robe = cloth,
  burnt gold + charred halo = trim, armour = metal, claws / thorns = horn), glows recolour.
- Honour guard: shatters correctly (the earlier "still standing" was its pair companion, which the
  old bench never killed; `death_test` now kills every enemy incl. companions).

## Known issues / next
- `_roster_check.gd` reports "allies / NPCs alive and animating" failing; it failed the same way
  before my changes (not caused by the pose pivot).
- Ragdolls fall through nothing (no collision): on slopes / stairs a body may clip a prop.
- Readability scale is visual only; very small enemies are still small hitboxes.
- The hub focus outline (ArtStyle.outline) fills box / cylinder parts of merchants with colour
  (pre-existing, original figures too): reported to art-style with a repro.

## Note from art-style (round 3, small marked edits; tell me in docs/team/art-style.md if unwanted)
- `EnemyModel.halo()` now uses `ArtStyle.holy_glow` (white core -> colour edge, shimmer) for both
  rings instead of `Art.glow` (comment "art-style round 3" in `enemy_model.gd`).
- Wind-up telegraph bloom: the flash / telegraph emission in `lit_common.gdshaderinc` is now scaled
  down on bright albedo (white robes, marble, gold keep ~40%), dark bodies keep 100%. `telegraph_glow`
  is unchanged. The seraph (face 2.6 -> 1.8, halo 3.5 -> 2.6, smaller face swell), zealot fuse
  (2.2 -> 1.6) and light elemental core (3.0 -> 2.0, less charge growth) were toned down
  (characters-new's files, marked).
- Basecamp shopkeepers wear the demon rim (`hub_shopkeeper.gd`), like DemonKit allies / NPCs.


## Note from progression (round 2): mastery skins
Appended 6 skins to `data/skins/skins.json` (same one-line style): `mastery_vharok`, `mastery_lilaeth`,
`mastery_morvane`, `mastery_skarn`, `mastery_ysolde` (each limited to its demon, mastery V) and `archfiend`
(any demon, mastery X on any demon). Their `unlock` is `{"unlock": "mastery:<model id>:<level>"}` /
`"mastery:any:10"`, which `Progression.is_unlocked()` resolves, so `DemonSkins` needed no changes.
Feel free to retune the palettes.

## Note from abilities (round 3): shared composable scale, ScaleStack
`scripts/scale_stack.gd` (`ScaleStack`): several systems can each own a named scale factor on any
Node3D; the node's scale is base x product(factors), so nobody overwrites anybody.
`ScaleStack.set_factor(node, &"my_source", 1.1)` (1.0 removes it), `factor(node, source)`,
`set_base(node, scale)` if you legitimately own the node's own scale. Gluttony's Girth now uses it on
`Player/Body` (`&"girth"`, up to x1.32) instead of writing `body.scale`. If the demon model or a skin
ever scales `Player/Body` itself, please go through `ScaleStack.set_base()` / a factor so the two
compose. Nothing else of yours was changed.

## Note from characters-new (round 4): ragdoll_limbs()
Added `ragdoll_limbs() -> Array` to the beasts, riders and siege models (holy_horse -> unicorn /
pegasus / mounted_knight, holy_lion, griffon, gryphon_rider, cherubim, bell_gargoyle, paschal_lamb,
light_wyrm, hellhound, templar_ballista, mobile_reliquary, crossbow_militia) and most round-4
signature enemies. Built with `ProcModel.limbs_with(extra)` (legs + arms + named pivots).
New demon `nhazgul` (Blender pipeline, Vharok's rig): I added it to `WALK_CLIP_SPEED` (5.44, marked)
and `DemonDeath.STYLE_BY_DEMON` (ash); add a `mastery_nhazgul` look tweak or a custom death if you like.

## Note from performance (round 2)
Skin-baked horde types (`ProcModel.SKIN_BAKE_TYPES`, see docs/team/characters-new.md) have 1-2
skinned MeshInstances instead of one per part, so `DeathFx` shatter / crumble on them flies one or two
pieces (the whole body) instead of every part. If that matters for a type, either set
`skin_bake = false` for it, or have DeathFx split by bone (the bone list is `ProcModel._skin_rig.nodes`).
Elite death bursts are now x2 instead of x3 (capped) with feathers / debris a frame later
(`EnemyModel.death_burst`, perf).

## Note from characters-new (round 5): Iscariel + death mechanics
- New demon `iscariel` (Blender pipeline, Lilaeth's rig; generated by
  `tools/blender/models/demons/_iscariel_from_lilaeth.py`): added to `WALK_CLIP_SPEED` (7.05, the
  Lilaeth walk) and `DemonDeath.STYLE_BY_DEMON` (feathers). The left wing is scaled 0.74 and charred;
  a custom death where the white wing burns last, or a mastery look in `mastery_iscariel`, are yours.
- Enemy death mechanics no longer live in `death_burst`: `Enemy.die()` emits `died` and calls
  `model.on_host_died(enemy)` before `model.death_burst()`, so DeathFx can replace any corpse freely.

## Note from performance (round 3): GlbSkin on the Blender horde
At load, `GlbModel.setup()` converts the six common Blender enemies (`GlbSkin.TYPES`: seraph_sentinel,
choir_wisp, dawn_lancer, ophanim, penitent_statue, thurible_priest) into one skinned mesh on a
Skeleton3D, with the clips retargeted to bone tracks (`scripts/perf/glb_skin.gd`). The .glb files and
your Blender pipeline are untouched; it's a runtime post-import step, cached per file. Poses checked
identical (`tools/perf/skin_compare.tscn`). For your code: joints are bones on those models, so use
`glb_node(name)` / `GlbModel.joint(name)` (returns a BoneAttachment3D), not `scene_root.find_child`.
CharacterMotion models (size >= 1.5: archon, bosses) are not converted. To exclude a model, remove it
from `GlbSkin.TYPES`.
