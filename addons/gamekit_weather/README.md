# gamekit_weather

Dynamic weather: cloud sky, GPU rain with impacts and distant curtains, wind gusts, volumetric and
distance fog, lightning with delayed thunder, procedural rain/wind/thunder sound, sun and exposure
changes, and wet surfaces (splatter, wet film, puddles with ripples) that stay dry under cover.
Depends on: `gamekit_core`.

| Type | What it is |
| --- | --- |
| `WeatherSystem` | Node. Blends `WeatherPreset`s and drives everything below. Creates `RainEmitter`, `RainOcclusion` and `WeatherAudio` as children |
| `WeatherPreset` | Resource: clouds, rain, lightning, wind, fog, sun and brightness for one weather state |
| `RainEmitter` | Node3D: rain particles, impacts, curtains and splash mist around the camera |
| `RainOcclusion` | Node3D: top-down height map so covered surfaces stay dry |
| `WeatherAudio` | Node: procedural sound on buses `WeatherRain`, `WeatherWind`, `WeatherThunder` |
| `presets/*.tres` | Clear, Partly Cloudy, Overcast, Light Rain, Storm, Thunderstorm |
| `resources/weather_environment.tres` | Environment with the weather sky and volumetric fog |
| `resources/weather_camera_attributes.tres` | Auto exposure (weather darkens it in storms) |
| `shaders/wet_prototype_grid.gdshader` | `gamekit_core`'s grid that gets wet |
| `shaders/weather_wetness.gdshaderinc` | Include to make any spatial shader wet |

## Setup

1. Copy the `[shader_globals]` section of this project's `project.godot` (`weather_wetness`,
   `weather_rain`, `weather_rain_occlusion`, `weather_occlusion_area`). Shaders that include
   `weather_wetness.gdshaderinc` don't compile without them, and `WeatherSystem` reports each missing one.
2. `WorldEnvironment`: use `resources/weather_environment.tres` and `weather_camera_attributes.tres`,
   or set your environment's sky material to `resources/weather_sky_material.tres`.
3. Add a `Node` with `WeatherSystem`. Assign `WorldEnvironment` and `sun`, or leave them empty to use the
   first ones in the scene. It starts on the first entry of `presets` (empty = the six built-in ones).
4. Surfaces get wet if their shader includes `weather_wetness.gdshaderinc`, for example
   `wet_prototype_grid.gdshader`.

Input: `cycle_weather` (added as F7 when missing; set `cycle_action` empty to turn it off).

## Script API

```gdscript
weather.set_weather(load("res://addons/gamekit_weather/presets/storm.tres"), 20.0) # 20 s blend
weather.set_weather(preset, 0.0)   # instantly
weather.next_weather()
weather.wetness = 1.0              # start the level wet
weather.trigger_lightning()
weather.weather_changed.connect(func(preset: WeatherPreset) -> void: print(preset.display_name))
weather.lightning_struck.connect(func(distance: float) -> void: pass)
```

## Wet surfaces in your own shaders

```glsl
#include "res://addons/gamekit_weather/shaders/weather_wetness.gdshaderinc"
// in fragment(), with world-space position and normal from vertex():
vec3 ripple = weather_apply_wetness(world_pos, world_normal, 0.8, TIME, albedo, roughness);
NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(ripple, 0.0)).xyz);
```

## Render layers

Rain is on layer 18 (`RenderLayers.WEATHER`), the occlusion capture pass on layer 17
(`RenderLayers.WEATHER_CAPTURE`). Keep level geometry off both. Everything else on layers 1-16 counts as
cover; the viewmodel (19) and water (20) don't. Rain stops on any surface, water included.

## Cost

Rain only simulates a 36 m box around the camera, and the particle count scales with intensity
(nothing runs in clear weather). The cover map re-renders only after the camera moves 4 m. Call
`occlusion.refresh()` after moving a roof.

## Extending

- **New weather:** duplicate a preset `.tres` and tune it. Raise `lightning_per_minute` for a thunderstorm.
- **New preset parameter:** add an export to `WeatherPreset`, blend it in `WeatherPreset.blend`, and use
  it in `WeatherSystem._apply`.
- **Recorded sound:** replace the streams in `WeatherAudio._on_generated`.
- **Gameplay reactions** (wet footsteps, AI shelter): read `WeatherSystem.current` and `wetness`, or
  subscribe to `weather_changed`.
