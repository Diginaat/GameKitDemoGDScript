class_name WeatherSystem
extends Node
## Drives the sky clouds, rain, fog, wind, lightning, sound, sun, exposure and surface wetness from
## WeatherPreset resources, with smooth transitions.
##
## Setup: add this node anywhere in the level. The WorldEnvironment's sky should use
## resources/weather_sky_material.tres (weather_environment.tres does), and project.godot must declare the
## four weather shader globals (see the module README). It finds the WorldEnvironment and the sun when they
## are not assigned, creates the rain, the rain occlusion map and the sound, and starts on the first preset.
## The cycle_action input (F7 by default) cycles presets.

signal weather_changed(preset: WeatherPreset)
## Emitted at each lightning flash. Distance is in meters.
signal lightning_struck(distance: float)

## Used when `presets` is left empty.
const DEFAULT_PRESETS: Array[String] = [
	"res://addons/gamekit_weather/presets/clear.tres",
	"res://addons/gamekit_weather/presets/partly_cloudy.tres",
	"res://addons/gamekit_weather/presets/overcast.tres",
	"res://addons/gamekit_weather/presets/light_rain.tres",
	"res://addons/gamekit_weather/presets/storm.tres",
	"res://addons/gamekit_weather/presets/thunderstorm.tres",
]
## Shader globals this system writes; project.godot must declare them.
const SHADER_GLOBALS: Array[String] = ["weather_wetness", "weather_rain", "weather_rain_occlusion", "weather_occlusion_area"]

const SPEED_OF_SOUND := 343.0
const WETNESS_GLOBAL := &"weather_wetness"
const RAIN_GLOBAL := &"weather_rain"
# (start time, strength, unused) of a main flash and two flickers.
const FLASH_PULSES: Array[Vector3] = [Vector3(0.0, 1.0, 0.0), Vector3(0.12, 0.6, 0.0), Vector3(0.3, 0.8, 0.0)]

## Presets cycled by next_weather(). The first one is applied at start. Leave empty to use DEFAULT_PRESETS.
@export var presets: Array[WeatherPreset] = []
## Default transition length in seconds.
@export var transition_time := 12.0
## Input action that cycles presets. Added (F7) when missing; empty disables it.
@export var cycle_action: StringName = &"cycle_weather"
## Clouds drift this many times faster than ground wind (they're higher up).
@export var cloud_wind_multiplier := 6.0
## Fraction of the wind that slants the rain.
@export var rain_wind_multiplier := 0.6
## How much storm clouds (cloud_darkness) dim the sky light, through Environment.background_energy_multiplier,
## so sky, ambient light, reflections and GI dim together.
@export_range(0, 1) var storm_sky_dimming := 0.5
## Volumetric fog tint in the darkest weather.
@export var storm_fog_color := Color(0.16, 0.17, 0.19)
## Shadow blur under a full overcast. Clouds act like a softbox, so shadows get very soft instead of
## disappearing. Uses shadow_blur, not the sun's angular size: a wider sun would also blow up its specular
## highlight on wet surfaces.
@export_range(1, 10) var overcast_shadow_blur := 6.0

@export_group("Lightning")
@export var lightning_energy := 2.5
@export var lightning_color := Color(0.78, 0.84, 1.0)
## Strikes land this far away, in meters. Thunder is delayed accordingly.
@export var lightning_distance_min := 300.0
@export var lightning_distance_max := 3000.0

@export_group("Sound")
@export var audio_enabled := true

@export_group("Scene")
## Found automatically when empty.
@export var world_environment: WorldEnvironment
## Found automatically when empty.
@export var sun: DirectionalLight3D
## Created automatically when empty.
@export var rain: RainEmitter

@export_group("Wetness")
## Seconds for surfaces to get fully wet in heavy rain.
@export var wetting_time := 20.0
## Seconds for surfaces to dry after the rain stops.
@export var drying_time := 90.0

## The blended state currently shown. Read-only for callers.
var current := WeatherPreset.new()
## The preset being shown or transitioned to.
var target: WeatherPreset
## Name of the preset being shown or transitioned to.
var weather_name: String:
	get:
		return target.display_name if target else current.display_name
