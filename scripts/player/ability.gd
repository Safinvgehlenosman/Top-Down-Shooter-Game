# Fixed ability.gd - Stores timers in GameState so UI can read them!

extends Node

const DashGhostScene := preload("res://scenes/dash_ghost.tscn")
const ShieldBubbleScene := preload("res://scenes/abilities/shield_bubble.tscn")
const GrenadeBulletScene := preload("res://scenes/bullets/grenade_bullet.tscn")

@onready var player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var animated_sprite: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D")
@onready var gun: Node2D = player.get_node_or_null("Gun")

# ✅ REMOVED: Local timer variables (these were the problem!)
# var ability_cooldown_left: float = 0.0  # OLD - Don't store locally!
# var ability_active_left: float = 0.0

var is_dashing: bool = false
var dash_dir: Vector2 = Vector2.ZERO
var dash_speed: float = 0.0

var slowmo_running: bool = false
var base_speed: float = 0.0

var dash_ghost_interval: float = 0.03
var dash_ghost_timer: float = 0.0

var active_bubble: Node2D = null

var invis_running: bool = false
var original_player_modulate: Color = Color.WHITE
var original_gun_modulate: Color = Color.WHITE

const AbilityType = GameState.AbilityType


func _ready() -> void:
	base_speed = GameConfig.player_move_speed
	
	# ✅ Initialize GameState timers if they don't exist
	if not "ability_cooldown_left" in GameState:
		GameState.ability_cooldown_left = 0.0
	if not "ability_active_left" in GameState:
		GameState.ability_active_left = 0.0
	
	# Store original colors
	if is_instance_valid(animated_sprite):
		original_player_modulate = animated_sprite.modulate
	if is_instance_valid(gun):
		original_gun_modulate = gun.modulate


func _physics_process(delta: float) -> void:
	# ✅ Update timers in GameState (so UI can read them!)
	if GameState.ability_cooldown_left > 0.0:
		GameState.ability_cooldown_left = max(GameState.ability_cooldown_left - delta, 0.0)

	if GameState.ability_active_left > 0.0:
		GameState.ability_active_left = max(GameState.ability_active_left - delta, 0.0)
		if GameState.ability_active_left <= 0.0:
			_end_ability()

	# Dash ghosts
	if is_dashing:
		dash_ghost_timer -= delta
		if dash_ghost_timer <= 0.0:
			_spawn_dash_ghost()
			dash_ghost_timer = dash_ghost_interval

	# Handle input each frame
	_process_ability_input()


func sync_from_gamestate() -> void:
	# When ability type changes, reset timers
	GameState.ability_cooldown_left = 0.0
	GameState.ability_active_left = 0.0


func _process_ability_input() -> void:
	var ability = GameState.ability

	if ability == AbilityType.NONE:
		return

	# ✅ Check cooldown from GameState
	if Input.is_action_just_pressed("ability") \
			and GameState.ability_cooldown_left <= 0.0 \
			and GameState.ability_active_left <= 0.0:
		_start_ability()


func _start_ability() -> void:
	var ability = GameState.ability
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
	var base_cooldown: float = data.get("cooldown", 18.0)

	# Apply invis duration bonuses (percent + flat seconds)
	var percent_bonus: float = 0.0
	if "invis_duration_bonus_percent" in GameState:
		percent_bonus = GameState.invis_duration_bonus_percent

	duration = duration * (1.0 + percent_bonus)

	# Apply cooldown multiplier from upgrades
	var multiplier: float = 1.0
	if "ability_cooldown_mult" in GameState:
		multiplier = GameState.ability_cooldown_mult
	var actual_cooldown: float = base_cooldown * multiplier

	# ✅ Store in GameState

	GameState.ability_active_left = duration
	GameState.ability_cooldown_left = actual_cooldown

	invis_running = true
	GameState.set_player_invisible(true)

	if is_instance_valid(animated_sprite):
		original_player_modulate = animated_sprite.modulate
	if is_instance_valid(gun):
		original_gun_modulate = gun.modulate

	var cloak_color := Color(1, 1, 1, 0.25)
	if is_instance_valid(animated_sprite):
		animated_sprite.modulate = cloak_color
	if is_instance_valid(gun):
		gun.modulate = cloak_color

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is Node and "aggro" in enemy:
			enemy.aggro = false


