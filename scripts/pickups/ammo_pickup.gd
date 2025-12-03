extends Area2D

@export var initial_speed: float = 80.0
@export var friction: float = 200.0

@export var jump_force: float = 60.0
@export var fall_gravity: float = 200.0

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
@onready var light: PointLight2D = $PointLight2D

var is_collected: bool = false

func _ready() -> void:
	add_to_group("room_cleanup")
	add_to_group("pickup_ammo")

func start_auto_collect(target: Node2D) -> void:
	"""Start auto-collecting this pickup towards the target (player)."""
	auto_collect_target = target

func _physics_process(delta: float) -> void:
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

	# Horizontal hop + friction
	global_position += velocity * delta
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	# Vertical arc
	z_velocity -= fall_gravity * delta
	z_height += z_velocity * delta
	if z_height < 0.0:
		z_height = 0.0
		z_velocity = 0.0

	sprite.position.y = -z_height


func launch() -> void:
	var angle = randf_range(-PI, PI)
	velocity = Vector2(cos(angle), sin(angle)) * initial_speed
	z_velocity = jump_force


func _on_body_entered(body: Node2D) -> void:
	if is_collected or not body.is_in_group("player"):
		return

	is_collected = true

	# 🟡 Determine pickup amount from current alt-weapon data
	var amount := 0

	if GameState.alt_weapon != GameState.AltWeaponType.NONE \
	and GameState.ALT_WEAPON_DATA.has(GameState.alt_weapon):
		var data = GameState.ALT_WEAPON_DATA[GameState.alt_weapon]
		amount = data.get("pickup_amount", 0)
		print("[AmmoPickup] Weapon:", data.get("id", "unknown"), "gives", amount, "ammo")

	# 🟡 Apply ammo → through GameState
	if amount > 0 and GameState.max_ammo > 0:
		GameState.set_ammo(min(GameState.ammo + amount, GameState.max_ammo))

		# Spawn ammo number popup
		_spawn_ammo_number(amount)

	# Disable visibility + collision
	if collision:
		collision.set_deferred("disabled", true)
	if sprite:
		sprite.visible = false
	if light:
		light.visible = false

	if sfx_pickup:
		sfx_pickup.play()
		await sfx_pickup.finished

	queue_free()


func _spawn_ammo_number(amount: int) -> void:
	# Load ammo number scene
	var ammo_number_scene = preload("res://scenes/ui/ammo_number.tscn")
	var ammo_number = ammo_number_scene.instantiate()
	
	# Position near pickup (slightly offset so visible)
	ammo_number.global_position = global_position + Vector2(randf_range(-20, 20), -30)
	
	# Set the amount text
	if ammo_number.has_node("Label"):
		ammo_number.get_node("Label").text = "+" + str(amount) + " AMMO"
	
	# Add to scene root (not as child of ammo, it's about to despawn!)
	get_tree().root.add_child(ammo_number)
