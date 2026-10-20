class_name PlayerMotor
extends RefCounted
## The movement simulation. Runs once per physics tick from FpsPlayerController: view yaw, abilities,
## stance, ground or air movement, then one move_body(). Horizontal motion uses Source-style
## accelerate/friction (MoveMath); vertical motion is gravity integrated half before and half after the
## move, which makes jump arcs exact at any tick rate.

signal jumped
## speed: downward speed at impact (m/s).
signal landed(speed: float)
## Vertical snap while grounded that is not explained by slope or platform motion (stairs). dy in m.
signal visual_step(dy: float)
signal state_changed(old_state: MovementState, new_state: MovementState)

## Mutually exclusive movement states. Crouch and sprint are concurrent modifiers, not states.
## CUSTOM: a game-defined ability is active (see MovementAbility.get_state_name()).
enum MovementState { GROUNDED, AIRBORNE, SLIDING, MANTLING, CLIMBING, SWIMMING, DISABLED, CUSTOM }

## Height the body is raised before grounded sweeps (see _lift_off_floor()).
const GROUND_LIFT := 0.02

var velocity := Vector3.ZERO
var state := MovementState.AIRBORNE
var is_on_floor := false
var is_sprinting := false
var floor_normal := Vector3.UP
var platform_velocity := Vector3.ZERO
var surface: Surfaces.SurfaceInfo = Surfaces.get_info(Surfaces.SurfaceType.DEFAULT)
var stance: PlayerStance
var steps: StepSolver
var penetration: PenetrationGuard
var time_since_grounded := 0.0
## Simulated seconds since spawn (deterministic clock for cooldowns).
var sim_time := 0.0
## Horizontal acceleration over the last tick (m/s²), for debug and camera tilt.
var horizontal_acceleration := Vector3.ZERO
## Abilities in priority order.
var abilities: Array[MovementAbility] = []
## The ability in control, or null during base ground/air movement.
var active_ability: MovementAbility

var jump_buffered: bool:
	get:
		return _jump_queued
var coyote_available: bool:
	get:
		return not is_on_floor and not _jumped_since_grounded and time_since_grounded <= settings.coyote_time
var settings: PlayerMovementSettings:
	get:
		return body.movement
var body: FpsPlayerController
var horizontal_velocity: Vector3:
	get:
		return Vector3(velocity.x, 0.0, velocity.z)
var jump_velocity: float:
	get:
		return MoveMath.jump_velocity(settings.jump_height, settings.gravity)
var min_floor_normal_y: float:
	get:
		return cos(deg_to_rad(settings.max_slope_degrees))

var _probe := KinematicCollision3D.new()
var _ground_check: RayCast3D
var _jump_queued := false
var _jump_queue_age := 0.0
var _jumped_since_grounded := false
var _jump_cut_available := false
var _sprint_toggled := false
var _last_floor_collider: Object
var _last_horizontal_velocity := Vector3.ZERO


func _init(p_body: FpsPlayerController, shape: CollisionShape3D, ground_check: RayCast3D) -> void:
	body = p_body
	_ground_check = ground_check
	steps = StepSolver.new(p_body)
	penetration = PenetrationGuard.new(p_body, shape)
	stance = PlayerStance.new(p_body, shape, p_body.movement)


## Replaces the ability list (priority order). An active ability that is no longer listed ends.
func set_abilities(list: Array[MovementAbility]) -> void:
	abilities = list.duplicate()
	if active_ability and active_ability not in abilities:
		_end_active_ability()


## First ability that is an instance of `type` (a script class such as SwimMovement), or null.
func get_ability(type: Variant) -> MovementAbility:
	for a in abilities:
		if is_instance_of(a, type):
			return a
	return null


func set_enabled(enabled: bool) -> void:
	if not enabled:
		_end_active_ability()
		velocity = Vector3.ZERO
		set_state(MovementState.DISABLED)
	elif state == MovementState.DISABLED:
		set_state(MovementState.AIRBORNE)


