class_name RenderLayers
## Visual (render) layer bits used by more than one system. Cameras render all layers unless noted; the
## planar water reflection leaves out the water itself and the first-person viewmodel.

## Layer 1: ordinary world geometry (Godot's default).
const WORLD := 1 << 0
## Layer 17: the rain occlusion capture pass; only its top-down camera renders it.
const WEATHER_CAPTURE := 1 << 16
## Layer 18: rain particles and curtains (not recorded as cover or as rain colliders).
const WEATHER := 1 << 17
## Layer 19: first-person viewmodel (weapons, arms).
const VIEWMODEL := 1 << 18
## Layer 20: water surfaces and the underwater view pass.
const WATER := 1 << 19
## All 20 visual layers.
const ALL := (1 << 20) - 1
