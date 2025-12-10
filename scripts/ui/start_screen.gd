extends CanvasLayer


# Updated node paths to match new structure
@onready var start_button: Button = $StartButton
@onready var quit_button: Button = $QuitButton
@onready var fullscreen_button: Button = $FullscreenButton

@export var button_paths: Array[NodePath] = []


var buttons: Array[Button] = []
var focused_index: int = 0


func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	fullscreen_button.pressed.connect(_on_fullscreen_button_pressed)

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	start_button.grab_focus()
	_setup_menu_buttons()

	var video_player = get_node_or_null("VideoStreamPlayer")
	if video_player:
		var video_path = "res://assets/videos/Timeline 1.webm"
		var video_stream = load(video_path)
		if video_stream:
			video_player.stream = video_stream
			video_player.play()



func _setup_menu_buttons() -> void:
	buttons.clear()

	for path in button_paths:
		var btn := get_node_or_null(path)
		if btn and btn is Button:
			buttons.append(btn)

	if buttons.is_empty():
		return

	for b in buttons:
		b.focus_mode = Control.FOCUS_ALL

	focused_index = 0
	buttons[focused_index].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if buttons.is_empty():
		return

	if event.is_action_pressed("ui_down"):
		_move_focus(1)
	elif event.is_action_pressed("ui_up"):
		_move_focus(-1)


func _move_focus(direction: int) -> void:
	if buttons.is_empty():
		return

	focused_index = (focused_index + direction + buttons.size()) % buttons.size()
	buttons[focused_index].grab_focus()


func _on_start_button_pressed() -> void:
	GameState.start_new_run()
	get_tree().change_scene_to_file("res://scenes/level_1.tscn")


func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _on_fullscreen_button_pressed() -> void:
	var w := get_window()
	if w.mode == Window.MODE_FULLSCREEN:
		w.mode = Window.MODE_WINDOWED
	else:
		w.mode = Window.MODE_FULLSCREEN
