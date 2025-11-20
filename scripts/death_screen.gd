extends CanvasLayer



func _on_restart_button_pressed() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func _on_quit_button_pressed() -> void:
	Engine.time_scale = 1.0
	get_tree().quit()
