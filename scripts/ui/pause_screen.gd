extends CanvasLayer

@onready var continue_button: Button = $ContinueButton
@onready var fullscreen_button: Button = $FullscreenButton
@onready var restart_button: Button = $RestartButton
@onready var quit_button: Button = $QuitButton

var buttons: Array[Button] = []
var focused_index: int = 0

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	
	if continue_button:
		continue_button.pressed.connect(_on_continue_pressed)
	if fullscreen_button:
		fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	
	buttons = [continue_button, fullscreen_button, restart_button, quit_button]
	for b in buttons:
		if b:
			b.focus_mode = Control.FOCUS_ALL

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
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
	for element_name in ["Ammo", "Coins", "Level", "PlayerInfo", "DoorArrowRoot"]:
		var element = ui.get_node_or_null(element_name)
		if element:
			element.visible = true

func _on_continue_pressed() -> void:
	hide_pause()

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
	GameState.start_new_run()
	# Wait one frame so the new run state fully propagates before loading the start screen
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")
