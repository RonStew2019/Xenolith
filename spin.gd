extends MeshInstance3D
## Gently spins a mesh around the Y axis. That's it. SRP, baby.

@export var spin_speed: float = 1.0


func _process(delta: float) -> void:
	rotate_y(spin_speed * delta)
