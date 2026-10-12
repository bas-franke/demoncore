# Survivors Base

A 3D, orthographic-camera Vampire Survivors-style base for Godot 4.7. Placeholder primitives only, so you can swap in real art.

## Controls
WASD / arrows / left stick: move. Weapons fire automatically. Esc / Start: pause.
Debug builds: **F1** instant level-up, **F2** toggle damage numbers.

## Layout
| Path | What |
|---|---|
| `autoload/game.gd` | `Game` singleton: player ref, world node, timer, kills, `Game.spawn()` |
| `scenes/main.tscn` | Run root: lights, ground, camera rig, spawner, UI |
| `scenes/player/` | `Player`: movement, stats, XP/levels, weapon + passive ownership |
| `scenes/enemies/` | Generic `Enemy` scene + `EnemyData` resource |
| `scenes/spawner/` | `EnemySpawner` + `SpawnRule` (enemy, start/end time, weight) |
| `scenes/weapons/` | `Weapon` base class, `Projectile`, and three weapons |
| `scenes/pickups/` | XP gems (tiered by value) |
| `scenes/ui/` | HUD, level-up, pause, game over |
| `scripts/upgrades/` | Level-up option rolling, `PassiveData` |
| `data/` | Enemy and passive `.tres` files |

## Extending
- **New enemy:** duplicate a file in `data/enemies/`, change its mesh and stats, then add a `SpawnRule` for it on `Main/EnemySpawner`.
- **New passive:** duplicate a file in `data/passives/`, set `stat` to any numeric `Player` property, then add it to `Player.passive_pool`.
- **New weapon:** make a scene whose root script `extends Weapon`. Override `attack()` (called every cooldown) and `_on_level_changed()`, fill in `level_descriptions` (one line per level), then add the scene to `Player.weapon_pool`.
- **Camera:** `Main/CameraRig/Camera3D`. `size` sets the zoom and `rotation.x` the tilt. If you change them, adjust `EnemySpawner.spawn_radius` so enemies still spawn off screen.

## Physics layers
1 world, 2 player, 3 enemies, 4 pickups. Enemies collide with each other but not with the player. Contact damage comes from the player's `Hurtbox`.

## Dev args
`godot --path . -- --autopilot --shot=out.png --shot-time=30` runs a bot that auto-picks upgrades and saves a screenshot.
