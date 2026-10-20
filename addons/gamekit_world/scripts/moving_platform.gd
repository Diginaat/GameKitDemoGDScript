class_name MovingPlatform
extends AnimatableBody3D
## Kinematic platform that oscillates along `travel` and/or spins about Y. Moves in the physics tick with
## sync-to-physics, so CharacterBody3D riders get correct platform velocity.

@export var travel := Vector3(0.0, 0.0, 6.0)
@export var period := 6.0
@export var spin_degrees_per_second := 0.0

var _start: Transform3D
var _time := 0.0


func _ready() -> void:
	sync_to_physics = true
	_start = transform


func _physics_process(delta: float) -> void:
	_time += delta
	var phase := _time / period * TAU if period > 0.0 else 0.0
	# Smooth back-and-forth: 0 -> travel -> 0, reversing gently at each end.
	var offset := travel * (0.5 - 0.5 * cos(phase))
	var basis := _start.basis.rotated(Vector3.UP, deg_to_rad(spin_degrees_per_second) * _time)
	transform = Transform3D(basis, _start.origin + offset)
