extends CanvasLayer
func _show_main_ui() -> void:
	var ui = get_parent()
	if not ui:
		return
	for element_name in ["Ammo", "Coins", "Level", "PlayerInfo", "DoorArrowRoot"]:
		var element = ui.get_node_or_null(element_name)
		if element:
			element.visible = true


@onready var restart_button: Button = $RestartButton
@onready var quit_button: Button = $QuitButton

var buttons: Array[Button] = []
var focused_index: int = 0

func _ready() -> void:
	print("=== DEATHSCREEN _ready() ===")
	print("DeathScreen instance created: ", self)
	print("DeathScreen path: ", get_path())
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

	buttons = [restart_button, quit_button]
	for b in buttons:
		if b:
			b.focus_mode = Control.FOCUS_ALL

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

func show_death_screen() -> void:
	print("=== DEATH SCREEN SHOW ===")
	print("Tree paused before: ", get_tree().paused)
	visible = true
	get_tree().paused = true
	print("Tree paused after: ", get_tree().paused)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_hide_main_ui()
	if restart_button:
		restart_button.grab_focus()
	print("=== DEATH SCREEN SHOW END ===")

func hide_death_screen() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func _hide_main_ui() -> void:
	var ui = get_parent()
	if not ui:
		return
	for child in ui.get_children():
		if child == self or child.name == "VHSLayer":
			continue
		child.visible = false

func _on_restart_pressed() -> void:
		print("=== RESTART PRESSED ===")
		print("Tree paused before unpause: ", get_tree().paused)
		get_tree().paused = false
		print("Tree paused after unpause: ", get_tree().paused)

		# Wait one frame
		await get_tree().process_frame
		print("After await, tree paused: ", get_tree().paused)

		visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		_show_main_ui()

		print("Starting new run...")
		GameState.start_new_run()

		print("Changing scene...")
		get_tree().change_scene_to_file("res://scenes/level_1.tscn")
		print("=== RESTART PRESSED END ===")

func _on_quit_pressed() -> void:
		# CRITICAL: Unpause BEFORE hiding and changing scene
		get_tree().paused = false

		# Wait one frame to ensure unpause takes effect
		await get_tree().process_frame

		visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		get_tree().change_scene_to_file("res://scenes/start_screen.tscn")
