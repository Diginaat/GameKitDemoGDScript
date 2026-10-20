class_name PlayerDebugOverlay
extends CanvasLayer
## F3: text readout of movement state. F4: in-world lines for the capsule, velocity, floor normal and step
## probe. Both cost nothing while hidden; the text refreshes at 10 Hz.

const REFRESH_INTERVAL := 0.1
const SEGMENTS := 16

@export var player_path: NodePath

var _player: FpsPlayerController
var _label: Label
var _lines: MeshInstance3D
var _mesh: ImmediateMesh
var _refresh := 0.0
var _tick_us_average := 0.0


func _ready() -> void:
	_player = get_node(player_path) as FpsPlayerController
	_label = Label.new()
	_label.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)

	_mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_lines = MeshInstance3D.new()
	_lines.mesh = _mesh
	_lines.material_override = material
	_lines.visible = false
	_lines.top_level = true
	_lines.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_player.add_child.call_deferred(_lines)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.DEBUG_OVERLAY):
		_label.visible = not _label.visible
	elif event.is_action_pressed(InputActions.DEBUG_DRAW):
		_lines.visible = not _lines.visible


func _process(delta: float) -> void:
	_tick_us_average = lerpf(_tick_us_average, _player.last_tick_microseconds, 0.05)
	if _lines.visible:
		_draw_lines()
	_refresh -= delta
	if not _label.visible or _refresh > 0.0:
		return
	_refresh = REFRESH_INTERVAL
	_label.text = _build_text()


func _build_text() -> String:
	var m := _player.motor
	var s := _player.movement
	var slope := rad_to_deg(acos(clampf(m.floor_normal.y, -1.0, 1.0)))
	var state_name: String = m.active_ability.get_state_name() if m.active_ability \
		else PlayerMotor.MovementState.keys()[m.state].capitalize()
	if m.stance.is_crouched:
		state_name += " +Crouch"
	if m.stance.is_stand_blocked:
		state_name += " (stand blocked)"
	if m.is_sprinting:
		state_name += " +Sprint"
	var lines := PackedStringArray([
		"Profile   %s  |  Camera %s" % [s.profile_name, _player.camera_settings.preset_name],
		"State     " + state_name,
		"H speed   %.2f m/s" % m.horizontal_velocity.length(),
		"V speed   %.2f m/s" % m.velocity.y,
		"Accel     %.1f m/s²" % m.horizontal_acceleration.length(),
		"Grounded  %s   normal (%.2f, %.2f, %.2f)  slope %.1f°" % [m.is_on_floor, m.floor_normal.x, m.floor_normal.y, m.floor_normal.z, slope],
		"Surface   " + Surfaces.SurfaceType.keys()[m.surface.type].capitalize(),
		"Jump buf  %s   coyote %s" % [m.jump_buffered, m.coyote_available],
		"Platform  (%.1f, %.1f, %.1f)" % [m.platform_velocity.x, m.platform_velocity.y, m.platform_velocity.z],
		"Physics   %d Hz   FPS %d   cap %d" % [Engine.physics_ticks_per_second, Engine.get_frames_per_second(), Engine.max_fps],
		"Tick cost %.1f µs   step queries %d" % [_tick_us_average, m.steps.queries_this_tick],
		"Memory    %.1f MB static" % (OS.get_static_memory_usage() / 1048576.0),
		"Engine    " + str(ProjectSettings.get_setting("physics/3d/physics_engine")),
	])
	return "\n".join(lines)


func _draw_lines() -> void:
	var m := _player.motor
	var origin := _player.get_global_transform_interpolated().origin
	var r := _player.movement.radius
	var h := m.stance.height
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	var capsule_color := Color.GREEN if m.is_on_floor else Color.ORANGE
	for i in SEGMENTS:
		var a0 := i * TAU / SEGMENTS
		var a1 := (i + 1) * TAU / SEGMENTS
		var p0 := Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		for y in [r, h - r]:
			_line(origin + p0 + Vector3.UP * y, origin + p1 + Vector3.UP * y, capsule_color)
		if i % 4 == 0:
			_line(origin + p0 + Vector3.UP * r, origin + p0 + Vector3.UP * (h - r), capsule_color)

	var center := origin + Vector3.UP * 0.05
	_line(center, center + m.velocity * 0.25, Color.CYAN)
	_line(center, center + m.floor_normal, Color.MAGENTA)
	var probe := m.steps.last_probe_point
	var probe_color := Color.YELLOW if m.steps.last_probe_accepted else Color.RED
	_line(probe - Vector3.RIGHT * 0.1, probe + Vector3.RIGHT * 0.1, probe_color)
	_line(probe - Vector3.BACK * 0.1, probe + Vector3.BACK * 0.1, probe_color)

	var interaction := _player.get_node_or_null("Interaction") as InteractionRay
	if interaction:
		_line(interaction.ray_from, interaction.ray_to, Color.WHITE if interaction.focused else Color.GRAY)

	_mesh.surface_end()


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(b)
