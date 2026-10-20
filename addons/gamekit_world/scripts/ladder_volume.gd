class_name LadderVolume
extends Area3D
## Climbable region. The volume's local +Z axis points away from the ladder face toward the climber.
## Extend the volume slightly above the top ledge so climbers hop off onto it. Bodies with
## on_ladder_entered(ladder) / on_ladder_exited(ladder) are told when they enter and leave.
## Collision mask: the climbers' layer.

var outward_normal: Vector3:
	get:
		return global_basis.z.slide(Vector3.UP).normalized()


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("on_ladder_entered"):
		body.on_ladder_entered(self)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("on_ladder_exited"):
		body.on_ladder_exited(self)
