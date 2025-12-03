extends Area2D

@export var initial_speed: float = 80.0
@export var friction: float = 200.0

@export var jump_force: float = 60.0      # how high the heart hops
@export var fall_gravity: float = 200.0   # how fast it falls back down

var velocity: Vector2 = Vector2.ZERO
var z_height: float = 0.0
var z_velocity: float = 0.0

var magnet_velocity: Vector2 = Vector2.ZERO

# Auto-collect variables
var auto_collect_target: Node2D = null
var auto_collect_speed: float = 500.0

@onready var sprite: Node2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var sfx_pickup: AudioStreamPlayer2D = $SFX_Pickup
@onready var light: PointLight2D = $PointLight2D   # <-- added

var is_collected: bool = false   # <-- added


func _ready() -> void:
	add_to_group("room_cleanup")
	add_to_group("pickup_heart")


func start_auto_collect(target: Node2D) -> void:
	"""Start auto-collecting this pickup towards the target (player)."""
	auto_collect_target = target


func launch() -> void:
	# random horizontal direction for the hop
	var angle: float = randf_range(-PI, PI)
	velocity = Vector2(cos(angle), sin(angle)) * initial_speed

	# vertical fake jump
	z_velocity = jump_force


func _physics_process(delta: float) -> void:
	# After being collected, do nothing (no bounce, no magnet, no ghost light movement)
	if is_collected:
		return

	# Auto-collect mode: fly directly to target
	if auto_collect_target:
		var to_target: Vector2 = auto_collect_target.global_position - global_position
		var distance := to_target.length()
		if distance < 8.0:
			# Close enough, trigger pickup
			_on_body_entered(auto_collect_target)
			return
		global_position += to_target.normalized() * auto_collect_speed * delta
		return

	# Magnet attraction with acceleration
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		var dist = global_position.distance_to(player.global_position)
		# Use dynamic magnet range from GameConfig
		var magnet_range: float = GameConfig.current_pickup_magnet_range
		if dist < magnet_range:
			# Calculate direction to player
			var dir = (player.global_position - global_position).normalized()
			# Add damping to prevent runaway velocity
			magnet_velocity *= 0.90  # Apply 10% friction each frame
			# Get dynamic acceleration and max speed from GameConfig
			var accel: float = GameConfig.current_pickup_magnet_accel
			var max_speed: float = GameConfig.current_pickup_magnet_speed
			# Stronger acceleration when very close (within 50 pixels)
			if dist < 50.0:
				accel *= 2.0  # Double acceleration when close
			# Accelerate toward player
			magnet_velocity += dir * accel * delta
			# Cap at maximum speed
			if magnet_velocity.length() > max_speed:
				magnet_velocity = magnet_velocity.normalized() * max_speed
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

	# fake vertical motion
	z_velocity -= fall_gravity * delta
	z_height += z_velocity * delta

	# hit "ground"
	if z_height < 0.0:
		z_height = 0.0
		z_velocity = 0.0

	# visual offset for jump
	sprite.position.y = -z_height


func _on_body_entered(body: Node2D) -> void:
	if is_collected:
		return

	if body.is_in_group("player"):
		is_collected = true

		# Get HP value based on level (randomized ranges)
		var hp_value: int = _get_hp_value_for_level()
		
		# heal player: we use negative damage
		if body.has_method("take_damage"):
			body.take_damage(-hp_value)
		
		# Spawn HP number popup
		_spawn_hp_number(hp_value)

		# immediately kill collisions + visuals + light
		if collision:
			collision.set_deferred("disabled", true)
		if sprite:
			sprite.visible = false
		if light:
			light.visible = false

		# play heart pickup sound and let it finish
		if sfx_pickup:
			sfx_pickup.play()
			await sfx_pickup.finished

		queue_free()


func _get_hp_value_for_level() -> int:
	var gm := get_tree().get_first_node_in_group("game_manager")
	var level := 1
	if gm:
		level = int(gm.current_level)
	
	var min_value: int
	var max_value: int
	
	# HP scales with level (hearts give more HP at high levels)
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
	
	print("[HPPickup] Level ", level, " - HP value: ", value, " (range: ", min_value, "-", max_value, ")")
	
	return value


func _spawn_hp_number(amount: int) -> void:
	# Load HP number scene
	var hp_number_scene = preload("res://scenes/ui/hp_number.tscn")
	var hp_number = hp_number_scene.instantiate()
	
	# Position near pickup (slightly offset so visible)
	hp_number.global_position = global_position + Vector2(randf_range(-20, 20), -30)
	
	# Set the amount text
	if hp_number.has_node("Label"):
		hp_number.get_node("Label").text = "+" + str(amount) + "HP"
	
	# Add to scene root (not as child of heart, it's about to despawn!)
	get_tree().root.add_child(hp_number)
