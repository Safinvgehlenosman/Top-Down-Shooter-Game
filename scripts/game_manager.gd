extends Node

@export var death_screen_path: NodePath

var death_screen: CanvasLayer
var is_in_death_sequence: bool = false

@onready var restart_button: Button = $"../UI/PauseScreen/RestartButton"
@onready var death_restart_button: Button = $"../UI/DeathScreen/Content/RestartButton"

@export var exit_door_path: NodePath
var exit_door: Area2D
var door_open: bool = false


func _process(_delta: float) -> void:
	if not door_open and get_tree().get_nodes_in_group("enemy").is_empty():
		_open_exit_door()


func _open_exit_door() -> void:
	if door_open:
		return
	door_open = true
	if exit_door and exit_door.has_method("open"):
		exit_door.open()




func _ready() -> void:
	if death_screen_path != NodePath():
		death_screen = get_node(death_screen_path)
		if death_screen:
			death_screen.visible = false
	
	if exit_door_path != NodePath():
		exit_door = get_node(exit_door_path)
		if exit_door:
			exit_door.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): # Esc
		_toggle_pause()

func _toggle_pause() -> void:
	get_tree().paused = !get_tree().paused
	
	var pause_menu := get_tree().get_first_node_in_group("pause")
	if pause_menu:
		pause_menu.visible = get_tree().paused

		if get_tree().paused:
			var first_button := pause_menu.get_node("RestartButton") # adjust path
			if first_button:
				first_button.grab_focus()

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


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
