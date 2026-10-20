@abstract
class_name MovementAbility
extends Node
## An optional movement mode (slide, mantle, ladder, swim, or your own) that takes over from the base
## ground/air movement while active. Abilities are nodes under the player's `Abilities` child; child order
## is priority (the first whose can_begin() passes takes over). Add, remove or reorder them in the editor or
## at runtime (e.g. unlocking a skill adds its node); the motor follows. Abilities move the body only through
## PlayerMotor.move_body() (or swept motion of their own).


## State reported while active. Custom abilities return PlayerMotor.MovementState.CUSTOM.
@abstract func get_state() -> PlayerMotor.MovementState


## Name shown in debug tools; defaults to the state, or the node name for custom abilities.
func get_state_name() -> String:
	var state := get_state()
	if state == PlayerMotor.MovementState.CUSTOM:
		return String(name)
	return PlayerMotor.MovementState.keys()[state].capitalize()


## Checked every tick while no ability is active, in priority order.
@abstract func can_begin(motor: PlayerMotor, cmd: PlayerCommand) -> bool


@abstract func begin(motor: PlayerMotor, cmd: PlayerCommand) -> void


## Simulates one tick, including moving the body. Return false to hand control back.
@abstract func tick(motor: PlayerMotor, cmd: PlayerCommand, dt: float) -> bool


@abstract func end(motor: PlayerMotor) -> void
