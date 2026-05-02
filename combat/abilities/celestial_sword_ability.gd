extends ProjectileAbility
class_name CelestialSwordAbility
## A celestial sword that toggles between a passive self-buff (aura on the
## wielder's reactor) and a deployed sword entity in the world.
##
## Part of the **Celestial Armory** loadout — up to three of these abilities
## share the loadout, each with a unique [member _sword_name] /
## [member _aura_name] pair (e.g. "Sword Alpha" / "Sword Alpha Aura").
##
## [b]Inverted toggle lifecycle:[/b] Unlike standard TOGGLE abilities where
## activation adds effects and deactivation removes them, this ability's
## passive buff exists when the ability is [b]INACTIVE[/b]:
##
##   • [b]Inactive[/b] (default) — aura effect is applied to the wielder's
##     reactor. The sword is "recalled" and granting its passive benefit.
##   • [b]Active[/b]  — aura is removed, sword is deployed as a
##     [CelestialSwordEntity] via [SwordProjectile]. No passive benefit.
##
## Because of this inversion, the ability manages its own effect lifecycle
## manually rather than using the base [code]_apply_effects[/code] /
## [code]_remove_effects[/code] pipeline. The [method on_equip] hook
## applies the initial passive buff when the ability is first equipped.
##
## [b]Sword tracking:[/b] Uses the same [code]tree_exiting[/code] pattern
## as [ResonancePillarAbility]: when the [SwordProjectile] exits the tree
## (impact or expiry), we scan for the newly-spawned [CelestialSwordEntity]
## with matching [code]owning_ability == self[/code] and store a [WeakRef].
## Also connects to the sword's [signal CelestialSwordEntity.recalled]
## signal to handle external destruction (reapply buff).

## The passive buff currently applied to the wielder's reactor, or null
## if the sword is deployed (buff removed).
var _passive_effect: CelestialSwordAuraEffect = null

## WeakRef to the deployed [CelestialSwordEntity], or null if recalled.
var _deployed_sword: WeakRef = null

## Display name for this sword (e.g. "Sword Alpha").
var _sword_name: String = "Celestial Sword"

## Display name for this sword's aura effect (e.g. "Sword Alpha Aura").
var _aura_name: String = "Celestial Sword Aura"

## Cached user reference for signal callbacks (recalled handler).
var _user_ref: WeakRef = null

## True while a [SwordProjectile] is in flight (between [method _fire_projectile]
## and [method _on_projectile_exiting]).  Guards [method activate] to prevent
## duplicate deploys or premature recalls during the travel window.
var _projectile_in_flight: bool = false


func _init(
	p_input: String = "ability_1",
	p_sword_name: String = "Celestial Sword",
	p_aura_name: String = "Celestial Sword Aura",
) -> void:
	ability_name = p_sword_name
	input_action = p_input
	activation_mode = ActivationMode.TOGGLE
	projectile_speed = 30.0
	projectile_lifetime = 3.0
	_sword_name = p_sword_name
	_aura_name = p_aura_name


## Called once when the ability is first equipped in a loadout.
## Applies the initial passive buff — the sword starts in "recalled"
## state, granting its aura to the wielder.
func on_equip(user: Node) -> void:
	_user_ref = weakref(user)
	var reactor := _get_reactor(user)
	if not reactor:
		return
	_passive_effect = CelestialSwordAuraEffect.new(_aura_name, user)
	reactor.apply_effect(_passive_effect)


## Completely overrides the standard toggle flow to implement the
## inverted lifecycle: first press deploys the sword (removes buff),
## second press recalls the sword (reapplies buff).
func activate(user: Node) -> void:
	# Guard: ignore input while a projectile is mid-flight.  This prevents
	# both duplicate deploys and premature recalls (see race condition docs).
	if _projectile_in_flight:
		return

	var reactor := _get_reactor(user)
	if not reactor:
		return
	_user_ref = weakref(user)

	if not _active:
		# -- Deploy: remove passive buff, fire sword projectile -----------
		if _passive_effect:
			reactor.remove_effect(_passive_effect)
			_passive_effect = null
		_fire_projectile(user)
		_active = true
		activated.emit(user)
	else:
		# -- Recall: bring sword back, reapply passive buff ---------------
		_active = false  # Set BEFORE recall so _on_sword_recalled no-ops
		_recall_deployed_sword()
		_passive_effect = CelestialSwordAuraEffect.new(_aura_name, user)
		reactor.apply_effect(_passive_effect)
		deactivated.emit(user)


