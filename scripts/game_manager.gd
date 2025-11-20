extends Node

@export var death_screen_path: NodePath

var death_screen: CanvasLayer
var is_in_death_sequence: bool = false


func _ready() -> void:
	if death_screen_path != NodePath():
		death_screen = get_node(death_screen_path)
		if death_screen:
			death_screen.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): # Esc
		_toggle_pause()

func _toggle_pause() -> void:
	get_tree().paused = !get_tree().paused  # flips true/false each time
	
	var pause_menu := get_tree().get_first_node_in_group("pause")
	if pause_menu:
		pause_menu.visible = get_tree().paused
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

	# Freeze gameplay
	Engine.time_scale = 0.0

	if death_screen:
		death_screen.visible = true

	# 👉 show OS cursor on death screen
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
