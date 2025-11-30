extends CharacterBody2D

signal died

# Core stats (tweak per slime in Inspector)
@export var speed: float = GameConfig.slime_move_speed
@export var max_health: int = GameConfig.slime_max_health
@export var heart_drop_chance: float = GameConfig.slime_heart_drop_chance
@export var contact_damage: int = GameConfig.slime_contact_damage
@export var contact_interval: float = 0.5   # seconds between hits while touching
var contact_timer: float = 0.0

@onready var hitbox: Area2D = $Hitbox
@export var vision_radius: float = 250.0
@onready var hp_fill: TextureProgressBar = $HPBar/HPFill
@onready var health_component: Node = $Health

# Raycast references for obstacle avoidance
@onready var raycast_forward: RayCast2D = $RayCastForward
@onready var raycast_left: RayCast2D = $RayCastLeft
@onready var raycast_right: RayCast2D = $RayCastRight

# Obstacle avoidance settings
@export var raycast_length: float = 50.0
@export var obstacle_avoidance_strength: float = 0.3
@export var personal_space_distance: float = 20.0  # Min distance from player/walls
@export var enable_flanking: bool = true
@export var flank_speed_multiplier: float = 0.5  # Speed while flanking (reduced from 0.6)
@export var sprint_when_losing_los: bool = true
@export var sprint_multiplier: float = 1.3

# Pack hunting behaviors
@export var enable_pack_hunting: bool = true
@export var pack_detection_radius: float = 150.0
@export var pack_speed_bonus: float = 1.20  # 20% speed boost when in pack
@export var min_pack_size: int = 2  # How many allies needed for pack bonus

# Ambush detection
@export var enable_ambush_detection: bool = true
@export var ambush_speed_multiplier: float = 1.25  # 25% faster when player trapped (reduced from 40%)
@export var ambush_aggro_boost: float = 1.3  # Wider aggro range

# Tactical retreat
@export var enable_tactical_retreat: bool = true
@export var retreat_hp_threshold: float = 0.5  # Retreat below 50% HP
@export var retreat_if_alone: bool = true  # Only retreat if no allies nearby
@export var retreat_speed_multiplier: float = 1.25  # Move 25% faster when retreating

# Pack spreading (surround player)
@export var enable_pack_spreading: bool = true
@export var spread_radius: float = 80.0  # How far from player to position
@export var min_pack_size_for_spread: int = 3  # Need 3+ for spreading

# How much we grow per level
@export var health_growth_per_level: float = 0.05
@export var damage_growth_per_level: float = 0.05

# Movement / behaviour tuning
@export var separation_radius: float = 24.0      # how close slimes can get to each other
@export var separation_strength: float = 0.3     # how strongly they push away
@export var strafe_amount: float = 0.3           # sideways movement while chasing
@export var aggro_radius: float = 180.0          # player distance that triggers aggro
@export var wander_speed: float = 40.0           # speed while idle wandering
@export var wander_change_interval: float = 1.5  # how often wander direction changes (seconds)

# NEW: de-aggro behaviour
@export var deaggro_delay: float = 1.2           # how long they keep searching after losing LOS
@export var last_seen_search_speed: float = 1.0  # speed multiplier while moving to last seen pos
var last_seen_player_pos: Vector2 = Vector2.ZERO
var lost_sight_timer: float = 0.0

# Stuck detection
@export var stuck_detection_enabled: bool = true
@export var stuck_time_threshold: float = 2.0    # seconds of barely moving to be "stuck"
@export var stuck_velocity_threshold: float = 10.0  # pixels/sec to be considered stuck
var stuck_timer: float = 0.0
var last_position: Vector2 = Vector2.ZERO
var unstuck_angle_offset: float = 0.0  # radians to offset approach when stuck
var my_flanking_offset: float = 0.0  # Persistent random offset for unique flanking angles

# Pack member cache (to avoid repeated tree searches)
var pack_members_cache: Array = []
var pack_cache_timer: float = 0.0
var pack_cache_interval: float = 0.5  # refresh every 0.5 seconds

