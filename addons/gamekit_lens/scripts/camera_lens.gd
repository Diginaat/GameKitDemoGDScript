class_name CameraLens
extends Node3D
## Photographic camera finish for a Camera3D: a full-screen lens pass (distortion, chromatic aberration,
## depth of field, halation, grading, vignette, grain) and a lens flare overlay for the sun and for lights
## in the FLARE_GROUP group. The look is a LensProfile.
##
## Setup: add as a child of the Camera3D (or set `camera`). Ported and refined from EpicCameraX (MIT,
## Diginaat / DevKine).
##
## The pass only draws while its camera is the current one, and it sits on RenderLayers.VIEWMODEL
## (first-person only), so mirror, rain-cover and other capture cameras never see it. It doesn't touch the
## camera's CameraAttributes (exposure stays with the environment and the weather).

## Lights (any Light3D) in this group get a lens flare. Opt-in, so big maps don't pay for every lamp.
const FLARE_GROUP := &"lens_flare"

const MAX_SOURCES := 16
const MAX_FLARES := 12 # lens_flare.gdshader MAX_FLARES
const SOURCE_RESCAN_INTERVAL := 0.5
const SUN_DISTANCE := 2000.0
const SCREEN_ENTRY_MARGIN := 0.08
const SCREEN_EDGE_SOFTNESS := 0.03
const EDGE_PRESENCE := 0.2

## The look. Null or a profile with everything off = no lens effect (the pass is hidden).
@export var profile: LensProfile:
	set(value):
		profile = value
		refresh()
## Camera to finish. Empty = the parent Camera3D.
@export var camera: Camera3D
## Sun for the sun flare. Empty = the first DirectionalLight3D in the scene.
@export var sun: DirectionalLight3D
## Physics layers that block a flare source (a wall in front of a lamp hides its flare).
@export_flags_3d_physics var occlusion_mask: int = CollisionLayers.WORLD
## Canvas layer of the flare overlay: above the 3D view, below HUDs on layer 1 and up.
@export var flare_canvas_layer := 0

var _quad: MeshInstance3D
var _post: ShaderMaterial
var _flare_layer: CanvasLayer
var _flare_rect: ColorRect
var _flare: ShaderMaterial
var _is_ready := false
var _camera: Camera3D
var _sun_searched := false
var _rescan := 0.0
var _lights: Array[Light3D] = []
var _ray: PhysicsRayQueryParameters3D

# Flare sources with temporal fade, keyed by instance id. Fixed arrays: no per-frame allocation.
var _ids := PackedInt64Array()
var _state := PackedVector4Array() # uv.x, uv.y, size, intensity
var _tint := PackedVector4Array()  # rgb, visibility gate
var _seen := PackedByteArray()
var _taken := PackedByteArray()
var _flare_data := PackedVector4Array()
var _flare_tint := PackedVector4Array()


func _ready() -> void:
	_ids.resize(MAX_SOURCES)
	_state.resize(MAX_SOURCES)
	_tint.resize(MAX_SOURCES)
	_seen.resize(MAX_SOURCES)
	_taken.resize(MAX_SOURCES)
	_flare_data.resize(MAX_FLARES)
	_flare_tint.resize(MAX_FLARES)

	_post = ShaderMaterial.new()
	_post.shader = load("res://addons/gamekit_lens/shaders/lens_post.gdshader")
	# First in the transparent pass. Godot copies the screen texture before transparents, so a later pass
	# would paint that copy over rain, water and Label3D. Transparents therefore draw on top of the lens
	# pass, without lens effects.
	_post.render_priority = Material.RENDER_PRIORITY_MIN
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(2.0, 2.0) # vertices = clip-space screen corners
	_quad = MeshInstance3D.new()
	_quad.name = "LensPass"
	_quad.mesh = quad_mesh
	_quad.material_override = _post
	_quad.layers = RenderLayers.VIEWMODEL
	_quad.extra_cull_margin = 16384.0
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_quad.position = Vector3(0.0, 0.0, -1.0)
	add_child(_quad)

	_flare = ShaderMaterial.new()
	_flare.shader = load("res://addons/gamekit_lens/shaders/lens_flare.gdshader")
	_flare_layer = CanvasLayer.new()
	_flare_layer.name = "LensFlare"
	_flare_layer.layer = flare_canvas_layer
	_flare_rect = ColorRect.new()
	_flare_rect.material = _flare
	_flare_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_flare_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flare_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flare_layer.add_child(_flare_rect)
	add_child(_flare_layer)

	_is_ready = true
	refresh()


