class_name InteractableButton
extends StaticBody3D
## A pressable button. Toggles `target` (anything with a toggle() method) and lights up.
## Interactable: get_prompt(), can_interact(), interact(). Highlightable: set_highlighted().

@export var target: NodePath
@export var prompt := "Press button"

var _material: StandardMaterial3D
var _on := false


func _ready() -> void:
	for child in get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			_material = child.material_override


func get_prompt(_interactor: Node) -> String:
	return prompt


func can_interact(_interactor: Node) -> bool:
	return true


func interact(_interactor: Node) -> void:
	_on = not _on
	if _material:
		_material.albedo_color = Color(0.2, 0.9, 0.3) if _on else Color(0.8, 0.15, 0.1)
	var node := get_node_or_null(target)
	if node and node.has_method("toggle"):
		node.toggle()


func set_highlighted(highlighted: bool) -> void:
	if _material == null:
		return
	_material.emission_enabled = highlighted
	_material.emission = Color(0.4, 0.4, 0.4)
