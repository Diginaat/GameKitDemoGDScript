class_name PlanarReflection
extends Node
## Planar reflection of a water's underside (total internal reflection seen from below). While the active
## camera is under the water, a camera mirrored across the still surface renders the scene into a
## half-resolution viewport; the water material samples it by projecting each surface point with the
## mirrored camera. The mirrored view leaves out the water and the viewmodel, and is fogged like the
## underwater path it stands for. Nothing renders while the camera is above the water or when disabled.
## Tuned by `settings`.

const TEXTURE_PARAM := &"reflection_tex"
const VIEW_PROJECTION_PARAM := &"reflection_view_projection"
const STRENGTH_PARAM := &"reflection_strength"
const DISTORTION_PARAM := &"reflection_distortion"
const EDGE_FADE_PARAM := &"reflection_edge_fade"

@export var water: WaterVolume
@export var material: ShaderMaterial
@export var settings: PlanarReflectionSettings = PlanarReflectionSettings.new():
	set(value):
		# Connected only while in the tree (_enter_tree/_exit_tree), so a swap reconnects here.
		var live := is_inside_tree()
		if live and settings.changed.is_connected(_apply):
			settings.changed.disconnect(_apply)
		settings = value if value else PlanarReflectionSettings.new()
		if live:
			settings.changed.connect(_apply)
			_apply()

var _environment: Environment
var _viewport: SubViewport
var _camera: Camera3D


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.size = Vector2i(2, 2)
	_camera = Camera3D.new()
	_camera.name = "MirrorCamera"
	_camera.cull_mask = RenderLayers.ALL & ~(RenderLayers.WATER | RenderLayers.VIEWMODEL)
	_camera.current = true
	_viewport.add_child(_camera)
	add_child(_viewport)
	var world := get_viewport().find_world_3d()
	if world and world.environment:
		_environment = world.environment.duplicate()
		_environment.fog_enabled = true
		_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		_environment.fog_light_energy = 1.0
		_environment.fog_sky_affect = 0.0
		_environment.fog_sun_scatter = 0.0
		_camera.environment = _environment
	if material:
		material.set_shader_parameter(TEXTURE_PARAM, _viewport.get_texture())
	_apply()


func _enter_tree() -> void:
	settings.changed.connect(_apply)


func _exit_tree() -> void:
	if settings.changed.is_connected(_apply):
		settings.changed.disconnect(_apply)


func _apply() -> void:
	var s := settings
	if _environment:
		_environment.fog_light_color = s.fog_color
		_environment.fog_density = s.fog_density
	if material == null:
		return
	material.set_shader_parameter(STRENGTH_PARAM, s.strength if s.enabled else 0.0)
	material.set_shader_parameter(DISTORTION_PARAM, s.distortion)
	material.set_shader_parameter(EDGE_FADE_PARAM, s.edge_fade)


func _process(_delta: float) -> void:
	var main := get_viewport().get_camera_3d()
	var active := settings.enabled and settings.strength > 0.0 and water != null and material != null \
		and main != null and _is_underwater(main.global_position)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		return

	var size := Vector2i(get_viewport().get_visible_rect().size * settings.resolution_scale)
	if _viewport.size != size:
		_viewport.size = size

	# Mirror across the plane y = level. Projecting points (not copying the image) makes the handedness
	# flip of a mirror irrelevant: the shader looks up where the mirrored camera saw each surface point.
	var level := water.surface_y
	var t := main.global_transform
	var origin := Vector3(t.origin.x, 2.0 * level - t.origin.y, t.origin.z)
	var forward := -t.basis.z
	var up := t.basis.y
	forward.y = -forward.y
	up.y = -up.y
	_camera.global_transform = Transform3D(Basis.looking_at(forward, up), origin)
	_camera.fov = main.fov
	_camera.keep_aspect = main.keep_aspect
	_camera.near = main.near
	_camera.far = main.far

	var view_projection := _camera.get_camera_projection() * Projection(_camera.global_transform.affine_inverse())
	material.set_shader_parameter(VIEW_PROJECTION_PARAM, view_projection)


func _is_underwater(point: Vector3) -> bool:
	return point.y < water.surface_y and water.bounds.has_point(point)
