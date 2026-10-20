class_name DemoHud
extends CanvasLayer
## The demo's HUD: crosshair, interaction prompt, ammo, current weather and lens look, a controls panel
## (H hides it), and muffled audio under water. Also lets the demo switch the lens look (L). It is an
## example of game UI on top of GameKit; copy and change it for your own game.

const CONTROLS := "WASD move    Mouse look    Space jump    Ctrl crouch    Shift sprint    Alt walk\n" \
	+ "Shift+Ctrl slide    Space+W at a ledge: mantle    E use / pick up    LMB fire / throw    R reload\n" \
	+ "1 / 2 / 3 weapons    F7 weather    L lens look    H hide help    Esc release mouse"

const CYCLE_LENS_ACTION := &"demo_cycle_lens"
const TOGGLE_HELP_ACTION := &"demo_toggle_help"

@export var player_path: NodePath
## Optional: shows the weather name.
@export var weather: WeatherSystem
## Lens looks for the L key, in order.
@export var lens_profiles: Array[LensProfile] = []

var _player: FpsPlayerController
var _lens: CameraLens
var _viewmodel: PlayerViewmodel
var _prompt: Label
var _ammo: Label
var _status: Label
var _help: Control
var _lens_index := 0
var _low_pass_index := -1


func _ready() -> void:
	_add_key(CYCLE_LENS_ACTION, KEY_L)
	_add_key(TOGGLE_HELP_ACTION, KEY_H)

	_player = get_node(player_path) as FpsPlayerController
	_viewmodel = _player.get_node_or_null("CameraRig/Pitch/Effects/Camera3D/Viewmodel") as PlayerViewmodel
	_lens = _player.get_node_or_null("CameraRig/Pitch/Effects/Camera3D/Lens") as CameraLens

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.add_theme_font_size_override("font_size", 22)
	crosshair.modulate = Color(1, 1, 1, 0.85)
	add_child(crosshair)

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position = Vector2(0, 42)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_style(_prompt, 19)
	add_child(_prompt)

	_ammo = Label.new()
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ammo.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ammo.position -= Vector2(28, 24)
	_style(_ammo, 22)
	add_child(_ammo)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.position += Vector2(-24, 18)
	_style(_status, 16)
	add_child(_status)

	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.07, 0.55)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.set_corner_radius_all(8)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box)
	var help := Label.new()
	help.text = CONTROLS
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_constant_override("line_spacing", 4)
	panel.add_child(help)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position += Vector2(18, -18)
	_help = panel
	add_child(panel)

	var interaction := _player.get_node_or_null("Interaction") as InteractionRay
	if interaction:
		interaction.prompt_changed.connect(func(text: String) -> void:
			_prompt.text = "" if text.is_empty() else "[E]  " + text)

	var swim := _player.motor.get_ability(SwimMovement) as SwimMovement
	if swim:
		swim.underwater_changed.connect(_set_underwater)

	if _lens and _lens.profile:
		_lens_index = maxi(lens_profiles.find(_lens.profile), 0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_HELP_ACTION):
		_help.visible = not _help.visible
	elif event.is_action_pressed(CYCLE_LENS_ACTION) and _lens and not lens_profiles.is_empty():
		_lens_index = (_lens_index + 1) % lens_profiles.size()
		_lens.profile = lens_profiles[_lens_index]


func _process(_delta: float) -> void:
	var weapon: Weapon = _viewmodel.current_weapon if _viewmodel else null
	_ammo.text = "" if weapon == null else "%s   %d / %d" % [weapon.display_name, weapon.ammo, weapon.magazine_size]
	var weather_text := "Weather  " + weather.weather_name if weather else ""
	var lens_text := "Lens  " + _lens.profile.display_name if _lens and _lens.profile else ""
	_status.text = weather_text + "\n" + lens_text


func _exit_tree() -> void:
	if _low_pass_index >= 0:
		AudioServer.remove_bus_effect(0, _low_pass_index)
	_low_pass_index = -1


func _set_underwater(underwater: bool) -> void:
	# Muffle the master bus while the eyes are under water.
	if _low_pass_index < 0:
		var filter := AudioEffectLowPassFilter.new()
		filter.cutoff_hz = 600.0
		AudioServer.add_bus_effect(0, filter)
		_low_pass_index = AudioServer.get_bus_effect_count(0) - 1
	AudioServer.set_bus_effect_enabled(0, _low_pass_index, underwater)


static func _style(label: Label, size: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 6)


## Adds an input action with a default key unless the project already defines it (rebindable).
static func _add_key(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)
