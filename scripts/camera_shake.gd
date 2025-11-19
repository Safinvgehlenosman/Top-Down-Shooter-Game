extends Camera2D

var shake_time_left: float = 0.0
var shake_duration: float = 0.0
var shake_strength: float = 0.0
var original_offset: Vector2


func _ready() -> void:
	original_offset = offset


func _process(delta: float) -> void:
	if shake_time_left > 0.0:
		shake_time_left -= delta

		var t: float = clamp(shake_time_left / shake_duration, 0.0, 1.0)
		var current_strength: float = shake_strength * t

		var random_offset := Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * current_strength

		offset = original_offset + random_offset
	else:
		offset = original_offset


func shake(strength: float, duration: float) -> void:
	shake_strength = strength
	shake_duration = max(duration, 0.001)
	shake_time_left = shake_duration