## Re-applies `profile` to the shaders. Call after changing profile values from code.
func refresh() -> void:
	if not _is_ready:
		return
	_quad.visible = profile != null and profile.any_post_effect
	if profile == null:
		return
	profile.apply_post(_post)
	profile.apply_flare(_flare)


func _process(delta: float) -> void:
	_camera = camera if camera else get_parent() as Camera3D
	var active := profile != null and _camera != null and _camera.is_current()
	_quad.visible = active and profile.any_post_effect
	if not active:
		_flare_rect.visible = false
		return
	_post.set_shader_parameter("post_dof_near_clip", _camera.near)
	_post.set_shader_parameter("post_dof_far_clip", _camera.far)
	_update_flares(delta)


func _update_flares(dt: float) -> void:
	var p := profile
	var cam := _camera
	var viewport := cam.get_viewport().get_visible_rect().size
	if not p.flare_enabled or viewport.x <= 0.0 or viewport.y <= 0.0:
		_flare_rect.visible = false
		_ids.fill(0)
		return

	_rescan -= dt
	if _rescan <= 0.0:
		_rescan = SOURCE_RESCAN_INTERVAL
		_lights.clear()
		for n in get_tree().get_nodes_in_group(FLARE_GROUP):
			if n is Light3D and not n is DirectionalLight3D:
				_lights.append(n)
	if sun == null and not _sun_searched:
		_sun_searched = true
		var scene := get_tree().current_scene
		if scene:
			var found := scene.find_children("*", "DirectionalLight3D", true, false)
			if not found.is_empty():
				sun = found[0] as DirectionalLight3D

	_seen.fill(0)
	for light in _lights:
		if not is_instance_valid(light) or not light.is_visible_in_tree() or light.light_energy < p.flare_energy_threshold:
			continue
		var pos := light.global_position
		var screen := _on_screen(cam, pos, viewport)
		if screen.z <= 0.0 or _occluded(cam, pos):
			continue
		var distance := cam.global_position.distance_to(pos)
		var distance_factor := clampf(1.0 / pow(maxf(distance, 1.0) / 12.0, p.flare_distance_falloff), 0.18, 1.0)
		var energy := maxf(light.light_energy - p.flare_energy_threshold, 0.0)
		var intensity := clampf(0.45 + energy * 0.2, 0.0, 8.0) * distance_factor * p.flare_intensity * screen.z
		var size := p.flare_size * (1.0 + energy * 0.08)
		var c := light.light_color
		_track(light.get_instance_id(), Vector4(screen.x, screen.y, size, intensity), Vector4(c.r, c.g, c.b, 0.2), dt)

	if p.sun_flare and sun != null and is_instance_valid(sun) and sun.is_visible_in_tree():
		var to_sun := sun.global_basis.z.normalized() # a light shines along -Z
		var facing := (-cam.global_basis.z).dot(to_sun)
		var pos := cam.global_position + to_sun * minf(SUN_DISTANCE, cam.far * 0.5)
		if facing > 0.0:
			var screen := _on_screen(cam, pos, viewport)
			if screen.z > 0.0 and not _occluded(cam, pos):
				# Scales with the sun's energy (no floor), so overcast weather that dims the sun dims the flare.
				var intensity := sun.light_energy * p.sun_flare_intensity * p.flare_intensity * screen.z * pow(facing, 1.35)
				var c := sun.light_color
				_track(sun.get_instance_id(), Vector4(screen.x, screen.y, p.flare_size * p.sun_flare_size, intensity),
					Vector4(c.r, c.g, c.b, 1.0), dt)

	# Sources that disappeared fade out instead of popping.
	for i in MAX_SOURCES:
		if _ids[i] == 0 or _seen[i]:
			continue
		var s := _state[i]
		s.w = lerpf(s.w, 0.0, 1.0 - exp(-p.flare_fade_out_speed * 1.5 * dt))
		_state[i] = s
		if s.w <= 0.01:
			_ids[i] = 0

	var count := _select_brightest()
	_flare_rect.visible = count > 0
	if count == 0:
		return
	_flare.set_shader_parameter("flare_count", count)
	_flare.set_shader_parameter("flare_data", _flare_data)
	_flare.set_shader_parameter("flare_tint", _flare_tint)


