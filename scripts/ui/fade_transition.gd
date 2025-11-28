extends CanvasLayer

signal fade_in_finished
signal fade_out_finished

@onready var fade_rect: ColorRect = $FadeRect

@export var fade_duration: float = 0.5

var is_fading: bool = false


func _ready() -> void:
	# Make sure it covers the entire screen
	if fade_rect:
		fade_rect.color = Color(0, 0, 0, 0)  # Start transparent
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		# Cover full viewport
		fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)


func fade_in() -> void:
	"""Fade to black"""
	if is_fading:
		return
	
	is_fading = true
	
	var tween = create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, fade_duration)
	tween.finished.connect(_on_fade_in_finished)


func fade_out() -> void:
	"""Fade from black to transparent"""
	if is_fading:
		return
	
	is_fading = true
	
	var tween = create_tween()
	tween.tween_property(fade_rect, "color:a", 0.0, fade_duration)
	tween.finished.connect(_on_fade_out_finished)


func _on_fade_in_finished() -> void:
	is_fading = false
	emit_signal("fade_in_finished")


func _on_fade_out_finished() -> void:
	is_fading = false
	emit_signal("fade_out_finished")


func set_black() -> void:
	"""Instantly set to black (for starting a level)"""
	if fade_rect:
		fade_rect.color = Color(0, 0, 0, 1)


func set_transparent() -> void:
	"""Instantly set to transparent"""
	if fade_rect:
		fade_rect.color = Color(0, 0, 0, 0)