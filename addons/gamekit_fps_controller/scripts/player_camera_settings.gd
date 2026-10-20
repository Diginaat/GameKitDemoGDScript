class_name PlayerCameraSettings
extends Resource
## Look input and purely visual camera effects. Nothing here changes gameplay; turning `motion_effects`
## off (the accessibility preset) leaves movement identical.

@export var preset_name := "Modern"

@export_group("Look")
## Source-style sensitivity: degrees per mouse count = 0.022 * sensitivity.
@export var mouse_sensitivity := 2.5
@export var invert_y := false
@export_range(45.0, 89.9) var max_pitch_degrees := 89.0
@export var vertical_fov := 72.0

@export_group("Smoothing (not motion effects)")
## Rate (1/s) at which the eye catches up after stair steps.
@export var step_smoothing_rate := 14.0
## Rate (1/s) of the eye-height change when crouching.
@export var crouch_smoothing_rate := 14.0

@export_group("Motion Effects")
## Master switch for every effect below (accessibility).
@export var motion_effects := true

@export var head_bob := true
@export var bob_amplitude := 0.03
## Meters travelled per full bob cycle (two footsteps).
@export var bob_stride_length := 2.4
@export var sprint_bob_scale := 1.5

@export var landing_kick := true
## Downward kick (m) per m/s of impact speed.
@export var landing_kick_per_speed := 0.012
@export var max_landing_kick := 0.16
@export var jump_kick := 0.02
@export var kick_stiffness := 170.0
@export var kick_damping := 22.0

@export var strafe_roll := true
@export var max_roll_degrees := 1.0
@export var roll_rate := 8.0

@export var acceleration_tilt := true
## Pitch tilt (degrees) per m/s² of forward acceleration.
@export var tilt_per_acceleration := 0.04
@export var max_tilt_degrees := 1.2
@export var tilt_rate := 6.0

@export var sprint_fov := true
@export var sprint_fov_increase := 6.0
@export var fov_rate := 7.0

@export var breathing := true
@export var breathing_amplitude := 0.003
@export var breathing_rate := 0.25

@export var recoil := true
@export var recoil_stiffness := 120.0
@export var recoil_damping := 18.0

@export_group("Lens")
## Photographic look of the camera's CameraLens (gamekit_lens/profiles/). Empty = keep the profile set on
## the Lens node.
@export var lens: LensProfile