## Teleports with a clean state (respawn, tests).
func teleport(position: Vector3) -> void:
	_end_active_ability()
	body.global_position = position
	body.reset_physics_interpolation()
	velocity = Vector3.ZERO
	is_on_floor = false
	_jump_queued = false
	_jumped_since_grounded = true
	if state != MovementState.DISABLED:
		set_state(MovementState.AIRBORNE)


func tick(cmd: PlayerCommand, dt: float) -> void:
	body.rotation = Vector3(0.0, cmd.yaw, 0.0)
	if state == MovementState.DISABLED or dt <= 0.0:
		return

	sim_time += dt
	var prev_horizontal := horizontal_velocity
	if cmd.jump_pressed:
		_jump_queued = true
		_jump_queue_age = 0.0

	_update_sprint(cmd)

	if active_ability == null:
		for ability in abilities:
			if ability.can_begin(self, cmd):
				active_ability = ability
				ability.begin(self, cmd)
				set_state(ability.get_state())
				break

	if active_ability:
		if not active_ability.tick(self, cmd, dt):
			_end_active_ability()
	else:
		stance.update(cmd, is_on_floor)
		if is_on_floor:
			_ground_move(cmd, dt)
		else:
			_air_move(cmd, dt)

	horizontal_acceleration = (horizontal_velocity - prev_horizontal) / dt
	_jump_queue_age += dt
	if _jump_queue_age > settings.jump_buffer_time:
		_jump_queued = false
	if not is_on_floor:
		time_since_grounded += dt


# ---- Base movement -----------------------------------------------------------------------------

func _ground_move(cmd: PlayerCommand, dt: float) -> void:
	# Source checks the jump button before friction: a jump on the landing tick skips friction.
	if wants_jump(cmd):
		jump(cmd)
		_air_move(cmd, dt)
		return

	var s := settings
	var h := MoveMath.apply_friction(horizontal_velocity, s.friction * surface.friction, s.stop_speed, dt)
	var wish := wish_movement(cmd)
	h = MoveMath.accelerate(h, wish[0], wish[1], s.ground_acceleration * surface.friction, dt)
	velocity = Vector3(h.x, 0.0, h.z)
	move_body(dt, true, true)


func _air_move(cmd: PlayerCommand, dt: float) -> void:
	var s := settings
	if not is_on_floor and wants_jump(cmd) and coyote_available:
		jump(cmd)

	if s.variable_jump_height and _jump_cut_available and not cmd.jump_held and velocity.y > 0.0:
		velocity.y *= s.jump_cut_multiplier
		_jump_cut_available = false

	var wish := wish_movement(cmd)
	var h := MoveMath.air_accelerate(horizontal_velocity, wish[0], wish[1], s.air_acceleration, s.air_speed_cap, dt)
	velocity = Vector3(h.x, velocity.y, h.z)

	apply_half_gravity(dt)
	move_body(dt, false)
	if not is_on_floor:
		apply_half_gravity(dt)


func apply_half_gravity(dt: float) -> void:
	velocity.y = maxf(velocity.y - settings.gravity * dt * 0.5, -settings.max_fall_speed)


func wants_jump(cmd: PlayerCommand) -> bool:
	return _jump_queued or (settings.allow_bunny_hop and settings.auto_bunny_hop and cmd.jump_held)


## Starts a jump: absolute upward speed (consistent from slopes), plus clamped platform velocity.
func jump(cmd: PlayerCommand, apply_speed_cap := true) -> void:
	var s := settings
	if apply_speed_cap and not s.allow_bunny_hop and s.bunny_hop_speed_cap > 0.0:
		velocity = MoveMath.clamp_horizontal(velocity, s.bunny_hop_speed_cap * max_ground_speed(cmd))
	var from_floor := is_on_floor
	velocity.y = jump_velocity
	if from_floor:
		velocity += _inherited_platform_velocity()
	_jump_queued = false
	_jumped_since_grounded = true
	_jump_cut_available = true
	is_on_floor = false
	if active_ability == null:
		set_state(MovementState.AIRBORNE)
	jumped.emit()


