extends CanvasLayer

func _ready() -> void:
	# Ensure this UI processes while paused and can receive signals
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Hidden by default when parent pause menu is shown
	visible = false

	# Look for QuitButton; allow common fallback path if nested under a Background/Control
	var btn := get_node_or_null("QuitButton")
	if btn == null:
		btn = get_node_or_null("Background/QuitButton")

	if btn:
		if not btn.pressed.is_connected(_on_quit_pressed):
			btn.pressed.connect(_on_quit_pressed)
	else:
		push_warning("[CREDITS] QuitButton not found. Check node path.")


func _on_quit_pressed() -> void:
	# Ask parent PauseScreen to restore the pause menu
	var p := get_parent()
	if p and p.has_method("_show_pause_menu"):
		print("[PAUSE] Returning to pause menu")
		p._show_pause_menu()
	else:
		push_warning("[CREDITS] Parent missing _show_pause_menu()")
