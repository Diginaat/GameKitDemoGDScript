class_name MantleMovement
extends MovementAbility
## Climbs onto ledges between PlayerMovementSettings.mantle_min_height and mantle_max_height while jump and
## forward are held. Detection sweeps the real capsule: up (headroom), forward (space on top), down
## (landing), then rays the landing for a walkable normal. The climb itself moves the body with
## move_and_collide(), up then forward, and aborts if anything blocks it, so it can never pass through
## geometry.

const LANDING_CLEARANCE := 0.02

var _hit := KinematicCollision3D.new()
var _ray := PhysicsRayQueryParameters3D.new()
var _target := Vector3.ZERO
var _forward := Vector3.ZERO
var _climbing := false
var _elapsed := 0.0


func get_state() -> PlayerMotor.MovementState:
	return PlayerMotor.MovementState.MANTLING


func can_begin(motor: PlayerMotor, cmd: PlayerCommand) -> bool:
	var s := motor.settings
	if not s.mantle_enabled or cmd.move.y < 0.5 or motor.stance.is_crouched:
		return false
	# Grounded: on the jump press. Airborne: while jump is held and not still rising fast.
	var trigger := cmd.jump_pressed if motor.is_on_floor else cmd.jump_held and motor.velocity.y < motor.jump_velocity * 0.6
	return trigger and _find_ledge(motor, cmd)


func _find_ledge(motor: PlayerMotor, cmd: PlayerCommand) -> bool:
	var s := motor.settings
	var body := motor.body
	var from := body.global_transform
	_forward = Basis.from_euler(Vector3(0.0, cmd.yaw, 0.0)) * Vector3.FORWARD

	# A wall right in front?
	if not body.test_move(from, _forward * s.mantle_reach, _hit) or _hit.get_normal().y > motor.min_floor_normal_y:
		return false
	var wall_distance := _hit.get_travel().length()

	# Headroom straight up.
	var up := _hit.get_travel().y if body.test_move(from, Vector3.UP * s.mantle_max_height, _hit) else s.mantle_max_height
	if up < s.mantle_min_height:
		return false
	var raised := from.translated(Vector3.UP * up)

	# Over the ledge: move past the wall by the capsule radius so the landing is on top, not on the edge.
	var over := _forward * (wall_distance + s.radius + 0.05)
	if body.test_move(raised, over, _hit):
		return false
	var above := raised.translated(over)

	# Down onto the top.
	if not body.test_move(above, Vector3.DOWN * up, _hit):
		return false
	var ledge_height := up + _hit.get_travel().y
	if ledge_height < maxf(s.mantle_min_height, s.step_height) or ledge_height > s.mantle_max_height:
		return false
	if not _is_walkable(body, _hit.get_position() + _forward * 0.05, motor.min_floor_normal_y):
		return false

	_target = from.origin + Vector3.UP * (ledge_height + LANDING_CLEARANCE) + over
	return true


func _is_walkable(body: CharacterBody3D, point: Vector3, min_normal_y: float) -> bool:
	_ray.from = point + Vector3.UP * 0.15
	_ray.to = point + Vector3.DOWN * 0.15
	_ray.collision_mask = body.collision_mask
	_ray.exclude = [body.get_rid()]
	var result := body.get_world_3d().direct_space_state.intersect_ray(_ray)
	return not result.is_empty() and result.normal.y >= min_normal_y


func begin(motor: PlayerMotor, _cmd: PlayerCommand) -> void:
	_climbing = true
	_elapsed = 0.0
	motor.consume_jump_buffer()
	motor.velocity = Vector3.ZERO


func tick(motor: PlayerMotor, _cmd: PlayerCommand, dt: float) -> bool:
	var s := motor.settings
	var body := motor.body
	_elapsed += dt
	var step := s.mantle_speed * dt
	var pos := body.global_position

	# Up first until level with the target, then forward.
	var motion: Vector3
	if pos.y < _target.y - 0.001:
		motion = Vector3.UP * minf(step, _target.y - pos.y)
	else:
		var flat := Vector3(_target.x - pos.x, 0.0, _target.z - pos.z)
		if flat.length() <= 0.001:
			return _finish(motor)
		motion = flat.limit_length(step)

	var collision := body.move_and_collide(motion)
	# Blocked (something moved into the way) or taking far too long: abort and fall back to normal movement.
	if (collision and collision.get_remainder().length() > 0.01) or _elapsed > 2.0:
		_climbing = false
		return false
	motor.velocity = motion / dt
	return true


func _finish(motor: PlayerMotor) -> bool:
	_climbing = false
	motor.velocity = _forward * minf(motor.settings.walk_speed, 2.0)
	return false


func end(motor: PlayerMotor) -> void:
	if _climbing:
		motor.velocity = Vector3.ZERO
	_climbing = false
