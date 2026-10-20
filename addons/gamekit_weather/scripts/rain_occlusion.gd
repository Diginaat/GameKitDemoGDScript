class_name RainOcclusion
extends Node3D
## Rain occlusion map: a top-down height map around the camera, so surfaces under a roof, an overhang or a
## table stay dry.
##
## A small orthographic camera in a SubViewport renders the scene from above; a full-screen pass turns its
## depth into world height (float texture). The wetness shader (weather_wetness.gdshaderinc) compares each
## surface with the highest surface above it via the weather_rain_occlusion and weather_occlusion_area
## shader globals.
##
## Cost: the map re-renders only when the followed node moves a grid step (snapped, so it never shimmers),
## not every frame. Call refresh() after moving a cover.

const OCCLUSION_GLOBAL := &"weather_rain_occlusion"
const AREA_GLOBAL := &"weather_occlusion_area"

## Node to center the map on. Defaults to the active camera.
@export var follow_target: Node3D
## Width of the covered square in meters.
@export var area_size := 64.0
## Map resolution in pixels (area_size / resolution = meters per texel).
@export_enum("256:256", "512:512", "1024:1024") var resolution: int = 512
## Re-render after moving this far (meters). Also the snapping grid.
@export var update_step := 4.0
## Capture from this high above the followed node.
@export var capture_height := 60.0
## Render layers that count as cover. Rain, water, the viewmodel and the capture pass don't.
@export_flags_3d_render var cover_layers: int = RenderLayers.ALL & ~(RenderLayers.WEATHER | RenderLayers.WEATHER_CAPTURE \
	| RenderLayers.VIEWMODEL | RenderLayers.WATER)

var _viewport: SubViewport
var _camera: Camera3D
var _center := Vector2(INF, INF)


func _ready() -> void:
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(resolution, resolution)
	_viewport.use_hdr_2d = true # float texture: exact heights in meters
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	# Exact depth: no upscaler, no temporal AA jitter, no AA blur.
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_viewport.scaling_3d_scale = 1.0
	_viewport.use_taa = false
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	add_child(_viewport)

	# Plain output: the scene's tonemap, fog, glow and exposure must not touch the heights.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(-1000.0, -1000.0, -1000.0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_camera = Camera3D.new()
	# Never interpolate: a blend between poses tilts the capture and misplaces covers.
	_camera.physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = area_size
	_camera.near = 0.5
	_camera.far = capture_height + 200.0
	_camera.cull_mask = cover_layers | RenderLayers.WEATHER_CAPTURE
	_camera.rotation = Vector3(-PI * 0.5, 0.0, 0.0) # straight down; screen up = world -Z
	_camera.environment = env
	_camera.attributes = CameraAttributesPractical.new()
	_viewport.add_child(_camera)

	var material := ShaderMaterial.new()
	material.shader = load("res://addons/gamekit_weather/shaders/rain_occlusion_capture.gdshader")
	var quad_mesh := QuadMesh.new()
	quad_mesh.material = material
	var quad := MeshInstance3D.new()
	quad.mesh = quad_mesh
	quad.layers = RenderLayers.WEATHER_CAPTURE
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	quad.position = Vector3(0.0, 0.0, -1.0)
	_camera.add_child(quad)

	RenderingServer.global_shader_parameter_set(OCCLUSION_GLOBAL, _viewport.get_texture())


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(AREA_GLOBAL, Vector4.ZERO)


func _process(_delta: float) -> void:
	var target: Node3D = follow_target if follow_target else get_viewport().get_camera_3d()
	if target == null or target == _camera:
		return
	var p := target.global_position
	var snapped_center := Vector2(p.x, p.z).snapped(Vector2(update_step, update_step))
	if snapped_center == _center:
		return
	_center = snapped_center
	_camera.global_position = Vector3(_center.x, p.y + capture_height, _center.y)
	_camera.reset_physics_interpolation()
	refresh()


## The current height map as an image (float heights in the red channel).
func get_height_image() -> Image:
	return _viewport.get_texture().get_image()


## Re-renders the map now (e.g. after building or moving a cover).
func refresh() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.global_shader_parameter_set(AREA_GLOBAL, Vector4(_center.x, _center.y, area_size, 1.0))
