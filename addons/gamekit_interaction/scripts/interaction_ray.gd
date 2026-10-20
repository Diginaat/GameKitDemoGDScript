class_name InteractionRay
extends Node
## Ray-based use system. Add it as a child of a PhysicsBody3D that is an interaction viewer: it has
## get_view_origin() -> Vector3, get_view_basis() -> Basis (-Z forward) and get_viewer_velocity() -> Vector3.
## Each physics tick it rays from the viewer's eye along the view; the hit collider (or one of its two
## parents) that is interactable (has interact()) becomes `focused`. use() activates it. Without an
## interactable, use() picks up light rigid bodies, which are then held by impulses (never by setting their
## transform) so they still collide properly; throw() throws them. It reads no input: the owner calls
## use()/throw() (player input, AI, scripted sequences).
##
## Interactable: get_prompt(interactor) -> String, can_interact(interactor) -> bool, interact(interactor).
## Optional highlight: set_highlighted(bool).

## Prompt for the HUD; an empty string hides it.
signal prompt_changed(text: String)
signal picked_up(body: RigidBody3D)
signal dropped(body: RigidBody3D)

@export var distance := 2.5
@export var max_pickup_mass := 40.0
@export var hold_distance := 1.6
@export var hold_stiffness := 18.0
@export var max_hold_speed := 12.0
@export var break_distance := 1.2
@export var throw_speed := 9.0
@export_flags_3d_physics var mask: int = CollisionLayers.WORLD | CollisionLayers.PROPS

var focused: Object
var held: RigidBody3D
var ray_from: Vector3
var ray_to: Vector3

var _carrier: PhysicsBody3D
var _ray := PhysicsRayQueryParameters3D.new()
var _focused_collider: Object


func _ready() -> void:
	_carrier = get_parent() as PhysicsBody3D
	assert(_carrier and _carrier.has_method("get_view_basis"),
		"%s: parent must be a PhysicsBody3D with get_view_origin/get_view_basis/get_viewer_velocity" % name)
	_ray.exclude = [_carrier.get_rid()]


func _physics_process(delta: float) -> void:
	var view: Basis = _carrier.get_view_basis()
	ray_from = _carrier.get_view_origin()
	ray_to = ray_from + view * Vector3.FORWARD * distance
	if held:
		_update_held(delta, view)
	else:
		_update_focus()


## Use: drop what is held, activate the focused interactable, or pick up a light prop.
func use() -> void:
	if held:
		drop()
		return
	if focused:
		if focused.can_interact(_carrier):
			focused.interact(_carrier)
		return
	if _focused_collider is RigidBody3D and _can_pick_up(_focused_collider):
		_pick_up(_focused_collider)


## Throws the held object along the view. Does nothing when nothing is held.
func throw() -> void:
	if held == null:
		return
	var body := held
	drop()
	body.apply_central_impulse(_carrier.get_view_basis() * Vector3.FORWARD * throw_speed * body.mass)


func drop() -> void:
	if held == null:
		return
	var body := held
	held = null
	_focused_collider = null
	if is_instance_valid(body):
		_carrier.remove_collision_exception_with(body)
		dropped.emit(body)
	prompt_changed.emit("")


func _can_pick_up(body: RigidBody3D) -> bool:
	return not body.freeze and body.mass <= max_pickup_mass


func _update_focus() -> void:
	_ray.from = ray_from
	_ray.to = ray_to
	_ray.collision_mask = mask
	var hit := _carrier.get_world_3d().direct_space_state.intersect_ray(_ray)
	var collider: Object = hit.get("collider")
	if collider == _focused_collider:
		return

	_focused_collider = collider
	var interactable := _find_interactable(collider as Node)
	if interactable == focused:
		return
	_set_highlight(focused, false)
	focused = interactable
	_set_highlight(focused, true)
	var prompt := ""
	if focused:
		prompt = focused.get_prompt(_carrier)
	elif collider is RigidBody3D and _can_pick_up(collider):
		prompt = "Pick up"
	prompt_changed.emit(prompt)


static func _find_interactable(node: Node) -> Object:
	var depth := 0
	while node and depth < 3:
		if node.has_method("interact"):
			return node
		node = node.get_parent()
		depth += 1
	return null


static func _set_highlight(target: Object, on: bool) -> void:
	if target and is_instance_valid(target) and target.has_method("set_highlighted"):
		target.set_highlighted(on)


func _pick_up(body: RigidBody3D) -> void:
	held = body
	# The carrier must not stand on, or be pushed by, what it is carrying.
	_carrier.add_collision_exception_with(body)
	_set_highlight(focused, false)
	focused = null
	prompt_changed.emit("Drop")
	picked_up.emit(body)


func _update_held(dt: float, view: Basis) -> void:
	var body := held
	if not is_instance_valid(body):
		held = null
		prompt_changed.emit("")
		return
	var target := ray_from + view * Vector3.FORWARD * hold_distance
	var error := target - body.global_position
	if error.length() > break_distance:
		drop()
		return
	# Impulse that changes the body's velocity to the one that closes the gap, plus the carrier's motion.
	var desired: Vector3 = (error * hold_stiffness + _carrier.get_viewer_velocity()).limit_length(max_hold_speed)
	# Counter gravity this tick so the object does not sag.
	var gravity: float = PhysicsServer3D.area_get_param(_carrier.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY)
	desired += Vector3.UP * gravity * dt * body.gravity_scale
	body.apply_central_impulse((desired - body.linear_velocity) * body.mass)
	body.apply_torque_impulse(-body.angular_velocity * 0.5 * body.mass * 0.1)
