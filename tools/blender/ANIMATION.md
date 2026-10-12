# SINBOUND animation guide (`sbanim`)

`tools/blender/sbanim.py` sits on top of `sb.anim`: you describe motion as **keyed offsets with
per-key eases + procedural layers**, `clip.bake()` samples every frame and calls `sb.anim(name, keys)`.
Output is the usual NLA track -> glTF -> Godot animation. Nothing in `sb.py` changes.

Reference rig showing every feature: `models/_anim_demo/_knight.py` (idle, walk, fly, attack, hit, death).

## Workflow (look at your motion)

```
blender -b --factory-startup --python tools/blender/anim_preview.py -- demons/vharok walk
blender -b --factory-startup --python tools/blender/anim_preview.py -- demons/vharok          # every anim
blender -b ... anim_preview.py -- demons/vharok attack --at 0,10,15,17,18,20,26,40 --view side --trace hand_R
```
-> `tools/blender/previews/<cat>_<name>_<anim>_sheet.png`: a grid of frames from a FIXED ortho camera
over a 0.5 m grid. Coloured lines show the motion arcs of the most-moving end joints, and a dot marks
where each joint is on that frame. Things to check: arcs are smooth, spacing changes
(slow-in/slow-out), feet don't slide or sink, holds read as holds, and the loop's first and last frames match.
Options: `--frames N --cols C --size PX --view side|front|back|three|top|game --at f,f,f --range a:b
--trace a,b|none --eevee`. It takes about 2 s per sheet (Workbench). Build with `build.py` as usual.

## Clip basics

```python
import sb, sbanim as A

c = A.Clip("attack", 40, joints=A.joints(root))   # joints=: key EVERY joint (no stale pose in Godot)
c.key(arm, 0)                                       # rest (offset 0)
c.key(arm, 12, rot=(-150, 0, 20), ease="quad_in")  # ease = segment LEAVING this key
c.key(arm, 16, rot=(-30, 0, 10), ease="sine_out")
c.pose(30, {arm: {"rot": (0, 0, 0)}, chest: {"rot": (5, 0, 0), "loc": (0, 0, -0.02)}}, mirror=True)
c.add(head, lambda f: (0, 3 * A.wave(c, f, cycles=2), 0))   # additive procedural layer (deg)
c.bake()
```
* Values are **offsets from rest**. `rot` is in degrees (Euler XYZ, added to rest), `loc` is in metres
  (added), and `scale` is a multiplier.
* Loop clips (`idle walk run fly hover loop`, or `loop=True`) wrap automatically. Frame `frames` equals frame 0,
  and the tangents are seamless, so you don't need a closing key.
* A single key means a constant pose for the whole clip, which is handy for "wings folded during walk".
* `c.mirror(src, dst=None, phase=0.5)` copies src's whole motion, mirrored, to the other side (`arm_L`
  pairs with `arm_R`, as do `.L/.R` and `Left/Right`). `pose(..., mirror=True)` keys both sides.
* `c.hold(f_from, f_to, joints=[...])` creates a hold. `c.events` stores impact frames returned by the generators.

Axes (character faces Blender -Y, joint with ~zero rest rotation): **rot X +** swings a hanging limb
BACK, tips an upward chain (spine/head) FORWARD, and turns a foot toe-DOWN. **rot Y +** tips the +X (left) side down.
**rot Z +** moves the left side back (yaw). For the mirror side, negate Y and Z rotation and X location.

## Eases (per key, applies to the segment leaving that key)

| ease | use |
|---|---|
| `smooth` (default) | auto-clamped spline, the Blender default feel, no overshoot |
| `spline` | Catmull-Rom with overshoot, for fluid arcs |
| `linear` | mechanical, constant speed (a planted foot sliding back) |
| `constant` / `snap` | holds, then pops at the next key (flashes, VFX meshes, eye blinks) |
| `*_in` (`quad_in`, `cubic_in`, `expo_in`) | slow start that hits the next key FAST (strikes, falling bodies) |
| `*_out` | fast start that settles into the next key (snaps, recoils, landing) |
| `*_inout`, `in`, `out`, `inout` (cubic) | ordinary pose-to-pose |
| `back_out[:s]`, `elastic_out[:period]`, `bounce_out` | overshoot, wobble, bounce |

Families: `sine quad cubic quart quint expo circ back elastic bounce`. You can also pass a callable `u -> 0..1`.

## Generators (all additive; combine freely in one clip)

