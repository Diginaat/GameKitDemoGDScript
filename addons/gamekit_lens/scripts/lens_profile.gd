class_name LensProfile
extends Resource
## A photographic look for CameraLens: lens (distortion, chromatic aberration, vignette, depth of field),
## film/sensor (halation, grain, bloom), grading and lens flares. Presets live in
## addons/gamekit_lens/profiles/. After changing values from code, call CameraLens.refresh() (or assign the
## profile again).

@export var display_name: String = "Natural"

@export_group("Vignette")
@export var vignette_enabled: bool = true
@export_range(0, 2, 0.01) var vignette_intensity: float = 0.22
## Distance from the center (1 = screen edge) where darkening starts.
@export_range(0, 2.5, 0.01) var vignette_size: float = 0.95
@export_range(0.001, 2, 0.01) var vignette_smoothness: float = 1.0
@export_range(0.25, 4, 0.01) var vignette_roundness: float = 1.0

@export_group("Chromatic Aberration")
## Lateral color fringes toward the frame edges, on high-contrast edges only.
@export var chromatic_aberration_enabled: bool = true
## Fringe width in pixels at the corners.
@export_range(0, 8, 0.01) var chromatic_aberration: float = 1.6
@export_range(0, 1, 0.01) var ca_edge_start: float = 0.55
@export_range(0, 4, 0.01) var ca_blur: float = 1.2
@export_range(0.5, 4, 0.01) var ca_radial_power: float = 1.85
@export_range(0.25, 4, 0.01) var ca_edge_response: float = 1.35
@export_range(0, 1, 0.01) var ca_highlight_fringe: float = 0.35

@export_group("Lens Distortion")
## Off by default: transparents (water surfaces, rain, Label3D) draw after the lens pass
## undistorted, so they shift against distorted geometry near the frame edges.
@export var distortion_enabled: bool = false
## Positive = barrel, negative = pincushion. The image is scaled so corners never sample
## outside the frame.
@export_range(-0.5, 0.5, 0.001) var distortion: float = 0.02
@export_range(-0.5, 0.5, 0.001) var distortion_cubic: float = 0.005

@export_group("Depth of Field")
## Lens blur by distance, applied after distortion. Off by default: it hides far targets.
@export var dof_enabled: bool = false
@export_range(0, 1, 0.01) var dof_amount: float = 0.5
@export var dof_near_enabled: bool = false
@export_range(0.01, 100, 0.01) var dof_near_distance: float = 0.5
@export_range(0.001, 20, 0.01) var dof_near_transition: float = 0.3
@export var dof_far_enabled: bool = true
@export_range(0.01, 500, 0.01) var dof_far_distance: float = 60.0
@export_range(0.001, 100, 0.01) var dof_far_transition: float = 30.0

@export_group("Halation")
## Warm glow that film shows around bright highlights.
@export var halation_enabled: bool = true
@export_range(0, 3, 0.01) var halation_intensity: float = 0.6
## Brightness (linear, before tonemapping) where halation starts.
@export_range(0, 4, 0.01) var halation_threshold: float = 1.2
@export_range(0.001, 2, 0.01) var halation_softness: float = 0.6
@export_range(0, 16, 0.01) var halation_radius: float = 2.5
@export var halation_color: Color = Color(0.96, 0.26, 0)
## Close highlights bleed wider than distant ones, and the bleed stops at depth edges.
@export var halation_depth_aware: bool = true
@export_range(0.1, 500, 0.01) var halation_depth_reference: float = 8.0
@export_range(0.1, 4, 0.01) var halation_depth_curve: float = 1.0
@export_range(0.05, 4, 0.01) var halation_depth_min_scale: float = 0.45
@export_range(0.05, 8, 0.01) var halation_depth_max_scale: float = 2.2
@export_range(0.01, 10, 0.01) var halation_depth_rejection: float = 1.25

@export_group("Highlight Bloom")
## Extra local bloom. Off by default: the Environment's glow already blooms.
@export var bloom_enabled: bool = false
@export_range(0, 3, 0.01) var bloom_intensity: float = 0.13
@export_range(0, 4, 0.01) var bloom_threshold: float = 1.0
@export_range(0.001, 2, 0.01) var bloom_softness: float = 0.57
@export_range(0, 12, 0.01) var bloom_radius: float = 1.31
@export var bloom_tint: Color = Color.WHITE

@export_group("Grain")
@export var grain_enabled: bool = true
## Digital sensor noise (colored, per channel) instead of monochrome film grain.
@export var rgb_sensor_noise: bool = true
@export_range(0, 0.2, 0.001) var grain_strength: float = 0.012
## Grain cell size in pixels.
@export_range(0.25, 8, 0.01) var grain_size: float = 1.5
@export_range(0, 20, 0.01) var grain_speed: float = 6.0
## Grain weight in shadows, mids and highlights. Real sensors are noisiest in the shadows.
@export_range(0, 4, 0.01) var grain_shadows: float = 1.6
@export_range(0, 4, 0.01) var grain_mids: float = 1.0
@export_range(0, 4, 0.01) var grain_highlights: float = 0.5

