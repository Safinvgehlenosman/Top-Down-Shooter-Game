extends CanvasLayer

@onready var continue_button: Button = $ContinueButton
@onready var fullscreen_button: Button = $FullscreenButton
@onready var quit_button: Button = $QuitButton
@onready var credits_button: Button = $CreditsButton
@onready var credits_screen: CanvasLayer = get_node_or_null("CreditsScreen")

var buttons: Array[Button] = []
var focused_index: int = 0
var _pause_vis_backup: Array = []

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	
	if continue_button:
		continue_button.pressed.connect(_on_continue_pressed)
	if fullscreen_button:
		fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

	# Credits handling: show/hide in-place while paused
	if credits_button:
		if not credits_button.pressed.is_connected(_on_credits_pressed):
			credits_button.pressed.connect(_on_credits_pressed)

	# Ensure CreditsScreen starts hidden
	if credits_screen:
		credits_screen.visible = false
	
	buttons = [continue_button, fullscreen_button, quit_button]
	for b in buttons:
		if b:
			b.focus_mode = Control.FOCUS_ALL

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Don't open pause if ShopUI is visible; shop owns ESC while open
		var shop_ui = get_tree().get_first_node_in_group("shop")
		if shop_ui and shop_ui.visible:
			return
		toggle_pause()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_down"):
		_move_focus(1)
	elif event.is_action_pressed("ui_up"):
		_move_focus(-1)

func _move_focus(direction: int) -> void:
	focused_index = (focused_index + direction + buttons.size()) % buttons.size()
	if buttons[focused_index]:
		buttons[focused_index].grab_focus()

func toggle_pause() -> void:
	if visible:
		hide_pause()
	else:
		show_pause()

func show_pause() -> void:
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_hide_main_ui()
	if continue_button:
		continue_button.grab_focus()

func hide_pause() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_show_main_ui()

func _hide_main_ui() -> void:
	var ui = get_parent()
	if not ui:
		return
	for child in ui.get_children():
		if child == self or child.name == "VHSLayer":
			continue
		child.visible = false

func _show_main_ui() -> void:
	var ui = get_parent()
	if not ui:
		return
	# Prefer the UI's refresh handler when available so Ammo visibility is enforced
	if ui and ui.has_method("refresh_ui_visibility"):
		ui.refresh_ui_visibility()
		return

	# Fallback: set elements visible
	for element_name in ["Ammo", "Coins", "Level", "PlayerInfo", "DoorArrowRoot"]:
		var element = ui.get_node_or_null(element_name)
		if element:
			element.visible = true

func _on_continue_pressed() -> void:
	print("[Pause] Continue pressed - before unpause paused=", get_tree().paused)
	# Ensure game is unpaused
	get_tree().paused = false
	# Hide this pause menu
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	# Restore main UI visibility: prefer parent refresh method
	var ui = get_parent()
	if ui and ui.has_method("refresh_ui_visibility"):
		print("[Pause] calling ui.refresh_ui_visibility()")
		ui.refresh_ui_visibility()
		# Also ensure parent container nodes are visible (refresh may only toggle inner labels)
		for container_name in ["PlayerInfo", "HPFill", "Coins", "Level", "DoorArrowRoot"]:
			var c = ui.get_node_or_null(container_name)
			if c:
				c.visible = true
				print("[Pause] restored container ->", container_name)
			else:
				print("[Pause] container missing ->", container_name)
	else:
		# Explicitly restore core UI elements
		for element_name in ["HPFill", "PlayerInfo", "Coins", "Level", "DoorArrowRoot"]:
			var element = ui.get_node_or_null(element_name) if ui else null
			if element:
				element.visible = true
				print("[Pause] restored visible ->", element_name)
			else:
				print("[Pause] missing UI element ->", element_name)

	print("[Pause] Continue done - after unpause paused=", get_tree().paused)


func _on_credits_pressed() -> void:
	_show_credits()


func _show_credits() -> void:
	if not credits_screen:
		credits_screen = get_node_or_null("CreditsScreen")
	if not credits_screen:
		push_warning("[PAUSE] CreditsScreen node not found")
		return

	# Backup visibility of all children so we can restore exactly
	_pause_vis_backup.clear()
	for child in get_children():
		var entry := {"path": child.get_path(), "visible": child.visible}
		# Don't hide the credits screen itself
		if child == credits_screen:
			continue
		_pause_vis_backup.append(entry)
		child.visible = false

	credits_screen.visible = true
	print("[PAUSE] Showing credits")
	# Remain paused
	get_tree().paused = true


func _show_pause_menu() -> void:
	# Hide credits overlay first
	if credits_screen:
		credits_screen.visible = false

	# Restore previous visibility
	for entry in _pause_vis_backup:
		var node = get_node_or_null(entry["path"])
		if node:
			node.visible = entry["visible"]

	_pause_vis_backup.clear()
	# Ensure the pause menu (this) is visible and focused
	visible = true
	print("[PAUSE] Returning to pause menu")
	if continue_button:
		continue_button.grab_focus()

func _on_fullscreen_pressed() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _on_restart_pressed() -> void:
	hide_pause()
	get_tree().paused = false
	GameState.start_new_run()
	# Wait one frame so the new run state fully propagates before loading the scene
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/level_1.tscn")

func _on_quit_pressed() -> void:
	hide_pause()
	get_tree().paused = false
	# Ensure run state is cleared when quitting to the start screen
	GameState.end_run_to_menu()
	# Wait one frame so the new run state fully propagates before loading the start screen
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")
