class_name RainEmitter
extends Node3D
## GPU rain around the camera: lit, see-through streaks of varying size, distant rain curtains, impacts
## where drops hit geometry (ring on wet surfaces, motion-blurred droplet crown), a low splash mist, and no
## rain under roofs.
##
## The emitter follows the current camera, so only a small volume around the player is simulated. A
## height-field collider (also following the camera) stops drops on the first surface they hit and spawns
## an impact there. `intensity` scales the live particle count via amount_ratio, so changing it never
## restarts the system.

const IMPACT_LIFETIME := 0.45

@export_range(0, 1) var intensity := 0.0:
	set(value):
		intensity = value
		_update_intensity()
## Horizontal wind in m/s. Slants the rain.
@export var wind := Vector3.ZERO:
	set(value):
		wind = value
		_update_motion()
## Color of the distant rain curtains. WeatherSystem sets it to the fog color so the curtains match the
## scene lighting.
@export var curtain_color := Color(0.6, 0.63, 0.68):
	set(value):
		curtain_color = value
		if _curtain_material:
			_curtain_material.set_shader_parameter("curtain_color", value)
## Node to center the rain on. Defaults to the active camera.
@export var follow_target: Node3D

@export_group("Volume")
## Particles at intensity 1. Cost scales with this, mostly as overdraw.
@export var max_drops := 24000
@export var area_size := 36.0
@export var emit_height := 14.0
@export var fall_speed := 11.0

@export_group("Look")
## Long, thin streaks read like real rain (a camera exposure smears each drop).
@export var streak_length := 1.1
@export var streak_width := 0.005
@export_range(0, 1) var opacity := 0.26

@export_group("Distance")
## Draw far-off rain as moving sheets and streaks on a cylinder around the camera.
@export var curtains_enabled := true
@export var curtain_radius := 22.0
## Low volumetric haze of spray at ground level that thickens with the rain (needs Environment volumetric
## fog).
@export var splash_mist_enabled := true
## Fog density of the splash mist at intensity 1.
@export_range(0, 1) var splash_mist_density := 0.06
## Height of the camera above the ground it stands on (the mist sits there).
@export var camera_height := 1.7

@export_group("Impacts")
@export var impacts_enabled := true
## Impact particles at intensity 1. Each draws a ring and a droplet crown.
@export var max_impacts := 8000
@export_range(0, 12) var droplets_per_impact := 6
## Faint spray puff at each impact. Off by default: single puffs tend to read as snowflakes.
@export var impact_mist := false

@export_group("Collision")
@export var collision_resolution: GPUParticlesCollisionHeightField3D.Resolution = \
	GPUParticlesCollisionHeightField3D.RESOLUTION_512
## Re-capture the collision height field this often (seconds) even when standing still, so moved objects
## don't leave invisible surfaces that drops splash on. 0 = only on move.
@export_range(0, 2) var collision_refresh_interval := 0.2

var _drops: GPUParticles3D
var _impacts: GPUParticles3D
var _collision: GPUParticlesCollisionHeightField3D
var _process_material: ParticleProcessMaterial
var _curtain: MeshInstance3D
var _curtain_material: ShaderMaterial
var _splash_mist: FogVolume
var _splash_mist_material: FogMaterial
var _collision_timer := 0.0


func _ready() -> void:
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	_build()
	_update_motion()
	_update_intensity()


func _process(delta: float) -> void:
	var target: Node3D = follow_target if follow_target else get_viewport().get_camera_3d()
	if target:
		global_position = target.global_position
		if _splash_mist:
			# World-snapped, not glued to the camera: a fog volume that moves every frame smears the
			# volumetric fog's temporal filter.
			var s := target.global_position.snapped(Vector3(2.0, 0.5, 2.0))
			_splash_mist.global_position = Vector3(s.x, s.y - camera_height + 0.6, s.z)
	if collision_refresh_interval > 0.0 and intensity > 0.001:
		_collision_timer -= delta
		if _collision_timer <= 0.0:
			_collision_timer = collision_refresh_interval
			RenderingServer.particles_collision_height_field_update(_collision.get_base())


