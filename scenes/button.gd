extends Button

@export var hover_scale := 0.37
@export var tween_duration := 0.08

var _base_scale := Vector2.ONE

func _ready() -> void:
	# Remember original scale
	_base_scale = scale
	# IMPORTANT: make it scale from the center, not top-left
	pivot_offset = size * 0.5
	
	# Make sure we get the signals (or connect them in the editor)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE * hover_scale, tween_duration)

func _on_mouse_exited() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", _base_scale, tween_duration)
