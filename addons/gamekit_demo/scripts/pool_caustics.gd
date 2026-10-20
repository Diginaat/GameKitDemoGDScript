@tool
class_name PoolCaustics
extends Node
## Points a pool_tile.gdshader material at its water: surface height, water rectangle and sun direction.
## pool_tile works in world space, so this keeps the caustics right wherever the pool scene is placed or
## turned.

@export var water: WaterVolume
## The pool_tile.gdshader material on the pool walls and floor.
@export var tile_material: ShaderMaterial


func _ready() -> void:
	if water == null or tile_material == null:
		return

	for child in water.get_children():
		var shape := child as CollisionShape3D
		if shape == null or not shape.shape is BoxShape3D:
			continue
		var size: Vector3 = shape.shape.size
		var bounds := shape.global_transform * AABB(-size / 2.0, size)
		tile_material.set_shader_parameter("water_surface_y", bounds.end.y)
		tile_material.set_shader_parameter("water_rect", Vector4(bounds.position.x, bounds.position.z, bounds.end.x, bounds.end.z))
		break

	# The sun lives in the main scene; when this scene is edited on its own the material keeps its value.
	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if root:
		var suns := root.find_children("*", "DirectionalLight3D", true, false)
		if not suns.is_empty():
			tile_material.set_shader_parameter("sun_direction", -(suns[0] as DirectionalLight3D).global_basis.z)
