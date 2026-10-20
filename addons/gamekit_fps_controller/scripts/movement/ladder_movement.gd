class_name LadderMovement
extends MovementAbility
## Source-style ladders. Inside a LadderVolume, pushing toward the ladder grabs it. Forward input climbs in
## the direction you look (look down + forward descends), back input descends, strafe moves sideways. Jump
## pushes off; leaving the top of the volume while climbing hops onto the ledge.

const LOOK_DOWN_DESCEND_DEGREES := -30.0

var _ladder: LadderVolume
var _overlaps := 0
var _last_inward := Vector3.ZERO


func get_state() -> PlayerMotor.MovementState:
	return PlayerMotor.MovementState.CLIMBING


func enter_volume(ladder: LadderVolume) -> void:
	_ladder = ladder
	_overlaps += 1


func exit_volume(_ladder_volume: LadderVolume) -> void:
	_overlaps = maxi(0, _overlaps - 1)
	if _overlaps == 0:
		_ladder = null


func can_begin(motor: PlayerMotor, cmd: PlayerCommand) -> bool:
	if not motor.settings.ladder_enabled or _ladder == null or cmd.jump_held:
		return false
	var wish_dir: Vector3 = motor.wish_movement(cmd)[0]
	# Pushing toward the ladder face grabs it; standing at the bottom and backing away does not.
	return wish_dir.dot(-_ladder.outward_normal) > 0.3


func begin(motor: PlayerMotor, _cmd: PlayerCommand) -> void:
	motor.velocity = Vector3.ZERO
	motor.consume_jump_buffer()


func tick(motor: PlayerMotor, cmd: PlayerCommand, dt: float) -> bool:
	var s := motor.settings
	if _ladder == null:
		# Climbed past the top of the volume: hop forward onto the ledge.
		if motor.velocity.y > 0.1:
			motor.velocity = Vector3.UP * 2.5 + _last_inward * 2.5
		return false

	var normal := _ladder.outward_normal
	_last_inward = -normal
	if cmd.jump_pressed:
		motor.consume_jump_buffer()
		motor.velocity = normal * s.ladder_jump_off_speed + Vector3.UP * 2.0
		return false

	var climb := cmd.move.y
	if climb > 0.0 and rad_to_deg(cmd.pitch) < LOOK_DOWN_DESCEND_DEGREES:
		climb = -climb
	var right := Vector3.UP.cross(normal).normalized()
	var side := cmd.move.x

	# Stepping off at the bottom.
	if motor.is_on_floor and climb < 0.0:
		return false

	motor.velocity = Vector3.UP * (climb * s.ladder_climb_speed) \
		- right * (side * s.ladder_climb_speed * 0.5) \
		- normal * 0.4 # keeps contact with the ladder face
	motor.move_body(dt, false)
	return true


func end(_motor: PlayerMotor) -> void:
	pass
