class_name PlayerCameraEffects
extends Node3D
## Purely visual camera motion on its own transform layer below the pitch node: head bob, landing and jump
## kicks, strafe roll, acceleration tilt, breathing, recoil punch and sprint FOV. It never touches the view
## angles or the body, so aim and collision are unaffected. Every effect has its own switch and
## PlayerCameraSettings.motion_effects disables them all.

var _player: FpsPlayerController
var _camera: Camera3D
var _bob_phase := 0.0
var _bob_weight := 0.0
var _kick := 0.0
var _kick_velocity := 0.0
var _recoil := Vector2.ZERO
var _recoil_velocity := Vector2.ZERO
var _roll := 0.0
var _tilt := 0.0
var _breath_phase := 0.0


func _ready() -> void:
	_player = owner as FpsPlayerController
	_camera = get_node("Camera3D") as Camera3D
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	_player.motor.landed.connect(_on_landed)
	_player.motor.jumped.connect(_on_jumped)


## View punch in degrees (x = pitch up, y = yaw). Visual only; springs back.
func add_recoil(degrees: Vector2) -> void:
	if _player.camera_settings.motion_effects and _player.camera_settings.recoil:
		_recoil_velocity += degrees * 30.0


func _on_landed(impact_speed: float) -> void:
	var cam := _player.camera_settings
	if not cam.motion_effects or not cam.landing_kick or impact_speed < 1.5:
		return
	# Impulse sized so the spring's peak displacement is roughly the requested kick.
	var kick := minf(impact_speed * cam.landing_kick_per_speed, cam.max_landing_kick)
	_kick_velocity -= kick * sqrt(cam.kick_stiffness) * 1.6


func _on_jumped() -> void:
	var cam := _player.camera_settings
	if cam.motion_effects and cam.landing_kick:
		_kick_velocity -= cam.jump_kick * sqrt(cam.kick_stiffness) * 1.6


func _process(delta: float) -> void:
	var dt := delta
	var cam := _player.camera_settings
	var motor := _player.motor
	var s := _player.movement

	# Springs always integrate so a disabled effect settles instead of freezing mid-kick.
	var k := _spring(_kick, _kick_velocity, cam.kick_stiffness, cam.kick_damping, dt)
	_kick = k.x
	_kick_velocity = k.y
	var r := _spring_vec(_recoil, _recoil_velocity, cam.recoil_stiffness, cam.recoil_damping, dt)
	_recoil = r[0]
	_recoil_velocity = r[1]

	var basis := Basis.from_euler(Vector3(0.0, _player.view_yaw, 0.0))
	var local_vel := basis.inverse() * motor.horizontal_velocity
	var speed := motor.horizontal_velocity.length()

	var offset := Vector3.ZERO
	var roll := 0.0
	var tilt := 0.0
	var fov := cam.vertical_fov

	if cam.motion_effects:
		if cam.head_bob:
			var bobbing := motor.state == PlayerMotor.MovementState.GROUNDED and speed > 0.3
			var target := clampf(speed / s.run_speed, 0.0, 1.6) if bobbing else 0.0
			_bob_weight = lerpf(_bob_weight, target, MoveMath.smooth_factor(10.0, dt))
			# Phase advances with distance, so bob frequency matches footstep rate at any speed.
			_bob_phase += speed * dt / maxf(cam.bob_stride_length, 0.1) * TAU
			var amp := cam.bob_amplitude * _bob_weight * (cam.sprint_bob_scale if motor.is_sprinting else 1.0)
			offset.y += sin(_bob_phase * 2.0) * amp
			offset.x += sin(_bob_phase) * amp * 0.6

		if cam.breathing:
			_breath_phase += dt * cam.breathing_rate * TAU
			offset.y += sin(_breath_phase) * cam.breathing_amplitude

		if cam.landing_kick:
			offset.y += _kick

		if cam.strafe_roll:
			roll = -clampf(local_vel.x / maxf(s.run_speed, 0.1), -1.0, 1.0) * cam.max_roll_degrees

		if cam.acceleration_tilt and motor.state == PlayerMotor.MovementState.GROUNDED:
			var forward_accel := -(basis.inverse() * motor.horizontal_acceleration).z
			tilt = clampf(-forward_accel * cam.tilt_per_acceleration, -cam.max_tilt_degrees, cam.max_tilt_degrees)

		if cam.sprint_fov and motor.is_sprinting and speed > s.run_speed:
			fov += cam.sprint_fov_increase * clampf((speed - s.run_speed) / maxf(s.sprint_speed - s.run_speed, 0.1), 0.0, 1.0)

	_roll = lerpf(_roll, roll, MoveMath.smooth_factor(cam.roll_rate, dt))
	_tilt = lerpf(_tilt, tilt, MoveMath.smooth_factor(cam.tilt_rate, dt))
	var recoil := _recoil if cam.motion_effects and cam.recoil else Vector2.ZERO

	position = offset
	rotation = Vector3(deg_to_rad(_tilt + recoil.x), deg_to_rad(recoil.y), deg_to_rad(_roll))
	_camera.fov = lerpf(_camera.fov, fov, MoveMath.smooth_factor(cam.fov_rate, dt))


# Semi-implicit Euler damped spring toward zero; stable for the stiffness range used at >= 20 fps.
# Returns (x, v).
static func _spring(x: float, v: float, k: float, c: float, dt: float) -> Vector2:
	dt = minf(dt, 0.05)
	v += (-k * x - c * v) * dt
	x += v * dt
	return Vector2(x, v)


static func _spring_vec(x: Vector2, v: Vector2, k: float, c: float, dt: float) -> Array:
	dt = minf(dt, 0.05)
	v += (-k * x - c * v) * dt
	x += v * dt
	return [x, v]
