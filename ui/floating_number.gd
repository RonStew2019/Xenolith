extends Label3D
class_name FloatingNumber
## Billboarded 3D label that shows a value, lingers, then fades upward.
##
## Lifecycle (driven externally via [method start_expire_sequence]):
##   1. Created and configured by caller.
##   2. Caller invokes start_expire_sequence() when the effect ends.
##   3. Lingers in place for 2 s.
##   4. Fades out + rises over 1.5 s.
##   5. queue_free().


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	pixel_size = 0.001
	font_size = 48
	modulate = Color(1.0, 0.55, 0.1)
	outline_modulate = Color(0.08, 0.04, 0.0)
	outline_size = 12


## Kick off the linger -> fade -> rise -> die sequence.
func start_expire_sequence() -> void:
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(self, "position", position + Vector3.UP * 1.5, 1.5)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 1.5)
	tw.tween_callback(queue_free)
