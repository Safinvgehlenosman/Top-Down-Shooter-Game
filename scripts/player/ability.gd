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
var dash_start_pos: Vector2 = Vector2.ZERO
var dash_travel_distance: float = 0.0
var _original_collision_mask: int = 0

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

	# Invis ambush timer handling (transient damage window after invis ends)
	if "invis_ambush_active" in GameState and GameState.invis_ambush_active:
		GameState.invis_ambush_time_left = max(GameState.invis_ambush_time_left - delta, 0.0)
		if GameState.invis_ambush_time_left <= 0.0:
			GameState.invis_ambush_active = false
			print("[INVIS] ambush expired")

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
			"invis":
				_start_invis(data)


func _start_invis(data: Dictionary) -> void:
	if invis_running:
		return

	var duration: float = data.get("duration", 3.0)
	var base_cooldown: float = data.get("cooldown", 18.0)

	# Apply invis duration multipliers from GameState
	if "invis_duration_mult" in GameState:
		duration = duration * GameState.invis_duration_mult

	# Gunslinger: halves duration but prevents shooting from breaking invis
	if "invis_gunslinger_enabled" in GameState and GameState.invis_gunslinger_enabled:
		duration = duration * 0.5
		print("[INVIS] Gunslinger owned: invis duration halved -> %.2f" % duration)

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




func _start_dash(data: Dictionary) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_dir.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")

	if input_dir == Vector2.ZERO:
		input_dir = player.aim_dir

	if input_dir == Vector2.ZERO:
		return

	dash_dir = input_dir.normalized()

	# Store dash start position for phase validation
	dash_start_pos = player.global_position

	var duration: float = data.get("duration", 0.12)
	var base_distance: float = data.get("distance", 220.0)
	var distance: float = base_distance
	if "dash_distance_bonus_percent" in GameState:
		# EXPONENTIAL SCALING: dash_distance_bonus_percent is now a multiplier (starts at 1.0)
		distance = base_distance * GameState.dash_distance_bonus_percent
	dash_travel_distance = distance
	dash_speed = distance / max(duration, 0.01)

	# Grant invulnerability for the dash duration (i-frames are now standard)
	var health_comp = player.get_node_or_null("Health")
	if health_comp and health_comp.has_method("grant_spawn_invincibility"):
		health_comp.grant_spawn_invincibility(duration)
	print("[DASH] start: distance=%.1f, duration=%.3f, i-frames applied" % [distance, duration])

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

	# Phase dash: temporarily disable collisions with wall layer (bit 1)
	if GameState.dash_phase_enabled:
		_original_collision_mask = int(player.collision_mask)
		# Clear bit 0 (layer 1) so we don't collide with walls
		player.collision_mask = int(player.collision_mask) & ~1
		print("[DASH] phase enabled - wall collisions disabled")

		   # ...existing code...




func _spawn_dash_ghost() -> void:
	if DashGhostScene == null:
		return

	var ghost := DashGhostScene.instantiate()
	ghost.global_position = player.global_position
	ghost.rotation = player.rotation

	get_tree().current_scene.add_child(ghost)
	if is_instance_valid(animated_sprite):
		ghost.setup_from_player(animated_sprite)




func _end_ability() -> void:
	if is_dashing:
		is_dashing = false
		dash_speed = 0.0

		# Restore collision mask if phase was active
		if GameState.dash_phase_enabled:
			# Validate final position: step backwards along dash_dir until not colliding with wall
			var space := player.get_world_2d().direct_space_state
			var params := PhysicsPointQueryParameters2D.new()
			params.collision_mask = 1  # walls layer
			params.exclude = [player]
			var overlapping := space.intersect_point(params)
			if overlapping.size() > 0:
				var step := 8.0
				var max_steps := int(ceil(dash_travel_distance / step))
				var placed := false
				for i in range(max_steps + 1):
					var test_pos := player.global_position - dash_dir * (i * step)
					params.position = test_pos
					if space.intersect_point(params).size() == 0:
						player.global_position = test_pos
						placed = true
						break
				if not placed:
					# Snap back to start if no valid spot found
					player.global_position = dash_start_pos
					print("[DASH] phase end: no valid spot, snapped back to start")
			else:
				print("[DASH] phase end: final position valid")
			# Restore original collision mask
			player.collision_mask = _original_collision_mask
			print("[DASH] collisions restored")
		
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

		# Activate ambush damage window when invis ends
		if "invis_ambush_enabled" in GameState and GameState.invis_ambush_enabled:
			if not GameState.invis_ambush_active:
				GameState.invis_ambush_active = true
				GameState.invis_ambush_time_left = GameState.invis_ambush_duration
				print("[INVIS] Ambush activated: dur=%.2f, dmg_mult=%.2f" % [GameState.invis_ambush_duration, GameState.invis_ambush_damage_mult])

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
