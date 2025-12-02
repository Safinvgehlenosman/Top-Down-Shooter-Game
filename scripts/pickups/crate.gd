extends Area2D

@export var CoinScene: PackedScene
@export var HeartScene: PackedScene  # optional

@export var hit_flash_time: float = 0.1
var hit_flash_timer: float = 0.0
var base_modulate: Color

var destroyed: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D          # Area2D hitbox
@onready var blocker_shape: CollisionShape2D = $Blocker/CollisionShape2D  # solid collider
@onready var health_component: Node = $Health


func _ready() -> void:
	if animated_sprite:
		animated_sprite.play("idle")
		base_modulate = animated_sprite.modulate

	# --- Wire up HealthComponent for crates ---
	if health_component:
		# Crate does NOT use GameState HP
		health_component.use_gamestate = false

		# Make sure it starts with at least 1 HP
		if health_component.max_health <= 0:
			health_component.max_health = 1
		if health_component.health <= 0:
			health_component.health = health_component.max_health

		# No i-frames for crates
		health_component.invincible_time = 0.0

		health_component.connect("damaged", Callable(self, "_on_health_damaged"))
		health_component.connect("died",    Callable(self, "_on_health_died"))


func _process(delta: float) -> void:
	_update_hit_feedback(delta)


func _update_hit_feedback(delta: float) -> void:
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0.0 and animated_sprite:
			animated_sprite.modulate = base_modulate


# --------------------------------------------------------------------
# LOOT + BREAK
# --------------------------------------------------------------------

func _spawn_loot() -> void:
	# Dynamic pickup spawn based on player needs
	var hp_percent := 1.0
	
	# Calculate HP percentage
	if GameState.max_health > 0:
		hp_percent = float(GameState.health) / float(GameState.max_health)
	
	# ⭐ Check if chaos challenge is active (no HP upgrades allowed)
	var chaos_active := not GameState.active_chaos_challenge.is_empty()
	
	# During chaos challenge always spawn coins
	if chaos_active:
		if CoinScene:
			var coin := CoinScene.instantiate()
			coin.global_position = global_position
			get_tree().current_scene.add_child(coin)
	# If HP is below max, always drop hearts
	elif hp_percent < 1.0 and HeartScene:
		var heart := HeartScene.instantiate()
		heart.global_position = global_position
		get_tree().current_scene.add_child(heart)
	# Otherwise drop coins
	elif CoinScene:
		var coin := CoinScene.instantiate()
		coin.global_position = global_position
		get_tree().current_scene.add_child(coin)




func _break_and_despawn() -> void:
	# disable both the Area2D hitbox and the solid collider
	if collision:
		collision.disabled = true
	if blocker_shape:
		blocker_shape.disabled = true

	# flash red + start timer
	if animated_sprite:
		animated_sprite.modulate = Color(1, 0.4, 0.4, 1)
	hit_flash_timer = hit_flash_time

	# scale pop
	scale = Vector2(1.6, 1.6)
	await get_tree().create_timer(0.2).timeout

	# shrink a bit before death
	scale = Vector2(1.4, 1.4)
	await get_tree().create_timer(0.2).timeout

	_spawn_loot()
	queue_free()


# --------------------------------------------------------------------
# DAMAGE FLOW
# --------------------------------------------------------------------

func take_damage(amount: int) -> void:
	if destroyed:
		return

	if health_component and health_component.has_method("take_damage"):
		health_component.take_damage(amount)


func _on_area_entered(area: Area2D) -> void:
	if destroyed:
		return

	if area.is_in_group("bullet"):
		# Bullet hits crate → crate takes 1 damage
		area.queue_free()
		take_damage(1)


func _on_health_damaged(_amount: int) -> void:
	# simple red flash
	if animated_sprite:
		animated_sprite.modulate = Color(1, 0.4, 0.4, 1)
	hit_flash_timer = hit_flash_time


func _on_health_died() -> void:
	if destroyed:
		return
	destroyed = true

	# Play break SFX once
	if has_node("SFX_Break"):
		$SFX_Break.play()

	# Do the break animation + loot
	call_deferred("_break_and_despawn")