@onready var sfx_land: AudioStreamPlayer2D = $SFX_Land
@onready var sfx_hurt: AudioStreamPlayer2D = $SFX_Hurt
@onready var sfx_death: AudioStreamPlayer2D = $SFX_Death

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_light: PointLight2D = $PointLight2D

@export var CoinScene: PackedScene
@export var HeartScene: PackedScene

var last_anim: StringName = ""
var last_frame: int = -1

# Animation jitter so multiple slimes don't sync perfectly
@export var animation_frame_jitter_max: int = 6
@export var animation_speed_jitter_percent: float = 0.12

# Landing sound tweaks to avoid many identical high-pitched hits
@export var land_sound_play_chance: float = 0.75
@export var land_sound_min_interval: float = 0.12  # seconds per-slime cooldown
@export var land_sound_pitch_jitter: float = 0.12  # +/- pitch variation
@export var land_sound_volume_db_min: float = -6.0
@export var land_sound_volume_db_max: float = -2.0
var _land_sound_cd: float = 0.0

# Internal state
var player: Node2D
var base_modulate: Color
var original_light_color: Color

# Hit flash timers
@export var hit_flash_time: float = 0.1
var hit_flash_timer: float = 0.0

@export var hit_light_flash_time: float = 0.1
var hit_light_timer: float = 0.0

# Aggro / wander state
var aggro: bool = false
var wander_timer: float = 0.0
var wander_direction: Vector2 = Vector2.ZERO

var is_dead: bool = false

# Knockback
@export var knockback_friction: float = 600.0
var knockback_velocity: Vector2 = Vector2.ZERO

# Time scale (for bullet time ability)
var time_scale: float = 1.0
var base_move_speed: float = 0.0
var base_wander_speed: float = 0.0


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D
	last_position = global_position  # Initialize stuck detection

	base_modulate = animated_sprite.modulate

	if hit_light:
		original_light_color = hit_light.color

	# Store base speeds before any multipliers
	base_move_speed = speed
	base_wander_speed = wander_speed
	
	# Random persistent flanking offset for unique pack behavior
	my_flanking_offset = randf_range(-PI/6, PI/6)

	# ❌ REMOVED - Smart AI makes them harder now, don't need raw stat buffs
	# Old approach: Dumb AI + 1.2x speed/health = artificially harder
	# New approach: Smart AI + balanced stats = naturally harder
	# speed *= 1.2
	# wander_speed *= 1.2
	# max_health = int(round(max_health * 1.2))

	# Apply level-based speed scaling (1.0x -> 2.0x over 50 levels)
	_apply_speed_scaling()

	# --- Health component wiring ---
	if health_component:
		health_component.max_health = max_health
		health_component.health     = max_health
		health_component.invincible_time = 0.0

		health_component.connect("damaged", Callable(self, "_on_health_damaged"))
		health_component.connect("died",    Callable(self, "_on_health_died"))

		_update_hp_bar()

	# De-sync animations between instances: pick a random start frame and slight speed jitter
	if animated_sprite:
		# Play first so animation resource is available
		animated_sprite.play("moving")

		# If sprite frames resource has the animation, clamp jitter to animation length
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("moving"):
			var fc = int(animated_sprite.sprite_frames.get_frame_count("moving"))
			if fc > 0:
				var max_j = int(min(fc - 1, animation_frame_jitter_max))
				var start_frame = int(randi() % (max_j + 1))
				animated_sprite.frame = start_frame

		# Small random speed variation so they don't animate in lockstep
		var speed_mult := 1.0 + randf_range(-animation_speed_jitter_percent, animation_speed_jitter_percent)
		# AnimatedSprite2D has `speed_scale` in Godot 4 — set it.
		animated_sprite.speed_scale = speed_mult


