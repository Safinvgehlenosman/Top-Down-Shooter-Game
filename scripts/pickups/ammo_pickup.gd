extends Area2D

@export var initial_speed: float = 80.0
@export var friction: float = 200.0

@export var jump_force: float = 60.0
@export var fall_gravity: float = 200.0

var velocity: Vector2 = Vector2.ZERO
var z_height: float = 0.0
var z_velocity: float = 0.0

@onready var sprite: Node2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var sfx_pickup: AudioStreamPlayer2D = $SFX_Pickup
@onready var light: PointLight2D = $PointLight2D

var is_collected: bool = false

func _ready() -> void:
	add_to_group("room_cleanup")

func _physics_process(delta: float) -> void:
	if is_collected:
		return

	# Magnet attraction
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		var dist = global_position.distance_to(player.global_position)
		if dist < GameConfig.pickup_magnet_range:
			var dir = (player.global_position - global_position).normalized()
			global_position += dir * GameConfig.pickup_magnet_strength * delta
			return

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
		print("[AmmoPickup] Ammo now:", GameState.ammo, "/", GameState.max_ammo)

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
