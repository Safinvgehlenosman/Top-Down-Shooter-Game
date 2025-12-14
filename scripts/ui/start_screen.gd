extends CanvasLayer

@onready var start_button: Button = get_node_or_null("StartButton")
@onready var quit_button: Button = get_node_or_null("QuitButton")
@onready var fullscreen_button: Button = get_node_or_null("FullscreenButton")
@onready var kill_counter: Label = get_node_or_null("KillCounter")
@onready var stats_button: Button = get_node_or_null("StatsButton")
@onready var version_label: Label = get_node_or_null("VersionLabel")


@export var button_paths: Array[NodePath] = []
@export var ambient_slime_scene: PackedScene
@export var min_spawn_interval: float = 0.1 # ABSOLUTE MAYHEM
@export var max_spawn_interval: float = 0.3 # ABSOLUTE MAYHEM

var spawn_timer: float = 0.0
var menu_kills: int = 0
var show_counter: bool = false
var buttons: Array[Button] = []
var focused_index: int = 0

func _ready() -> void:
	if version_label:
		var v = ProjectSettings.get_setting("application/config/version", "DEV")
		version_label.text = "Version: v%s" % str(v)

	if start_button:
		start_button.pressed.connect(_on_start_button_pressed)
	else:
		push_error("[StartScreen] Missing StartButton node at path 'StartButton'")

	if quit_button:
		quit_button.pressed.connect(_on_quit_button_pressed)
	else:
		push_error("[StartScreen] Missing QuitButton node at path 'QuitButton'")

	if fullscreen_button:
		fullscreen_button.pressed.connect(_on_fullscreen_button_pressed)
	else:
		push_error("[StartScreen] Missing FullscreenButton node at path 'FullscreenButton'")

	if stats_button:
		stats_button.pressed.connect(_on_stats_button_pressed)
	else:
		push_error("[StartScreen] Missing StatsButton node at path 'StatsButton'")

	_schedule_next_spawn()


	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if start_button:
		start_button.grab_focus()
	_setup_menu_buttons()
	
	var video_player = get_node_or_null("VideoStreamPlayer")
	if video_player:
		var video_path = "res://assets/videos/Timeline 1.webm"
		var video_stream = load(video_path)
		if video_stream:
			video_player.stream = video_stream
			video_player.play()

func _process(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_ambient_slime()
		_schedule_next_spawn()

func _schedule_next_spawn() -> void:
	spawn_timer = randf_range(min_spawn_interval, max_spawn_interval)

func _spawn_ambient_slime() -> void:
	
	if not ambient_slime_scene:
		return
	
	var slime = ambient_slime_scene.instantiate()
	for i in range(slime.get_child_count()):
		var child = slime.get_child(i)
	
	# Get the current scene (the actual game world, not the CanvasLayer)
	var current_scene = get_tree().current_scene
	if current_scene:
		current_scene.add_child(slime)
		slime.z_index = 5  # In front of background, behind UI text
	else:
		# Fallback: add to root
		get_tree().root.add_child(slime)
		slime.z_index = 5
	for i in range(slime.get_child_count()):
		var child = slime.get_child(i)
	
	# Connect kill signal
	if slime.has_signal("slime_killed"):
		slime.slime_killed.connect(_on_menu_slime_killed)


func _on_menu_slime_killed() -> void:
	menu_kills += 1
	
	if menu_kills >= 5:
		if kill_counter:
			kill_counter.visible = true
		else:
			push_error("[StartScreen] Missing KillCounter node at path 'KillCounter'")
	
	if kill_counter:
		kill_counter.text = str(menu_kills)

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

func _on_stats_button_pressed() -> void:
	# Open the StatsScreen scene
	get_tree().change_scene_to_file("res://scenes/stats_screen.tscn")
