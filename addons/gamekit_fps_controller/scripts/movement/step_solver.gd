class_name StepSolver
extends RefCounted
## Collision-aware step-up (Source StepMove, done with Godot body test-motion on PhysX): when grounded
## horizontal motion is blocked by a steep face, sweep the capsule up, forward and down. If the real surface
## under the landing is walkable and no higher than the step height, the body is placed at the swept
## landing. Every leg is a shape cast, so the body never passes through geometry.
##
## A capsule's rounded bottom first lands on the step's corner, slightly below the step top. That is
## expected: the solver repeats on the following ticks as the capsule rolls over the corner, and the motor
## treats a successful step as grounded so gravity and floor snap do not pull it back off. Step-down is
## handled by CharacterBody3D.floor_snap_length.

const MIN_STEP := 0.02
const MIN_FORWARD_TRAVEL := 0.002
const WALKABLE_PROBE_INSET := 0.03
const RAY_REACH := 0.1

## Debug: last landing point tested and whether it was accepted.
var last_probe_point := Vector3.ZERO
var last_probe_accepted := false
var queries_this_tick := 0

var _body: CharacterBody3D
var _hit := KinematicCollision3D.new()
var _ray := PhysicsRayQueryParameters3D.new()


func _init(body: CharacterBody3D) -> void:
	_body = body
	_ray.exclude = [body.get_rid()]


## Tries to climb a step in the way of horizontal_motion. On success moves the body to the landing (this
## tick's horizontal motion included) and returns the height gained; 0 = no step. feet_y is the resting
## feet height; the body may currently be lifted slightly above it.
func try_step_up(horizontal_motion: Vector3, step_height: float, min_floor_normal_y: float, feet_y: float) -> float:
	queries_this_tick = 0
	if horizontal_motion.length_squared() < 1e-8:
		return 0.0

	var from := _body.global_transform
	# 1. Blocked at all? Walkable slopes are left to move_and_slide.
	if not _test(from, horizontal_motion) or _hit.get_normal().y >= min_floor_normal_y:
		return 0.0

	# 2. Up, as far as the ceiling allows (measured from the resting feet height).
	var max_up := step_height - (from.origin.y - feet_y)
	var up := _hit.get_travel().y if _test(from, Vector3.UP * max_up) else max_up
	if up < MIN_STEP:
		return 0.0
	var raised := from.translated(Vector3.UP * up)

	# 3. Forward at the raised height.
	var forward := horizontal_motion
	if _test(raised, forward):
		forward = _hit.get_travel()
		if forward.length_squared() < MIN_FORWARD_TRAVEL * MIN_FORWARD_TRAVEL:
			return 0.0
	var moved := raised.translated(forward)

	# 4. Down onto the step (or its corner).
	if not _test(moved, Vector3.DOWN * (moved.origin.y - feet_y + MIN_STEP)):
		return 0.0
	var landing := moved.origin + _hit.get_travel()
	var climbed := landing.y - feet_y
	last_probe_point = _hit.get_position()
	last_probe_accepted = false
	if climbed < MIN_STEP or climbed > step_height + 0.001:
		return 0.0

	# 5. The contact may be the step's edge, whose normal says nothing about the surface. Ray the real
	# surface just past the edge: it must be walkable and within step height of the feet.
	var probe := _probe_surface(_hit.get_position() + horizontal_motion.normalized() * WALKABLE_PROBE_INSET)
	if probe.is_empty() or probe.normal.y < min_floor_normal_y or probe.position.y - feet_y > step_height + 0.01:
		return 0.0

	last_probe_accepted = true
	_body.global_position = landing
	return climbed


## Keeps a grounded player on stairs and down small ledges when the engine's own floor snap fails (on PhysX
## it can, while the capsule rim still touches the edge it is leaving). Lifts off current contacts, sweeps
## down up to step_height, and accepts walkable floor, or an edge the capsule rests on when walkable ground
## lies directly below its centre. Returns true when grounded.
func try_snap_down(step_height: float, min_floor_normal_y: float, lift: float) -> bool:
	var from := _body.global_transform
	var up := _hit.get_travel().y if _test(from, Vector3.UP * lift) else lift
	var raised := from.translated(Vector3.UP * up)
	if not _test(raised, Vector3.DOWN * (step_height + up)):
		return false
	var landing := raised.origin + _hit.get_travel()
	var floor := _hit.get_normal().y >= min_floor_normal_y
	if not floor:
		# Resting on an edge: only grounded if there is walkable ground right under the centre.
		var probe := _probe_surface(landing + Vector3.DOWN * (step_height * 0.5), step_height * 0.5 + 0.05)
		if probe.is_empty() or probe.normal.y < min_floor_normal_y:
			return false
	_body.global_position = landing
	return true


func _test(from: Transform3D, motion: Vector3) -> bool:
	queries_this_tick += 1
	return _body.test_move(from, motion, _hit)


## Returns {position, normal} of the surface under `point`, or an empty dictionary.
func _probe_surface(point: Vector3, reach := RAY_REACH) -> Dictionary:
	queries_this_tick += 1
	_ray.from = point + Vector3.UP * reach
	_ray.to = point + Vector3.DOWN * reach
	_ray.collision_mask = _body.collision_mask
	return _body.get_world_3d().direct_space_state.intersect_ray(_ray)
