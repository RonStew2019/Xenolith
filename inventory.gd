extends Node
class_name Inventory
## Generic resource inventory that stores named resource types as integer
## amounts.  Attach as a child of a character to give it an inventory.
##
## Example:
##   inventory.add_resource(&"flux", 100)
##   if inventory.has_enough(&"flux", 50):
##       inventory.remove_resource(&"flux", 50)

# -- Signals ---------------------------------------------------------------

## Emitted whenever a resource amount changes (add or remove).
signal resource_changed(resource_type: StringName, new_amount: int)
## Emitted when resources are added — useful for floating "+N" UI feedback.
signal resource_added(resource_type: StringName, amount_added: int)

# -- Internal State --------------------------------------------------------

## Maps resource type names to integer amounts.
var _resources: Dictionary = {}

# -- Public API ------------------------------------------------------------

## Add [param amount] units of [param resource_type] to the inventory.
## Creates the entry if it doesn't exist yet.
func add_resource(resource_type: StringName, amount: int) -> void:
	if amount <= 0:
		return
	var current: int = _resources.get(resource_type, 0)
	var new_amount: int = current + amount
	_resources[resource_type] = new_amount
	resource_added.emit(resource_type, amount)
	resource_changed.emit(resource_type, new_amount)


## Remove [param amount] units of [param resource_type].
## Returns [code]true[/code] on success, [code]false[/code] if the
## inventory doesn't hold enough (no change is made in that case).
func remove_resource(resource_type: StringName, amount: int) -> bool:
	if amount <= 0:
		return true
	var current: int = _resources.get(resource_type, 0)
	if current < amount:
		return false
	var new_amount: int = current - amount
	if new_amount == 0:
		_resources.erase(resource_type)
	else:
		_resources[resource_type] = new_amount
	resource_changed.emit(resource_type, new_amount)
	return true


## Return the current amount of [param resource_type] (0 if not present).
func get_amount(resource_type: StringName) -> int:
	return _resources.get(resource_type, 0)


## Convenience check: does the inventory hold at least [param amount]?
func has_enough(resource_type: StringName, amount: int) -> bool:
	return get_amount(resource_type) >= amount


## Return a shallow copy of the full resource dictionary.
func get_all_resources() -> Dictionary:
	return _resources.duplicate()