func apply_level(level: int) -> void:
	var level_offset = max(level - 1, 0)
	var final_max_hp := max_health

	if level_offset > 0:
		if health_growth_per_level != 0.0:
			var hp_mult = 1.0 + health_growth_per_level * level_offset
			final_max_hp = int(round(max_health * hp_mult))

		if damage_growth_per_level != 0.0:
			var dmg_mult = 1.0 + damage_growth_per_level * level_offset
			contact_damage = int(round(contact_damage * dmg_mult))

	max_health = final_max_hp
	if health_component:
		health_component.max_health = final_max_hp
		health_component.health     = final_max_hp


func _physics_process(delta: float) -> void:
	# Apply time_scale to delta for bullet time effect
	var scaled_delta = delta * time_scale

	# contact damage timer
	if contact_timer > 0.0:
		contact_timer -= scaled_delta
	if contact_timer <= 0.0:
		_try_contact_damage()

	# decrement per-instance land-sound cooldown
	if _land_sound_cd > 0.0:
		_land_sound_cd = max(0.0, _land_sound_cd - scaled_delta)

	if is_dead:
		_update_hit_feedback(scaled_delta)
		return

	_update_hit_feedback(scaled_delta)
	_update_behavior_visuals()
	
	_update_ai(scaled_delta)
	_update_animation_sfx()

	# decay knockback over time
	if knockback_velocity.length() > 0.0:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_friction * scaled_delta)

	if velocity.x < -1:
		animated_sprite.flip_h = false
	elif velocity.x > 1:
		animated_sprite.flip_h = true

	# Scale velocity for move_and_slide (which uses raw delta)
	# We need to compensate because move_and_slide uses the engine's delta,
	# but our velocity was calculated with scaled_delta
	velocity *= time_scale

	move_and_slide()


func _try_contact_damage() -> void:
	if hitbox == null:
		return

	for body in hitbox.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(contact_damage)
			contact_timer = contact_interval
			break


# --- AI / MOVEMENT --------------------------------------------------

