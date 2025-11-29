extends Area2D

@export var initial_speed: float = 80.0
@export var friction: float = 200.0

@export var jump_force: float = 60.0      # how high the heart hops
@export var fall_gravity: float = 200.0   # how fast it falls back down

var velocity: Vector2 = Vector2.ZERO
var z_height: float = 0.0
var z_velocity: float = 0.0

var magnet_velocity: Vector2 = Vector2.ZERO
var magnet_acceleration: float = 800.0  # How fast pickups accelerate toward player
var max_magnet_speed: float = 600.0     # Maximum speed cap

@onready var sprite: Node2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var sfx_pickup: AudioStreamPlayer2D = $SFX_Pickup
@onready var light: PointLight2D = $PointLight2D   # <-- added

var is_collected: bool = false   # <-- added


func _ready() -> void:
	add_to_group("room_cleanup")


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

		# heal player: we use negative damage
		if body.has_method("take_damage"):
			body.take_damage(-10)

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
