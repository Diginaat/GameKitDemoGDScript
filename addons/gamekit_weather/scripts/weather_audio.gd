class_name WeatherAudio
extends Node
## Procedural rain, wind and thunder sound, with no audio files.
##
## Noise buffers are generated once on a worker thread and shaped with audio bus filters (buses
## WeatherRain, WeatherWind and WeatherThunder, created on first use and sent to Master). WeatherSystem sets
## rain_amount and wind_amount each frame and calls play_thunder(). To use recorded sounds instead, replace
## the streams in _on_generated().

const MIX_RATE := 22050
const RAIN_SECONDS := 3.0
const WIND_SECONDS := 4.0
const THUNDER_SECONDS := 6.0
const THUNDER_VARIANTS := 3
const MAX_PENDING_THUNDER := 4

const RAIN_BUS := &"WeatherRain"
const WIND_BUS := &"WeatherWind"
const THUNDER_BUS := &"WeatherThunder"

@export var volume_db := -4.0

## 0..1, rain loudness.
var rain_amount := 0.0
## 0..1, wind loudness including gusts. Also opens the wind filter (whoosh).
var wind_amount := 0.0

var _rain_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _thunder_players: Array[AudioStreamPlayer] = []
var _thunder_streams: Array[AudioStreamWAV] = []
var _streams_ready := false
var _wind_filter: AudioEffectBandPassFilter
var _generation: Thread
# Thunder waiting for its sound delay: seconds left and strength. Time < 0 = free slot.
var _pending_time := PackedFloat32Array()
var _pending_strength := PackedFloat32Array()


func _ready() -> void:
	var high := AudioEffectHighPassFilter.new()
	high.cutoff_hz = 700.0
	var low := AudioEffectLowPassFilter.new()
	low.cutoff_hz = 9000.0
	_ensure_bus(RAIN_BUS, [high, low])
	var band := AudioEffectBandPassFilter.new()
	band.cutoff_hz = 400.0
	band.resonance = 0.8
	_ensure_bus(WIND_BUS, [band])
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.95
	reverb.wet = 0.35
	_ensure_bus(THUNDER_BUS, [reverb])
	_wind_filter = AudioServer.get_bus_effect(AudioServer.get_bus_index(WIND_BUS), 0) as AudioEffectBandPassFilter

	_rain_player = _make_player(RAIN_BUS)
	_wind_player = _make_player(WIND_BUS)
	for i in 2:
		_thunder_players.append(_make_player(THUNDER_BUS))
	_pending_time.resize(MAX_PENDING_THUNDER)
	_pending_time.fill(-1.0)
	_pending_strength.resize(MAX_PENDING_THUNDER)
	_generation = Thread.new()
	_generation.start(_generate)


func _exit_tree() -> void:
	if _generation and _generation.is_started():
		_generation.wait_to_finish()
		_generation = null
	# Release the streams now; a looping playback still held at quit is reported as leaked.
	for player: AudioStreamPlayer in [_rain_player, _wind_player] + _thunder_players:
		player.stop()
		player.stream = null


func _process(delta: float) -> void:
	if _generation and _generation.is_started() and not _generation.is_alive():
		_on_generated(_generation.wait_to_finish())
		_generation = null
	_update_loop(_rain_player, rain_amount, delta)
	_update_loop(_wind_player, wind_amount, delta)
	_wind_filter.cutoff_hz = 250.0 + 1100.0 * wind_amount

	for i in MAX_PENDING_THUNDER:
		if _pending_time[i] < 0.0:
			continue
		_pending_time[i] -= delta
		if _pending_time[i] < 0.0:
			_start_thunder(_pending_strength[i])


## Thunder after `delay` seconds (light travels faster than sound). strength 0..1: close strikes are louder
## and sharper.
func play_thunder(delay: float, strength: float) -> void:
	if not _streams_ready:
		return
	for i in MAX_PENDING_THUNDER:
		if _pending_time[i] < 0.0:
			_pending_time[i] = maxf(delay, 0.0)
			_pending_strength[i] = strength
			return