func _update_ai(delta: float) -> void:
	if not player:
		return
	
	# Update stuck detection
	if stuck_detection_enabled:
		_update_stuck_detection(delta)
	
	# Update pack cache periodically
	pack_cache_timer -= delta
	if pack_cache_timer <= 0.0:
		pack_cache_timer = pack_cache_interval
		_refresh_pack_cache()
	
	# Local speed variable - never modify base_move_speed or speed directly
	var effective_speed: float = base_move_speed
	
	# ------------------------------------------------------
	# PLAYER INVISIBLE → wander mode
	# ------------------------------------------------------
	if GameState.player_invisible:
		aggro = false
		stuck_timer = 0.0
		
		wander_timer -= delta
		if wander_timer <= 0.0:
			wander_timer = wander_change_interval
			wander_direction = Vector2(
				randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)
			).normalized()
		
		velocity = wander_direction * wander_speed
	
	# ------------------------------------------------------
	# NORMAL BEHAVIOUR (player visible)
	# ------------------------------------------------------
	else:
		var to_player: Vector2 = player.global_position - global_position
		var distance: float = to_player.length()
		var can_see := _can_see_player()
		
		# TACTICAL RETREAT - Run away if low HP and alone
		if _should_retreat():
			aggro = false
			stuck_timer = 0.0
			effective_speed *= retreat_speed_multiplier
			
			var away_from_player: Vector2 = (global_position - player.global_position).normalized()
			velocity = away_from_player * effective_speed
		
		# NORMAL AI
		else:
			# CHECK FOR AMBUSH OPPORTUNITY
			var player_cornered: bool = _is_player_cornered()
			
			# Modify aggro radius based on ambush
			var effective_aggro_radius: float = aggro_radius
			if player_cornered:
				effective_aggro_radius *= ambush_aggro_boost
			
			# Aggro logic with improved persistence
			if not aggro and distance <= effective_aggro_radius and can_see:
				aggro = true
				last_seen_player_pos = player.global_position
				lost_sight_timer = 0.0
			
			# Maintain aggro
			if aggro:
				if can_see:
					last_seen_player_pos = player.global_position
					lost_sight_timer = 0.0
				else:
					lost_sight_timer += delta
				
				# De-aggro conditions
				var deaggro_distance = 270.0
				if distance > deaggro_distance or lost_sight_timer >= deaggro_delay:
					aggro = false
			
			# Apply speed bonuses to effective_speed
			if player_cornered and aggro:
				effective_speed *= ambush_speed_multiplier
			
			# Movement decisions
			if aggro:
				if can_see:
					# PACK HUNTING BONUS
					var pack_status: Dictionary = _get_pack_status()
					
					if pack_status.in_pack:
						effective_speed *= pack_speed_bonus
					
					# DIRECTIONAL FLANKING - Attack from spread angles, always advancing
					if pack_status.pack_size >= min_pack_size_for_spread:
						var slime_id = get_instance_id()
						var angle_variant = (int(slime_id) % 5) - 2  # -2, -1, 0, 1, 2
						
						# Calculate approach angle with spread
						var base_angle = to_player.angle()
						var spread_angle = deg_to_rad(25.0)  # 25 degrees spread
						var my_angle = base_angle + (angle_variant * spread_angle)
						
						# ALWAYS move toward player from this angle
						var approach_dir = Vector2.from_angle(my_angle)
						velocity = approach_dir * effective_speed
						
						# If very close, switch to direct pursuit
						if to_player.length() < 40.0:
							velocity = to_player.normalized() * effective_speed * 1.3  # 30% faster when close
					else:
						# Solo or small pack - direct chase
						var forward: Vector2 = to_player.normalized()
						
						# Apply stuck offset if needed
						if abs(unstuck_angle_offset) > 0.01:
							forward = forward.rotated(unstuck_angle_offset)
						
						velocity = forward * effective_speed
				
				elif lost_sight_timer < deaggro_delay:
					# Search last seen position
					var to_last_seen := last_seen_player_pos - global_position
					if to_last_seen.length() > 4.0:
						velocity = to_last_seen.normalized() * effective_speed * last_seen_search_speed
					else:
						velocity = Vector2.ZERO
			else:
				# Wander
				stuck_timer = 0.0
				
				wander_timer -= delta
				if wander_timer <= 0.0:
					wander_timer = wander_change_interval
					wander_direction = Vector2(
						randf_range(-1.0, 1.0),
						randf_range(-1.0, 1.0)
					).normalized()
				
				velocity = wander_direction * wander_speed
	
	# ------------------------------------------------------
	# SHARED LOGIC (applies to all states)
	# ------------------------------------------------------
	
	# Prevent getting stuck inside player
	if player:
		var to_player_vec = player.global_position - global_position
		var dist_to_player = to_player_vec.length()
		
		if dist_to_player < personal_space_distance and dist_to_player > 0:
			var push_away = -to_player_vec.normalized()
			var push_strength = (1.0 - dist_to_player / personal_space_distance)
			velocity += push_away * base_move_speed * push_strength * 0.5
	
	# Raycast-based obstacle avoidance (reduced during flanking)
	var obstacle_avoid: Vector2 = _get_raycast_avoidance(velocity)
	var pack_status_avoid: Dictionary = _get_pack_status()
	if pack_status_avoid.in_pack and pack_status_avoid.pack_size >= 3:
		velocity += obstacle_avoid * 0.3  # Reduced during flanking
	else:
		velocity += obstacle_avoid
	
	# Separation force
	var separation: Vector2 = Vector2.ZERO
	var nearby_enemies: Array = pack_members_cache if pack_members_cache.size() > 0 else get_tree().get_nodes_in_group("enemy")
	
	# Get pack status for separation calculations
	var pack_status_sep: Dictionary = _get_pack_status()
	
	# Wider personal space during pack flanking to prevent stacking
	var effective_separation_radius: float = separation_radius
	if pack_status_sep.in_pack and pack_status_sep.pack_size >= 3:
		effective_separation_radius = separation_radius * 1.5  # 36 units instead of 24
	
	for other in nearby_enemies:
		if other == self or not is_instance_valid(other):
			continue
		
		var other_node := other as Node2D
		if other_node == null:
			continue
		
		var diff: Vector2 = global_position - other_node.global_position
		var dist: float = diff.length()
		
		if dist > 0.0 and dist < effective_separation_radius:
			separation += diff.normalized() * (1.0 - dist / effective_separation_radius)
	
	# Separation strength - stronger during flanking to maintain spread
	var sep_strength: float
	if pack_status_sep.in_pack and pack_status_sep.pack_size >= 3:
		sep_strength = separation_strength * 0.6  # Strong enough to maintain spread
	elif aggro:
		sep_strength = separation_strength * 0.2  # Weak during aggro
	else:
		sep_strength = separation_strength  # Full strength when wandering
	
	# Apply separation force
	velocity += separation * sep_strength * base_move_speed
	
	# Knockback (always applies)
	velocity += knockback_velocity