## Surface wetness 0..1; lags behind the rain. Set it to start a level after rain.
var wetness: float:
	get:
		return _wetness
	set(value):
		_wetness = clampf(value, 0.0, 1.0)
var audio: WeatherAudio
var occlusion: RainOcclusion

var _from := WeatherPreset.new()
var _progress := 1.0
var _duration := 1.0
var _index := 0
var _time := 0.0
var _wetness := 0.0
var _cloud_offset := Vector2.ZERO
var _cloud_period := 0.0
var _sky_material: ShaderMaterial
var _environment: Environment
var _camera_attributes: CameraAttributes
var _gust_noise := FastNoiseLite.new()
var _lightning_light: DirectionalLight3D
var _next_strike := 0.0
var _flash_time := -1.0
var _sky_horizon_color := Color(0.62, 0.68, 0.76)
var _sky_overcast_color := Color(0.46, 0.48, 0.52)

# Scene values at start; the weather scales them and restores them on exit (resources are shared).
var _base_sun_energy := 1.0
var _base_sun_fog_energy := 1.0
var _base_sun_shadow_blur := 1.0
var _base_sun_specular := 1.0
var _base_sun_shadow_opacity := 1.0
var _base_sun_shadows := true
var _base_sun_visible := true
var _base_fog_density := 0.0
var _base_background_energy := 1.0
var _base_fog_anisotropy := 0.2
var _base_fog_sky_affect := 1.0
var _base_fog_ambient_inject := 0.0
var _base_fog_light_energy := 1.0
var _base_fog_distance_density := 0.0
var _base_fog_sky_affect_distance := 0.0
var _base_fog_enabled := false
var _base_fog_albedo := Color.WHITE
var _base_fog_light_color := Color.WHITE
var _base_exposure := 1.0
var _base_auto_exposure_scale := 0.4


func _ready() -> void:
	var scene: Node = get_tree().current_scene if get_tree().current_scene else get_parent()
	if world_environment == null:
		world_environment = _find_first(scene, "WorldEnvironment") as WorldEnvironment
	if sun == null:
		sun = _find_first(scene, "DirectionalLight3D") as DirectionalLight3D
	if rain == null:
		rain = RainEmitter.new()
		rain.name = "Rain"
		add_child(rain)
	# Keeps covered surfaces dry; runs always (surfaces also dry after rain).
	occlusion = RainOcclusion.new()
	occlusion.name = "RainOcclusion"
	add_child(occlusion)
	if audio_enabled:
		audio = WeatherAudio.new()
		audio.name = "Audio"
		add_child(audio)

	_lightning_light = DirectionalLight3D.new()
	_lightning_light.name = "Lightning"
	_lightning_light.light_color = lightning_color
	_lightning_light.light_energy = 0.0
	_lightning_light.shadow_enabled = false
	_lightning_light.visible = false
	add_child(_lightning_light)
	_gust_noise.frequency = 0.15
	_gust_noise.seed = randi()

	_capture_scene_base()
	for global_name in SHADER_GLOBALS:
		if not ProjectSettings.has_setting("shader_globals/" + global_name):
			push_error("WeatherSystem: add the '%s' shader global in Project Settings > Shader Globals (see addons/gamekit_weather/README.md)." % global_name)
	_ensure_cycle_action()

	if presets.is_empty():
		for path in DEFAULT_PRESETS:
			presets.append(load(path) as WeatherPreset)
	set_weather(presets[0], 0.0)