func _build() -> void:
	_process_material = ParticleProcessMaterial.new()
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_material.emission_box_extents = Vector3(area_size * 0.5, 0.5, area_size * 0.5)
	_process_material.gravity = Vector3.ZERO
	_process_material.spread = 1.5
	# Drop size variation (the streak shader also varies each drop).
	_process_material.scale_min = 0.7
	_process_material.scale_max = 1.3
	_process_material.particle_flag_align_y = true
	_process_material.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	if impacts_enabled:
		_process_material.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
		_process_material.sub_emitter_amount_at_collision = 1

	var drop_material := ShaderMaterial.new()
	drop_material.shader = _load_shader("rain_streak")
	drop_material.set_shader_parameter("streak_length", streak_length)
	drop_material.set_shader_parameter("streak_width", streak_width)
	drop_material.set_shader_parameter("opacity", opacity)
	drop_material.set_shader_parameter("far_fade", area_size * 0.9)

	_drops = _make_particles(max_drops, (emit_height + 6.0) / fall_speed, _process_material)
	var drop_mesh := QuadMesh.new()
	drop_mesh.material = drop_material
	_drops.draw_pass_1 = drop_mesh
	_drops.visibility_aabb = AABB(Vector3(-area_size, -emit_height - 10.0, -area_size),
		Vector3(area_size * 2.0, emit_height + 12.0, area_size * 2.0))
	_drops.collision_base_size = 0.02
	# Start pre-simulated: no "front" of rain falling from the sky when it begins.
	_drops.preprocess = _drops.lifetime
	add_child(_drops)

	# Impacts don't move; their shader animates the ring and droplets.
	var impact_process := ParticleProcessMaterial.new()
	impact_process.gravity = Vector3.ZERO
	impact_process.initial_velocity_min = 0.0
	impact_process.initial_velocity_max = 0.0
	_impacts = _make_particles(max_impacts, IMPACT_LIFETIME, impact_process)
	_impacts.visibility_aabb = _drops.visibility_aabb
	var ring := PlaneMesh.new()
	ring.size = Vector2.ONE
	ring.material = _make_impact_material(0)
	var passes: Array[Mesh] = [ring, _make_crown_sheet_mesh(24, _make_impact_material(3))]
	if droplets_per_impact > 0:
		passes.append(_make_crown_mesh(droplets_per_impact, _make_impact_material(1)))
	if impact_mist:
		var puff := QuadMesh.new()
		puff.material = _make_impact_material(2)
		passes.append(puff)
	_impacts.draw_passes = passes.size()
	for i in passes.size():
		_impacts.set_draw_pass_mesh(i, passes[i])
	add_child(_impacts)
	if impacts_enabled:
		_drops.sub_emitter = _drops.get_path_to(_impacts)

	if curtains_enabled:
		_curtain_material = ShaderMaterial.new()
		_curtain_material.shader = _load_shader("rain_curtain")
		_curtain_material.set_shader_parameter("fall_speed", fall_speed)
		_curtain_material.set_shader_parameter("curtain_color", curtain_color)
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = curtain_radius
		cylinder.bottom_radius = curtain_radius
		cylinder.height = 30.0
		cylinder.radial_segments = 48
		cylinder.rings = 1
		cylinder.cap_top = false
		cylinder.cap_bottom = false
		cylinder.material = _curtain_material
		_curtain = MeshInstance3D.new()
		_curtain.mesh = cylinder
		_curtain.position = Vector3(0.0, 6.0, 0.0)
		_curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_curtain.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_curtain.layers = RenderLayers.WEATHER
		add_child(_curtain)

	if splash_mist_enabled:
		_splash_mist_material = FogMaterial.new()
		_splash_mist_material.density = 0.0
		_splash_mist_material.albedo = Color(0.85, 0.88, 0.92)
		_splash_mist_material.height_falloff = 2.5 # densest at the ground, thinning out upward
		_splash_mist_material.edge_fade = 0.4
		_splash_mist = FogVolume.new()
		_splash_mist.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		# Larger than the rain area with soft edges, so its 2 m position steps never show.
		_splash_mist.size = Vector3(area_size * 1.5, 1.2, area_size * 1.5)
		_splash_mist.top_level = true
		_splash_mist.material = _splash_mist_material
		add_child(_splash_mist)

	_collision = GPUParticlesCollisionHeightField3D.new()
	_collision.size = Vector3(area_size, emit_height + 12.0, area_size)
	_collision.resolution = collision_resolution
	_collision.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_collision.follow_camera_enabled = true
	# cull_mask = which particles collide; heightfield_mask = which geometry is recorded.
	_collision.cull_mask = RenderLayers.WEATHER
	_collision.heightfield_mask = RenderLayers.ALL & ~(RenderLayers.WEATHER | RenderLayers.WEATHER_CAPTURE | RenderLayers.VIEWMODEL)
	add_child(_collision)


