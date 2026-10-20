class_name SwimMovement
extends MovementAbility
## Swimming inside a WaterVolume once enough of the body is submerged. Full 3D movement along the view
## direction, jump/crouch to rise/sink, water drag, buoyancy that floats the head at the surface, and
## climbing out onto ledges through MantleMovement. Emits underwater_changed for camera/audio treatment.

signal underwater_changed(underwater: bool)

const EXIT_HYSTERESIS := 0.8
# Standing on ground with the eyes this far above the surface counts as wading, not swimming: buoyancy
# aims the feet 1.5 m deep and pressed a swimmer into stairs that rise above that, stalling it there.
const WADE_HEAD_CLEARANCE := 0.1

var is_underwater := false

var _water: WaterVolume


func get_state() -> PlayerMotor.MovementState:
	return PlayerMotor.MovementState.SWIMMING


func enter_volume(water: WaterVolume) -> void:
	_water = water


func exit_volume(water: WaterVolume) -> void:
	if _water == water:
		_water = null


## Water depth at the feet; 0 outside the water's box. The box test does not rely on overlap signals alone:
## a missed exit left a stale volume, and dry ground below the pool's surface then read as deep water, so
## the player kept swimming on land.
func _depth(motor: PlayerMotor) -> float:
	if _water == null:
		return 0.0
	var feet := motor.body.global_position
	var b := _water.bounds
	var inside := feet.x > b.position.x and feet.x < b.end.x and feet.z > b.position.z and feet.z < b.end.z \
		and feet.y > b.position.y - 0.5
	return _water.surface_y - feet.y if inside else 0.0


static func _wading(motor: PlayerMotor, depth: float) -> bool:
	return motor.is_on_floor and depth < motor.stance.eye_height - WADE_HEAD_CLEARANCE


func can_begin(motor: PlayerMotor, _cmd: PlayerCommand) -> bool:
	var s := motor.settings
	var depth := _depth(motor)
	return s.swim_enabled and depth >= s.standing_height * s.swim_depth_fraction and not _wading(motor, depth)


func begin(motor: PlayerMotor, _cmd: PlayerCommand) -> void:
	motor.stance.try_stand(false)
	# Entering from a fall: water absorbs most of the downward speed.
	if motor.velocity.y < 0.0:
		motor.velocity.y *= 0.3


func tick(motor: PlayerMotor, cmd: PlayerCommand, dt: float) -> bool:
	var s := motor.settings
	var depth := _depth(motor)
	var eye_depth := depth - motor.stance.eye_height
	_set_underwater(eye_depth > 0.0)
	if _water == null or depth < s.standing_height * s.swim_depth_fraction * EXIT_HYSTERESIS or _wading(motor, depth):
		return false

	# Head floats just above the surface.
	var float_depth := motor.stance.eye_height - 0.15

	var view := Basis.from_euler(Vector3(cmd.pitch, cmd.yaw, 0.0))
	var wish := view * Vector3(cmd.move.x, 0.0, -cmd.move.y)
	if cmd.jump_held:
		wish += Vector3.UP
	if cmd.crouch_held:
		wish += Vector3.DOWN
	# Can't swim upward out of the water by looking up; the surface holds you at float depth.
	if depth <= float_depth and wish.y > 0.0:
		wish.y = 0.0
	var amount := minf(wish.length(), 1.0)
	var wish_dir := wish.normalized() if amount > 1e-4 else Vector3.ZERO
	var wish_speed := s.swim_speed * amount * (1.3 if motor.is_sprinting else 1.0)

	# Climbing out: at the surface, jump + forward at a ledge yields to the mantle ability.
	if cmd.jump_held and cmd.move.y > 0.5 and depth < float_depth + 0.3:
		var mantle := motor.get_ability(MantleMovement) as MantleMovement
		if mantle and mantle.can_begin(motor, cmd):
			return false

	var v := MoveMath.apply_friction(motor.velocity, s.water_friction, 0.5, dt)
	v = MoveMath.accelerate(v, wish_dir, wish_speed, s.swim_acceleration, dt)

	# Buoyancy: with no vertical intent, drift to float depth.
	if absf(wish.y) < 0.1:
		var error := depth - float_depth
		v.y = move_toward(v.y, clampf(error * 2.0, -1.5, 1.5), 6.0 * dt)

	motor.velocity = v
	motor.move_body(dt, true)
	return true


func end(_motor: PlayerMotor) -> void:
	_set_underwater(false)


func _set_underwater(value: bool) -> void:
	if value == is_underwater:
		return
	is_underwater = value
	underwater_changed.emit(value)