func _track(id: int, target: Vector4, tint: Vector4, step: float) -> void:
	var slot := -1
	var free := -1
	for i in MAX_SOURCES:
		if _ids[i] == id:
			slot = i
			break
		if _ids[i] == 0 and free < 0:
			free = i
	if slot < 0:
		if free < 0:
			return
		slot = free
		_ids[slot] = id
		_state[slot] = Vector4(target.x, target.y, target.z, 0.0)
	var current := _state[slot]
	var speed := profile.flare_fade_in_speed if target.w >= current.w else profile.flare_fade_out_speed
	var k := 1.0 - exp(-speed * step)
	_state[slot] = Vector4(target.x, target.y, lerpf(current.z, target.z, k), lerpf(current.w, target.w, k))
	_tint[slot] = tint
	_seen[slot] = 1


## Copies the strongest sources (intensity × size) into the shader arrays; returns the count.
func _select_brightest() -> int:
	_flare_data.fill(Vector4.ZERO)
	_flare_tint.fill(Vector4.ZERO)
	_taken.fill(0)
	var count := 0
	while count < MAX_FLARES:
		var best := -1
		var best_score := 0.001
		for i in MAX_SOURCES:
			var s := _state[i]
			var score := s.w * s.z
			if _ids[i] != 0 and not _taken[i] and s.w > 0.001 and score > best_score:
				best = i
				best_score = score
		if best < 0:
			break
		_taken[best] = 1
		_flare_data[count] = _state[best]
		_flare_tint[count] = _tint[best]
		count += 1
	return count


## Returns (uv.x, uv.y, presence); presence 0 = off screen.
static func _on_screen(cam: Camera3D, pos: Vector3, viewport: Vector2) -> Vector3:
	if cam.is_position_behind(pos):
		return Vector3.ZERO
	var sp := cam.unproject_position(pos)
	var uv := Vector2(sp.x / viewport.x, sp.y / viewport.y)
	return Vector3(uv.x, uv.y, _axis_presence(uv.x) * _axis_presence(uv.y))


## 1 inside the frame, fading to EDGE_PRESENCE at the edge and to 0 just outside, so a flare slides in as
## its source nears the frame.
static func _axis_presence(v: float) -> float:
	if v < -SCREEN_ENTRY_MARGIN or v > 1.0 + SCREEN_ENTRY_MARGIN:
		return 0.0
	if v < 0.0:
		return EDGE_PRESENCE * smoothstep(-SCREEN_ENTRY_MARGIN, 0.0, v)
	if v > 1.0:
		return EDGE_PRESENCE * (1.0 - smoothstep(1.0, 1.0 + SCREEN_ENTRY_MARGIN, v))
	return lerpf(EDGE_PRESENCE, 1.0, smoothstep(0.0, SCREEN_EDGE_SOFTNESS, minf(v, 1.0 - v)))


func _occluded(cam: Camera3D, pos: Vector3) -> bool:
	if occlusion_mask == 0:
		return false
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.hit_from_inside = true
	_ray.from = cam.global_position
	_ray.to = pos
	_ray.collision_mask = occlusion_mask
	return not cam.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()
