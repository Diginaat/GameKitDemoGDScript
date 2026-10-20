class_name CollisionLayers
## Physics layer bits the GameKit modules assume (names in Project Settings > Layer Names > 3D Physics).
## Bodies: world geometry on WORLD, the player on PLAYER (mask WORLD | PROPS), rigid props on PROPS.
## Volumes (water, ladders) sit on TRIGGERS and mask the bodies they react to.

## Layer 1: static and animated level geometry.
const WORLD := 1 << 0
## Layer 2: player characters.
const PLAYER := 1 << 1
## Layer 3: rigid props (pushable, pickable).
const PROPS := 1 << 2
## Layer 4: trigger volumes (water, ladders).
const TRIGGERS := 1 << 3
