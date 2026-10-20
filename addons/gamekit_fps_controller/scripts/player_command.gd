class_name PlayerCommand
extends RefCounted
## One physics tick of player intent, analogous to Source's CUserCmd. Produced by PlayerInput from devices,
## or by tests/AI, and consumed by PlayerMotor. Keeping intent separate from devices makes movement
## deterministic and scriptable.

## x = strafe right, y = forward. Length is clamped to 1 (diagonals are normalized).
var move := Vector2.ZERO
## View angles in radians at the time of this tick.
var yaw := 0.0
var pitch := 0.0
var jump_held := false
var jump_pressed := false
var crouch_held := false
var crouch_pressed := false
var sprint_held := false
var sprint_pressed := false
var walk_held := false


func copy() -> PlayerCommand:
	var c := PlayerCommand.new()
	c.move = move
	c.yaw = yaw
	c.pitch = pitch
	c.jump_held = jump_held
	c.jump_pressed = jump_pressed
	c.crouch_held = crouch_held
	c.crouch_pressed = crouch_pressed
	c.sprint_held = sprint_held
	c.sprint_pressed = sprint_pressed
	c.walk_held = walk_held
	return c