@export_group("Grading")
@export var grading_enabled: bool = true
@export_range(0, 3, 0.01) var exposure: float = 1.0
## Contrast around middle grey (0.18 linear).
@export_range(0.5, 1.5, 0.01) var contrast: float = 1.04
@export_range(0, 2, 0.01) var saturation: float = 1.02
## White balance: positive = warmer.
@export_range(-1, 1, 0.001) var temperature: float = 0.02
## Positive = greener, negative = more magenta.
@export_range(-1, 1, 0.001) var tint: float = 0.0
## Added to the linear, not yet exposed image: keep tiny (0.001), dark scenes amplify it.
@export var lift: Color = Color.BLACK
@export var gamma: Color = Color.WHITE
@export var gain: Color = Color.WHITE

@export_group("LUT")
@export var lut_enabled: bool = false
## 2D strip LUT: width = size * size, height = size.
@export var lut_texture: Texture2D
@export_range(2, 65, 1) var lut_size: int = 33
@export_range(0, 1, 0.01) var lut_strength: float = 1.0

@export_group("Lens Flare")
@export var flare_enabled: bool = true
## Flare from the scene's sun (CameraLens.Sun). Scales with the sun's energy, so weather that
## dims the sun dims the flare too.
@export var sun_flare: bool = true
@export_range(0, 8, 0.01) var flare_intensity: float = 0.35
@export_range(0, 8, 0.01) var flare_blur: float = 1.8
@export_range(0, 0.05, 0.0001) var flare_chroma: float = 0.02
@export_range(0, 4, 0.01) var flare_halo: float = 0.15
@export_range(0, 4, 0.01) var flare_ghosts: float = 0.5
@export_range(0, 4, 0.01) var flare_rays: float = 0.0
@export_range(4, 16, 1) var flare_ray_count: float = 7.0
@export_range(0.2, 4, 0.01) var flare_ray_length: float = 1.65
@export_range(0, 1, 0.01) var flare_imperfection: float = 0.2
@export_range(0.1, 3, 0.01) var flare_ghost_spread: float = 1.0
@export_range(0.1, 4, 0.01) var flare_source_bloom: float = 1.25
## Flare size as a fraction of the screen height.
@export_range(0.001, 0.25, 0.001) var flare_size: float = 0.055
@export_range(0.1, 4, 0.01) var sun_flare_size: float = 3.0
@export_range(0, 8, 0.01) var sun_flare_intensity: float = 1.0
## Lights below this energy make no flare.
@export_range(0, 100, 0.01) var flare_energy_threshold: float = 2.0
@export_range(0, 10, 0.01) var flare_distance_falloff: float = 1.0
## How fast flares appear and fade (1/s). Fading hides the pop when a source gets blocked.
@export_range(0.1, 60, 0.01) var flare_fade_in_speed: float = 30.0
@export_range(0.1, 60, 0.01) var flare_fade_out_speed: float = 20.0
## Hide a flare when the screen behind its source isn't bright (a cloud or object covers it).
@export var flare_visibility_gating: bool = true
@export_range(0, 2, 0.01) var flare_visibility_threshold: float = 0.65
## Keep ghosts off the exact screen center (the crosshair).
@export var flare_center_safe_zone: bool = true


## False when every screen effect is off; the lens pass is then skipped entirely.
var any_post_effect: bool:
	get:
		return vignette_enabled or chromatic_aberration_enabled or distortion_enabled or dof_enabled \
			or halation_enabled or bloom_enabled or grain_enabled or grading_enabled \
			or (lut_enabled and lut_texture != null)


