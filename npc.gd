extends CharacterBase
## NPC host — a [CharacterBase] that delegates all behavior to a
## swappable [AIController] child.
##
## By default a [WanderAI] is attached in [method _ready]; call
## [method set_controller] at runtime to hot-swap any other AI
## (e.g. [code]$MyNpc.set_controller(CombatAI.new())[/code]).

var _active_controller: AIController


func _ready() -> void:
	super._ready()
	_setup_reactor()
	set_controller(WanderAI.new())


func _setup_reactor() -> void:
	_reactor = ReactorCore.new()
	_reactor.name = "ReactorCore"
	add_child(_reactor)
	_reactor.reactor_breached.connect(die)
	_bind_reactor_glow(_reactor)


# ── AI delegation ────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _active_controller:
		_active_controller.tick(delta)


## Hot-swap this NPC's active controller. Pass [code]null[/code] to
## detach the current controller without replacing it (e.g. as part
## of a custom death/cleanup flow). Handles on_exit/on_enter ordering.
func set_controller(new_controller: AIController) -> void:
	if _active_controller:
		_active_controller.on_exit()
		_active_controller.queue_free()
		_active_controller = null
	if new_controller:
		_active_controller = new_controller
		new_controller.host = self
		add_child(new_controller)
		new_controller.on_enter()