```python
A.breathe(c, chest, amp=2, rise=0.008, swell=0.015, cycles=2, shoulders=[arm_L, arm_R], head=head)
A.noise(c, head, rot=(3, 5, 2), freq=0.4, seed=1)        # living drift (loop-safe Perlin)
A.jitter(c, arm_R, rot=(1.5, 1, 1.5), start=12, end=17)   # tremble/strain in a window
A.walk(c, {"hips": hips, "spine": spine, "chest": chest, "head": head,
           "thigh": (tL, tR), "shin": (sL, sR), "foot": (fL, fR), "arm": (aL, aR), "fore": (oL, oR)},
       stride=24, knee=60, stance=0.6, arm=18, lean=7, twist=9, heavy=0.4)
A.stride_speed(leg_len=0.9, stride=24, frames=32)        # m/s that matches the stride (no foot skating)
A.wing_beat(c, [wing_L, wing_mid_L, wing_tip_L], amp=42, down=0.36, lag=0.08, flex=36, sweep=22,
            feathers=[(feather_joint_L, s_0_to_1), ...], body=hips, lift=0.07)
A.overlap(c, [tail0, tail1, tail2, tail3], delay=2, decay=0.85)      # wave: animate tail0, tip follows
A.overlap(c, plume_chain, source=head, delay=2.5)                     # drag: lags the head, settles
A.follow_through(c, cape_chain, freq=2.0, damping=0.14, gravity=6, falloff=0.85, wind=None, floor=None)
ev = A.attack(c, {"antic": {...}, "strike": {...}, "follow": {...}}, antic=12, antic_hold=5, strike=3,
              hold=5, recover=16, overshoot=0.12)                     # ev["impact"] = damage frame
A.hit_react(c, {hips: {"loc": (0, .07, 0)}, chest: {"rot": (-14, 3, 8)}, head: {"rot": (-18, 0, -10)}},
            rise=2, settle=13, stagger=1)
A.death(c, body, fall=(-84, 0, 6), drop=(0, .25, .16), buckle_pose={...}, limp_pose={...}, recoil={...})
```
* **walk**: the left foot makes contact at phase 0 and the right at 0.5. Stance is the linear sweep with the foot planted
  and flat (heel strike, then flat, then toe-off). Swing is the knee fold followed by an eased reach. `auto_bob` derives the hip
  height from the leg angles so the lowest foot stays on the ground. The pelvis yaw and roll are counter-rotated by the torso,
  the arms swing opposite the legs with drag, and the head stabilises. Tune `heavy` (0..1) for brutes, `stride`/`knee` for
  gait size, and `stance` for heavier contact (0.65) or lighter (0.55).
* **wing_beat**: the downstroke is fast (`down` = fraction of the cycle) with the wing extended and feathers spread. The upstroke is slow,
  with the outer links folding and sweeping back and the feathers closing. Each link lags its parent by `lag` cycles, so the tip whips.
  Axes are for the +X wing (`down_axis`, `sweep_axis`, `twist_axis`, `feather_axis`), and the right side is mirrored automatically.
* **follow_through** is a verlet chain pinned at `chain[0]` that springs toward the keyed pose. It reacts to
  EVERYTHING else in the clip (walk bob, lunges, falls). Loops are pre-rolled so the seam is clean. Use
  `floor=0.03` for capes on a corpse and `wind=(0, 6, 0)` for streaming in flight. The chain must be a parent chain.
* **attack** timeline: rest, then a slow antic, then a moving hold (`push`), then an accelerating strike
  (`quad_in`), then IMPACT at `strike * (1 + overshoot)`, then a settling hold, then the follow pose, then an eased recovery. Keep
  `strike` at 2-4 frames and `hold` at 3-6. Snap a VFX mesh on and off with `ease="constant"` keys around `ev["impact"]`.
* **death**: stagger away, knees buckle, topple (`quad_in`, which reads as gravity), then impact, 2 decaying
  bounces, and limbs flopping into `limp_pose` (back_out). `body` must pivot at the feet. Raise `drop.z` so the
  torso rests ON the ground, not in it, and check this with the contact sheet.

## Upgrading existing raw `sb.anim` code (no rewrite)

```python
sb.anim("idle", keys)                 # existing code
A.cyclic("idle")                      # Cycles modifier: seamless loop tangents (no hitch at the seam)
A.interpolate("hit", "BACK", "EASE_OUT")   # Blender interpolation on every key of that clip
keys[j] = A.make_cycle(keys[j], 60)   # force last key == first
```

## Quality checklist
1. Every clip keys every joint (`joints=A.joints(root)`), because Godot keeps stale transforms otherwise.
2. Attacks: the anticipation lasts at least 2x as long as the strike, the impact holds for 3-6 frames, and something overshoots.
3. Loops: use whole `cycles` for every periodic layer (`A.wave(c, f, cycles=2)`, `noise` handles this itself).
4. Add secondary motion to anything that dangles (capes, chains, tails, hair, banners, wings at rest).
5. Look at the contact sheet before you call a clip done.
