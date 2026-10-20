class_name PlanarReflectionSettings
extends Resource
## Tunables for PlanarReflection (the pool mirrored in the water's underside). Edits apply live, also while
## the game runs (each setter emits `changed`).

## Off: no extra render; the underside shows the plain water colour.
@export var enabled := true:
	set(value):
		enabled = value
		emit_changed()
## Blend of the reflection over the plain water colour (0..1).
@export_range(0.0, 1.0, 0.01) var strength := 1.0:
	set(value):
		strength = value
		emit_changed()
## Reflection render size relative to the screen; higher is sharper and costlier.
@export_range(0.1, 1.0, 0.05) var resolution_scale := 0.5:
	set(value):
		resolution_scale = value
		emit_changed()
## How far waves bend the reflection, in reflection-texture units.
@export_range(0.0, 0.2, 0.005) var distortion := 0.04:
	set(value):
		distortion = value
		emit_changed()
## Fade to the water colour near the reflection's screen edges, in texture units.
@export_range(0.001, 0.3, 0.005) var edge_fade := 0.05:
	set(value):
		edge_fade = value
		emit_changed()
## Underwater fog of the mirrored path (match underwater_view.gdshader water_color and density).
@export var fog_color := Color(0.1, 0.42, 0.47):
	set(value):
		fog_color = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var fog_density := 0.2:
	set(value):
		fog_density = value
		emit_changed()