func _can_see_player() -> bool:
	if not player:
		return false

	# While invisible, slimes can never see the player
	if GameState.player_invisible:
		return false

	if global_position.distance_to(player.global_position) > vision_radius:
		return false

	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	query.exclude = [self]
	query.collision_mask = collision_mask

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		return true

	return result.get("collider") == player


func _get_raycast_avoidance(desired_velocity: Vector2) -> Vector2:
	"""Raycast-based obstacle avoidance - steers around walls intelligently."""
	if desired_velocity.length() < 1.0:
		return Vector2.ZERO
	
	var avoidance = Vector2.ZERO
	var move_dir = desired_velocity.normalized()
	
	# Update raycast directions to face movement
	if raycast_forward:
		raycast_forward.target_position = move_dir * raycast_length
	if raycast_left:
		raycast_left.target_position = move_dir.rotated(-PI/4) * raycast_length
	if raycast_right:
		raycast_right.target_position = move_dir.rotated(PI/4) * raycast_length
	
	# Force update
	if raycast_forward:
		raycast_forward.force_raycast_update()
	if raycast_left:
		raycast_left.force_raycast_update()
	if raycast_right:
		raycast_right.force_raycast_update()
	
	# Check forward raycast
	if raycast_forward and raycast_forward.is_colliding():
		var collision_point = raycast_forward.get_collision_point()
		var to_collision = collision_point - global_position
		var distance = to_collision.length()
		
		if distance < 40.0:
			# Wall ahead! Check which side is clearer
			var left_clear = raycast_left and not raycast_left.is_colliding()
			var right_clear = raycast_right and not raycast_right.is_colliding()
			
			if left_clear and right_clear:
				# Both sides clear - pick the side that keeps us moving toward goal
				if randf() > 0.5:
					avoidance = move_dir.rotated(-PI/2) * speed * 0.8
				else:
					avoidance = move_dir.rotated(PI/2) * speed * 0.8
			elif left_clear:
				avoidance = move_dir.rotated(-PI/2) * speed * 0.8
			elif right_clear:
				avoidance = move_dir.rotated(PI/2) * speed * 0.8
			else:
				# Both sides blocked - back up slightly
				avoidance = -move_dir * speed * 0.3
	
	# Check side raycasts for fine-tuning
	if raycast_left and raycast_left.is_colliding():
		var collision_point = raycast_left.get_collision_point()
		var distance = collision_point.distance_to(global_position)
		if distance < 30.0:
			# Wall on left - nudge right
			avoidance += move_dir.rotated(PI/2) * speed * 0.3
	
	if raycast_right and raycast_right.is_colliding():
		var collision_point = raycast_right.get_collision_point()
		var distance = collision_point.distance_to(global_position)
		if distance < 30.0:
			# Wall on right - nudge left
			avoidance += move_dir.rotated(-PI/2) * speed * 0.3
	
	return avoidance


