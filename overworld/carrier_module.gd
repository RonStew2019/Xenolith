extends Resource
class_name CarrierModule
## Base class for all carrier modules.
##
## Modules are [Resource]-based so they can be saved, loaded, and shared
## between carriers.  Each module occupies one slot and draws power from
## the carrier's reactor budget (except reactors themselves).
##
## Subclasses override [method get_module_type] and optionally
## [method on_install] / [method on_uninstall] for side effects.

# -- Properties ------------------------------------------------------------

## Display name shown in UI and debug logs.
@export var module_name: StringName = &""

## Tooltip / description text for UI.
@export var description: String = ""

## How much reactor power this module consumes when installed.
@export var power_cost: int = 1

# -- Virtual Methods -------------------------------------------------------

## Called when the module is installed into a carrier slot.
## Override in subclasses for install-time side effects.
func on_install(_carrier: Carrier) -> void:
	pass


## Called when the module is removed from a carrier slot.
## Override in subclasses for uninstall-time cleanup.
func on_uninstall(_carrier: Carrier) -> void:
	pass


## Returns a type identifier for this module (e.g. [code]&"fabricator"[/code]).
## Must be overridden by every concrete subclass.
func get_module_type() -> StringName:
	return &""
