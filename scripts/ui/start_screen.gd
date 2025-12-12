extends CanvasLayer

@onready var start_button: Button = $StartButton
@onready var quit_button: Button = $QuitButton
@onready var fullscreen_button: Button = $FullscreenButton
@onready var kill_counter: Label = $KillCounter

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
	start_button.pressed.connect(_on_start_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	fullscreen_button.pressed.connect(_on_fullscreen_button_pressed)
	_schedule_next_spawn()
	
	print("🎬 StartScreen ready!")
	print("   Ambient scene assigned: ", ambient_slime_scene != null)
	
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

func _process(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0:
		print("⏰ Spawn timer triggered!")
		_spawn_ambient_slime()
		_schedule_next_spawn()

func _schedule_next_spawn() -> void:
	spawn_timer = randf_range(min_spawn_interval, max_spawn_interval)
	print("📅 Next spawn in: ", spawn_timer, " seconds")

func _spawn_ambient_slime() -> void:
	print("🎯 Attempting to spawn slime...")
	
	if not ambient_slime_scene:
		print("❌ No ambient_slime_scene assigned!")
		return
	
	var slime = ambient_slime_scene.instantiate()
	print("🔍 Checking slime BEFORE adding to scene:")
	print("   Slime children count: ", slime.get_child_count())
	for i in range(slime.get_child_count()):
		var child = slime.get_child(i)
		print("   Child ", i, ": ", child.name, " (", child.get_class(), ")")
	print("✅ Slime instantiated: ", slime)
	
	# Get the current scene (the actual game world, not the CanvasLayer)
	var current_scene = get_tree().current_scene
	if current_scene:
		current_scene.add_child(slime)
		slime.z_index = 5  # In front of background, behind UI text
		print("✅ Added to current_scene, z_index: 5")
	else:
		# Fallback: add to root
		get_tree().root.add_child(slime)
		slime.z_index = 5
		print("✅ Added to root, z_index: 5")
	print("🔍 Checking slime AFTER adding to scene:")
	print("   Slime children count: ", slime.get_child_count())
	for i in range(slime.get_child_count()):
		var child = slime.get_child(i)
		print("   Child ", i, ": ", child.name, " (", child.get_class(), ")")
	
	# Connect kill signal
	if slime.has_signal("slime_killed"):
		slime.slime_killed.connect(_on_menu_slime_killed)
		print("✅ Connected slime_killed signal")
	else:
		print("❌ Slime doesn't have slime_killed signal!")

func _on_menu_slime_killed() -> void:
	print("🎉 Menu slime killed! Total kills: ", menu_kills + 1)
	menu_kills += 1
	
	if menu_kills >= 5:
		kill_counter.visible = true
		print("🏆 Kill counter now visible!")
	
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