func consume_jump_buffer() -> void:
	_jump_queued = false


# ---- Movement helpers shared with abilities ----------------------------------------------------

## Horizontal wish direction from the view yaw, and the wish speed for the current stance/sprint:
## [wish_dir: Vector3, wish_speed: float].
func wish_movement(cmd: PlayerCommand) -> Array:
	var basis := Basis.from_euler(Vector3(0.0, cmd.yaw, 0.0))
	var dir := basis * Vector3(cmd.move.x, 0.0, -cmd.move.y)
	var amount := minf(cmd.move.length(), 1.0)
	var wish_dir := dir.normalized() if amount > 1e-4 else Vector3.ZERO
	return [wish_dir, max_ground_speed(cmd) * amount]


## Full-input speed for the current stance, sprint and walk modifiers, and surface.
func max_ground_speed(cmd: PlayerCommand) -> float:
	var s := settings
	var speed: float
	if stance.is_crouched:
		speed = s.crouch_speed
	elif is_sprinting:
		speed = s.sprint_speed
	elif cmd.walk_held:
		speed = s.walk_speed
	else:
		speed = s.run_speed
	return speed * surface.speed_multiplier


func _update_sprint(cmd: PlayerCommand) -> void:
	var s := settings
	if s.sprint_toggle:
		if cmd.sprint_pressed:
			_sprint_toggled = not _sprint_toggled
		if cmd.move.length_squared() < 0.01:
			_sprint_toggled = false
	var wants := _sprint_toggled if s.sprint_toggle else cmd.sprint_held
	# Sprint state only changes on the ground, so air speed keeps the takeoff mode.
	if is_on_floor or state == MovementState.SWIMMING:
		is_sprinting = wants and not stance.is_crouched and cmd.move.y > s.sprint_min_forward_input


## The single place the body moves. Runs the step solver, move_and_slide, then landing, ceiling, platform,
## surface and prop-push bookkeeping. ground_move: walking/sliding. As in Source, these never produce
## vertical velocity, so sliding up a step corner or over a ramp crest cannot launch the player.
func move_body(dt: float, try_step: bool, ground_move := false) -> void:
	var s := settings
	var was_on_floor := is_on_floor
	var pre_velocity_y := velocity.y
	var pre_position := body.global_position

	_last_horizontal_velocity = horizontal_velocity
	if was_on_floor:
		_lift_off_floor()
	var climbed := 0.0
	if try_step and was_on_floor:
		climbed = steps.try_step_up(horizontal_velocity * dt, s.step_height, min_floor_normal_y, pre_position.y)
	var stepped := climbed > 0.0
	if stepped:
		# The step already moved the body this tick. A zero-motion slide still updates floor contact and
		# applies platform motion; the player's own velocity is kept for the next tick.
		body.velocity = Vector3.ZERO
		body.move_and_slide()
	else:
		body.velocity = velocity
		body.move_and_slide()
		velocity = body.velocity
	velocity = penetration.resolve(velocity)
	if ground_move:
		velocity.y = 0.0

	# A step counts as grounded even while the capsule's rim still rests on the step corner.
	var on_floor := stepped or (body.is_on_floor() and velocity.y <= jump_velocity * 0.5)
	if not on_floor and try_step and was_on_floor and not _jumped_since_grounded and velocity.y <= 0.0 \
			and steps.try_snap_down(s.step_height, min_floor_normal_y, GROUND_LIFT):
		on_floor = true
		velocity = penetration.resolve(velocity)
	if body.is_on_ceiling() and velocity.y > 0.0:
		velocity.y = 0.0

	if on_floor:
		floor_normal = body.get_floor_normal() if body.is_on_floor() else Vector3.UP
		if velocity.y < 0.0:
			velocity.y = 0.0
		time_since_grounded = 0.0
		_jumped_since_grounded = false
		_jump_cut_available = false
	elif was_on_floor and not _jumped_since_grounded:
		# Walked off a ledge or a moving platform: carry its motion, but never launch.
		velocity += _inherited_platform_velocity()

	if stepped:
		visual_step.emit(climbed)
	elif on_floor and was_on_floor:
		_detect_visual_step(pre_position, dt)

	is_on_floor = on_floor
	if not on_floor:
		platform_velocity = Vector3.ZERO
	elif body.is_on_floor():
		platform_velocity = body.get_platform_velocity()

	if active_ability == null:
		set_state(MovementState.GROUNDED if on_floor else MovementState.AIRBORNE)
	if on_floor and not was_on_floor:
		landed.emit(maxf(0.0, -pre_velocity_y))

	_update_surface(on_floor)
	if body.is_on_wall():
		_push_props(dt)


