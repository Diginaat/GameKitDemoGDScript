class_name SlidingDoor
extends AnimatableBody3D
## Kinematic sliding door, usable directly or toggled by a button. Moves in the physics tick with
## sync-to-physics, so it pushes the player instead of overlapping them.

@export var open_offset := Vector3(0.0, 2.4, 0.0)
@export var speed := 2.0

var _closed: Vector3
var _open := false
var _t := 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	sync_to_physics = true
	_closed = position
	for child in get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			_material = child.material_override


func toggle() -> void:
	_open = not _open


func get_prompt(_interactor: Node) -> String:
	return "Close door" if _open else "Open door"


func can_interact(_interactor: Node) -> bool:
	return true


func interact(_interactor: Node) -> void:
	toggle()


func set_highlighted(highlighted: bool) -> void:
	if _material == null:
		return
	_material.emission_enabled = highlighted
	_material.emission = Color(0.25, 0.25, 0.25)


func _physics_process(delta: float) -> void:
	var length := maxf(open_offset.length(), 0.01)
	_t = move_toward(_t, 1.0 if _open else 0.0, speed * delta / length)
	position = _closed + open_offset * smoothstep(0.0, 1.0, _t)
