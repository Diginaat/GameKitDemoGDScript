# gamekit_interaction

Use, pick up and throw. Depends on: `gamekit_core`.

| Type | What it is |
| --- | --- |
| Interactable (duck typed) | Any node with `get_prompt(interactor)`, `can_interact(interactor)`, `interact(interactor)` |
| Highlight (duck typed) | Optional focus feedback: `set_highlighted(on: bool)` |
| Viewer (duck typed) | What the ray needs from its carrier: `get_view_origin()`, `get_view_basis()`, `get_viewer_velocity()` |
| `InteractionRay` | Node: focus ray, `use()`, `throw()`, `drop()`, impulse-based holding; signals `prompt_changed`, `picked_up`, `dropped` |
| `InteractableButton` | StaticBody3D: calls `interact` on its `target` |
| `SlidingDoor` | AnimatableBody3D: slides by `open_offset` |

## Setup

1. Add an `InteractionRay` node as a child of a `PhysicsBody3D` that has the viewer methods
   (`FpsPlayerController` does).
2. Call `use()` / `throw()` from your input code; `InteractionRay` reads no input itself.
3. Show `prompt_changed` text in your HUD.

## Your own interactables

Add the three interactable methods to a script on the collider's node or on one of its two parents:

```gdscript
extends StaticBody3D


func get_prompt(_interactor: Node) -> String:
	return "Pull lever"


func can_interact(_interactor: Node) -> bool:
	return true


func interact(_interactor: Node) -> void:
	pass # ...
```

Check `interactor` against your game's type when the object needs more (inventory, team).

Rigid bodies on the ray's `mask` (World and Props by default) up to `max_pickup_mass` can be picked up.