func _get_pack_status() -> Dictionary:
	"""Check if this slime is part of a pack hunting the player."""
	if not enable_pack_hunting:
		return {"in_pack": false, "pack_size": 0, "allies": []}
	
	var allies_hunting: Array = []
	
	# Find nearby allies that can also see the player
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy == self or not is_instance_valid(enemy):
			continue
		
		var dist: float = global_position.distance_to(enemy.global_position)
		
		if dist < pack_detection_radius:
			# Check if ally can see player too
			if is_instance_valid(enemy) and enemy.has_method("_can_see_player") and enemy._can_see_player():
				allies_hunting.append(enemy)
	
	var in_pack: bool = allies_hunting.size() >= min_pack_size
	
	return {
		"in_pack": in_pack,
		"pack_size": allies_hunting.size() + 1,
		"allies": allies_hunting
	}


func _is_player_cornered() -> bool:
	"""Check if player has their back against a wall (ambush opportunity!)"""
	if not enable_ambush_detection or not player:
		return false
	
	var space_state = get_world_2d().direct_space_state
	var player_pos: Vector2 = player.global_position
	
	# Cast rays from player in 8 directions
	var directions: Array = [
		Vector2.RIGHT,
		Vector2.LEFT,
		Vector2.UP,
		Vector2.DOWN,
		Vector2.ONE.normalized(),
		Vector2(-1, 1).normalized(),
		Vector2(1, -1).normalized(),
		Vector2(-1, -1).normalized()
	]
	
	var blocked_directions: int = 0
	
	for dir in directions:
		var query = PhysicsRayQueryParameters2D.create(
			player_pos,
			player_pos + dir * 60.0
		)
		query.exclude = [player, self]
		query.collision_mask = 1  # Walls only
		
		var result = space_state.intersect_ray(query)
		
		if not result.is_empty():
			blocked_directions += 1
	
	# If 5+ directions blocked, player is cornered!
	return blocked_directions >= 5


func _should_retreat() -> bool:
	"""Check if slime should tactically retreat."""
	if not enable_tactical_retreat or not health_component:
		return false
	
	var hp_percent: float = float(health_component.health) / float(health_component.max_health)
	
	# Not low enough HP to retreat
	if hp_percent > retreat_hp_threshold:
		return false
	
	# Check if alone (if retreat_if_alone is true)
	if retreat_if_alone:
		var allies_nearby: int = 0
		var space_state = get_world_2d().direct_space_state
		
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if enemy == self or not is_instance_valid(enemy):
				continue
			
			var dist: float = global_position.distance_to(enemy.global_position)
			if dist < 120.0:  # Reduced radius
				# Check if we can actually see the ally (not blocked by walls)
				var query = PhysicsRayQueryParameters2D.create(global_position, enemy.global_position)
				query.exclude = [self]
				query.collision_mask = 1  # Walls only
				
				var result = space_state.intersect_ray(query)
				
				# Only count ally if we can see them (no wall blocking)
				if result.is_empty() or result.get("collider") == enemy:
					allies_nearby += 1
		
		# Has allies nearby - don't retreat
		if allies_nearby > 0:
			return false
	
	return true
func _get_flanking_position() -> Vector2:
	"""Calculate position to surround player as part of pack."""
	if not enable_pack_spreading or not player:
		return player.global_position
	
	var pack_status: Dictionary = _get_pack_status()
	
	# Not enough allies for spreading
	if pack_status.pack_size < min_pack_size_for_spread:
		return player.global_position
	
	# Get all pack members including self
	var pack_members: Array = pack_status.allies + [self]
	
	# Find our index in the pack
	var my_index: int = pack_members.find(self)
	
	if my_index == -1:
		return player.global_position
	
	# Calculate angle for this slime to take flanking position
	var angle_step: float = TAU / pack_status.pack_size
	var my_angle: float = angle_step * my_index
	
	# Position around player at spread_radius
	var target_offset: Vector2 = Vector2.from_angle(my_angle) * spread_radius
	var target_pos: Vector2 = player.global_position + target_offset
	
	return target_pos


