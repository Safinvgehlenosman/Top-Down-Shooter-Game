extends Node2D

@onready var label: Label = $Label
@onready var light: PointLight2D = get_node_or_null("PointLight2D")

var lifetime: float = 0.8


func _ready() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(self, "position:y", position.y - 40, lifetime)
	tween.tween_property(label, "modulate:a", 0.0, lifetime)
	
	if light:
		tween.tween_property(light, "energy", 0.0, lifetime)
	
	tween.chain().tween_callback(queue_free)
