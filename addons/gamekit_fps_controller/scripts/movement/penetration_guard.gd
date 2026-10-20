class_name PenetrationGuard
extends RefCounted
## Pushes the capsule out of any geometry it ended a move inside, and removes velocity into those surfaces.
## Needed on the PhysX backend: its body motion test keeps only the closest sweep hit, so a surface the
## capsule already touches (a wall in a corner, the floor) can hide the real obstacle, and the move ends up
## to one tick of motion inside it. The overlap query used here (collide_shape -> computePenetration) is a
## separate, reliable code path. The query capsule is shrunk by SKIN so ordinary resting contact is not
## treated as overlap.

const SKIN := 0.005
const MAX_ITERATIONS := 4
const MAX_RESULTS := 16

## Total correction applied on the last call (debug).
var last_correction := Vector3.ZERO

var _body: CharacterBody3D
var _shape_node: CollisionShape3D
var _query_shape := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


func _init(body: CharacterBody3D, shape_node: CollisionShape3D) -> void:
	_body = body
	_shape_node = shape_node
	_query.shape = _query_shape
	_query.exclude = [body.get_rid()]


## Resolves overlaps at the current pose and returns `velocity` without its parts into the surfaces it was
## pushed out of. last_correction tells how far the body moved.
func resolve(velocity: Vector3) -> Vector3:
	var capsule := _shape_node.shape as CapsuleShape3D
	_query_shape.radius = capsule.radius - SKIN
	_query_shape.height = maxf(capsule.height - 2.0 * SKIN, 2.0 * _query_shape.radius)
	_query.collision_mask = _body.collision_mask
	var space := _body.get_world_3d().direct_space_state
	var total := Vector3.ZERO

	for iteration in MAX_ITERATIONS:
		_query.transform = _shape_node.global_transform
		var pairs := space.collide_shape(_query, MAX_RESULTS)
		if pairs.size() < 2:
			break

		# Deepest overlap first; the remaining ones are re-evaluated next iteration from the new pose.
		var push := Vector3.ZERO
		for i in range(0, pairs.size() - 1, 2):
			# Pair = (query origin, origin - mtd_dir * depth); the MTD direction pushes the query shape out.
			var candidate: Vector3 = pairs[i] - pairs[i + 1]
			if candidate.length_squared() > push.length_squared():
				push = candidate
		if push.length_squared() < 1e-10:
			break

		var normal := push.normalized()
		push += normal * SKIN
		_body.global_position += push
		total += push
		var into := velocity.dot(normal)
		if into < 0.0:
			velocity -= normal * into

	last_correction = total
	return velocity
