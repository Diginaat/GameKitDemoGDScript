class_name PlayerCameraController
extends Node3D
## Places the camera rig every rendered frame. The rig is top-level with physics interpolation off: its
## position comes from the body's interpolated transform plus the eye height, and its rotation straight from
## the controller's view angles, so aiming has zero added latency while position stays smooth at any frame
## rate.
##
## Eye height (crouch) and stair-step smoothing are advanced per physics tick and interpolated with the same
## fraction as the body, so they cancel the body's discontinuities instead of fighting them.

## The rendering camera.
var camera: Camera3D
## The camera's photographic finish (child of `camera`), if the scene has one.
var lens: CameraLens

var _player: FpsPlayerController
var _pitch: Node3D
var _eye_prev := 0.0
var _eye_curr := 0.0
var _step_prev := 0.0
var _step_curr := 0.0
var _lens_from: PlayerCameraSettings


func _ready() -> void:
	_player = get_parent() as FpsPlayerController
	_pitch = get_node("Pitch") as Node3D
	camera = get_node("Pitch/Effects/Camera3D") as Camera3D
	for child in camera.get_children():
		if lens == null and child is CameraLens:
			lens = child
	top_level = true
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	# Run before the player each physics tick so offsets added by this tick's events are interpolated from zero.
	process_physics_priority = -10

	_eye_curr = _player.motor.stance.eye_height
	_eye_prev = _eye_curr
	_player.motor.visual_step.connect(func(dy: float) -> void: _step_curr -= dy)
	# Airborne crouch moves the feet; shift the eye the other way so the view does not jump.
	_player.motor.stance.changed.connect(func(_crouched: bool, feet_shift: float) -> void: _eye_curr -= feet_shift)
	camera.fov = _player.camera_settings.vertical_fov
	camera.keep_aspect = Camera3D.KEEP_HEIGHT


func _physics_process(delta: float) -> void:
	var cam := _player.camera_settings
	if cam != _lens_from:
		# Settings swapped (profile / reduced motion): apply its lens look.
		_lens_from = cam
		if lens and cam.lens:
			lens.profile = cam.lens
	_eye_prev = _eye_curr
	_step_prev = _step_curr
	_eye_curr = lerpf(_eye_curr, _player.motor.stance.eye_height, MoveMath.smooth_factor(cam.crouch_smoothing_rate, delta))
	var max_lag := _player.movement.step_height * 1.5
	_step_curr = clampf(_step_curr * (1.0 - MoveMath.smooth_factor(cam.step_smoothing_rate, delta)), -max_lag, max_lag)


func _process(_delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	if not get_tree().physics_interpolation:
		f = 1.0
	var eye := lerpf(_eye_prev, _eye_curr, f) + lerpf(_step_prev, _step_curr, f)
	var origin := _player.get_global_transform_interpolated().origin
	global_transform = Transform3D(Basis.from_euler(Vector3(0.0, _player.view_yaw, 0.0)), origin + Vector3.UP * eye)
	_pitch.rotation = Vector3(_player.view_pitch, 0.0, 0.0)


## Snaps smoothing after teleports so the camera does not glide.
func reset_smoothing() -> void:
	_eye_curr = _player.motor.stance.eye_height
	_eye_prev = _eye_curr
	_step_prev = 0.0
	_step_curr = 0.0
