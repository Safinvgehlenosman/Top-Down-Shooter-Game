extends Node2D

@export var rise_speed: float = 30.0
@export var lifetime: float = 0.8
@export var fade_start: float = 0.4

var velocity: Vector2 = Vector2.ZERO
var time_alive: float = 0.0

@onready var label: Label = $Label


func _ready() -> void:
	# Random slight horizontal drift
	velocity = Vector2(randf_range(-10, 10), -rise_speed)
	
	# Start fading after fade_start duration
	modulate.a = 1.0


func setup(damage: int, crit: bool = false) -> void:
	label.text = str(damage)
	
	if crit:
		label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))  # Gold
		label.add_theme_font_size_override("font_size", 20)
	else:
		label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))  # Red
		label.add_theme_font_size_override("font_size", 14)


func _process(delta: float) -> void:
	time_alive += delta
	
	if time_alive >= lifetime:
		queue_free()
		return
	
	# Move upward
	position += velocity * delta
	
	# Fade out in last portion of lifetime
	if time_alive >= fade_start:
		var fade_progress = (time_alive - fade_start) / (lifetime - fade_start)
		modulate.a = 1.0 - fade_progress