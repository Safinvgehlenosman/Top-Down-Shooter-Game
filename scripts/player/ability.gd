extends Node

# This node controls dash, slowmo, bubble and invis, and keeps ability timers in GameState.

const DashGhostScene := preload("res://scenes/dash_ghost.tscn")
const ShieldBubbleScene := preload("res://scenes/abilities/shield_bubble.tscn")

@onready var player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var animated_sprite: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D")
@onready var gun: Node2D = player.get_node_or_null("Gun")  # adjust path if needed

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

var active_bubble: Node2D = null

# --- Invisibility state -----------------------------------------------
var invis_running: bool = false
var original_player_modulate: Color = Color.WHITE
var original_gun_modulate: Color = Color.WHITE


func _ready() -> void:
	# Base player speed from config
	base_speed = GameConfig.player_move_speed

	# Sync timers from GameState (start_new_run sets them to 0)
	ability = GameState.ability
	ability_cooldown_left = GameState.ability_cooldown_left
	ability_active_left = GameState.ability_active_left

	# Store original colors, guarding against nulls
	if is_instance_valid(animated_sprite):
		original_player_modulate = animated_sprite.modulate
	if is_instance_valid(gun):
		original_gun_modulate = gun.modulate


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
		"bubble":
			_start_bubble(data)
		"invis":
			_start_invis(data)


func _start_invis(data: Dictionary) -> void:
	if invis_running:
		return

	var duration: float = data.get("duration", 3.0)
	var cooldown: float = data.get("cooldown", 18.0)

	ability_active_left = duration
	ability_cooldown_left = cooldown

	invis_running = true
	GameState.player_invisible = true

	# Remember current colors
	if is_instance_valid(animated_sprite):
		original_player_modulate = animated_sprite.modulate
	if is_instance_valid(gun):
		original_gun_modulate = gun.modulate

	# Fade both player + gun
	var cloak_color := Color(1, 1, 1, 0.25)
	if is_instance_valid(animated_sprite):
		animated_sprite.modulate = cloak_color
	if is_instance_valid(gun):
		gun.modulate = cloak_color

	# Optional: clear current aggro immediately
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is Node and "aggro" in enemy:
			enemy.aggro = false



func _start_bubble(data: Dictionary) -> void:
	if ShieldBubbleScene == null:
		return

	var duration: float = data.get("duration", 3.0)
	var cooldown: float = data.get("cooldown", 12.0)

	ability_active_left = duration
	ability_cooldown_left = cooldown

	var bubble := ShieldBubbleScene.instantiate()
	bubble.global_position = player.global_position

	if bubble.has_method("setup"):
		bubble.setup(duration)

	get_tree().current_scene.add_child(bubble)
	active_bubble = bubble


func _start_dash(data: Dictionary) -> void:
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
	if is_instance_valid(animated_sprite):
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

	Engine.time_scale = factor
	player.speed = base_speed / max(factor, 0.01)


func _end_ability() -> void:
	if is_dashing:
		is_dashing = false
		dash_speed = 0.0

	if slowmo_running:
		slowmo_running = false
		Engine.time_scale = 1.0
		player.speed = base_speed

	if invis_running:
		invis_running = false
		GameState.player_invisible = false

		if is_instance_valid(animated_sprite):
			animated_sprite.modulate = original_player_modulate
		if is_instance_valid(gun):
			gun.modulate = original_gun_modulate

	ability_active_left = 0.0



func get_dash_velocity() -> Vector2:
	if is_dashing:
		return dash_dir * dash_speed
	return Vector2.ZERO
