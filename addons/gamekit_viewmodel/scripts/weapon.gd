class_name Weapon
extends Node3D
## A viewmodel weapon. Owns ammo, fire rate and its AnimationPlayer clips (equip, holster, fire, reload).
## Builds placeholder geometry and clips in code when the scene provides none, so it works without assets;
## a production weapon scene supplies its own meshes and an AnimationPlayer with the same clip names. It
## never touches locomotion or collision.

signal fired(weapon: Weapon)

const CLIP_EQUIP := &"equip"
const CLIP_HOLSTER := &"holster"
const CLIP_FIRE := &"fire"
const CLIP_RELOAD := &"reload"

@export var display_name := "Rifle"
@export var automatic := true
@export var fire_interval := 0.1
@export var magazine_size := 30
@export var fire_range := 100.0
@export var hit_impulse := 6.0
## View punch in degrees (x = up, y = sideways max).
@export var recoil_degrees := Vector2(0.9, 0.35)
@export var placeholder_color := Color(0.22, 0.24, 0.27)
@export var placeholder_size := Vector3(0.06, 0.09, 0.42)

var ammo := 0
var is_reloading: bool:
	get:
		return _anim.is_playing() and _anim.current_animation == CLIP_RELOAD
var is_switching: bool:
	get:
		return _anim.is_playing() and _anim.current_animation in [CLIP_EQUIP, CLIP_HOLSTER]

var _anim: AnimationPlayer
var _next_fire_time := 0.0


func _ready() -> void:
	ammo = magazine_size
	_anim = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _anim == null:
		_anim = _build_placeholder()
	_anim.animation_finished.connect(_on_animation_finished)


func equip() -> void:
	visible = true
	_anim.play(CLIP_EQUIP)


func holster() -> void:
	_anim.play(CLIP_HOLSTER)


## Fires if ready. origin/direction describe the aim ray.
func try_fire(origin: Vector3, direction: Vector3, exclude: RID, space: PhysicsDirectSpaceState3D) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_fire_time or is_reloading or is_switching:
		return false
	if ammo <= 0:
		reload()
		return false
	_next_fire_time = now + fire_interval
	ammo -= 1
	_anim.stop()
	_anim.play(CLIP_FIRE)

	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * fire_range, 1 | 4, [exclude])
	var hit := space.intersect_ray(query)
	var body := hit.get("collider") as RigidBody3D
	if body:
		body.apply_impulse(direction * hit_impulse, hit.position - body.global_position)
	fired.emit(self)
	return true


func reload() -> void:
	if ammo == magazine_size or is_reloading or is_switching:
		return
	_anim.play(CLIP_RELOAD)


func _on_animation_finished(clip: StringName) -> void:
	if clip == CLIP_RELOAD:
		ammo = magazine_size
	elif clip == CLIP_HOLSTER:
		visible = false


# ---- Placeholder content -----------------------------------------------------------------------

func _build_placeholder() -> AnimationPlayer:
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = placeholder_color
	metal.metallic = 0.6
	metal.roughness = 0.45
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.78, 0.6, 0.48)
	skin.roughness = 0.8
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.25, 0.3, 0.22)
	sleeve.roughness = 0.9
	var s := placeholder_size
	_add_box(pivot, Vector3(0.0, 0.0, -s.z * 0.5), s, metal)                                            # receiver
	_add_box(pivot, Vector3(0.0, s.y * 0.15, -s.z - 0.08), Vector3(0.025, 0.025, 0.16), metal)          # barrel
	_add_box(pivot, Vector3(0.0, -s.y, -s.z * 0.25), Vector3(0.04, 0.1, 0.05), metal)                   # grip
	_add_box(pivot, Vector3(0.0, -s.y * 0.9, -s.z * 0.6), Vector3(0.035, 0.12, 0.06), metal)            # magazine
	_add_box(pivot, Vector3(0.0, -s.y * 0.9, -s.z * 0.18), Vector3(0.06, 0.06, 0.08), skin)             # right hand
	_add_box(pivot, Vector3(0.02, -s.y * 0.9, 0.08), Vector3(0.08, 0.08, 0.22), sleeve)                 # right forearm
	_add_box(pivot, Vector3(-0.01, -s.y * 0.55, -s.z * 0.8), Vector3(0.06, 0.05, 0.08), skin)           # left hand
	_add_box(pivot, Vector3(-0.09, -s.y * 0.9, -s.z * 0.55), Vector3(0.08, 0.08, 0.24), sleeve)

	var anim := AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	add_child(anim)
	var library := AnimationLibrary.new()
	var lowered := Vector3(0.05, -0.3, 0.1)
	var lowered_rot := Vector3(-0.9, 0.3, 0.2)
	var zero := Vector3.ZERO
	library.add_animation(CLIP_EQUIP, _clip(0.3, [[0.0, lowered, lowered_rot], [0.3, zero, zero]]))
	library.add_animation(CLIP_HOLSTER, _clip(0.25, [[0.0, zero, zero], [0.25, lowered, lowered_rot]]))
	library.add_animation(CLIP_FIRE, _clip(0.12, [
		[0.0, zero, zero],
		[0.03, Vector3(0.0, 0.005, 0.035), Vector3(0.06, 0.0, 0.0)],
		[0.12, zero, zero]]))
	library.add_animation(CLIP_RELOAD, _clip(1.1, [
		[0.0, zero, zero],
		[0.25, Vector3(0.02, -0.08, 0.02), Vector3(-0.2, 0.2, 0.7)],
		[0.8, Vector3(0.02, -0.1, 0.02), Vector3(-0.25, 0.25, 0.75)],
		[1.1, zero, zero]]))
	anim.add_animation_library("", library)
	return anim


## keys: [[time, position, rotation], ...]
static func _clip(length: float, keys: Array) -> Animation:
	var a := Animation.new()
	a.length = length
	var p := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(p, "Pivot:position")
	var r := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(r, "Pivot:rotation")
	for key in keys:
		a.track_insert_key(p, key[0], key[1])
		a.track_insert_key(r, key[0], key[2])
	return a


static func _add_box(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var box := MeshInstance3D.new()
	box.mesh = mesh
	box.material_override = material
	box.position = pos
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box.layers = RenderLayers.VIEWMODEL
	parent.add_child(box)
