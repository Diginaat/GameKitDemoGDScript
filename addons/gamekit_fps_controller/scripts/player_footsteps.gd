class_name PlayerFootsteps
extends Node
## Movement audio: surface-aware footsteps driven by distance travelled on the ground (so cadence follows
## actual speed and stops when stationary), plus jump, land, slide and crouch sounds. All streams are
## optional; when unassigned, synthesized placeholders are used. Set enabled false to mute.

@export var enabled := true
## Stride (m) at walking pace; scales up with speed.
@export var base_stride := 0.75
@export var stride_per_speed := 0.1
@export var crouch_volume_db := -10.0
@export var footstep_override: AudioStream
@export var land_override: AudioStream
@export var jump_override: AudioStream

var _player: FpsPlayerController
var _steps: AudioStreamPlayer
var _body: AudioStreamPlayer
var _slide: AudioStreamPlayer
var _distance := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_player = get_parent() as FpsPlayerController
	_steps = AudioStreamPlayer.new()
	_steps.max_polyphony = 3
	_body = AudioStreamPlayer.new()
	_body.max_polyphony = 2
	_slide = AudioStreamPlayer.new()
	_slide.stream = PlaceholderSounds.loop(0.35, 0.25)
	_slide.volume_db = -8.0
	add_child(_steps)
	add_child(_body)
	add_child(_slide)

	var motor := _player.motor
	motor.landed.connect(_on_landed)
	motor.jumped.connect(func() -> void:
		_play(_body, jump_override if jump_override else PlaceholderSounds.burst(0.12, 0.3, 30.0, 0.35), 1.0, -6.0))
	motor.state_changed.connect(func(_old: PlayerMotor.MovementState, state: PlayerMotor.MovementState) -> void:
		if not enabled:
			return
		if state == PlayerMotor.MovementState.SLIDING:
			_slide.play()
		else:
			_slide.stop())
	motor.stance.changed.connect(func(crouched: bool, _feet_shift: float) -> void:
		_play(_body, PlaceholderSounds.burst(0.18, 0.1, 14.0, 0.15), 0.8 if crouched else 1.0, -14.0))


func _physics_process(delta: float) -> void:
	var motor := _player.motor
	if motor.state != PlayerMotor.MovementState.GROUNDED:
		# Restart the stride on landing so the landing sound is not doubled by a step.
		_distance = 0.0
		return
	var speed := motor.horizontal_velocity.length()
	if speed < 0.5:
		_distance = maxf(_distance - delta * 2.0, 0.0)
		return
	_distance += speed * delta
	var stride := base_stride + speed * stride_per_speed
	if _distance >= stride:
		_distance -= stride
		_play_footstep(motor.surface, speed)


func _play_footstep(surface: Surfaces.SurfaceInfo, speed: float) -> void:
	var stream := footstep_override if footstep_override else PlaceholderSounds.burst(0.09, surface.footstep_brightness, 38.0, 0.4)
	var volume := linear_to_db(clampf(speed / _player.movement.run_speed, 0.35, 1.3)) - 4.0
	if _player.motor.stance.is_crouched:
		volume += crouch_volume_db
	_play(_steps, stream, surface.footstep_pitch * _rng.randf_range(0.9, 1.1), volume)


func _on_landed(impact_speed: float) -> void:
	if impact_speed < 1.5:
		return
	var surface := _player.motor.surface
	var stream := land_override if land_override else PlaceholderSounds.burst(0.22, surface.footstep_brightness * 0.6, 16.0, 0.6)
	var volume := linear_to_db(clampf(impact_speed / 8.0, 0.3, 1.2))
	_play(_body, stream, surface.footstep_pitch * 0.8, volume)
	_distance = 0.0


func _play(player: AudioStreamPlayer, stream: AudioStream, pitch: float, volume_db: float) -> void:
	if not enabled:
		return
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()
