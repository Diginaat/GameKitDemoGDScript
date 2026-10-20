class_name MoveMath
## Source-inspired acceleration and friction (see Source SDK 2013 gamemovement.cpp: Friction, Accelerate,
## AirAccelerate). Pure functions on horizontal velocity so they can be tested without a scene.


## Source ground friction, integrated exactly instead of per-tick so stopping distance does not depend on
## the physics tick rate. Source's rule is drop = max(speed, stop_speed) * friction * dt: above stop_speed
## that is exponential decay, below it a constant deceleration.
static func apply_friction(velocity: Vector3, friction: float, stop_speed: float, dt: float) -> Vector3:
	var speed := velocity.length()
	if speed < 1e-4:
		return Vector3.ZERO
	if friction <= 0.0 or dt <= 0.0:
		return velocity

	var new_speed := speed
	var remaining := dt
	if stop_speed <= 0.0:
		new_speed *= exp(-friction * remaining)
		remaining = 0.0
	elif new_speed > stop_speed:
		var time_to_stop_speed := log(new_speed / stop_speed) / friction
		if time_to_stop_speed >= remaining:
			new_speed *= exp(-friction * remaining)
			remaining = 0.0
		else:
			new_speed = stop_speed
			remaining -= time_to_stop_speed

	if remaining > 0.0:
		new_speed = maxf(0.0, new_speed - friction * stop_speed * remaining)

	return velocity * (new_speed / speed)


## Source Accelerate: adds speed along wish_dir until the projection of velocity onto it reaches
## wish_speed. Speed in other directions is untouched, which is what preserves momentum while still giving
## instant directional control.
static func accelerate(velocity: Vector3, wish_dir: Vector3, wish_speed: float, accel: float, dt: float) -> Vector3:
	var add_speed := wish_speed - velocity.dot(wish_dir)
	if add_speed <= 0.0:
		return velocity
	var accel_speed := minf(accel * wish_speed * dt, add_speed)
	return velocity + wish_dir * accel_speed


## Source AirAccelerate: like accelerate() but the projected-speed target is capped at air_speed_cap while
## the acceleration rate still uses the full wish speed. Strafing perpendicular to velocity therefore turns
## (and can gain speed: air strafing).
static func air_accelerate(velocity: Vector3, wish_dir: Vector3, wish_speed: float, accel: float, air_speed_cap: float, dt: float) -> Vector3:
	var capped_wish := minf(wish_speed, air_speed_cap)
	var add_speed := capped_wish - velocity.dot(wish_dir)
	if add_speed <= 0.0:
		return velocity
	var accel_speed := minf(accel * wish_speed * dt, add_speed)
	return velocity + wish_dir * accel_speed


## Clamps the horizontal (XZ) speed, keeping the vertical component.
static func clamp_horizontal(velocity: Vector3, max_speed: float) -> Vector3:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var speed := h.length()
	if speed <= max_speed or speed < 1e-4:
		return velocity
	h *= max_speed / speed
	return Vector3(h.x, velocity.y, h.z)


## Launch speed that reaches `height` under `gravity`.
static func jump_velocity(height: float, gravity: float) -> float:
	return sqrt(2.0 * gravity * height)


## Frame-rate-independent exponential smoothing factor for lerp(a, b, factor).
static func smooth_factor(rate: float, dt: float) -> float:
	return 1.0 - exp(-rate * dt)