static func _load_shader(shader_name: String) -> Shader:
	return load("res://addons/gamekit_weather/shaders/%s.gdshader" % shader_name)


static func _make_particles(amount: int, lifetime: float, process: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.fixed_fps = 0
	p.process_material = process
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.layers = RenderLayers.WEATHER
	return p


static func _make_impact_material(mode: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _load_shader("rain_impact")
	material.set_shader_parameter("mode", mode)
	material.set_shader_parameter("lifetime", IMPACT_LIFETIME)
	return material


## Open cylinder for the crown sheet; UV.x = angle (0..1), UV.y = height (0..1). The shader shapes and
## animates it.
static func _make_crown_sheet_mesh(segments: int, material: Material) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in segments + 1:
		var u := float(i) / segments
		for v in 2:
			vertices.append(Vector3(cos(u * TAU), v, sin(u * TAU)))
			uvs.append(Vector2(u, v))
	for i in segments:
		var a := i * 2
		indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	mesh.custom_aabb = AABB(Vector3(-0.2, -0.05, -0.2), Vector3(0.4, 0.3, 0.4))
	return mesh


## One small quad per droplet; COLOR.r is the droplet index (0..1) for the shader.
static func _make_crown_mesh(droplets: int, material: Material) -> ArrayMesh:
	var corners: Array[Vector2] = [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in droplets:
		var index_color := Color(float(i) / droplets, 0.0, 0.0)
		var b := i * 4
		for c in corners:
			vertices.append(Vector3(c.x, c.y, 0.0))
			uvs.append(c + Vector2(0.5, 0.5))
			colors.append(index_color)
		indices.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	# The shader moves droplets up to ~0.4 m from the particle; keep them from being culled.
	mesh.custom_aabb = AABB(Vector3(-0.5, -0.1, -0.5), Vector3(1.0, 0.6, 1.0))
	return mesh


func _update_motion() -> void:
	if _process_material == null or _drops == null:
		return
	var velocity := Vector3(wind.x, -fall_speed, wind.z)
	_process_material.direction = velocity.normalized()
	_process_material.initial_velocity_min = velocity.length() * 0.95
	_process_material.initial_velocity_max = velocity.length() * 1.05
	if _curtain_material:
		_curtain_material.set_shader_parameter("wind", Vector2(wind.x, wind.z))
	# Spawn upwind so slanted rain still lands around the camera.
	var horizontal := Vector3(wind.x, 0.0, wind.z)
	_drops.position = Vector3(0.0, emit_height, 0.0) - horizontal * (emit_height / fall_speed)


func _update_intensity() -> void:
	if _drops == null:
		return
	var active := intensity > 0.001
	_drops.amount_ratio = intensity
	_impacts.amount_ratio = intensity
	_drops.emitting = active
	if _curtain:
		_curtain.visible = active
		_curtain_material.set_shader_parameter("intensity", intensity)
	if _splash_mist:
		_splash_mist.visible = active
		# Spray grows faster than linearly: light rain barely mists, heavy rain does.
		_splash_mist_material.density = splash_mist_density * intensity * intensity
