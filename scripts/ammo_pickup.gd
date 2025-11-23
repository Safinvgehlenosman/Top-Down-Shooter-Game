extends Area2D

@export var initial_speed: float = 80.0
@export var friction: float = 200.0

const ALT_WEAPON_NONE := 0
const ALT_WEAPON_SHOTGUN := 1
const ALT_WEAPON_SNIPER := 2

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
	pass


func launch() -> void:
	# random horizontal direction for the hop
	var angle: float = randf_range(-PI, PI)
	velocity = Vector2(cos(angle), sin(angle)) * initial_speed

	# vertical fake jump
	z_velocity = jump_force


func _physics_process(delta: float) -> void:
	if is_collected:
		return

	# Magnet attraction
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		var dist: float = global_position.distance_to(player.global_position)
		if dist < GameConfig.pickup_magnet_range:
			var dir: Vector2 = (player.global_position - global_position).normalized()
			global_position += dir * GameConfig.pickup_magnet_strength * delta
			return

	# Horizontal bounce movement
	global_position += velocity * delta
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	# Vertical arc
	z_velocity -= fall_gravity * delta
	z_height += z_velocity * delta

	if z_height < 0.0:
		z_height = 0.0
		z_velocity = 0.0

	sprite.position.y = -z_height


func _on_body_entered(body: Node2D) -> void:
	if is_collected:
		return

	if not body.is_in_group("player"):
		return

	is_collected = true

	var amount: int = 0

	# 🔥 Use GameState's weapon data
	if GameState.alt_weapon != ALT_WEAPON_NONE \
			and GameState.ALT_WEAPON_DATA.has(GameState.alt_weapon):
		var data = GameState.ALT_WEAPON_DATA[GameState.alt_weapon]
		amount = data.get("pickup_amount", 0)

	# Apply ammo if relevant
	if amount > 0 and body.has_method("add_ammo"):
		body.add_ammo(amount)

	# Disable visuals and collisions
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
