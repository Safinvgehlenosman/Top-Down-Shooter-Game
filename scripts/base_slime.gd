extends CharacterBody2D

signal died

# Core stats (tweak per slime in Inspector)
@export var speed: float = GameConfig.slime_move_speed
@export var max_health: int = GameConfig.slime_max_health
@export var heart_drop_chance: float = GameConfig.slime_heart_drop_chance
@export var contact_damage: int = GameConfig.slime_contact_damage
@export var contact_interval: float = 0.5   # seconds between hits while touching
var contact_timer: float = 0.0

@onready var hitbox: Area2D = $Hitbox       # <-- adjust path to your slime's Area2D
@export var vision_radius: float = 250.0

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

# Internal state
var health: int = 0
var player: Node2D
var base_modulate: Color
var original_light_color: Color  # store whatever the light color is in the inspector

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


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D
	health = max_health

	base_modulate = animated_sprite.modulate

	if hit_light:
		original_light_color = hit_light.color

	animated_sprite.play("moving")


func apply_level(level: int) -> void:
	# level 1 = no scaling
	var level_offset = max(level - 1, 0)

	if level_offset <= 0:
		health = max_health
		return

	# HP scaling
	if health_growth_per_level != 0.0:
		var hp_mult = 1.0 + health_growth_per_level * level_offset
		max_health = int(round(max_health * hp_mult))
		health = max_health
	else:
		health = max_health

	# Damage scaling
	if damage_growth_per_level != 0.0:
		var dmg_mult = 1.0 + damage_growth_per_level * level_offset
		contact_damage = int(round(contact_damage * dmg_mult))


func _physics_process(delta: float) -> void:
	# contact damage timer
	if contact_timer > 0.0:
		contact_timer -= delta
	if contact_timer <= 0.0:
		_try_contact_damage()

	if is_dead:
		_update_hit_feedback(delta)
		return

	_update_hit_feedback(delta)
	_update_ai(delta)
	_update_animation_sfx()
	
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

	# Distance & direction to player
	var to_player: Vector2 = player.global_position - global_position
	var distance: float = to_player.length()
	var can_see := _can_see_player()

	# --- Aggro state machine ---

	# Gain aggro when close *and* visible
	if distance <= aggro_radius and can_see:
		aggro = true
		last_seen_player_pos = player.global_position
		lost_sight_timer = 0.0
	elif aggro:
		# Already aggro but maybe lost LOS
		if can_see:
			# Still see the player: keep resetting timers + last seen
			last_seen_player_pos = player.global_position
			lost_sight_timer = 0.0
		else:
			# Lost LOS: count up de-aggro timer
			lost_sight_timer += delta
			if lost_sight_timer >= deaggro_delay:
				aggro = false

	# --- Movement decisions ---

	if aggro:
		if can_see:
			# Direct chase with a little sideways strafe
			var forward: Vector2 = to_player.normalized()
			var right: Vector2 = Vector2(-forward.y, forward.x)
			var strafe: Vector2 = right * strafe_amount

			var dir: Vector2 = (forward + strafe).normalized()
			velocity = dir * speed
		elif lost_sight_timer < deaggro_delay:
			# SEARCH: move to last seen player position
			var to_last_seen := last_seen_player_pos - global_position
			if to_last_seen.length() > 4.0:
				var dir_search := to_last_seen.normalized()
				velocity = dir_search * speed * last_seen_search_speed
			else:
				# Reached last seen spot → slow down (will de-aggro once timer finishes)
				velocity = Vector2.ZERO
	else:
		# Simple wander when not aggro
		wander_timer -= delta
		if wander_timer <= 0.0:
			wander_timer = wander_change_interval
			wander_direction = Vector2(
				randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)
			).normalized()

		velocity = wander_direction * wander_speed

	# --- Separation from other enemies (all in "enemy" group) ---
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
	# you can re-add collision steering here later if you want


func _can_see_player() -> bool:
	if not player:
		return false

	# Check radius first
	if global_position.distance_to(player.global_position) > vision_radius:
		return false

	# LOS raycast
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
	# sprite flash
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0.0:
			animated_sprite.modulate = base_modulate

	# light flash
	if hit_light and hit_light_timer > 0.0:
		hit_light_timer -= delta
		if hit_light_timer <= 0.0 and health > 0:
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
			sfx_land.stop()
			sfx_land.play()

	last_anim = current_anim
	last_frame = current_frame


# --- DAMAGE & DEATH ------------------------------------------------

func take_damage(amount: int) -> void:
	if is_dead:
		return
	if amount <= 0:
		return

	aggro = true

	health = max(health - amount, 0)

	# sprite flash
	animated_sprite.modulate = Color(1, 0.4, 0.4, 1)
	hit_flash_timer = hit_flash_time

	# light flash
	if hit_light:
		hit_light.color = Color(1.0, 0.25, 0.25, 1.0)
		hit_light_timer = hit_light_flash_time

	if health > 0:
		if sfx_hurt:
			sfx_hurt.stop()
			sfx_hurt.play()
	else:
		is_dead = true

		if hit_light:
			hit_light.color = Color(1.0, 0.25, 0.25, 1.0)

		if sfx_death:
			sfx_death.stop()
			sfx_death.play()

		die()


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
