extends Node

@export var death_screen_path: NodePath
@export var shop_path: NodePath
@export var exit_door_path: NodePath
@export var ui_root_path: NodePath

var game_ui: CanvasLayer

var next_scene_path: String = ""

var shop_ui: CanvasLayer
var death_screen: CanvasLayer
var is_in_death_sequence: bool = false

var exit_door: Area2D
var door_open: bool = false

@onready var restart_button: Button = $"../UI/PauseScreen/RestartButton"
@onready var death_restart_button: Button = $"../UI/DeathScreen/Content/RestartButton"


func _ready() -> void:
	# Death screen
	if death_screen_path != NodePath():
		death_screen = get_node(death_screen_path)
		if death_screen:
			death_screen.visible = false

	# Exit door
	if exit_door_path != NodePath():
		exit_door = get_node(exit_door_path)
		if exit_door:
			exit_door.visible = false

	# Shop UI
	if shop_path != NodePath():
		shop_ui = get_node(shop_path)
		if shop_ui:
			shop_ui.visible = false
	
	if ui_root_path != NodePath():
		game_ui = get_node(ui_root_path)


func _process(_delta: float) -> void:
	if not door_open and get_tree().get_nodes_in_group("enemy").is_empty():
		_open_exit_door()


func _open_exit_door() -> void:
	if door_open:
		return
	door_open = true
	if exit_door and exit_door.has_method("open"):
		exit_door.open()


# Called by the exit door when the player reaches it
func on_player_reached_exit(target_scene: String) -> void:
	if is_in_death_sequence:
		return

	next_scene_path = target_scene
	_open_shop()


func _open_shop() -> void:
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if shop_ui:
		shop_ui.visible = true
		if shop_ui.has_method("refresh_from_state"):
			shop_ui.refresh_from_state()
			
	if game_ui:
		game_ui.visible = false        # 👈 hide HUD while in shop


func load_next_level() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	if shop_ui:
		shop_ui.visible = false

	get_tree().paused = false

	if next_scene_path != "":
		get_tree().change_scene_to_file(next_scene_path)
		
	if game_ui:
		game_ui.visible = true         # 👈 show HUD again


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): # Esc
		_toggle_pause()


func _toggle_pause() -> void:
	get_tree().paused = !get_tree().paused
	
	var pause_menu := get_tree().get_first_node_in_group("pause")
	if pause_menu:
		pause_menu.visible = get_tree().paused

		if get_tree().paused:
			var first_button := pause_menu.get_node("RestartButton")
			if first_button:
				first_button.grab_focus()

	# Show mouse when paused, hide mouse when unpaused
	if get_tree().paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func on_player_died() -> void:
	if is_in_death_sequence:
		return

	is_in_death_sequence = true

	# Slow motion
	Engine.time_scale = GameConfig.death_slowmo_scale

	# Start a one-shot timer for the slowmo duration
	var t := get_tree().create_timer(GameConfig.death_slowmo_duration)
	_show_death_screen_after_timer(t)


func _show_death_screen_after_timer(timer: SceneTreeTimer) -> void:
	await timer.timeout

	Engine.time_scale = 0.0

	if death_screen:
		death_screen.visible = true
		if death_restart_button:
			death_restart_button.grab_focus()

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
