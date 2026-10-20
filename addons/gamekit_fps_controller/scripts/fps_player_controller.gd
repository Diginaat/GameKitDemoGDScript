class_name FpsPlayerController
extends CharacterBody3D
## Root of the first-person player. Owns the CharacterBody3D configuration, the view angles and the
## PlayerMotor, and runs the simulation once per physics tick. Presentation (camera, viewmodel, audio,
## interaction) lives in child nodes that read state and connect to motor signals. Water, ladders and the
## interaction ray reach the player only through the duck-typed GameKit methods below (water user, ladder
## user, interaction viewer).

@export var movement: PlayerMovementSettings = PlayerMovementSettings.new()
@export var camera_settings: PlayerCameraSettings = PlayerCameraSettings.new()

## When true, PlayerInput is ignored and `command` is supplied externally (tests, AI, cutscenes).
var use_external_command := false
## The intent simulated on the next physics tick.
var command := PlayerCommand.new()
var view_yaw := 0.0
var view_pitch := 0.0
var motor: PlayerMotor
var player_input: PlayerInput
var interaction: InteractionRay
## Wall-clock cost of the last simulation tick, for the debug overlay (microseconds).
var last_tick_microseconds := 0

var _abilities: Node


func _enter_tree() -> void:
	# Built here rather than in _ready so child components can connect to motor signals in their own _ready.
	if motor:
		return
	var shape := get_node("CollisionShape3D") as CollisionShape3D
	motor = PlayerMotor.new(self, shape, get_node_or_null("GroundCheck") as RayCast3D)
	_apply_body_settings()
	_abilities = get_node_or_null("Abilities")
	if _abilities:
		_abilities.child_order_changed.connect(_collect_abilities)
		_abilities.child_entered_tree.connect(func(_child: Node) -> void: _collect_abilities())
		_abilities.child_exiting_tree.connect(_on_ability_exiting)
	_collect_abilities()


func _ready() -> void:
	player_input = get_node_or_null("Input") as PlayerInput
	interaction = get_node_or_null("Interaction") as InteractionRay
	set_look(rotation.y, 0.0)


func _physics_process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	if not use_external_command and player_input:
		command = player_input.build_command()
		if interaction and player_input.mouse_captured:
			if Input.is_action_just_pressed(InputActions.INTERACT):
				interaction.use()
			elif interaction.held and Input.is_action_just_pressed(InputActions.FIRE):
				interaction.throw()
	command.yaw = view_yaw
	command.pitch = view_pitch
	motor.tick(command, delta)
	if use_external_command:
		# Edge-triggered inputs last one tick.
		command.jump_pressed = false
		command.crouch_pressed = false
		command.sprint_pressed = false
	last_tick_microseconds = Time.get_ticks_usec() - start


## Sets view angles (radians). Pitch is clamped to the camera limit.
func set_look(yaw: float, pitch: float) -> void:
	var limit := deg_to_rad(camera_settings.max_pitch_degrees)
	view_yaw = wrapf(yaw, -PI, PI)
	view_pitch = clampf(pitch, -limit, limit)


func add_look(yaw_delta: float, pitch_delta: float) -> void:
	set_look(view_yaw + yaw_delta, view_pitch + pitch_delta)


## Swaps the movement profile at runtime. The same motor runs every profile.
func apply_movement_settings(settings: PlayerMovementSettings) -> void:
	movement = settings
	_apply_body_settings()
	motor.stance.configure(settings)


# ---- GameKit duck-typed interfaces --------------------------------------------------------------

func on_water_entered(water: WaterVolume) -> void:
	var swim := motor.get_ability(SwimMovement) as SwimMovement
	if swim:
		swim.enter_volume(water)


func on_water_exited(water: WaterVolume) -> void:
	var swim := motor.get_ability(SwimMovement) as SwimMovement
	if swim:
		swim.exit_volume(water)


## [center, half_height, radius] of the body, for water ripples.
func get_water_extent() -> Array:
	var height := motor.stance.height
	return [global_position + Vector3.UP * height * 0.5, height * 0.5, movement.radius]


func on_ladder_entered(ladder: LadderVolume) -> void:
	var climb := motor.get_ability(LadderMovement) as LadderMovement
	if climb:
		climb.enter_volume(ladder)


func on_ladder_exited(ladder: LadderVolume) -> void:
	var climb := motor.get_ability(LadderMovement) as LadderMovement
	if climb:
		climb.exit_volume(ladder)


func get_view_origin() -> Vector3:
	return global_position + Vector3.UP * motor.stance.eye_height


func get_view_basis() -> Basis:
	return Basis.from_euler(Vector3(view_pitch, view_yaw, 0.0))


func get_viewer_velocity() -> Vector3:
	return motor.velocity


func _apply_body_settings() -> void:
	motion_mode = MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(movement.max_slope_degrees)
	# Snap follows stairs down, and must exceed the motor's pre-move floor lift.
	floor_snap_length = maxf(movement.step_height, PlayerMotor.GROUND_LIFT * 2.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_block_on_wall = true
	# The motor adds a clamped platform velocity itself; letting the engine add it too would double it.
	platform_on_leave = PLATFORM_ON_LEAVE_DO_NOTHING
	platform_floor_layers = 0xFFFFFFFF


## Abilities are the MovementAbility children of the `Abilities` node, in child order (priority). Re-read
## whenever children are added, removed or moved.
func _collect_abilities() -> void:
	var list: Array[MovementAbility] = []
	if _abilities:
		for child in _abilities.get_children():
			if child is MovementAbility and not child.is_queued_for_deletion():
				list.append(child)
	motor.set_abilities(list)


func _on_ability_exiting(child: Node) -> void:
	# Still a child while exiting: rebuild without it.
	var list: Array[MovementAbility] = []
	for other in _abilities.get_children():
		if other != child and other is MovementAbility:
			list.append(other)
	motor.set_abilities(list)
