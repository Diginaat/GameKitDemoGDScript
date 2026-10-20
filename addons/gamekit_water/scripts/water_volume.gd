class_name WaterVolume
extends Area3D
## Swimmable water: an Area3D with one BoxShape3D child; the box's top is the surface. Gameplay (swimming)
## uses that flat level. With `rendered` on, the volume builds its own visuals when it enters the tree: a
## PhysX GPU water surface (pool_water.gdshader) that bodies in the water ripple, the per-pixel underwater
## view, and the planar underside reflection. Place it inside four walls: the surface spans exactly the
## box's top face. Collision mask: swimmers (and props to ripple).
##
## Water users: bodies with on_water_entered(water) / on_water_exited(water) are told when they enter and
## leave. A body with get_water_extent() -> [center: Vector3, half_height: float, radius: float] sets its
## ripple size; other bodies ripple the surface with a default size.

# Ripple tuning, after the example project's buoyant_body.gd: a body disturbs the surface only near it, and
# more while moving.
const RIPPLE_REACH := 0.3
# Kept small: a swimmer's head sits in its own proxy, and a deep resting dent put the eye above the drawn
# surface while it was below the still level.
const RESTING_WAKE := 0.03
const WAKE_REFERENCE_SPEED := 5.0
const SPLASH_REFERENCE_SPEED := 8.0
# The ripple solver does not conserve volume: its mean is measured on a grid and the material shifts the
# drawn surface back to surface_y. Measured every few ticks, eased so corrections are not visible.
const LEVEL_SAMPLES := 5
const LEVEL_INTERVAL := 6
const LEVEL_EASE_RATE := 2.0

const LEVEL_CORRECTION_PARAM := &"level_correction"
# Surface height inputs shared with the underwater view, so its waterline matches the drawn waves.
const SHARED_SURFACE_PARAMS: Array[StringName] = [
	&"ripple_height_tex", &"ocean_height_tex", &"ripple_domain_size", &"ocean_domain_size", &"grid_center",
]

## Off: an invisible swimmable volume (no surface, underwater view or reflection).
@export var rendered := true
## Underside reflection settings; null for no planar reflection.
@export var reflection: PlanarReflectionSettings

var surface_y := 0.0
## World-space box of the water.
var bounds := AABB()
## Rendered water surface, built in _ready; null when not rendered or without a RenderingDevice.
var surface: PhysXWaterSurface3D
## Full-screen underwater pass material (underwater_view.gdshader), built in _ready.
var underwater_view: ShaderMaterial

var _bodies: Array[Node3D] = []
var _level_correction := 0.0
var _level_target := 0.0
var _tick := 0
var _cull_bounds_set := false


func _ready() -> void:
	for child in get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var box: BoxShape3D = child.shape
			surface_y = child.global_position.y + box.size.y * 0.5 * child.global_basis.get_scale().y
			var size: Vector3 = box.size * child.global_basis.get_scale()
			bounds = AABB(child.global_position - size * 0.5, size)
			break
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if rendered:
		_build_visuals()
	set_physics_process(surface != null)


func _build_visuals() -> void:
	var size := bounds.size
	var center := bounds.get_center()
	var material := ShaderMaterial.new()
	material.shader = load("res://addons/gamekit_water/shaders/pool_water.gdshader")
	# The PhysX water node needs a RenderingDevice: it crashes on its first tick without one (headless).
	# Without one, draw the same material on a still plane.
	if RenderingServer.get_rendering_device() == null:
		material.set_shader_parameter("water_level", surface_y)
		var plane := MeshInstance3D.new()
		plane.name = "Surface"
		plane.top_level = true
		plane.position = Vector3(center.x, 0.0, center.z)
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(size.x, size.z)
		plane.mesh = mesh
		plane.material_override = material
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plane.layers = RenderLayers.WATER
		# Lifted to the surface by the vertex shader: keep it from being culled at its rest height.
		plane.extra_cull_margin = absf(surface_y) + 1.0
		add_child(plane)
	else:
		var footprint := Vector2(size.x, size.z)
		surface = PhysXWaterSurface3D.new()
		surface.name = "Surface"
		# Grids are centred on the node; at world Y 0 the mean level is simply water_level.
		surface.top_level = true
		surface.position = Vector3(center.x, 0.0, center.z)
		surface.water_level = surface_y
		surface.depth = size.y
		surface.domain_size = footprint
		surface.grid_resolution = _stable_ripple_resolution(minf(size.x, size.z), size.y)
		surface.damping = 1.2
		surface.ripple_amplitude = 0.6
		# A sheltered pool: faint wind chop, no whitecaps.
		surface.ocean_domain_size = footprint
		surface.ocean_grid_resolution = 64
		surface.wind_speed = 4.0
		surface.wind_direction = Vector2(1.0, 0.4)
		surface.fetch = maxf(size.x, size.z)
		surface.wave_amplitude = 1.0
		surface.choppiness = 0.3
		surface.foam_enabled = false
		# Caustics come from the pool tile shader (see pool_tile.gdshader for why).
		surface.caustics_enabled = false
		surface.water_material = material
		add_child(surface)
		if reflection:
			var mirror := PlanarReflection.new()
			mirror.name = "Reflection"
			mirror.water = self
			mirror.material = material
			mirror.settings = reflection
			add_child(mirror)
	# Underwater view for any camera inside the box (fog along the underwater part of each view ray).
	underwater_view = ShaderMaterial.new()
	underwater_view.shader = load("res://addons/gamekit_water/shaders/underwater_view.gdshader")
	underwater_view.render_priority = Material.RENDER_PRIORITY_MAX
	underwater_view.set_shader_parameter("surface_y", surface_y)
	underwater_view.set_shader_parameter("box_min", bounds.position)
	underwater_view.set_shader_parameter("box_max", bounds.end)
	var view := MeshInstance3D.new()
	view.name = "UnderwaterView"
	view.layers = RenderLayers.WATER
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	view.mesh = quad
	view.material_override = underwater_view
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Positioned in clip space by the shader: never frustum-culled.
	view.extra_cull_margin = 16384.0
	add_child(view)


