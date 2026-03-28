extends Node
## Global clock that emits synchronized combat ticks.
## Register as autoload "CombatTickClock" in Project Settings.
##
## Every reactor, every status effect, every heat calculation pulses
## to this single heartbeat.  Pause it for menus or cutscenes.

signal tick

## Seconds between each combat tick.
@export var tick_interval: float = 0.1

var _timer: float = 0.0
var _active: bool = true


func _process(delta: float) -> void:
	if not _active:
		return
	_timer += delta
	if _timer >= tick_interval:
		_timer -= tick_interval
		tick.emit()


## Pause / resume tick emission (e.g. menus, cutscenes).
func set_active(active: bool) -> void:
	_active = active


## Reset the internal timer without pausing.
func reset_timer() -> void:
	_timer = 0.0