func _exit_tree() -> void:
	# Environment, camera attributes and sun are shared; leave them as we found them.
	if _camera_attributes:
		_camera_attributes.exposure_multiplier = _base_exposure
		_camera_attributes.auto_exposure_scale = _base_auto_exposure_scale
	if _environment:
		_environment.background_energy_multiplier = _base_background_energy
		_environment.volumetric_fog_density = _base_fog_density
		_environment.volumetric_fog_albedo = _base_fog_albedo
		_environment.volumetric_fog_ambient_inject = _base_fog_ambient_inject
		_environment.volumetric_fog_anisotropy = _base_fog_anisotropy
		_environment.volumetric_fog_sky_affect = _base_fog_sky_affect
		_environment.fog_enabled = _base_fog_enabled
		_environment.fog_density = _base_fog_distance_density
		_environment.fog_light_color = _base_fog_light_color
		_environment.fog_light_energy = _base_fog_light_energy
		_environment.fog_sky_affect = _base_fog_sky_affect_distance
	if sun:
		sun.light_energy = _base_sun_energy
		sun.light_volumetric_fog_energy = _base_sun_fog_energy
		sun.shadow_enabled = _base_sun_shadows
		sun.shadow_blur = _base_sun_shadow_blur
		sun.light_specular = _base_sun_specular
		sun.shadow_opacity = _base_sun_shadow_opacity
		sun.visible = _base_sun_visible
	RenderingServer.global_shader_parameter_set(WETNESS_GLOBAL, 0.0)
	RenderingServer.global_shader_parameter_set(RAIN_GLOBAL, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not cycle_action.is_empty() and InputMap.has_action(cycle_action) and event.is_action_pressed(cycle_action):
		next_weather()


func _process(delta: float) -> void:
	_time += delta
	if target and _progress < 1.0:
		_progress = minf(_progress + delta / _duration, 1.0)
		WeatherPreset.blend(_from, target, smoothstep(0.0, 1.0, _progress), current)
	_update_lightning(delta)
	_apply(delta)


## Transitions to a preset over `duration` seconds (negative = transition_time, 0 = instantly).
func set_weather(preset: WeatherPreset, duration := -1.0) -> void:
	if duration < 0.0:
		duration = transition_time
	target = preset
	_index = maxi(presets.find(preset), 0)
	WeatherPreset.blend(current, current, 0.0, _from)
	if duration <= 0.0:
		_progress = 1.0
		WeatherPreset.blend(preset, preset, 1.0, current)
		_wetness = preset.rain_intensity
	else:
		_progress = 0.0
		_duration = duration
	weather_changed.emit(preset)


func next_weather() -> void:
	if not presets.is_empty():
		set_weather(presets[(_index + 1) % presets.size()])


## Fires a lightning strike now, at a random distance unless one is given.
func trigger_lightning(distance := -1.0) -> void:
	if distance < 0.0:
		distance = randf_range(lightning_distance_min, lightning_distance_max)
	var azimuth := randf() * TAU
	var elevation := deg_to_rad(randf_range(20.0, 60.0))
	var direction := Vector3(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))
	if _sky_material:
		_sky_material.set_shader_parameter("lightning_direction", direction)
	_lightning_light.basis = Basis.looking_at(-direction)
	_flash_time = 0.0
	var closeness := 1.0 - inverse_lerp(lightning_distance_min, lightning_distance_max, distance)
	if audio:
		audio.play_thunder(distance / SPEED_OF_SOUND, closeness)
	lightning_struck.emit(distance)


func _update_lightning(dt: float) -> void:
	if current.lightning_per_minute > 0.05:
		_next_strike -= dt
		if _next_strike <= 0.0:
			trigger_lightning()
			_next_strike = 60.0 / current.lightning_per_minute * randf_range(0.4, 1.6)
	else:
		_next_strike = randf_range(2.0, 6.0)

	var flash := 0.0
	if _flash_time >= 0.0:
		_flash_time += dt
		# A main flash and two flickers, like a real multi-stroke strike.
		for pulse in FLASH_PULSES:
			if _flash_time >= pulse.x:
				flash = maxf(flash, pulse.y * exp(-(_flash_time - pulse.x) * 18.0))
		if _flash_time > 1.0:
			_flash_time = -1.0
	_lightning_light.visible = flash > 0.01
	_lightning_light.light_energy = flash * lightning_energy
	if _sky_material:
		_sky_material.set_shader_parameter("lightning_flash", flash)


