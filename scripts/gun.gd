extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

func _process(_delta: float) -> void:
	# Aim toward mouse position in world space
	look_at(get_global_mouse_position())