func _update_behavior_visuals() -> void:
	"""Visual feedback for different AI states."""
	if not animated_sprite or not hit_light:
		return
	
	# Reset to default
	var target_modulate: Color = base_modulate
	var target_light_color: Color = original_light_color
	var target_light_energy: float = 1.5
	
	# Check current behavior state
	if _should_retreat():
		# RETREATING - Blue tint, dim light
		target_modulate = Color(0.8, 0.8, 1.0)
		target_light_color = Color(0.5, 0.5, 1.0)
		target_light_energy = 0.5
	
	elif _is_player_cornered():
		# AMBUSH - Red aggressive glow
		target_modulate = Color(1.2, 0.9, 0.9)
		target_light_color = Color(1.0, 0.3, 0.3)
		target_light_energy = 1.8
	
	elif _get_pack_status().in_pack:
		# PACK HUNTING - Orange cooperative glow
		target_modulate = Color(1.1, 1.0, 0.9)
		target_light_color = Color(1.0, 0.7, 0.3)
		target_light_energy = 1.6
	
	# Smooth transition to target values
	animated_sprite.modulate = animated_sprite.modulate.lerp(target_modulate, 0.1)
	hit_light.color = hit_light.color.lerp(target_light_color, 0.1)
	hit_light.energy = lerp(hit_light.energy, target_light_energy, 0.1)


func _refresh_pack_cache() -> void:
	"""Refresh the cached list of nearby pack members (performance optimization)."""
	pack_members_cache.clear()
	
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy == self or not is_instance_valid(enemy):
			continue
		
		var dist: float = global_position.distance_to(enemy.global_position)
		
		# Cache enemies within a reasonable distance
		if dist < pack_detection_radius * 1.5:
			pack_members_cache.append(enemy)


func _update_stuck_detection(delta: float) -> void:
	"""Detect if slime is stuck and apply unstuck behavior."""
	if not aggro:
		stuck_timer = 0.0
		unstuck_angle_offset = 0.0
		return
	
	# Check if we've moved much
	var distance_moved = global_position.distance_to(last_position)
	
	if distance_moved < stuck_velocity_threshold * delta:
		# Not moving much
		stuck_timer += delta
		
		if stuck_timer >= stuck_time_threshold:
			# We're stuck! Apply a random angle offset
			unstuck_angle_offset = randf_range(-PI/3, PI/3)  # +/- 60 degrees
			stuck_timer = 0.0  # Reset timer
	else:
		# Moving fine, decay the offset
		if abs(unstuck_angle_offset) > 0.01:
			unstuck_angle_offset *= 0.95  # Gradually remove offset
		else:
			unstuck_angle_offset = 0.0
		
		stuck_timer = max(0.0, stuck_timer - delta * 2.0)  # Decay stuck timer
	
	# Update last position
	last_position = global_position


# --- VISUAL / AUDIO FEEDBACK ---------------------------------------

func _update_hit_feedback(delta: float) -> void:
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0.0:
			animated_sprite.modulate = base_modulate

	if hit_light and hit_light_timer > 0.0:
		hit_light_timer -= delta
		if hit_light_timer <= 0.0 and not is_dead:
			hit_light.color = original_light_color


func _update_animation_sfx() -> void:
	if not animated_sprite:
		return

	var current_anim: StringName = animated_sprite.animation
	var current_frame: int = animated_sprite.frame

	if current_anim == "moving" \
		and current_frame == 9 \
		and (last_anim != current_anim or last_frame != current_frame):

		if sfx_land:
			_maybe_play_land_sound()

	last_anim = current_anim
	last_frame = current_frame


func _update_hp_bar() -> void:
	if hp_fill and health_component:
		var max_hp: int = health_component.max_health
		var current_hp: int = health_component.health

		hp_fill.max_value = max_hp
		hp_fill.value = current_hp


# --- DAMAGE & DEATH ------------------------------------------------

