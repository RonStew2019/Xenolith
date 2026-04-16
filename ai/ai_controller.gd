extends Node
class_name AIController
## Base class for swappable AI / control controllers that drive a
## [CharacterBase]-derived host.
##
## A host instantiates one [AIController] child (typically in its
## [code]_ready()[/code]) and calls [method tick] each physics frame.
## Swapping is done via [code]host.set_controller(new_controller)[/code]
## which triggers the outgoing controller's [method on_exit] followed
## by the incoming controller's [method on_enter].
##
## Controllers may read/write any public-ish state on the host (e.g.
## [code]host._apply_movement()[/code], [code]host._loadout[/code],
## [code]host.punch_reach[/code]) and own their own internal state
## (cooldowns, state-machine flags, wander targets, etc.).

## Typed ref to the host character. Set by the host immediately before
## [method on_enter] is invoked; never null during an active tick.
var host: CharacterBase


## Called once after the controller is attached and [member host] is set.
## Override to capture spawn position, start timers, build UI, etc.
func on_enter() -> void:
	pass


## Called before the controller is detached / queue_freed on swap.
## Override to release UI, cameras, input captures, running timers.
func on_exit() -> void:
	pass


## Driven by the host's [code]_physics_process[/code] each frame.
## Override to run the AI's per-frame logic (typically ends with a
## [code]host._apply_movement(dir, delta)[/code] call).
func tick(_delta: float) -> void:
	pass
