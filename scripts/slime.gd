extends CharacterBody2D

signal died


# Core stats (default from GameConfig, still overridable in Inspector)
@export var speed: float              = GameConfig.slime_move_speed
@export var max_health: int           = GameConfig.slime_max_health
@export var heart_drop_chance: float  = GameConfig.slime_heart_drop_chance  # 0–1

# Movement / behaviour tuning
@export var separation_radius: float = 24.0      # how close slimes can get to each other
@export var separation_strength: float = 0.7     # how strongly they push away
@export var strafe_amount: float = 0.3           # sideways movement while chasing
@export var aggro_radius: float = 180.0          # player distance that triggers permanent aggro
@export var wander_speed: float = 40.0           # speed while idle wandering
@export var wander_change_interval: float = 1.5  # how often wander direction changes (seconds)

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
var original_light_color: Color  # <-- new: store whatever the light color is in the inspector

# Hit flash timers
@export var hit_flash_time: float = 0.1
var hit_flash_timer: float = 0.0

@export var hit_light_flash_time: float = 0.1
var hit_light_timer: float = 0.0

# Smoothed velocity target
var target_velocity: Vector2 = Vector2.ZERO

# Aggro state
var aggro: bool = false

# Wander state
var wander_timer: float = 0.0
var wander_direction: Vector2 = Vector2.ZERO

var is_dead: bool = false


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D
	health = max_health

	base_modulate = animated_sprite.modulate

	# store whatever color you set on the PointLight2D in the inspector
	if hit_light:
		original_light_color = hit_light.color

	# ensure drop chance is synced with config (but still overridable per slime)
	heart_drop_chance = GameConfig.slime_heart_drop_chance

	animated_sprite.play("moving")


func _physics_process(delta: float) -> void:
	if is_dead:
		_update_hit_feedback(delta)
		return

	_update_hit_feedback(delta)
	_update_ai(delta)
	_update_animation_sfx()

	move_and_slide()


# --- AI / MOVEMENT --------------------------------------------------

func _update_ai(delta: float) -> void:
	if not player:
		return

	# Distance & direction to player
	var to_player: Vector2 = player.global_position - global_position
	var distance: float = to_player.length()

	# Only aggro if player is close AND visible
	if distance <= aggro_radius and _can_see_player():
		aggro = true

	var can_see := _can_see_player()

	if aggro and can_see:
		# Chase with a little sideways strafe
		var forward: Vector2 = to_player.normalized()
		var right: Vector2 = Vector2(-forward.y, forward.x)
		var strafe: Vector2 = right * strafe_amount

		var dir: Vector2 = (forward + strafe).normalized()
		velocity = dir * speed
	else:
		# Simple wander (used when not aggro OR aggro but lost sight)
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
		var dist: float = diff.length()
		if dist > 0.0 and dist < separation_radius:
			separation += diff.normalized() * (1.0 - dist / separation_radius)

	velocity += separation * separation_strength * speed

	# (Optional) keep the collision-steering from before here if you liked it.



func _can_see_player() -> bool:
	if not player:
		return false

	var space_state := get_world_2d().direct_space_state

	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		player.global_position
	)

	# Exclude this slime from the ray
	query.exclude = [self]

	# Use the same collision mask the slime uses
	query.collision_mask = collision_mask

	# Only collide with bodies (tiles, player, crates…)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var result := space_state.intersect_ray(query)

	# No collision → we see the player clearly
	if result.is_empty():
		return true

	# If the first thing we hit IS the player → we also see them
	var collider = result.get("collider")
	return collider == player



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
			# restore whatever color the light had in the inspector
			hit_light.color = original_light_color


func _update_animation_sfx() -> void:
	if not animated_sprite:
		return

	var current_anim: StringName = animated_sprite.animation
	var current_frame: int = animated_sprite.frame

	# Play land SFX only once when we ENTER frame 1 of "moving"
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

	# being hit always aggro's the slime
	aggro = true

	health = max(health - amount, 0)

	# --- SPRITE FLASH ---
	animated_sprite.modulate = Color(1, 0.4, 0.4, 1)
	hit_flash_timer = hit_flash_time

	# --- LIGHT FLASH ---
	if hit_light:
		# turn light red on hit
		hit_light.color = Color(1.0, 0.25, 0.25, 1.0)
		hit_light_timer = hit_light_flash_time

	if health > 0:
		if sfx_hurt:
			sfx_hurt.stop()
			sfx_hurt.play()
	else:
		is_dead = true  # mark it as dead so we stop interacting

		# final hit: keep light solid red (no timer revert because health == 0)
		if hit_light:
			hit_light.color = Color(1.0, 0.25, 0.25, 1.0)

		if sfx_death:
			sfx_death.stop()
			sfx_death.play()

		die()


func die() -> void:
	# stop colliding / animating, but keep _physics_process running for flashes
	collision_shape.set_deferred("disabled", true)
	animated_sprite.stop()
	_die_after_sound()


func _die_after_sound() -> void:
	# Wait for death SFX, then drop loot and free
	if sfx_death:
		await sfx_death.finished

	_spawn_loot()
	emit_signal("died")
	queue_free()


func _spawn_loot() -> void:
	# heart?
	if HeartScene and randf() < heart_drop_chance:
		var heart := HeartScene.instantiate()
		heart.global_position = global_position
		get_tree().current_scene.add_child(heart)
		return

	# otherwise coin
	if CoinScene:
		var coin := CoinScene.instantiate()
		coin.global_position = global_position
		get_tree().current_scene.add_child(coin)


# --- CONTACT DAMAGE ------------------------------------------------

func _on_hitbox_body_entered(body: Node2D) -> void:
	if is_dead:
		return

	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(GameConfig.slime_contact_damage)

		if body.has_method("apply_knockback"):
			body.apply_knockback(global_position)
