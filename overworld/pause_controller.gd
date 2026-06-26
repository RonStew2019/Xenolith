extends Node
class_name PauseController
## FTL-style real-time-with-pause toggle.
##
## Listens for the Space key to pause/unpause the game via
## [member SceneTree.paused].  Must have [code]process_mode[/code] set to
## [constant PROCESS_MODE_ALWAYS] so input is received while paused.
##
## Emits [signal pause_toggled] so UI nodes (e.g. [OverworldHUD]) can
## react without polling.

# -- Signals ---------------------------------------------------------------

## Emitted when the pause state changes.
signal pause_toggled(is_paused: bool)

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_SPACE:
			_toggle_pause()


# -- Internals ------------------------------------------------------------

func _toggle_pause() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = not tree.paused
	pause_toggled.emit(tree.paused)
	print("[PauseController] %s" % ("PAUSED" if tree.paused else "UNPAUSED"))
