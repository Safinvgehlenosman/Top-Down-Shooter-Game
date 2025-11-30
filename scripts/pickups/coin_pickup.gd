extends Area2D

@export var initial_speed: float = 80.0
@export var friction: float = 200.0

@export var jump_force: float = 60.0      # how high the coin hops
@export var fall_gravity: float = 200.0   # how fast it falls back down

var velocity: Vector2 = Vector2.ZERO
var z_height: float = 0.0
var z_velocity: float = 0.0
var has_landed: bool = false
var is_collected: bool = false   # <-- new

var magnet_velocity: Vector2 = Vector2.ZERO
var magnet_acceleration: float = 800.0  # How fast pickups accelerate toward player
var max_magnet_speed: float = 600.0     # Maximum speed cap

@onready var sprite: Node2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var sfx_land: AudioStreamPlayer2D = $SFX_Spawn
@onready var sfx_pickup: AudioStreamPlayer2D = $SFX_Collect
@onready var light: PointLight2D = $PointLight2D   # <-- new


func _ready() -> void:
	add_to_group("room_cleanup")

func launch() -> void:
	# random horizontal direction for the hop
	var angle: float = randf_range(-PI, PI)
	velocity = Vector2(cos(angle), sin(angle)) * initial_speed

	# vertical fake jump
	z_velocity = jump_force


func _physics_process(delta: float) -> void:
	# After pickup: no more movement / magnet / light drifting
	if is_collected:
		return

	# Magnet attraction with acceleration
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		var dist: float = global_position.distance_to(player.global_position)
		if dist < GameConfig.pickup_magnet_range:
			# Calculate direction to player
			var dir: Vector2 = (player.global_position - global_position).normalized()
			# Add damping to prevent runaway velocity
			magnet_velocity *= 0.90  # Apply 10% friction each frame
			# Stronger acceleration when very close (within 50 pixels)
			var accel = magnet_acceleration
			if dist < 50.0:
				accel *= 2.0  # Double acceleration when close
			# Accelerate toward player
			magnet_velocity += dir * accel * delta
			# Cap at maximum speed
			if magnet_velocity.length() > max_magnet_speed:
				magnet_velocity = magnet_velocity.normalized() * max_magnet_speed
			# Move with accumulated velocity
			global_position += magnet_velocity * delta
			# Skip normal hop physics while being magnetized
			return
		else:
			# Reset velocity when outside magnet range
			magnet_velocity = Vector2.ZERO

	# move horizontally
	global_position += velocity * delta
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	# fake vertical jump
	z_velocity -= fall_gravity * delta
	z_height += z_velocity * delta

	# coin hits "ground"
	if z_height < 0.0:
		z_height = 0.0

		if not has_landed:
			has_landed = true
			if sfx_land:
				sfx_land.play()

	# visual offset for jump
	sprite.position.y = -z_height


func _on_body_entered(body: Node2D) -> void:
	if is_collected:
		return

	if body.is_in_group("player"):
		is_collected = true

		# Get coin value based on level (randomized ranges)
		var coin_value: int = _get_coin_value_for_level()
		
		# ⭐ If coin pickups are disabled by chaos challenge, set value to 0
		if GameState.coin_pickups_disabled:
			print("[CoinPickup] Coin pickups disabled by chaos challenge! Value set to 0")
			coin_value = 0
		
		GameState.add_coins(coin_value)
		
		# Spawn coin number popup
		_spawn_coin_number(coin_value)

		# disable interaction & hide while sound plays
		if collision:
			collision.set_deferred("disabled", true)
		if sprite:
			sprite.visible = false
		if light:
			light.visible = false  # <-- kill the light instantly

		if sfx_pickup:
			sfx_pickup.play()
			await sfx_pickup.finished

		queue_free()


func _get_coin_value_for_level() -> int:
	var gm := get_tree().get_first_node_in_group("game_manager")
	var level := 1
	if gm:
		level = int(gm.current_level)
	
	var min_value: int
	var max_value: int
	
	# Determine range based on level
	if level <= 5:
		min_value = 10
		max_value = 15
	elif level <= 10:
		min_value = 16
		max_value = 20
	elif level <= 15:
		min_value = 21
		max_value = 25
	elif level <= 20:
		min_value = 26
		max_value = 30
	elif level <= 25:
		min_value = 31
		max_value = 35
	else:
		# Level 26+
		min_value = 36
		max_value = 40
	
	# Return random value in range
	var value = randi_range(min_value, max_value)
	
	print("[CoinPickup] Level ", level, " - Coin value: ", value, " (range: ", min_value, "-", max_value, ")")
	
	return value


func _spawn_coin_number(amount: int) -> void:
	# Load coin number scene
	var coin_number_scene = preload("res://scenes/ui/coins_number.tscn")
	var coin_number = coin_number_scene.instantiate()
	
	# Position near pickup (slightly offset so visible)
	coin_number.global_position = global_position + Vector2(randf_range(-20, 20), -30)
	
	# Set the amount text with color based on value
	if coin_number.has_node("Label"):
		var label = coin_number.get_node("Label")
		label.text = "+" + str(amount) + " COINS"
		
		# Bigger numbers = brighter color and larger size
		if amount >= 30:
			label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))  # Bright gold
			label.add_theme_font_size_override("font_size", 20)
		elif amount >= 20:
			label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))  # Normal gold
			label.add_theme_font_size_override("font_size", 18)
		else:
			label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))  # Light yellow
			label.add_theme_font_size_override("font_size", 16)
	
	# Add to scene root (not as child of coin, it's about to despawn!)
	get_tree().root.add_child(coin_number)
	
	print("[CoinPickup] Spawned coin number: +", amount)
