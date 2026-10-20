class_name PlayerStance
extends RefCounted
## Standing/crouching. Owns the capsule size so the collider always matches the stance. Crouching only ever
## shrinks the capsule into space it already occupied, so it is always safe; standing is allowed only after
## a shape query proves the taller capsule fits. The body origin is at the feet.

## Emitted when the stance changes. feet_shift: how far the feet moved up (airborne crouch tucks the legs).
signal changed(crouched: bool, feet_shift: float)

# Shrinks the clearance query slightly so resting contact with the floor/walls is not "blocked".
const CLEARANCE_SKIN := 0.01

var is_crouched := false
## True when the player wants to stand but geometry above prevents it.
var is_stand_blocked := false
var height: float:
	get:
		return _settings.crouch_height if is_crouched else _settings.standing_height
var eye_height: float:
	get:
		return _settings.crouch_eye_height if is_crouched else _settings.standing_eye_height

var _body: CharacterBody3D
var _shape_node: CollisionShape3D
var _shape: CapsuleShape3D
var _query_shape := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _settings: PlayerMovementSettings
var _toggle_wants_crouch := false


func _init(body: CharacterBody3D, shape_node: CollisionShape3D, settings: PlayerMovementSettings) -> void:
	_body = body
	_shape_node = shape_node
	# A unique shape per player: resizing a shared scene resource would resize every instance.
	_shape = CapsuleShape3D.new()
	_shape_node.shape = _shape
	_settings = settings
	_query.shape = _query_shape
	_query.collision_mask = body.collision_mask
	_query.exclude = [body.get_rid()]
	_apply_size()


func configure(settings: PlayerMovementSettings) -> void:
	# Keep the current stance; only the dimensions change. Normal input handling stands the player up later.
	_settings = settings
	_apply_size()


## Applies crouch input. force_crouch keeps the player crouched (slides).
func update(cmd: PlayerCommand, grounded: bool, force_crouch := false) -> void:
	if cmd.crouch_pressed:
		_toggle_wants_crouch = not _toggle_wants_crouch
	var want_crouch := force_crouch or (_toggle_wants_crouch if _settings.crouch_toggle else cmd.crouch_held)

	if want_crouch and not is_crouched:
		crouch(grounded)
	elif not want_crouch and is_crouched:
		is_stand_blocked = not try_stand(grounded)
	else:
		is_stand_blocked = false


func crouch(grounded: bool) -> void:
	if is_crouched:
		return
	var delta := _settings.standing_height - _settings.crouch_height
	is_crouched = true
	_toggle_wants_crouch = true
	_apply_size()
	var feet_shift := 0.0
	if not grounded:
		# Source-style airborne crouch: keep the head where it is and tuck the feet up.
		feet_shift = delta
		_body.global_position += Vector3.UP * delta
	changed.emit(true, feet_shift)


func try_stand(grounded: bool) -> bool:
	if not is_crouched:
		return true
	var delta := _settings.standing_height - _settings.crouch_height
	# In the air prefer dropping the feet back down (head fixed); fall back to growing upward.
	var feet_shift: float
	if not grounded and can_fit(_settings.standing_height, -delta):
		feet_shift = -delta
	elif can_fit(_settings.standing_height, 0.0):
		feet_shift = 0.0
	else:
		return false

	is_crouched = false
	_toggle_wants_crouch = false
	if feet_shift != 0.0:
		_body.global_position += Vector3.UP * feet_shift
	_apply_size()
	changed.emit(false, feet_shift)
	return true


## Whether a capsule of `height` with feet raised by feet_offset overlaps nothing.
func can_fit(capsule_height: float, feet_offset: float) -> bool:
	_query_shape.radius = _settings.radius - CLEARANCE_SKIN
	_query_shape.height = maxf(capsule_height - 2.0 * CLEARANCE_SKIN, 2.0 * _query_shape.radius)
	var origin := _body.global_position + Vector3.UP * (feet_offset + capsule_height * 0.5)
	_query.transform = Transform3D(Basis.IDENTITY, origin)
	_query.collision_mask = _body.collision_mask
	var space := _body.get_world_3d().direct_space_state
	return space.intersect_shape(_query, 1).is_empty()


func _apply_size() -> void:
	var h := height
	_shape.radius = _settings.radius
	_shape.height = h
	_shape_node.position = Vector3(0.0, h * 0.5, 0.0)