func _start_bubble(data: Dictionary) -> void:
	if ShieldBubbleScene == null:
		return

	# Base duration from config
	var base_duration: float = data.get("duration", 3.0)

	# Apply bubble duration bonuses: multiplicative percent + additive seconds
	var percent_bonus: float = 0.0
	if "bubble_duration_bonus_percent" in GameState:
		percent_bonus = GameState.bubble_duration_bonus_percent
	var flat_bonus: float = 0.0
	if "bubble_duration_bonus_seconds" in GameState:
		flat_bonus = GameState.bubble_duration_bonus_seconds
	# legacy compatibility: include older field if present
	if "ability_bubble_duration_bonus" in GameState:
		flat_bonus += GameState.ability_bubble_duration_bonus

	var duration: float = base_duration * (1.0 + percent_bonus) + flat_bonus

	var base_cooldown: float = data.get("cooldown", 12.0)

	# ✅ Apply cooldown multiplier
	var multiplier: float = 1.0
	if "ability_cooldown_mult" in GameState:
		multiplier = GameState.ability_cooldown_mult
	var actual_cooldown: float = base_cooldown * multiplier

	# ✅ Store in GameState
	GameState.ability_active_left = duration
	GameState.ability_cooldown_left = actual_cooldown

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
	var base_distance: float = data.get("distance", 220.0)
	var distance: float = base_distance
	if "dash_distance_bonus_percent" in GameState:
		# EXPONENTIAL SCALING: dash_distance_bonus_percent is now a multiplier (starts at 1.0)
		distance = base_distance * GameState.dash_distance_bonus_percent
	dash_speed = distance / max(duration, 0.01)

	var base_cooldown: float = data.get("cooldown", 5.0)

	# ✅ Apply cooldown multiplier
	var multiplier: float = 1.0
	if "ability_cooldown_mult" in GameState:
		multiplier = GameState.ability_cooldown_mult
	var actual_cooldown: float = base_cooldown * multiplier

	# Store in GameState
	GameState.ability_active_left = duration
	GameState.ability_cooldown_left = actual_cooldown

	is_dashing = true
	dash_ghost_timer = 0.0

	# ⭐ DASH + GRENADE SYNERGY: Spawn grenades when dashing
	if GameState.has_dash_grenade_synergy:
		_spawn_dash_grenades()


func _spawn_dash_grenades() -> void:
	"""Spawn grenades in a line along the dash direction (synergy effect)."""
	if GrenadeBulletScene == null:
		return
	
	var grenade_count: int = GameState.dash_grenade_synergy_grenades
	if grenade_count <= 0:
		return
	
	# Get grenade data from GameState
	var grenade_data: Dictionary = GameState.ALT_WEAPON_DATA.get(GameState.AltWeaponType.GRENADE, {})
	var bullet_speed: float = grenade_data.get("bullet_speed", 500.0)
	var damage: float = grenade_data.get("damage", 40.0)
	var explosion_radius: float = grenade_data.get("explosion_radius", 80.0)
	
	# Spawn grenades in a line along the dash direction
	var spacing: float = 40.0  # Distance between grenades
	var start_offset: float = -((grenade_count - 1) * spacing) / 2.0  # Center the line
	
	for i in range(grenade_count):
		var offset := start_offset + (i * spacing)
		var spawn_pos := player.global_position + (dash_dir * offset)
		
		var grenade = GrenadeBulletScene.instantiate()
		grenade.global_position = spawn_pos
		grenade.direction = dash_dir
		grenade.speed = bullet_speed * 0.5  # Same multiplier as gun uses
		grenade.damage = damage
		
		if "explosion_radius" in grenade:
			grenade.explosion_radius = explosion_radius
		
		get_tree().current_scene.add_child(grenade)


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

	var base_duration: float = data.get("duration", 3.0)
	var base_cooldown: float = data.get("cooldown", 30.0)
	var factor: float = data.get("factor", 0.3)
	# Apply additional slowmo time from upgrades (flat seconds)
	var duration: float = base_duration
	if "slowmo_time_bonus_seconds" in GameState:
		duration += GameState.slowmo_time_bonus_seconds

	# Apply cooldown multiplier
	var multiplier: float = 1.0
	if "ability_cooldown_mult" in GameState:
		multiplier = GameState.ability_cooldown_mult
	var actual_cooldown: float = base_cooldown * multiplier

	# Store in GameState
	GameState.ability_active_left = duration
	GameState.ability_cooldown_left = actual_cooldown

	slowmo_running = true

	# Don't use Engine.time_scale - slow enemies individually instead
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if enemy.has_method("set_time_scale"):
			enemy.set_time_scale(factor)
	
	# ⭐ SYNERGY 4: Fire turret 360° burst when slowmo activates
	if GameState.has_turret_slowmo_sprinkler_synergy:
		_fire_turret_sprinkler_burst()


