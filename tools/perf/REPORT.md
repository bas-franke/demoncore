# SINBOUND performance report
Machine: Ryzen 5 7600X / RTX 4070 Ti, Vulkan Forward+, 1280x720, vsync off, Godot 4.7.2. Bench: res://tools/perf/bench.tscn.

## TL;DR
CPU-bound in physics. At 300 enemies one 60 Hz physics step costs ~20-30 ms (> 16.7 ms frame), so Godot runs max_physics_steps_per_frame (8) every frame and frames collapse from ~25 ms to 150-200 ms. Disabling only enemy _physics_process: 203 ms → 42 ms.

| phase (full2 15:36) | avg ms | fps | 1% low | GPU ms | phys steps/frame | draw calls | visible prims |
|---|---|---|---|---|---|---|---|
| baseline | 1.56 | 640 | 468 | 1.2 | 0.1 | 272 | 79k |
| 150 enemies | 25.4 | 39 | 18 | 5.7 | 1.6 | 1565 | 694k |
| 300 enemies | 144.5 | 6.9 | 5.0 | 28.1 | 8 | 2089 | 1.31M |
| +400 shards | 168.3 | 5.9 | 4.6 | 32.0 | 8 | 2379 | 1.42M |
| +boss | 187.3 | 5.3 | 4.3 | 32.9 | 8 | 2761 | 1.48M |
| +all weapons | 203.4 | 4.9 | 3.8 | 19.7 | 8 | 3034 | 1.73M |
| same, enemy AI off | 42.4 | 23.6 | 13.2 | 10.7 | 2.6 | 2337 | 0.79M |

Per-enemy microbench (300 enemies): Enemy._physics_process 52-76 µs (16-23 ms/step; enemy.gd:103). move_and_slide 44-65 µs vs 8-16 µs without enemy-vs-enemy collision (enemy.gd:129; enemy.tscn collision_mask=5). Art.flash 43-88 µs/call (art.gd:190; enemy.gd:150 per frame, enemy.gd:391 per hit). AnimationPlayer.advance 14-33 µs; EnemyModel.animate 5-11 µs. Enemy spawn 2.2-4.0 ms each (enemy_spawner.gd:93, glb_model.gd setup/convert_materials, enemy.gd _ready). Shard spawn 1.4-2.4 ms each (xp_gem.gd:97). XPGem._physics_process 3-5 µs each (xp_gem.gd:51).

## Prioritized bottlenecks
- **P0 Physics spiral** — physics_ticks_per_second=30 (interpolation already on), max_physics_steps_per_frame=2-3; then get a step under ~8 ms with P1-P3. *(Applied by integrator.)*
- **P1 Enemy-enemy collision** — mask=1 (world only) in enemy.tscn + spatial-hash separation force (or direct integration + separation) in enemy.gd; expect -10-15 ms/step. Separation is needed or enemies collapse onto the player.
- **P2 Art.flash recursion** — cache flashable GeometryInstance3D list once per model; skip unchanged values; better: set a flash start time once and fade in shader from TIME. Same for demon_model.gd:175.
- **P3 Spawn hitches** — pool enemies + shards; convert GLB materials once per model path then duplicate; static HolyTelegraph materials; cache capsule shapes per size. Late-game ~15 spawns/s → 30-60 ms of spikes per second.
- **P4 Soul shards** — +400 cost +24 ms, +290 draw calls, ~600 GeometryInstances. Replace with a SoulShardField manager (3 MultiMeshes by tier, custom data for spin/pop, motion in shader, packed arrays, distance pickup, no per-shard Area3D); update enemy.gd:418 (_drop_xp O(n) scan) and player.gd:230.
- **P5 Enemy meshes** — rigid multi-part GLBs: lancer 20 meshes/46 nodes/4.9k tris/20 shadow casters; ophanim 20/52/4.6k/20; sentinel 21/48/4.9k/21; priest 13/29/4.9k/10; statue 8/22/3.4k/8; wisp 10/26/1.1k/0. At 300: ~3.7k shadow casters, 0.9M shadow prims (shadows off: 946k→120k shadow prims, 21.7k→8.8k render objects). Join each enemy into one skinned mesh in build.py; body-only shadows or blob shadows; visibility_range/LOD (none set today); for 300+ consider VAT + MultiMesh per type. (GLB swap already cut visible prims 65% vs old primitive art.)
- **P6 GPU (secondary)** — 20-33 ms at 300 enemies; cumulative ladder: shadows off 30.6 → models hidden 21.8 → VFX hidden 22.4 → post FX off 13.1 ms. Drop DoF near blur, SSAO quality 0/1 + half_size, fewer glow levels, sun shadow distance 55→35-40, offer FXAA/TAA vs MSAA 2x. Cap/pool death bursts (enemy_model.gd:399 spawns 10-20 nodes + tweens per death). Watch vfx_haze screen copy.
- **P7 Shader-global buffer** — buffer_size=524288 (8 MB) vs ~14-35k used slots; 131072 is plenty after merging; keep lit_static for non-flashing things.
- **P8 Misc** — script errors are perf hazards (a mid-edit sfx.gd caused ~8.9k "play on Nil" errors/min → 0.7 fps); 22-27 pipeline compiles per run (pre-warm); lights and particles fine; O(n) group scans in targeting.gd:9, infernal_chain.gd:109, ravagers_cleave.gd:67, foliage.gd:414, game_feel.gd:318 → use a shared spatial grid; cap Label3D damage numbers (57-126 alive).

## Order of work
1) physics settings 2) flash cache 3) collision mask + separation 4) pooling + convert-once materials 5) shard MultiMesh 6) merged skinned enemies + body-only shadows 7) post-FX quality, VFX pooling, buffer size.

## How to run
`powershell -File tools/perf/run_bench.ps1 -Label X [-Extra "--bench-phases=a,b" | "--bench-short"]`, then `tools/perf/show_summary.ps1`. Bench keeps the player stationary/invulnerable with xp_gain=0, spawns enemies in view, tops up enemies/shards each frame, keeps the boss alive; diag_* phases are cumulative.
