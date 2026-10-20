class_name Surfaces
## Surface lookup. A collider declares its surface with integer metadata META_KEY (a SurfaceType value);
## colliders without it are SurfaceType.DEFAULT.

enum SurfaceType { DEFAULT, CONCRETE, METAL, WOOD, GRASS, ICE, MUD }

const META_KEY := &"surface"


## friction: multiplies ground friction and acceleration (Source surfaceFriction).
## speed_multiplier: multiplies wish speed. footstep_pitch: pitch of the placeholder footstep sound.
## footstep_brightness: 0 = dull thud, 1 = bright click (placeholder synthesis).
class SurfaceInfo:
	var type: int
	var friction: float
	var speed_multiplier: float
	var footstep_pitch: float
	var footstep_brightness: float

	func _init(p_type: int, p_friction: float, p_speed: float, p_pitch: float, p_brightness: float) -> void:
		type = p_type
		friction = p_friction
		speed_multiplier = p_speed
		footstep_pitch = p_pitch
		footstep_brightness = p_brightness


static var _table: Array[SurfaceInfo] = [
	SurfaceInfo.new(SurfaceType.DEFAULT, 1.0, 1.0, 1.0, 0.5),
	SurfaceInfo.new(SurfaceType.CONCRETE, 1.0, 1.0, 1.0, 0.55),
	SurfaceInfo.new(SurfaceType.METAL, 1.0, 1.0, 1.35, 0.95),
	SurfaceInfo.new(SurfaceType.WOOD, 1.0, 1.0, 0.8, 0.4),
	SurfaceInfo.new(SurfaceType.GRASS, 1.0, 1.0, 0.7, 0.15),
	SurfaceInfo.new(SurfaceType.ICE, 0.12, 1.0, 1.2, 0.8),
	SurfaceInfo.new(SurfaceType.MUD, 1.4, 0.65, 0.55, 0.05),
]


static func get_info(type: int) -> SurfaceInfo:
	return _table[type]


static func from_collider(collider: Object) -> SurfaceInfo:
	if collider is Node and collider.has_meta(META_KEY):
		var value: int = collider.get_meta(META_KEY)
		if value >= 0 and value < _table.size():
			return _table[value]
	return _table[0]


static func tag(node: Node, type: int) -> void:
	node.set_meta(META_KEY, type)
