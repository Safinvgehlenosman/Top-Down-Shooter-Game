extends Node

@export var death_screen_path: NodePath
@export var shop_path: NodePath
@export var exit_door_path: NodePath
@export var ui_root_path: NodePath

@export var slime_scene: PackedScene
@export var crate_scene: PackedScene

@export var exit_door_scene: PackedScene
@export var room_scenes: Array[PackedScene] = []

var current_level: int = 1



# 70% slime, 30% crate by default. Rest = nothing.
@export_range(0.0, 1.0, 0.01) var slime_chance: float = 0.7
@export_range(0.0, 1.0, 0.01) var crate_chance: float = 0.3

@onready var room_container: Node2D = $"../RoomContainer"

var current_room: Node2D
var alive_enemies: int = 0
var door_spawn_point: Node2D = null
var current_exit_door: Node2D = null



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
	randomize()

	# Death screen
	if death_screen_path != NodePath():
		death_screen = get_node(death_screen_path)
		if death_screen:
			death_screen.visible = false

	# Shop UI
	if shop_path != NodePath():
		shop_ui = get_node(shop_path)
		if shop_ui:
			shop_ui.visible = false

	if ui_root_path != NodePath():
		game_ui = get_node(ui_root_path)

	current_level = 1
	_load_room()



func _load_room() -> void:
	# clear previous room if there was one
	if current_room and current_room.is_inside_tree():
		current_room.queue_free()

	current_room = null
	current_exit_door = null
	alive_enemies = 0
	door_spawn_point = null

	var scene_for_level := _pick_room_scene_for_level(current_level)
	if scene_for_level == null:
		push_warning("No room_scenes assigned on GameManager")
		return

	current_room = scene_for_level.instantiate()
	room_container.add_child(current_room)

	_spawn_room_content()



func _pick_room_scene_for_level(level: int) -> PackedScene:
	if room_scenes.is_empty():
		return null

	# For now, just completely random every level
	return room_scenes[randi() % room_scenes.size()]




func _spawn_room_content() -> void:
	if current_room == null:
		return

	var spawn_points = current_room.get_spawn_points()
	if spawn_points.is_empty():
		push_warning("Room has no spawn points")
		return

	# randomize order and reserve one point for door later
	spawn_points.shuffle()
	door_spawn_point = spawn_points.pop_back()

	alive_enemies = 0

	for spawn in spawn_points:
		var r := randf()

		if r <= slime_chance and slime_scene:
			# slime only
			var slime := slime_scene.instantiate()
			slime.global_position = spawn.global_position
			current_room.add_child(slime)

			alive_enemies += 1

			if slime.has_signal("died"):
				slime.died.connect(_on_enemy_died)

		elif r <= slime_chance + crate_chance and crate_scene:
			# crate only
			var crate := crate_scene.instantiate()
			crate.global_position = spawn.global_position
			current_room.add_child(crate)
		else:
			# empty, nothing spawned on this marker
			pass

	# if for some reason no enemies spawned, spawn the door right away
	if alive_enemies == 0:
		_spawn_exit_door()


func _on_enemy_died() -> void:
	alive_enemies = max(alive_enemies - 1, 0)
	if alive_enemies == 0:
		_spawn_exit_door()

func _spawn_exit_door() -> void:
	if current_exit_door != null:
		return # already spawned

	if exit_door_scene == null:
		push_warning("No exit_door_scene assigned")
		return

	if door_spawn_point == null:
		push_warning("No door_spawn_point set (not enough markers?)")
		return

	current_exit_door = exit_door_scene.instantiate()
	current_exit_door.global_position = door_spawn_point.global_position
	current_room.add_child(current_exit_door)

	# automatically play its "open" logic if it has one
	if current_exit_door.has_method("open"):
		current_exit_door.open()

	


func _process(_delta: float) -> void:
	pass


func _open_exit_door() -> void:
	if door_open:
		return
	door_open = true
	if exit_door and exit_door.has_method("open"):
		exit_door.open()


# Called by the exit door when the player reaches it
func on_player_reached_exit() -> void:
	if is_in_death_sequence:
		return

	_open_shop()



func _open_shop() -> void:
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if shop_ui:
		shop_ui.visible = true
		if shop_ui.has_method("refresh_from_state"):
			shop_ui._setup_cards()
			shop_ui.refresh_from_state()
			
	if game_ui:
		game_ui.visible = false        # 👈 hide HUD while in shop


func load_next_level() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	if shop_ui:
		shop_ui.visible = false

	get_tree().paused = false

	# increase level, then reroll a room
	current_level += 1
	_load_room()

	if game_ui:
		game_ui.visible = true         # show HUD again



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
