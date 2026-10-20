class_name PlayerViewmodel
extends Node3D
## First-person hands/weapon presentation under the camera. Holds Weapon children, switches between them
## (1/2, 3 holsters), forwards fire/reload, and adds procedural motion: look sway (inertia), movement bob,
## landing dip, sprint and crouch poses, and lowering while a prop is carried. Reads player state only; the
## controller works identically without this node.

@export var rest_position := Vector3(0.17, -0.17, -0.22)
@export var sway_amount := 0.02
@export var sway_rotation := 0.06
@export var sway_rate := 9.0
@export var bob_amount := 0.012
@export var kick_back := 0.025

var current_weapon: Weapon:
	get:
		return _weapons[_current] if _current >= 0 else null

var _player: FpsPlayerController
var _camera_effects: PlayerCameraEffects
var _interaction: InteractionRay
var _weapons: Array[Weapon] = []
var _current := -1
var _prev_yaw := 0.0
var _prev_pitch := 0.0
var _sway := Vector2.ZERO
var _bob_phase := 0.0
var _dip := 0.0
var _dip_velocity := 0.0
var _kick := 0.0
var _kick_velocity := 0.0
var _pose_blend := 0.0 # 0 = ready, 1 = lowered (sprint/carry)


func _ready() -> void:
	_player = owner as FpsPlayerController
	_camera_effects = get_parent().get_parent() as PlayerCameraEffects
	_interaction = _player.get_node_or_null("Interaction") as InteractionRay
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	for child in get_children():
		if child is Weapon:
			child.visible = false
			child.fired.connect(_on_fired)
			_weapons.append(child)
	_player.motor.landed.connect(func(speed: float) -> void: _dip_velocity -= minf(speed * 0.02, 0.12) * 12.0)
	_prev_yaw = _player.view_yaw
	_prev_pitch = _player.view_pitch
	if not _weapons.is_empty():
		select(0)


func select(index: int) -> void:
	if index == _current or index >= _weapons.size():
		return
	if current_weapon:
		current_weapon.holster()
	_current = index
	if current_weapon:
		current_weapon.equip()


func holster() -> void:
	if current_weapon:
		current_weapon.holster()
	_current = -1


func _is_lowered() -> bool:
	var motor := _player.motor
	return (motor.is_sprinting and motor.horizontal_velocity.length() > _player.movement.run_speed * 0.9) \
		or (_interaction != null and _interaction.held != null) \
		or motor.state in [PlayerMotor.MovementState.CLIMBING, PlayerMotor.MovementState.MANTLING, PlayerMotor.MovementState.SWIMMING]


func _process(delta: float) -> void:
	_handle_input()
	_animate(delta)


func _handle_input() -> void:
	if _player.use_external_command or _player.player_input == null or not _player.player_input.mouse_captured:
		return
	if Input.is_action_just_pressed(InputActions.WEAPON_1):
		select(0)
	if Input.is_action_just_pressed(InputActions.WEAPON_2):
		select(1)
	if Input.is_action_just_pressed(InputActions.HOLSTER):
		holster()
	var weapon := current_weapon
	if weapon == null or _is_lowered():
		return
	if Input.is_action_just_pressed(InputActions.RELOAD):
		weapon.reload()
	var trigger := Input.is_action_pressed(InputActions.FIRE) if weapon.automatic else Input.is_action_just_pressed(InputActions.FIRE)
	if trigger:
		var aim := get_viewport().get_camera_3d().global_transform
		weapon.try_fire(aim.origin, -aim.basis.z, _player.get_rid(), _player.get_world_3d().direct_space_state)


func _on_fired(weapon: Weapon) -> void:
	_kick_velocity += kick_back * 40.0
	var r := weapon.recoil_degrees
	if _camera_effects:
		_camera_effects.add_recoil(Vector2(r.x, randf_range(-r.y, r.y)))


func _animate(dt: float) -> void:
	var motor := _player.motor
	var effects := _player.camera_settings.motion_effects

	# Look sway: the weapon lags behind view rotation, then catches up (inertia).
	var d_yaw := angle_difference(_prev_yaw, _player.view_yaw)
	var d_pitch := _player.view_pitch - _prev_pitch
	_prev_yaw = _player.view_yaw
	_prev_pitch = _player.view_pitch
	var sway_target := Vector2(-d_yaw, -d_pitch) / maxf(dt, 1e-4) * 0.01 if effects else Vector2.ZERO
	sway_target = sway_target.limit_length(1.0)
	_sway = _sway.lerp(sway_target, MoveMath.smooth_factor(sway_rate, dt))

	var speed := motor.horizontal_velocity.length()
	var bob_weight := clampf(speed / _player.movement.run_speed, 0.0, 1.5) \
		if effects and motor.state == PlayerMotor.MovementState.GROUNDED else 0.0
	_bob_phase += speed * dt / 2.4 * TAU

	var d := _spring_step(_dip, _dip_velocity, 160.0, 20.0, dt)
	_dip = d.x
	_dip_velocity = d.y
	var k := _spring_step(_kick, _kick_velocity, 260.0, 26.0, dt)
	_kick = k.x
	_kick_velocity = k.y
	_pose_blend = lerpf(_pose_blend, 1.0 if _is_lowered() else 0.0, MoveMath.smooth_factor(10.0, dt))

	position = rest_position \
		+ Vector3(_sway.x * sway_amount, _sway.y * sway_amount, 0.0) \
		+ Vector3(sin(_bob_phase) * bob_amount, absf(sin(_bob_phase)) * -bob_amount, 0.0) * bob_weight \
		+ Vector3(0.0, _dip if effects else 0.0, _kick) \
		+ Vector3(-0.04, -0.06, 0.03) * _pose_blend \
		+ (Vector3(-0.015, 0.01, 0.0) if motor.stance.is_crouched else Vector3.ZERO)
	rotation = Vector3(
		_sway.y * sway_rotation - _pose_blend * 0.5,
		_sway.x * sway_rotation + _pose_blend * 0.6,
		_sway.x * sway_rotation * 0.5 + _pose_blend * 0.25)


# Returns (x, v) after one damped spring step toward zero.
static func _spring_step(x: float, v: float, k: float, c: float, dt: float) -> Vector2:
	dt = minf(dt, 0.05)
	v += (-k * x - c * v) * dt
	x += v * dt
	return Vector2(x, v)
