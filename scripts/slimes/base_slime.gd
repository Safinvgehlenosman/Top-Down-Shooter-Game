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

# How much we grow per level
@export var health_growth_per_level: float = 0.05
@export var damage_growth_per_level: float = 0.10

# Movement / behaviour tuning
@export var separation_radius: float = 24.0      # how close slimes can get to each other
@export var separation_strength: float = 0.7     # how strongly they push away
@export var strafe_amount: float = 0.3           # sideways movement while chasing
@export var aggro_radius: float = 180.0          # player distance that triggers aggro
@export var wander_speed: float = 40.0           # speed while idle wandering
@export var wander_change_interval: float = 1.5  # how often wander direction changes (seconds)

# NEW: de-aggro behaviour
@export var deaggro_delay: float = 1.2           # how long they keep searching after losing LOS
@export var last_seen_search_speed: float = 1.0  # speed multiplier while moving to last seen pos
var last_seen_player_pos: Vector2 = Vector2.ZERO
var lost_sight_timer: float = 0.0

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


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D

	base_modulate = animated_sprite.modulate

	if hit_light:
		original_light_color = hit_light.color

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
	# contact damage timer
	if contact_timer > 0.0:
		contact_timer -= delta
	if contact_timer <= 0.0:
		_try_contact_damage()

	# decrement per-instance land-sound cooldown
	if _land_sound_cd > 0.0:
		_land_sound_cd = max(0.0, _land_sound_cd - delta)

	if is_dead:
		_update_hit_feedback(delta)
		return

	_update_hit_feedback(delta)
	_update_ai(delta)
	_update_animation_sfx()

	# decay knockback over time
	if knockback_velocity.length() > 0.0:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_friction * delta)

	if velocity.x < -1:
		animated_sprite.flip_h = false
	elif velocity.x > 1:
		animated_sprite.flip_h = true

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

	# ------------------------------------------------------
	# PLAYER INVISIBLE → forget them and wander normally
	# ------------------------------------------------------
	if GameState.player_invisible:
		aggro = false

		# normal wander logic
		wander_timer -= delta
		if wander_timer <= 0.0:
			wander_timer = wander_change_interval
			wander_direction = Vector2(
				randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)
			).normalized()

		velocity = wander_direction * wander_speed

		# separation so they don't stack
		var separation: Vector2 = Vector2.ZERO
		for other in get_tree().get_nodes_in_group("enemy"):
			if other == self:
				continue

			var other_node := other as Node2D
			if other_node == null:
				continue

			var diff: Vector2 = global_position - other_node.global_position
			var dist_sep: float = diff.length()
			if dist_sep > 0.0 and dist_sep < separation_radius:
				separation += diff.normalized() * (1.0 - dist_sep / separation_radius)

		velocity += separation * separation_strength * speed

		# wall avoidance
		var motion := velocity * delta
		if test_move(global_transform, motion):
			var motion_x := Vector2(motion.x, 0.0)
			var motion_y := Vector2(0.0, motion.y)

			if not test_move(global_transform, motion_x):
				motion = motion_x
			elif not test_move(global_transform, motion_y):
				motion = motion_y
			else:
				motion = Vector2.ZERO

			if delta > 0.0:
				velocity = motion / delta

		# knockback still applies
		velocity += knockback_velocity
		return

	# ------------------------------------------------------
	# NORMAL BEHAVIOUR (player visible)
	# ------------------------------------------------------
	var to_player: Vector2 = player.global_position - global_position
	var distance: float = to_player.length()
	var can_see := _can_see_player()

	# aggro logic
	if distance <= aggro_radius and can_see:
		aggro = true
		last_seen_player_pos = player.global_position
		lost_sight_timer = 0.0
	elif aggro:
		if can_see:
			last_seen_player_pos = player.global_position
			lost_sight_timer = 0.0
		else:
			lost_sight_timer += delta
			if lost_sight_timer >= deaggro_delay:
				aggro = false

	# movement decisions
	if aggro:
		if can_see:
			var forward: Vector2 = to_player.normalized()
			var right: Vector2 = Vector2(-forward.y, forward.x)
			var strafe: Vector2 = right * strafe_amount

			var dir: Vector2 = (forward + strafe).normalized()
			velocity = dir * speed
		elif lost_sight_timer < deaggro_delay:
			var to_last_seen := last_seen_player_pos - global_position
			if to_last_seen.length() > 4.0:
				var dir_search := to_last_seen.normalized()
				velocity = dir_search * speed * last_seen_search_speed
			else:
				velocity = Vector2.ZERO
	else:
		wander_timer -= delta
		if wander_timer <= 0.0:
			wander_timer = wander_change_interval
			wander_direction = Vector2(
				randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)
			).normalized()

		velocity = wander_direction * wander_speed

	# separation
	var separation2: Vector2 = Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self:
			continue

		var other_node2 := other as Node2D
		if other_node2 == null:
			continue

		var diff2: Vector2 = global_position - other_node2.global_position
		var dist_sep2: float = diff2.length()
		if dist_sep2 > 0.0 and dist_sep2 < separation_radius:
			separation2 += diff2.normalized() * (1.0 - dist_sep2 / separation_radius)

	velocity += separation2 * separation_strength * speed

	# wall avoidance
	var motion2 := velocity * delta
	if test_move(global_transform, motion2):
		var motion_x2 := Vector2(motion2.x, 0.0)
		var motion_y2 := Vector2(0.0, motion2.y)

		if not test_move(global_transform, motion_x2):
			motion2 = motion_x2
		elif not test_move(global_transform, motion_y2):
			motion2 = motion_y2
		else:
			motion2 = Vector2.ZERO

		if delta > 0.0:
			velocity = motion2 / delta

	# finally, add knockback
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