## No-op — TOGGLE deactivation is handled inside [method activate] on
## the second press, not on key release.
func deactivate(_user: Node) -> void:
	pass


## Force-remove all state: recall deployed sword, remove passive buff,
## reset activation. Called on death / loadout swap.
func force_deactivate(user: Node) -> void:
	var was_active := _active
	_active = false  # Set BEFORE recall so _on_sword_recalled no-ops
	_recall_deployed_sword()
	if _passive_effect:
		var reactor := _get_reactor(user)
		if reactor:
			reactor.remove_effect(_passive_effect)
		_passive_effect = null
	_deployed_sword = null
	_projectile_in_flight = false
	_user_ref = null
	_applied_effects.clear()
	if was_active:
		deactivated.emit(user)


## Return a fresh, independent copy bound to the same input action.
## Overrides base because our _init takes three params, not one.
func duplicate_ability() -> Ability:
	return CelestialSwordAbility.new(input_action, _sword_name, _aura_name)


# -- Overrides -------------------------------------------------------------

## Spawn a [SwordProjectile] instead of the base [Projectile].
## Passes [code]self[/code] as [code]owning_ability[/code] so the spawned
## [CelestialSwordEntity] gets a back-reference for tracking.
func _fire_projectile(user: Node) -> void:
	var tree := user.get_tree()
	if not tree:
		return

	var direction := _get_aim_direction(user)

	var proj := SwordProjectile.new()
	proj.setup(
		user,
		direction,
		projectile_speed,
		projectile_lifetime,
		_sword_name,
		self,
	)

	tree.current_scene.add_child(proj)
	proj.global_position = _get_spawn_position(user, direction)
	_projectile_in_flight = true

	# Register sword-tracking hook: when the projectile exits the tree
	# (terrain impact OR lifetime expiry), scan for the newly-spawned
	# CelestialSwordEntity and claim it for recall / force_deactivate.
	proj.tree_exiting.connect(_on_projectile_exiting.bind(user))


# -- Sword Tracking --------------------------------------------------------

## Handler for each spawned [SwordProjectile]'s [signal Node.tree_exiting].
## Scans the [code]"characters"[/code] group for a [CelestialSwordEntity]
## whose [member CelestialSwordEntity.owning_ability] matches [code]self[/code]
## and that isn't already tracked.
func _on_projectile_exiting(user: Node) -> void:
	_projectile_in_flight = false
	if not is_instance_valid(user):
		return
	var tree := user.get_tree()
	if not tree:
		return
	for node in tree.get_nodes_in_group("characters"):
		if not (node is CelestialSwordEntity):
			continue
		var sword: CelestialSwordEntity = node
		if sword.owning_ability != self:
			continue
		# Found our sword — store WeakRef and connect recalled signal.
		_deployed_sword = weakref(sword)
		sword.recalled.connect(_on_sword_recalled.bind(user))
		break


## Called when the deployed sword is recalled externally (e.g. destroyed
## by an enemy, or some future mechanic). Reapplies the passive buff if
## the ability is still in "active" (sword deployed) state.
func _on_sword_recalled(user: Node) -> void:
	_deployed_sword = null
	if not _active:
		return
	if not is_instance_valid(user):
		return
	var reactor := _get_reactor(user)
	if not reactor:
		return
	_passive_effect = CelestialSwordAuraEffect.new(_aura_name, user)
	reactor.apply_effect(_passive_effect)
	_active = false
	deactivated.emit(user)


## Recall the currently deployed sword if it still exists.
func _recall_deployed_sword() -> void:
	if _deployed_sword == null:
		return
	var sword: Node = _deployed_sword.get_ref()
	if sword and is_instance_valid(sword) and not sword.is_queued_for_deletion():
		sword.recall()
	_deployed_sword = null
