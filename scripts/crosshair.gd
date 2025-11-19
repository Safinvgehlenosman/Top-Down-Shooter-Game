extends Node2D

func _ready() -> void:
	# Hide the normal OS mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _process(_delta: float) -> void:
	# Move the crosshair to the mouse position in the world
	global_position = get_global_mouse_position()
