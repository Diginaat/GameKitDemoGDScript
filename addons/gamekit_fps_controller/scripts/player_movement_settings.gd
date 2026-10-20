class_name PlayerMovementSettings
extends Resource
## Every gameplay movement tunable. Profiles (Source Classic, Modern AAA) are saved instances in
## res://addons/gamekit_fps_controller/resources/; both run through the same motor. Defaults equal the
## Modern AAA profile. Units are meters, seconds, kilograms. Source values convert at 1 unit = 1 inch
## (0.0254 m), which gives the 72-unit player hull a realistic 1.83 m height.

@export var profile_name := "Modern AAA"

@export_group("Body")
@export var radius := 0.4
@export var standing_height := 1.83
@export var crouch_height := 1.0
@export var standing_eye_height := 1.65
@export var crouch_eye_height := 0.85

@export_group("Speeds")
@export var walk_speed := 2.4
@export var run_speed := 4.6
@export var sprint_speed := 7.0
@export var crouch_speed := 2.2

@export_group("Ground")
## Source sv_accelerate. Time to reach wish speed from rest = 1 / acceleration (seconds).
@export var ground_acceleration := 11.0
## Source sv_friction. Exponential decay rate above stop_speed (1/s).
@export var friction := 6.0
## Source sv_stopspeed. Below this speed friction decelerates at friction * stop_speed.
@export var stop_speed := 2.0

@export_group("Air")
@export var gravity := 17.0
@export var air_acceleration := 4.0
## Source's 30-unit air wish-speed cap. Bigger = more air control, smaller = more strafe-gain.
@export var air_speed_cap := 0.76
@export var max_fall_speed := 55.0

@export_group("Jump")
@export var jump_height := 1.0
@export var variable_jump_height := true
## Upward speed is multiplied by this when jump is released while rising.
@export_range(0.0, 1.0) var jump_cut_multiplier := 0.55
@export var jump_buffer_time := 0.12
@export var coyote_time := 0.1
## Jumping on the landing tick skips friction, preserving speed (classic bunny hop).
@export var allow_bunny_hop := false
## Holding jump re-jumps on landing.
@export var auto_bunny_hop := false
## When bunny hop is off, horizontal speed is capped to this multiple of the current max ground speed at
## takeoff (HL2 PreventBunnyJumping uses 1.1).
@export var bunny_hop_speed_cap := 1.0

@export_group("Sprint and Crouch")
@export var sprint_toggle := false
## Sprint only while the forward input exceeds this (1 = straight forward only, -1 = any direction).
@export_range(-1.0, 1.0) var sprint_min_forward_input := 0.5
@export var crouch_toggle := false

@export_group("Collision")
@export var step_height := 0.4
@export var max_slope_degrees := 46.0
## Cap on platform velocity added when leaving a moving platform (prevents launches).
@export var max_platform_inherit_speed := 8.0
## Maximum force the player can push props with (N).
@export var push_force := 900.0
## Props heavier than this are not pushed at all (kg).
@export var max_push_mass := 250.0

@export_group("Slide")
@export var slide_enabled := true
@export var slide_min_start_speed := 5.5
@export var slide_start_boost := 1.5
@export var slide_friction := 0.9
@export var slide_end_speed := 2.6
@export var slide_max_duration := 1.1
@export var slide_cooldown := 0.4

@export_group("Mantle")
@export var mantle_enabled := true
@export var mantle_min_height := 0.5
## Also limits climbing out of water: a floating player's feet are about eye height below the surface.
@export var mantle_max_height := 1.8
@export var mantle_reach := 0.6
@export var mantle_speed := 4.5

@export_group("Ladder")
@export var ladder_enabled := true
@export var ladder_climb_speed := 3.0
@export var ladder_jump_off_speed := 4.0

@export_group("Swim")
@export var swim_enabled := true
@export var swim_speed := 3.2
@export var swim_acceleration := 6.0
@export var water_friction := 2.5
## Fraction of standing height that must be submerged to swim.
@export_range(0.0, 1.0) var swim_depth_fraction := 0.55
