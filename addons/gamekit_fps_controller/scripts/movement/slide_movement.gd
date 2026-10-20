class_name SlideMovement
extends MovementAbility
## Sprint + crouch starts a slide: crouched capsule, a small speed boost, low friction, gravity pulling along
## slopes and light steering. Ends when slow, airborne, after crouch is released, or by jumping.

var _elapsed := 0.0
var _cooldown_until := 0.0


func get_state() -> PlayerMotor.MovementState:
	return PlayerMotor.MovementState.SLIDING


func can_begin(motor: PlayerMotor, cmd: PlayerCommand) -> bool:
	var s := motor.settings
	return s.slide_enabled \
		and cmd.crouch_pressed \
		and motor.is_on_floor \
		and motor.is_sprinting \
		and motor.sim_time >= _cooldown_until \
		and motor.horizontal_velocity.length() >= s.slide_min_start_speed


func begin(motor: PlayerMotor, _cmd: PlayerCommand) -> void:
	_elapsed = 0.0
	motor.stance.crouch(true)
	motor.velocity += motor.horizontal_velocity.normalized() * motor.settings.slide_start_boost


func tick(motor: PlayerMotor, cmd: PlayerCommand, dt: float) -> bool:
	var s := motor.settings
	_elapsed += dt

	if motor.wants_jump(cmd):
		# Slide-jump keeps slide speed (no bunny-hop cap) and stays crouched until the stance code stands up.
		motor.jump(cmd, false)
		motor.apply_half_gravity(dt)
		motor.move_body(dt, false)
		return false

	var released := cmd.crouch_pressed if s.crouch_toggle else not cmd.crouch_held
	if released or not motor.is_on_floor:
		return false

	# Past the max duration friction ramps up to normal ground friction.
	var friction := s.slide_friction if _elapsed < s.slide_max_duration else s.friction
	var h := MoveMath.apply_friction(motor.horizontal_velocity, friction * motor.surface.friction, 0.5, dt)

	# Gravity component along the floor plane: speeds up downhill, slows uphill.
	var n := motor.floor_normal
	var downhill := (Vector3.DOWN - n * Vector3.DOWN.dot(n)) * s.gravity
	h += Vector3(downhill.x, 0.0, downhill.z) * dt

	var wish := motor.wish_movement(cmd)
	h = MoveMath.air_accelerate(h, wish[0], wish[1], s.air_acceleration, s.air_speed_cap, dt)

	motor.velocity = Vector3(h.x, 0.0, h.z)
	motor.move_body(dt, true, true)
	return motor.is_on_floor and motor.horizontal_velocity.length() > s.slide_end_speed


func end(motor: PlayerMotor) -> void:
	_cooldown_until = motor.sim_time + motor.settings.slide_cooldown