func _apply(dt: float) -> void:
	var c := current
	# Gusts: slow noise around the base wind speed.
	var gust := clampf(_gust_noise.get_noise_1d(_time) * 1.6 + 0.5, 0.0, 1.0)
	var wind_speed := c.wind_speed * (1.0 + c.gustiness * (gust * 1.4 - 0.4))
	var heading := deg_to_rad(c.wind_direction_degrees)
	var wind := Vector2(sin(heading), -cos(heading)) * wind_speed
	var darkness := 1.0 - c.scene_brightness

	if _sky_material:
		_cloud_offset += wind * cloud_wind_multiplier * dt
		if _cloud_period > 0.0:
			_cloud_offset = Vector2(fposmod(_cloud_offset.x, _cloud_period), fposmod(_cloud_offset.y, _cloud_period))
		_sky_material.set_shader_parameter("cloud_coverage", c.cloud_coverage)
		_sky_material.set_shader_parameter("cloud_density", c.cloud_density)
		_sky_material.set_shader_parameter("cloud_darkness", c.cloud_darkness)
		_sky_material.set_shader_parameter("overcast", c.overcast)
		_sky_material.set_shader_parameter("cloud_offset", _cloud_offset)

	# How much direct sunlight still reaches the air below the clouds. Fog sits under the cloud layer, so it
	# only scatters sunlight that gets through.
	var sun_through_clouds := (1.0 - c.overcast) * (1.0 - 0.6 * c.cloud_coverage * c.cloud_density)
	if sun:
		# A thick overcast leaves no direct sunlight; the sky lights everything. Smooth curve: gone well
		# before the sky is fully closed.
		var direct_sun := c.sun_energy_scale * (1.0 - smoothstep(0.25, 0.8, c.overcast))
		sun.light_energy = _base_sun_energy * direct_sun
		sun.light_volumetric_fog_energy = _base_sun_fog_energy * sun_through_clouds
		# Clouds spread the sunlight like a softbox: softer shadows as the sky closes.
		sun.shadow_blur = lerpf(_base_sun_shadow_blur, overcast_shadow_blur, 1.0 - sun_through_clouds)
		# Diffuse light under clouds makes no sharp highlights (wet floors would otherwise show a hard sun
		# glint even in a storm).
		sun.light_specular = _base_sun_specular * (1.0 - smoothstep(0.1, 0.5, c.overcast))
		# A sun with no energy left is switched off entirely: one less light.
		sun.visible = _base_sun_visible and direct_sun > 0.0005
		# Shadows fade out with the sun instead of switching off (no popping).
		var shadow_fade := smoothstep(0.0, 0.2, direct_sun)
		sun.shadow_opacity = _base_sun_shadow_opacity * shadow_fade
		sun.shadow_enabled = _base_sun_shadows and shadow_fade > 0.001
	_apply_exposure()
	if _environment:
		var sky_light := 1.0 - storm_sky_dimming * c.cloud_darkness
		_environment.background_energy_multiplier = _base_background_energy * sky_light
		_environment.volumetric_fog_density = _base_fog_density + c.fog_density
		# Fog is lit by the sky (ambient inject) like real haze, so only tint it grey.
		_environment.volumetric_fog_albedo = _base_fog_albedo.lerp(storm_fog_color, darkness * 0.5)
		_environment.volumetric_fog_ambient_inject = 1.0
		# Weather fog would hide the cloud deck entirely; let it show through.
		_environment.volumetric_fog_sky_affect = _base_fog_sky_affect * lerpf(1.0, 0.1, 1.0 - sun_through_clouds)
		# Overcast light comes from everywhere, so no bright glow toward the sun.
		_environment.volumetric_fog_anisotropy = _base_fog_anisotropy * sun_through_clouds
		# Distance fog is an unlit color: give it the sky's horizon color at the sky's brightness so it
		# blends into the horizon.
		_environment.fog_enabled = c.distance_fog > 0.0005
		_environment.fog_density = c.distance_fog
		_environment.fog_light_color = _horizon_color() * _base_background_energy * sky_light
		_environment.fog_light_energy = 1.0
		_environment.fog_sky_affect = c.overcast * 0.5

	rain.intensity = c.rain_intensity
	rain.wind = Vector3(wind.x, 0.0, wind.y) * rain_wind_multiplier
	if _environment:
		rain.curtain_color = _environment.fog_light_color

	if audio:
		audio.rain_amount = c.rain_intensity
		audio.wind_amount = clampf(wind_speed / 20.0, 0.0, 1.0)

	# Surfaces lag behind the rain: they wet over seconds and dry over minutes.
	if c.rain_intensity > 0.02:
		_wetness = move_toward(_wetness, 1.0, dt / wetting_time * (0.3 + 0.7 * c.rain_intensity))
	else:
		_wetness = move_toward(_wetness, 0.0, dt / drying_time)
	RenderingServer.global_shader_parameter_set(WETNESS_GLOBAL, _wetness)
	RenderingServer.global_shader_parameter_set(RAIN_GLOBAL, c.rain_intensity)