func take_damage(amount: int) -> void:
	if is_dead:
		return
	if amount <= 0:
		return

	if health_component and health_component.has_method("take_damage"):
		health_component.take_damage(amount)


func apply_burn(dmg_per_tick: int, duration: float, interval: float) -> void:
	if health_component and health_component.has_method("apply_burn"):
		health_component.apply_burn(dmg_per_tick, duration, interval)


func die() -> void:
	collision_shape.set_deferred("disabled", true)
	animated_sprite.stop()
	_die_after_sound()


func _die_after_sound() -> void:
	if sfx_death:
		await sfx_death.finished

	_spawn_loot()
	emit_signal("died")
	queue_free()


func _spawn_loot() -> void:
	if HeartScene and randf() < heart_drop_chance:
		var heart := HeartScene.instantiate()
		heart.global_position = global_position
		get_tree().current_scene.add_child(heart)
		return

	if CoinScene:
		var coin := CoinScene.instantiate()
		coin.global_position = global_position
		get_tree().current_scene.add_child(coin)


# --- CONTACT DAMAGE ------------------------------------------------

func _on_hitbox_body_entered(body: Node2D) -> void:
	if is_dead:
		return

	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(contact_damage)

		if body.has_method("apply_knockback"):
			body.apply_knockback(global_position)


func apply_knockback(from_position: Vector2, strength: float) -> void:
	var dir := (global_position - from_position).normalized()
	knockback_velocity += dir * strength


func _on_health_damaged(_amount: int) -> void:
	aggro = true

	animated_sprite.modulate = Color(1, 0.4, 0.4, 1)
	hit_flash_timer = hit_flash_time

	if hit_light:
		hit_light.color = Color(1.0, 0.25, 0.25, 1.0)
		hit_light_timer = hit_light_flash_time

	if not is_dead and sfx_hurt:
		sfx_hurt.stop()
		sfx_hurt.play()

	call_deferred("_update_hp_bar")


func _on_health_died() -> void:
	if is_dead:
		return

	is_dead = true

	if hit_light:
		hit_light.color = Color(1.0, 0.25, 0.25, 1.0)

	if sfx_death:
		sfx_death.stop()
		sfx_death.play()

	call_deferred("_update_hp_bar")
	die()


func _maybe_play_land_sound() -> void:
	# If we're on cooldown, skip
	if _land_sound_cd > 0.0:
		return

	# Probabilistic play to reduce overlap
	if randf() > land_sound_play_chance:
		_land_sound_cd = land_sound_min_interval
		return

	# Reserve cooldown immediately
	_land_sound_cd = land_sound_min_interval

	if not sfx_land:
		return

	# Randomize pitch and volume slightly to make repeated hits less grating
	var pitch := 1.0 + randf_range(-land_sound_pitch_jitter, land_sound_pitch_jitter)
	sfx_land.pitch_scale = pitch

	var vol := randf_range(land_sound_volume_db_min, land_sound_volume_db_max)
	sfx_land.volume_db = vol

	# Restart the sound so it plays from start with new settings
	sfx_land.stop()
	sfx_land.play()

func force_deaggro() -> void:
	aggro = false
	lost_sight_timer = deaggro_delay


func _apply_speed_scaling() -> void:
	"""Scale movement speed from 1.0x to 1.5x linearly over 100 levels."""
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if not game_manager:
		return

	var level = game_manager.current_level if "current_level" in game_manager else 1

	# Linear scaling: 1.0 + (level - 1) / 100.0, capped at 1.5x
	# More moderate scaling - smart AI provides difficulty, not raw speed
	var speed_multiplier = 1.0 + min((level - 1) / 100.0, 0.5)

	# Apply to movement speed
	if base_move_speed > 0.0:
		speed = base_move_speed * speed_multiplier

	# Apply to wander speed
	if base_wander_speed > 0.0:
		wander_speed = base_wander_speed * speed_multiplier


func set_time_scale(scale_value: float) -> void:
	"""Set time scale for bullet time effect."""
	time_scale = clamp(scale_value, 0.0, 1.0)
