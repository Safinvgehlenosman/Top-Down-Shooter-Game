extends Node

# This node controls dash + slowmo, and keeps ability timers in GameState.

const DashGhostScene := preload("res://scenes/dash_ghost.tscn")

@onready var player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var animated_sprite: AnimatedSprite2D = player.animated_sprite

var ability: int = GameState.ability

var ability_cooldown_left: float = 0.0
var ability_active_left: float = 0.0

var is_dashing: bool = false
var dash_dir: Vector2 = Vector2.ZERO
var dash_speed: float = 0.0

var slowmo_running: bool = false
var base_speed: float = 0.0

var dash_ghost_interval: float = 0.03
var dash_ghost_timer: float = 0.0


func _ready() -> void:
	# Base player speed from config
	base_speed = GameConfig.player_move_speed

	# Sync timers from GameState (start_new_run sets them to 0)
	ability = GameState.ability
	ability_cooldown_left = GameState.ability_cooldown_left
	ability_active_left = GameState.ability_active_left


func _physics_process(delta: float) -> void:
	# Update timers
	if ability_cooldown_left > 0.0:
		ability_cooldown_left = max(ability_cooldown_left - delta, 0.0)

	if ability_active_left > 0.0:
		ability_active_left = max(ability_active_left - delta, 0.0)
		if ability_active_left <= 0.0:
			_end_ability()

	# Write back so UI can read directly from GameState
	GameState.ability_cooldown_left = ability_cooldown_left
	GameState.ability_active_left = ability_active_left

	# Dash ghosts
	if is_dashing:
		dash_ghost_timer -= delta
		if dash_ghost_timer <= 0.0:
			_spawn_dash_ghost()
			dash_ghost_timer = dash_ghost_interval

	# Handle input each frame
	_process_ability_input()


func sync_from_gamestate() -> void:
	# If upgrades change ability or ability data, we can resync here.
	ability = GameState.ability


func _process_ability_input() -> void:
	ability = GameState.ability

	if ability == GameState.ABILITY_NONE:
		return

	if Input.is_action_just_pressed("ability") \
			and ability_cooldown_left <= 0.0 \
			and ability_active_left <= 0.0:
		_start_ability()


func _start_ability() -> void:
	var data: Dictionary = GameState.ABILITY_DATA.get(ability, {})
	if data.is_empty():
		return

	var ability_type: String = data.get("type", "")
	match ability_type:
		"dash":
			_start_dash(data)
		"slowmo":
			_start_slowmo(data)


func _start_dash(data: Dictionary) -> void:
	# Direction from movement or fallback to aim_dir
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_dir.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")

	if input_dir == Vector2.ZERO:
		input_dir = player.aim_dir

	if input_dir == Vector2.ZERO:
		return

	dash_dir = input_dir.normalized()

	var duration: float = data.get("duration", 0.12)
	var distance: float = data.get("distance", 220.0)
	dash_speed = distance / max(duration, 0.01)

	ability_active_left = duration
	ability_cooldown_left = data.get("cooldown", 5.0)

	is_dashing = true
	dash_ghost_timer = 0.0


func _spawn_dash_ghost() -> void:
	if DashGhostScene == null:
		return

	var ghost := DashGhostScene.instantiate()
	ghost.global_position = player.global_position
	ghost.rotation = player.rotation

	get_tree().current_scene.add_child(ghost)
	ghost.setup_from_player(animated_sprite)


func _start_slowmo(data: Dictionary) -> void:
	if slowmo_running:
		return

	var duration: float = data.get("duration", 3.0)
	var cooldown: float = data.get("cooldown", 30.0)
	var factor: float = data.get("factor", 0.3)

	ability_active_left = duration
	ability_cooldown_left = cooldown

	slowmo_running = true

	# Slow down the world…
	Engine.time_scale = factor
	# …but keep player speed feeling normal
	player.speed = base_speed / max(factor, 0.01)


func _end_ability() -> void:
	if is_dashing:
		is_dashing = false
		dash_speed = 0.0

	if slowmo_running:
		slowmo_running = false
		Engine.time_scale = 1.0
		player.speed = base_speed

	ability_active_left = 0.0


# --- Helpers for Player movement --------------------------------------


func get_dash_velocity() -> Vector2:
	if is_dashing:
		return dash_dir * dash_speed
	return Vector2.ZERO
