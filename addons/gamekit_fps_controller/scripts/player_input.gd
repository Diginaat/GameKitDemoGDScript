class_name PlayerInput
extends Node
## Turns devices into view angles and PlayerCommands. Mouse look is applied to the controller the moment
## the event arrives (no smoothing, no acceleration), so the camera, which reads the angles every rendered
## frame, never lags the mouse.

## Source's m_yaw/m_pitch: degrees per mouse count at sensitivity 1.
const DEGREES_PER_COUNT := 0.022

var mouse_captured: bool:
	get:
		return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

var _player: FpsPlayerController


func _ready() -> void:
	InputActions.ensure_defaults()
	_player = get_parent() as FpsPlayerController
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and mouse_captured:
		var cam := _player.camera_settings
		var scale := deg_to_rad(DEGREES_PER_COUNT * cam.mouse_sensitivity)
		# screen_relative is unaffected by window stretch, so sensitivity does not change with resolution.
		var rel: Vector2 = e.screen_relative
		_player.add_look(-rel.x * scale, (rel.y if cam.invert_y else -rel.y) * scale)
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed(InputActions.RELEASE_MOUSE):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed and not mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


## Samples the current device state. Called from the physics tick, so "just pressed" is per physics frame.
func build_command() -> PlayerCommand:
	var cmd := PlayerCommand.new()
	if not mouse_captured:
		return cmd
	# get_vector clamps the length to 1, which normalizes diagonals.
	cmd.move = Input.get_vector(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT, InputActions.MOVE_BACK, InputActions.MOVE_FORWARD)
	cmd.jump_held = Input.is_action_pressed(InputActions.JUMP)
	cmd.jump_pressed = Input.is_action_just_pressed(InputActions.JUMP)
	cmd.crouch_held = Input.is_action_pressed(InputActions.CROUCH)
	cmd.crouch_pressed = Input.is_action_just_pressed(InputActions.CROUCH)
	cmd.sprint_held = Input.is_action_pressed(InputActions.SPRINT)
	cmd.sprint_pressed = Input.is_action_just_pressed(InputActions.SPRINT)
	cmd.walk_held = Input.is_action_pressed(InputActions.WALK)
	return cmd
