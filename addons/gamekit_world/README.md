# gamekit_world

Level building blocks. Depends on: `gamekit_core`.

| Type | What it is |
| --- | --- |
| `LadderVolume` | Area3D: climbable region; tells ladder-user bodies when they enter and leave |
| Ladder user (duck typed) | Bodies with `on_ladder_entered(ladder)` and `on_ladder_exited(ladder)` climb (`FpsPlayerController` does) |
| `MovingPlatform` | AnimatableBody3D: cosine travel (`travel`, `period`) and spin (`spin_degrees_per_second`) |

## Ladder setup

1. Area3D with `LadderVolume` and a `BoxShape3D` covering the climbable face.
2. Layer Triggers (4), mask the climbers' layer (Player, 2). `Monitorable` can be off.
3. Rotate it so its local +Z points away from the wall, toward the climber.
4. Make it a little taller than the top ledge so climbers hop off onto it.

## Moving platforms

Any `AnimatableBody3D` (with *Sync to Physics* on) moved by animation or code carries the player.
`MovingPlatform` is a ready-made one; put it on layer World (1).
