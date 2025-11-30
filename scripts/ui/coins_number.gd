extends Node2D

@export var rise_speed: float = 30.0
@export var lifetime: float = 0.8

@onready var label: Label = $Label
@onready var point_light: PointLight2D = get_node_or_null("PointLight2D")


func _ready() -> void:
	# Animate upward movement and fade
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Move upward
	tween.tween_property(self, "position", position + Vector2(0, -40), lifetime)
	
	# Fade out label
	if label:
		tween.tween_property(label, "modulate:a", 0.0, lifetime)
	
	# Fade out light
	if point_light:
		tween.tween_property(point_light, "energy", 0.0, lifetime)
	
	# Despawn after animation
	tween.chain().tween_callback(queue_free)
