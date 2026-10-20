class_name WeatherPreset
extends Resource
## One weather state. WeatherSystem blends between presets over time. To add a parameter: add an export
## here, blend it in blend(), and use it in WeatherSystem._apply().

@export var display_name: String = "Clear"

@export_group("Clouds")
## Fraction of the sky covered by clouds.
@export_range(0, 1) var cloud_coverage: float = 0.2
## Cloud opacity.
@export_range(0, 1) var cloud_density: float = 0.8
## Darkens cloud undersides, for rain and storm clouds.
@export_range(0, 1) var cloud_darkness: float = 0.0
## Pulls the whole sky toward a flat grey.
@export_range(0, 1) var overcast: float = 0.0

@export_group("Precipitation")
@export_range(0, 1) var rain_intensity: float = 0.0
## Lightning flashes per minute. 0 = no lightning; a thunderstorm uses 4-10.
@export_range(0, 30) var lightning_per_minute: float = 0.0

@export_group("Atmosphere")
## Wind in m/s. Moves clouds and slants rain.
@export_range(0, 30) var wind_speed: float = 3.0
## Wind heading in degrees, 0 = toward -Z. Blended along the shortest turn.
@export_range(0, 360) var wind_direction_degrees: float = 30.0
## How much the wind varies in gusts (rain slant and wind sound).
@export_range(0, 1) var gustiness: float = 0.2
## Added to the environment's volumetric fog density.
@export_range(0, 0.2) var fog_density: float = 0.0
## Cheap exponential distance fog density (Environment.FogDensity). 0 = off.
@export_range(0, 0.1) var distance_fog: float = 0.0
## Multiplier for the sun's energy.
@export_range(0, 1) var sun_energy_scale: float = 1.0
## Camera exposure multiplier. Below 1 darkens the whole picture (thick clouds).
@export_range(0.1, 1) var scene_brightness: float = 1.0


## Writes the blend of a and b into `into` (no allocation). The name comes from b.
static func blend(a: WeatherPreset, b: WeatherPreset, weight: float, into: WeatherPreset) -> void:
	into.display_name = b.display_name
	into.cloud_coverage = lerpf(a.cloud_coverage, b.cloud_coverage, weight)
	into.cloud_density = lerpf(a.cloud_density, b.cloud_density, weight)
	into.cloud_darkness = lerpf(a.cloud_darkness, b.cloud_darkness, weight)
	into.overcast = lerpf(a.overcast, b.overcast, weight)
	into.rain_intensity = lerpf(a.rain_intensity, b.rain_intensity, weight)
	into.lightning_per_minute = lerpf(a.lightning_per_minute, b.lightning_per_minute, weight)
	into.wind_speed = lerpf(a.wind_speed, b.wind_speed, weight)
	into.gustiness = lerpf(a.gustiness, b.gustiness, weight)
	into.fog_density = lerpf(a.fog_density, b.fog_density, weight)
	into.distance_fog = lerpf(a.distance_fog, b.distance_fog, weight)
	into.sun_energy_scale = lerpf(a.sun_energy_scale, b.sun_energy_scale, weight)
	into.scene_brightness = lerpf(a.scene_brightness, b.scene_brightness, weight)
	var heading := lerp_angle(deg_to_rad(a.wind_direction_degrees), deg_to_rad(b.wind_direction_degrees), weight)
	into.wind_direction_degrees = fposmod(rad_to_deg(heading), 360.0)