func _start_thunder(strength: float) -> void:
	var player := _thunder_players[1] if _thunder_players[0].playing else _thunder_players[0]
	player.stream = _thunder_streams[randi_range(0, THUNDER_VARIANTS - 1)]
	player.pitch_scale = lerpf(0.75, 1.15, strength) * randf_range(0.95, 1.05)
	player.volume_db = volume_db + linear_to_db(lerpf(0.25, 1.0, strength))
	player.play()


func _update_loop(player: AudioStreamPlayer, amount: float, dt: float) -> void:
	if player.stream == null:
		return
	var target := volume_db + linear_to_db(maxf(amount, 0.0001))
	player.volume_db = lerpf(player.volume_db, target, 1.0 - exp(-3.0 * dt))
	if amount > 0.001 and not player.playing:
		player.volume_db = -60.0
		player.play()
	elif amount <= 0.001 and player.playing and player.volume_db < -50.0:
		player.stop()


func _on_generated(data: Array) -> void:
	_rain_player.stream = _make_stream(data[0], true)
	_wind_player.stream = _make_stream(data[1], true)
	for i in THUNDER_VARIANTS:
		_thunder_streams.append(_make_stream(data[2 + i], false))
	_streams_ready = true


# --- Generation (worker thread; pure functions of a seeded generator) -----------------------------------

static func _generate() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var result := [_generate_rain(rng), _generate_wind(rng)]
	for i in THUNDER_VARIANTS:
		result.append(_generate_thunder(rng))
	return result


## Pink noise (patter of many drops) plus sparse louder close drops.
static func _generate_rain(rng: RandomNumberGenerator) -> PackedByteArray:
	var count := int(RAIN_SECONDS * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var drop := 0.0
	for i in count:
		var white := rng.randf_range(-1.0, 1.0)
		b0 = 0.99765 * b0 + white * 0.099046
		b1 = 0.963 * b1 + white * 0.2965164
		b2 = 0.57 * b2 + white * 1.0526913
		var pink := (b0 + b1 + b2 + white * 0.1848) * 0.11
		if rng.randf() < 0.0015:
			drop = rng.randf_range(0.2, 0.6)
		drop *= 0.985
		_write(data, i, pink + drop * white)
	return data


## Brown noise; the bus band-pass turns it into wind, and moving the cutoff gives the whoosh.
static func _generate_wind(rng: RandomNumberGenerator) -> PackedByteArray:
	var count := int(WIND_SECONDS * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var brown := 0.0
	for i in count:
		brown = (brown + 0.02 * rng.randf_range(-1.0, 1.0)) / 1.02
		_write(data, i, brown * 3.5)
	return data


## A sharp crack followed by a long rolling rumble.
static func _generate_thunder(rng: RandomNumberGenerator) -> PackedByteArray:
	var count := int(THUNDER_SECONDS * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var brown := 0.0
	var roll := 0.0
	var roll_target := 1.0
	for i in count:
		var t := float(i) / MIX_RATE
		var white := rng.randf_range(-1.0, 1.0)
		brown = (brown + 0.03 * white) / 1.03
		# Slowly wandering loudness gives the rolling rumble.
		if i % 2000 == 0:
			roll_target = rng.randf_range(0.3, 1.0)
		roll = lerpf(roll, roll_target, 0.0004)
		var crack := white * exp(-t * 30.0) * 0.6
		var rumble := brown * 6.0 * minf(t * 8.0, 1.0) * exp(-t / 1.8) * roll
		_write(data, i, crack + rumble)
	return data


## 16-bit little-endian PCM sample.
static func _write(data: PackedByteArray, index: int, value: float) -> void:
	data.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))


# --- Helpers -------------------------------------------------------------------------------------------

static func _make_stream(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = data.size() / 2
	return stream


func _make_player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.volume_db = -60.0
	add_child(player)
	return player


## Creates the bus (sending to Master) once; reuses it on scene reloads.
static func _ensure_bus(bus_name: StringName, effects: Array) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")
	for effect: AudioEffect in effects:
		AudioServer.add_bus_effect(index, effect)