## Writes the post-processing uniforms of lens_post.gdshader.
func apply_post(m: ShaderMaterial) -> void:
	m.set_shader_parameter("enable_vignette", vignette_enabled)
	m.set_shader_parameter("vignette_intensity", vignette_intensity)
	m.set_shader_parameter("vignette_size", vignette_size)
	m.set_shader_parameter("vignette_smoothness", vignette_smoothness)
	m.set_shader_parameter("vignette_roundness", vignette_roundness)
	m.set_shader_parameter("enable_chromatic_aberration", chromatic_aberration_enabled)
	m.set_shader_parameter("chromatic_aberration", chromatic_aberration)
	m.set_shader_parameter("ca_edge_start", ca_edge_start)
	m.set_shader_parameter("ca_blur", ca_blur)
	m.set_shader_parameter("ca_radial_power", ca_radial_power)
	m.set_shader_parameter("ca_edge_response", ca_edge_response)
	m.set_shader_parameter("ca_highlight_fringe", ca_highlight_fringe)
	m.set_shader_parameter("enable_distortion", distortion_enabled)
	m.set_shader_parameter("distortion", distortion)
	m.set_shader_parameter("distortion_cubic", distortion_cubic)
	m.set_shader_parameter("distortion_overscan", distortion_overscan())
	m.set_shader_parameter("distortion_center", Vector2(0.5, 0.5))
	m.set_shader_parameter("enable_post_dof", dof_enabled)
	m.set_shader_parameter("post_dof_amount", dof_amount)
	m.set_shader_parameter("post_dof_near_enabled", dof_near_enabled)
	m.set_shader_parameter("post_dof_near_distance", dof_near_distance)
	m.set_shader_parameter("post_dof_near_transition", maxf(dof_near_transition, 0.001))
	m.set_shader_parameter("post_dof_far_enabled", dof_far_enabled)
	m.set_shader_parameter("post_dof_far_distance", dof_far_distance)
	m.set_shader_parameter("post_dof_far_transition", maxf(dof_far_transition, 0.001))
	m.set_shader_parameter("enable_halation", halation_enabled)
	m.set_shader_parameter("halation_intensity", halation_intensity)
	m.set_shader_parameter("halation_threshold", halation_threshold)
	m.set_shader_parameter("halation_softness", halation_softness)
	m.set_shader_parameter("halation_radius", halation_radius)
	m.set_shader_parameter("halation_color", _rgb(halation_color))
	m.set_shader_parameter("halation_depth_aware", halation_depth_aware)
	m.set_shader_parameter("halation_depth_reference", halation_depth_reference)
	m.set_shader_parameter("halation_depth_curve", halation_depth_curve)
	m.set_shader_parameter("halation_depth_min_scale", halation_depth_min_scale)
	m.set_shader_parameter("halation_depth_max_scale", halation_depth_max_scale)
	m.set_shader_parameter("halation_depth_rejection", halation_depth_rejection)
	m.set_shader_parameter("enable_highlight_bloom", bloom_enabled)
	m.set_shader_parameter("bloom_intensity", bloom_intensity)
	m.set_shader_parameter("bloom_threshold", bloom_threshold)
	m.set_shader_parameter("bloom_softness", bloom_softness)
	m.set_shader_parameter("bloom_radius", bloom_radius)
	m.set_shader_parameter("bloom_tint", _rgb(bloom_tint))
	m.set_shader_parameter("enable_grain", grain_enabled)
	m.set_shader_parameter("enable_rgb_digital_noise", rgb_sensor_noise)
	m.set_shader_parameter("grain_strength", grain_strength)
	m.set_shader_parameter("grain_size", grain_size)
	m.set_shader_parameter("grain_speed", grain_speed)
	m.set_shader_parameter("grain_shadows", grain_shadows)
	m.set_shader_parameter("grain_mids", grain_mids)
	m.set_shader_parameter("grain_highlights", grain_highlights)
	m.set_shader_parameter("enable_color_grading", grading_enabled)
	m.set_shader_parameter("exposure", exposure)
	m.set_shader_parameter("contrast", contrast)
	m.set_shader_parameter("saturation", saturation)
	m.set_shader_parameter("temperature", temperature)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("lift", _rgb(lift))
	m.set_shader_parameter("gamma", _rgb(gamma))
	m.set_shader_parameter("gain", _rgb(gain))
	m.set_shader_parameter("enable_lut", lut_enabled and lut_texture != null)
	m.set_shader_parameter("lut_size", float(lut_size))
	m.set_shader_parameter("lut_strength", lut_strength)
	if lut_texture:
		m.set_shader_parameter("lut_texture", lut_texture)


## Writes the uniforms of lens_flare.gdshader that do not change per frame.
func apply_flare(m: ShaderMaterial) -> void:
	m.set_shader_parameter("master_intensity", 1) # intensity is folded into each source
	m.set_shader_parameter("blur_amount", flare_blur)
	m.set_shader_parameter("chroma_amount", flare_chroma)
	m.set_shader_parameter("halo_intensity", flare_halo)
	m.set_shader_parameter("ghost_intensity", flare_ghosts)
	m.set_shader_parameter("ray_intensity", flare_rays)
	m.set_shader_parameter("imperfection", flare_imperfection)
	m.set_shader_parameter("ray_count", flare_ray_count)
	m.set_shader_parameter("ray_length", flare_ray_length)
	m.set_shader_parameter("ghost_spread", flare_ghost_spread)
	m.set_shader_parameter("source_bloom_scale", flare_source_bloom)
	m.set_shader_parameter("enable_source_visibility_gating", flare_visibility_gating)
	m.set_shader_parameter("source_visibility_threshold", flare_visibility_threshold)
	m.set_shader_parameter("source_visibility_softness", 0.18)
	m.set_shader_parameter("source_visibility_sample_radius", 0.006)
	m.set_shader_parameter("enable_center_safe_zone", flare_center_safe_zone)
	m.set_shader_parameter("allowed_flare_area_radius_scale", 0.55)
	m.set_shader_parameter("center_dead_zone_radius_scale", 0.114)
	m.set_shader_parameter("allowed_flare_area_feather", 0.15)

## Zoom that keeps the distorted corners inside the frame: the barrel factor at the corner (r² = 2 in the
## shader's -1..1 space).
func distortion_overscan() -> float:
	return maxf(1.0, 1.0 + distortion * 2.0 + distortion_cubic * 4.0) if distortion_enabled else 1.0


static func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