## Darkens the picture for thick clouds. Auto exposure would undo a plain exposure change, so with it on,
## dark weather lowers its target brightness.
func _apply_exposure() -> void:
	if _camera_attributes == null:
		return
	if _camera_attributes.auto_exposure_enabled:
		_camera_attributes.auto_exposure_scale = _base_auto_exposure_scale * current.scene_brightness
		_camera_attributes.exposure_multiplier = _base_exposure
	else:
		_camera_attributes.auto_exposure_scale = _base_auto_exposure_scale
		_camera_attributes.exposure_multiplier = _base_exposure * current.scene_brightness


## The sky shader's horizon color for the current weather (matches sky_gradient()).
func _horizon_color() -> Color:
	var overcast_grey := _sky_overcast_color * (1.0 - 0.65 * current.cloud_darkness)
	return _sky_horizon_color.lerp(overcast_grey, current.overcast)


func _capture_scene_base() -> void:
	if world_environment:
		_environment = world_environment.environment
		_camera_attributes = world_environment.camera_attributes
	if _camera_attributes:
		_base_exposure = _camera_attributes.exposure_multiplier
		_base_auto_exposure_scale = _camera_attributes.auto_exposure_scale
	if _environment:
		_base_fog_density = _environment.volumetric_fog_density
		_base_fog_albedo = _environment.volumetric_fog_albedo
		_base_fog_ambient_inject = _environment.volumetric_fog_ambient_inject
		_base_background_energy = _environment.background_energy_multiplier
		_base_fog_anisotropy = _environment.volumetric_fog_anisotropy
		_base_fog_sky_affect = _environment.volumetric_fog_sky_affect
		_base_fog_enabled = _environment.fog_enabled
		_base_fog_distance_density = _environment.fog_density
		_base_fog_light_color = _environment.fog_light_color
		_base_fog_light_energy = _environment.fog_light_energy
		_base_fog_sky_affect_distance = _environment.fog_sky_affect
		if _environment.sky and _environment.sky.sky_material is ShaderMaterial:
			_sky_material = _environment.sky.sky_material
			# Read once: querying shader defaults stalls the render thread. Null without a GPU (headless);
			# keep the defaults then.
			var horizon: Variant = _sky_parameter(&"sky_horizon_color")
			if horizon is Color:
				_sky_horizon_color = horizon
			var overcast_color: Variant = _sky_parameter(&"overcast_color")
			if overcast_color is Color:
				_sky_overcast_color = overcast_color
			var cloud_scale: Variant = _sky_parameter(&"cloud_scale")
			# Cloud textures tile every 1 / cloud_scale meters; wrap drift there to keep precision.
			var scale: float = cloud_scale if cloud_scale is float else 0.0
			_cloud_period = 1.0 / scale if scale > 0.0 else 0.0
			_sky_material.set_shader_parameter("lightning_color", lightning_color)
	if _sky_material == null:
		push_warning("WeatherSystem: the environment's sky should use gamekit_weather/resources/weather_sky_material.tres; clouds are disabled.")
	if sun:
		_base_sun_energy = sun.light_energy
		_base_sun_fog_energy = sun.light_volumetric_fog_energy
		_base_sun_shadows = sun.shadow_enabled
		_base_sun_shadow_blur = sun.shadow_blur
		_base_sun_specular = sun.light_specular
		_base_sun_shadow_opacity = sun.shadow_opacity
		_base_sun_visible = sun.visible


## Slow (syncs with the render thread); only call at setup.
func _sky_parameter(param: StringName) -> Variant:
	var value: Variant = _sky_material.get_shader_parameter(param)
	if value == null and _sky_material.shader:
		value = RenderingServer.shader_get_parameter_default(_sky_material.shader.get_rid(), param)
	return value


func _ensure_cycle_action() -> void:
	if cycle_action.is_empty() or InputMap.has_action(cycle_action):
		return
	InputMap.add_action(cycle_action)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F7
	InputMap.action_add_event(cycle_action, key)


static func _find_first(root: Node, type_name: String) -> Node:
	var found := root.find_children("*", type_name, true, false)
	return found[0] if not found.is_empty() else null