## Workaround for a verified PhysX-backend issue: when the capsule starts a motion test while touching the
## floor, the sweep can miss a wall ahead and the body ends up to one tick of motion inside it. Starting the
## grounded sweeps a hair above the floor avoids it; floor snap (always longer than the lift) returns the
## body to the floor in the same move.
func _lift_off_floor() -> void:
	var lift := _probe.get_travel().y if body.test_move(body.global_transform, Vector3.UP * GROUND_LIFT, _probe) else GROUND_LIFT
	if lift > 0.0:
		body.global_position += Vector3.UP * lift


func _inherited_platform_velocity() -> Vector3:
	var v := platform_velocity
	var max_speed := settings.max_platform_inherit_speed
	return v.normalized() * max_speed if v.length_squared() > max_speed * max_speed else v


func _detect_visual_step(pre_position: Vector3, dt: float) -> void:
	var delta := body.global_position - pre_position
	var dy := delta.y - platform_velocity.y * dt
	var horizontal := Vector2(delta.x, delta.z).length()
	var slope_allowance := horizontal * tan(deg_to_rad(settings.max_slope_degrees)) + 0.01
	if absf(dy) > slope_allowance:
		visual_step.emit(dy)


func _update_surface(on_floor: bool) -> void:
	if not on_floor or _ground_check == null:
		return
	_ground_check.force_raycast_update()
	var collider := _ground_check.get_collider() if _ground_check.is_colliding() else null
	if collider == _last_floor_collider:
		return
	_last_floor_collider = collider
	surface = Surfaces.from_collider(collider)


## Pushes rigid props the player walks into with a force-limited impulse. The impulse only makes up the
## speed difference along the push direction, scaled down for heavy props, so walking into a crate moves it
## at walking pace instead of launching it. Props above max_push_mass do not move.
func _push_props(dt: float) -> void:
	var s := settings
	for i in body.get_slide_collision_count():
		var collision := body.get_slide_collision(i)
		var prop := collision.get_collider() as RigidBody3D
		if prop == null or prop.freeze or prop.mass > s.max_push_mass:
			continue
		var dir := -collision.get_normal()
		dir.y = 0.0
		if dir.length_squared() < 1e-4:
			continue
		dir = dir.normalized()
		var desired_speed := maxf(0.0, _last_horizontal_velocity.dot(dir))
		var closing := desired_speed - prop.linear_velocity.dot(dir)
		if closing <= 0.0:
			continue
		var impulse := minf(prop.mass * closing, s.push_force * dt)
		prop.apply_impulse(dir * impulse, collision.get_position() - prop.global_position)


func set_state(new_state: MovementState) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	state_changed.emit(old, new_state)


func _end_active_ability() -> void:
	if active_ability == null:
		return
	var ability := active_ability
	active_ability = null
	ability.end(self)
	if state != MovementState.DISABLED:
		set_state(MovementState.GROUNDED if is_on_floor else MovementState.AIRBORNE)


## Lets abilities force grounded bookkeeping after moving the body themselves.
func set_floor_state(on_floor: bool) -> void:
	is_on_floor = on_floor
	if on_floor:
		time_since_grounded = 0.0
		_jumped_since_grounded = false