## Ripple cells per side that keep the engine's explicit wave solver stable: the wave speed sqrt(g * depth)
## may cross at most half a cell per 60 Hz tick. At 2 m depth, 128 cells over 10 m (0.94 cells per tick)
## diverged to NaN within seconds of swimming; 64 (0.47) stays stable.
static func _stable_ripple_resolution(side: float, depth: float) -> int:
	const MAX_CELLS_PER_TICK := 0.5
	var speed := sqrt(9.81 * depth)
	return clampi(floori(side * MAX_CELLS_PER_TICK * 60.0 / speed), 16, 128)


func _physics_process(delta: float) -> void:
	_correct_level(delta)
	for body in _bodies:
		var extent := _extent(body)
		var center: Vector3 = extent[0]
		var gap := absf(center.y - surface_y) - float(extent[1])
		var proximity := clampf(1.0 - gap / RIPPLE_REACH, 0.0, 1.0)
		var id := _ripple_id(body)
		if proximity <= 0.0:
			surface.clear_sphere(id)
			continue
		var velocity := _velocity_of(body)
		var speed := Vector2(velocity.x, velocity.z).length()
		var strength := clampf(RESTING_WAKE + (1.0 - RESTING_WAKE) * speed / WAKE_REFERENCE_SPEED, RESTING_WAKE, 1.0) * proximity
		surface.submit_sphere(id, Vector3(center.x, surface_y, center.z), float(extent[2]), strength)


func _correct_level(dt: float) -> void:
	if not _cull_bounds_set:
		_cull_bounds_set = _widen_cull_bounds(surface)
	_tick += 1
	if _tick % LEVEL_INTERVAL == 0:
		var shape: BoxShape3D = (get_child(0) as CollisionShape3D).shape
		var half := Vector2(shape.size.x, shape.size.z) * 0.45
		var sum := 0.0
		var count := 0
		for i in LEVEL_SAMPLES:
			for j in LEVEL_SAMPLES:
				var t := Vector2(i, j) / (LEVEL_SAMPLES - 1) * 2.0 - Vector2.ONE
				var h: float = surface.sample_height(global_position + Vector3(t.x * half.x, 0.0, t.y * half.y))
				if is_finite(h):
					sum += h
					count += 1
		if count > 0:
			_level_target = surface_y - sum / count
	_level_correction = lerpf(_level_correction, _level_target, 1.0 - exp(-LEVEL_EASE_RATE * dt))
	var water := surface.water_material as ShaderMaterial
	if water == null:
		return
	water.set_shader_parameter(LEVEL_CORRECTION_PARAM, _level_correction)
	if underwater_view == null:
		return
	underwater_view.set_shader_parameter(LEVEL_CORRECTION_PARAM, _level_correction)
	# The node binds (and may rebind) these on its own material only.
	for param in SHARED_SURFACE_PARAMS:
		underwater_view.set_shader_parameter(param, water.get_shader_parameter(param))


## The node's surface mesh is a flat plane at the node's height (Y 0); the water material lifts it to the
## water level in the vertex shader, which culling does not see. Without a wider margin the whole surface
## was culled whenever the camera looked up from under water.
func _widen_cull_bounds(node: Node) -> bool:
	var found := false
	for child in node.get_children(true):
		if child is GeometryInstance3D:
			child.extra_cull_margin = absf(surface_y - child.global_position.y) + 1.0
			# Kept out of the planar reflection.
			child.layers = RenderLayers.WATER
			found = true
	return found


func _exit_tree() -> void:
	if surface:
		for body in _bodies:
			surface.clear_sphere(_ripple_id(body))
	_bodies.clear()


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("on_water_entered"):
		body.on_water_entered(self)
	if surface == null:
		return
	_bodies.append(body)
	# Splash scaled by the entry speed.
	var speed := absf(_velocity_of(body).y)
	if speed > 1.0:
		var at := Vector3(body.global_position.x, surface_y, body.global_position.z)
		surface.submit_impulse(at, float(_extent(body)[2]) * 1.5, minf(speed / SPLASH_REFERENCE_SPEED, 1.0))


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("on_water_exited"):
		body.on_water_exited(self)
	if surface and body in _bodies:
		_bodies.erase(body)
		surface.clear_sphere(_ripple_id(body))


static func _ripple_id(body: Node) -> int:
	# Instance ids are 64-bit; the ripple id is a 32-bit int (the C# version truncated the same way).
	var id := body.get_instance_id() & 0xFFFFFFFF
	return id - 0x100000000 if id >= 0x80000000 else id


static func _velocity_of(body: Node3D) -> Vector3:
	if body is CharacterBody3D:
		return body.velocity
	if body is RigidBody3D:
		return body.linear_velocity
	return Vector3.ZERO


## Vertical centre, half height and horizontal radius of a body, for ripple proxies.
static func _extent(body: Node3D) -> Array:
	if body.has_method("get_water_extent"):
		return body.get_water_extent()
	return [body.global_position, 0.3, 0.4]
