class_name PlaceholderSounds
## Synthesizes simple placeholder sounds (filtered noise bursts) so movement audio works with no assets.
## Replace by assigning real streams on PlayerFootsteps; nothing else depends on this.

const MIX_RATE := 22050

static var _cache := {}


## Releases cached streams.
static func clear_cache() -> void:
	_cache.clear()


## duration: seconds. brightness: 0 = dull (heavy low-pass), 1 = bright. decay: envelope decay rate (1/s).
## volume: peak amplitude 0..1.
static func burst(duration: float, brightness: float, decay: float, volume: float) -> AudioStreamWAV:
	var key := [duration, brightness, decay, volume]
	if _cache.has(key):
		return _cache[key]

	var samples := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = samples ^ int(brightness * 1000.0)
	# One-pole low-pass; coefficient from brightness.
	var alpha := lerpf(0.04, 0.6, clampf(brightness, 0.0, 1.0))
	var filtered := 0.0
	for i in samples:
		var t := float(i) / MIX_RATE
		var attack := minf(1.0, t / 0.004)
		var envelope := attack * exp(-decay * t)
		var noise := rng.randf() * 2.0 - 1.0
		filtered += alpha * (noise - filtered)
		data.encode_s16(i * 2, int(clampf(filtered * envelope * volume * 2.5, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	_cache[key] = stream
	return stream


## Looping noise bed (slides).
static func loop(brightness: float, volume: float) -> AudioStreamWAV:
	var stream: AudioStreamWAV = burst(1.0, brightness, 0.0, volume).duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = MIX_RATE
	return stream