func _end_ability() -> void:
	if is_dashing:
		is_dashing = false
		dash_speed = 0.0
		
		# ⭐ SYNERGY 5: Auto-fire shotgun on dash end (moved after is_dashing reset)
		if GameState.has_shotgun_dash_autofire_synergy and GameState.alt_weapon == GameState.AltWeaponType.SHOTGUN:
			_auto_fire_shotgun_on_dash_end()

	if slowmo_running:
		slowmo_running = false
		# Restore enemy time scales
		var enemies = get_tree().get_nodes_in_group("enemy")
		for enemy in enemies:
			if enemy.has_method("set_time_scale"):
				enemy.set_time_scale(1.0)

	if invis_running:
		invis_running = false
		GameState.set_player_invisible(false)

		if is_instance_valid(animated_sprite):
			animated_sprite.modulate = original_player_modulate
		if is_instance_valid(gun):
			gun.modulate = original_gun_modulate

	GameState.ability_active_left = 0.0


# ==============================
# SYNERGY HELPER FUNCTIONS
# ==============================

func _auto_fire_shotgun_on_dash_end() -> void:
	"""SYNERGY 5: Auto-fire shotgun in dash direction when dash ends."""

	if not is_instance_valid(gun):

		return
	
	var shotgun_data: Dictionary = GameState.ALT_WEAPON_DATA.get(GameState.AltWeaponType.SHOTGUN, {})
	if shotgun_data.is_empty():

		return
	
	# Fire shotgun manually using stored dash direction
	var bullet_scene: PackedScene = shotgun_data.get("bullet_scene")
	if bullet_scene == null:

		return
	
	var pellets: int = shotgun_data.get("pellets", 8)
	var spread_deg: float = shotgun_data.get("spread_degrees", 30.0)
	var spread_rad: float = deg_to_rad(spread_deg)
	var bullet_speed: float = shotgun_data.get("bullet_speed", 500.0)
	var damage: float = shotgun_data.get("damage", 20.0)
	
	var muzzle_pos := player.global_position + dash_dir * 16.0  # Offset from player

	for i in range(pellets):
		var angle := randf_range(-spread_rad, spread_rad)
		var dir := dash_dir.rotated(angle)
		
		var bullet = bullet_scene.instantiate()
		bullet.global_position = muzzle_pos
		bullet.direction = dir
		bullet.speed = bullet_speed
		bullet.damage = roundi(damage)
		
		get_tree().current_scene.add_child(bullet)


func _fire_turret_sprinkler_burst() -> void:
	"""SYNERGY 4: Fire 360° burst from turret when slowmo activates."""

	# Find the player's active turret
	var turrets = get_tree().get_nodes_in_group("turret")
	if turrets.is_empty():

		return
	
	for turret in turrets:
		if turret.has_method("do_sprinkler_burst"):
			turret.do_sprinkler_burst()


func get_dash_velocity() -> Vector2:
	if is_dashing:
		return dash_dir * dash_speed
	return Vector2.ZERO
