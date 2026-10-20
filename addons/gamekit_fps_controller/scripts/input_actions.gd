class_name InputActions
## Action names and default bindings. Defaults are registered at startup only for actions the project's
## Input Map does not define, so bindings stay editable in Project Settings.

const MOVE_FORWARD := &"move_forward"
const MOVE_BACK := &"move_back"
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const JUMP := &"jump"
const CROUCH := &"crouch"
const SPRINT := &"sprint"
const WALK := &"walk"
const INTERACT := &"interact"
const FIRE := &"fire"
const ALT_FIRE := &"alt_fire"
const RELOAD := &"reload"
const WEAPON_1 := &"weapon_1"
const WEAPON_2 := &"weapon_2"
const HOLSTER := &"holster"
const RELEASE_MOUSE := &"release_mouse"
const DEBUG_OVERLAY := &"debug_overlay"
const DEBUG_DRAW := &"debug_draw"
const CYCLE_PROFILE := &"cycle_profile"
const TOGGLE_ACCESSIBILITY := &"toggle_accessibility"
const CYCLE_TICK_RATE := &"cycle_tick_rate"
const CYCLE_FPS_CAP := &"cycle_fps_cap"
const RESPAWN := &"respawn"

static var _registered := false


static func ensure_defaults() -> void:
	if _registered:
		return
	_registered = true
	_key(MOVE_FORWARD, [KEY_W])
	_key(MOVE_BACK, [KEY_S])
	_key(MOVE_LEFT, [KEY_A])
	_key(MOVE_RIGHT, [KEY_D])
	_key(JUMP, [KEY_SPACE])
	_key(CROUCH, [KEY_CTRL, KEY_C])
	_key(SPRINT, [KEY_SHIFT])
	_key(WALK, [KEY_ALT])
	_key(INTERACT, [KEY_E])
	_mouse(FIRE, MOUSE_BUTTON_LEFT)
	_mouse(ALT_FIRE, MOUSE_BUTTON_RIGHT)
	_key(RELOAD, [KEY_R])
	_key(WEAPON_1, [KEY_1])
	_key(WEAPON_2, [KEY_2])
	_key(HOLSTER, [KEY_3])
	_key(RELEASE_MOUSE, [KEY_ESCAPE])
	_key(DEBUG_OVERLAY, [KEY_F3])
	_key(DEBUG_DRAW, [KEY_F4])
	_key(CYCLE_PROFILE, [KEY_F1])
	_key(TOGGLE_ACCESSIBILITY, [KEY_F2])
	_key(CYCLE_TICK_RATE, [KEY_F5])
	_key(CYCLE_FPS_CAP, [KEY_F6])
	_key(RESPAWN, [KEY_F9])


static func _key(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key: Key in keys:
		var e := InputEventKey.new()
		e.physical_keycode = key
		InputMap.action_add_event(action, e)


static func _mouse(action: StringName, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)
